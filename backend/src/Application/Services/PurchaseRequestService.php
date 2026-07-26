<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\PurchaseRequestRepository;
use App\Shared\Http\HttpException;

final class PurchaseRequestService
{
    public function __construct(
        private readonly PurchaseRequestRepository $repository,
        private readonly AuditRepository $auditRepository
    ) {
    }

    public function paginate(int $page, int $perPage): array
    {
        return $this->repository->paginate($page, $perPage);
    }

    public function findById(int $id): array
    {
        $row = $this->repository->findById($id);
        if (!$row) {
            throw new HttpException('Purchase request not found', 404);
        }

        return $row;
    }

    public function create(array $payload, int $actorId, ?string $ip): int
    {
        $warehouseId = (int)($payload['warehouse_id'] ?? 0);
        $items = $payload['items'] ?? [];

        if ($warehouseId <= 0) {
            throw new HttpException('Warehouse is required', 422);
        }
        if (!is_array($items) || $items === []) {
            throw new HttpException('At least one item is required', 422);
        }

        foreach ($items as $idx => $item) {
            if ((int)($item['product_id'] ?? 0) <= 0 || (int)($item['quantity_requested'] ?? 0) <= 0) {
                throw new HttpException("Invalid item at index {$idx}", 422);
            }
        }

        $requestNumber = $payload['request_number'] ?? ('PR-' . date('Ymd') . '-' . strtoupper(substr(bin2hex(random_bytes(4)), 0, 6)));

        $id = $this->repository->create([
            'request_number' => $requestNumber,
            'requester_id' => $actorId,
            'warehouse_id' => $warehouseId,
            'status' => strtoupper((string)($payload['status'] ?? 'SUBMITTED')),
            'needed_at' => $payload['needed_at'] ?? null,
            'notes' => $payload['notes'] ?? null,
            'items' => $items,
        ]);

        $this->auditRepository->log($actorId, 'CREATE', 'purchase_request', $id, ['request_number' => $requestNumber], $ip);
        return $id;
    }

    public function updateStatus(int $id, string $status, int $actorId, ?string $ip): void
    {
        $allowed = ['DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'CONVERTED'];
        $normalized = strtoupper($status);
        if (!in_array($normalized, $allowed, true)) {
            throw new HttpException('Invalid purchase request status', 422);
        }

        $this->findById($id);
        $this->repository->updateStatus($id, $normalized);
        $this->auditRepository->log($actorId, 'UPDATE_STATUS', 'purchase_request', $id, ['status' => $normalized], $ip);
    }
}