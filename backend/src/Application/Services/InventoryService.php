<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\InventoryRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Shared\Http\HttpException;

final class InventoryService
{
    public function __construct(
        private readonly InventoryRepository $repository,
        private readonly ProductRepository $productRepository,
        private readonly AuditRepository $auditRepository,
        private readonly StockService $stockService
    ) {
    }

    public function paginateSessions(int $page, int $perPage): array
    {
        return $this->repository->paginateSessions($page, $perPage);
    }

    public function findSession(int $id): array
    {
        $session = $this->repository->findSession($id);
        if (!$session) {
            throw new HttpException('Inventory session not found', 404);
        }

        return $session;
    }

    public function createSession(array $payload, int $actorId, ?string $ip): int
    {
        $warehouseId = (int)($payload['warehouse_id'] ?? 0);
        if ($warehouseId <= 0) {
            throw new HttpException('Warehouse is required', 422);
        }

        $code = $payload['code'] ?? ('INV-' . date('Ymd') . '-' . strtoupper(substr(bin2hex(random_bytes(4)), 0, 5)));

        $id = $this->repository->createSession([
            'code' => $code,
            'warehouse_id' => $warehouseId,
            'counting_mode' => strtoupper((string)($payload['counting_mode'] ?? 'GLOBAL')),
            'status' => 'IN_PROGRESS',
            'created_by' => $actorId,
            'notes' => $payload['notes'] ?? null,
        ]);

        $this->auditRepository->log($actorId, 'CREATE', 'inventory_session', $id, ['code' => $code], $ip);

        return $id;
    }

    public function addCount(int $sessionId, array $payload, int $actorId, ?string $ip): int
    {
        $session = $this->findSession($sessionId);
        if (!in_array($session['status'], ['IN_PROGRESS', 'DRAFT'], true)) {
            throw new HttpException('Session is not editable', 422);
        }

        $productId = (int)($payload['product_id'] ?? 0);
        $countedQty = (int)($payload['counted_qty'] ?? 0);

        if ($productId <= 0 || $countedQty < 0) {
            throw new HttpException('Invalid count payload', 422);
        }

        $expectedQty = $this->repository->expectedQuantity((int)$session['warehouse_id'], $productId);
        $differenceQty = $countedQty - $expectedQty;

        $id = $this->repository->addCount([
            'session_id' => $sessionId,
            'product_id' => $productId,
            'expected_qty' => $expectedQty,
            'counted_qty' => $countedQty,
            'difference_qty' => $differenceQty,
            'location_id' => isset($payload['location_id']) ? (int)$payload['location_id'] : null,
            'counted_by' => $actorId,
            'notes' => $payload['notes'] ?? null,
        ]);

        $this->auditRepository->log($actorId, 'COUNT', 'inventory_session_item', $id, ['session_id' => $sessionId], $ip);

        return $id;
    }

    public function finalize(int $sessionId, int $actorId, ?string $ip): void
    {
        $session = $this->findSession($sessionId);

        if ($session['status'] === 'COMPLETED') {
            throw new HttpException('Session already completed', 422);
        }

        foreach ($session['items'] as $item) {
            $diff = (int)$item['difference_qty'];
            if ($diff === 0) {
                continue;
            }

            $this->stockService->createMovement([
                'product_id' => (int)$item['product_id'],
                'warehouse_id' => (int)$session['warehouse_id'],
                'type' => 'ADJUSTMENT',
                'quantity' => (int)$item['counted_qty'],
                'reason_code' => 'INVENTORY',
                'reference_type' => 'INVENTORY_SESSION',
                'reference_id' => $sessionId,
                'notes' => 'Inventory adjustment generated from session',
            ], $actorId, $ip);
        }

        $this->repository->markSessionCompleted($sessionId);
        $this->auditRepository->log($actorId, 'FINALIZE', 'inventory_session', $sessionId, [], $ip);
    }
}
