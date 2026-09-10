<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Infrastructure\Persistence\PurchaseRequestRepository;
use App\Shared\Http\HttpException;

final class PurchaseRequestService
{
    public function __construct(
        private readonly PurchaseRequestRepository $repository,
        private readonly AuditRepository $auditRepository,
        private readonly ProductRepository $productRepository
    ) {
    }

    /** @param array{scope?: string, status?: string} $filters */
    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        return $this->repository->paginate($page, $perPage, $filters);
    }

    public function findById(int $id): array
    {
        $row = $this->repository->findById($id);
        if (!$row) {
            throw new HttpException('Demande d\'achat introuvable', 404);
        }

        return $row;
    }

    public function create(array $payload, int $actorId, ?string $ip): int
    {
        $warehouseId = (int)($payload['warehouse_id'] ?? 0);
        $items = $payload['items'] ?? [];

        if ($warehouseId <= 0) {
            throw new HttpException('L\'entrepot est requis', 422);
        }
        if (!is_array($items) || $items === []) {
            throw new HttpException('Au moins un article est requis', 422);
        }

        foreach ($items as $idx => $item) {
            $productId = (int)($item['product_id'] ?? 0);
            if ($productId <= 0 || (int)($item['quantity_requested'] ?? 0) <= 0) {
                throw new HttpException("Article invalide a la ligne {$idx}", 422);
            }
            $product = $this->productRepository->findById($productId);
            if ($product && (int)($product['has_variants'] ?? 0) === 1 && empty($item['variant_id'])) {
                throw new HttpException("Ce produit utilise des variantes : precise laquelle a la ligne {$idx}", 422);
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
            throw new HttpException('Statut de demande d\'achat invalide', 422);
        }

        $this->findById($id);
        $this->repository->updateStatus($id, $normalized);
        $this->auditRepository->log($actorId, 'UPDATE_STATUS', 'purchase_request', $id, ['status' => $normalized], $ip);
    }
}