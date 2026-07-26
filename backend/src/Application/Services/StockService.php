<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Infrastructure\Persistence\StockAlertRepository;
use App\Infrastructure\Persistence\StockMovementRepository;
use App\Infrastructure\Persistence\WarehouseRepository;
use App\Shared\Database\Database;
use App\Shared\Http\HttpException;
use Throwable;

final class StockService
{
    public function __construct(
        private readonly ProductRepository $productRepository,
        private readonly WarehouseRepository $warehouseRepository,
        private readonly StockMovementRepository $movementRepository,
        private readonly StockAlertRepository $alertRepository,
        private readonly AuditRepository $auditRepository
    ) {
    }

    public function paginateMovements(int $page, int $perPage, array $filters = []): array
    {
        return $this->movementRepository->paginate($page, $perPage, $filters);
    }

    public function lowStockAlerts(): array
    {
        $low = $this->productRepository->lowStock();
        $delayedPo = Database::connection()->query("SELECT po.id, po.order_number, po.expected_at, s.name supplier_name FROM purchase_orders po INNER JOIN suppliers s ON s.id=po.supplier_id WHERE po.status IN ('PENDING','PARTIAL') AND po.expected_at IS NOT NULL AND po.expected_at < NOW() ORDER BY po.expected_at ASC")->fetchAll();
        $persistent = $this->alertRepository->paginate(1, 200, ['status' => 'OPEN'])['data'];

        return [
            'low_stock' => $low,
            'delayed_po' => $delayedPo,
            'persistent' => $persistent,
        ];
    }

    public function createMovement(array $payload, int $actorId, ?string $ip): int
    {
        $productId = (int)($payload['product_id'] ?? 0);
        $warehouseId = (int)($payload['warehouse_id'] ?? 0);
        $type = strtoupper((string)($payload['type'] ?? ''));
        $quantity = (int)($payload['quantity'] ?? 0);
        $destinationWarehouseId = isset($payload['destination_warehouse_id']) ? (int)$payload['destination_warehouse_id'] : null;

        if ($productId <= 0 || $warehouseId <= 0 || $quantity <= 0 || !in_array($type, ['IN', 'OUT', 'ADJUSTMENT', 'TRANSFER'], true)) {
            throw new HttpException('Invalid stock movement payload', 422);
        }

        $product = $this->productRepository->findById($productId);
        if (!$product) {
            throw new HttpException('Product not found', 404);
        }

        $warehouse = $this->warehouseRepository->findById($warehouseId);
        if (!$warehouse) {
            throw new HttpException('Warehouse not found', 404);
        }

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            $current = $this->productRepository->stockLevel($productId, $warehouseId);
            $currentQty = $current['quantity'] ?? 0;
            $nextQty = $currentQty;

            if ($type === 'IN') {
                $nextQty = $currentQty + $quantity;
            } elseif ($type === 'OUT') {
                $nextQty = $currentQty - $quantity;
                if ($nextQty < 0) {
                    throw new HttpException('Insufficient stock', 422);
                }
            } elseif ($type === 'ADJUSTMENT') {
                $nextQty = $quantity;
            } else {
                if (!$destinationWarehouseId || $destinationWarehouseId === $warehouseId) {
                    throw new HttpException('A valid destination warehouse is required for transfer', 422);
                }

                $destinationWarehouse = $this->warehouseRepository->findById($destinationWarehouseId);
                if (!$destinationWarehouse) {
                    throw new HttpException('Destination warehouse not found', 404);
                }

                $nextQty = $currentQty - $quantity;
                if ($nextQty < 0) {
                    throw new HttpException('Insufficient stock for transfer', 422);
                }

                $destinationCurrent = $this->productRepository->stockLevel($productId, $destinationWarehouseId);
                $destinationQty = ($destinationCurrent['quantity'] ?? 0) + $quantity;

                $this->productRepository->upsertStockLevel($productId, $destinationWarehouseId, $destinationQty);
            }

            $this->productRepository->upsertStockLevel($productId, $warehouseId, $nextQty);

            $movementId = $this->movementRepository->create([
                'product_id' => $productId,
                'warehouse_id' => $warehouseId,
                'destination_warehouse_id' => $destinationWarehouseId,
                'source_location_id' => isset($payload['source_location_id']) ? (int)$payload['source_location_id'] : null,
                'destination_location_id' => isset($payload['destination_location_id']) ? (int)$payload['destination_location_id'] : null,
                'type' => $type,
                'quantity' => $quantity,
                'balance_after' => $nextQty,
                'reference_type' => $payload['reference_type'] ?? null,
                'reference_id' => isset($payload['reference_id']) ? (int)$payload['reference_id'] : null,
                'notes' => $payload['notes'] ?? null,
                'reason_code' => $payload['reason_code'] ?? null,
                'moved_by' => $actorId,
            ]);

            if ($type === 'TRANSFER' && $destinationWarehouseId) {
                $this->movementRepository->create([
                    'product_id' => $productId,
                    'warehouse_id' => $destinationWarehouseId,
                    'destination_warehouse_id' => null,
                    'type' => 'IN',
                    'quantity' => $quantity,
                    'balance_after' => (int)($this->productRepository->stockLevel($productId, $destinationWarehouseId)['quantity'] ?? 0),
                    'reference_type' => 'TRANSFER',
                    'reference_id' => $movementId,
                    'notes' => 'Auto generated destination move',
                    'reason_code' => $payload['reason_code'] ?? 'TRANSFER',
                    'moved_by' => $actorId,
                ]);
            }

            $this->auditRepository->log($actorId, 'CREATE', 'stock_movement', $movementId, $payload, $ip);
            $this->refreshProductAlert($productId, $warehouseId);
            if ($ownsTransaction) {
                $pdo->commit();
            }

            return $movementId;
        } catch (Throwable $exception) {
            if ($ownsTransaction && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $exception;
        }
    }

    private function refreshProductAlert(int $productId, int $warehouseId): void
    {
        $product = $this->productRepository->findById($productId);
        if (!$product) {
            return;
        }

        $stock = (int)($product['stock_total'] ?? 0);
        $threshold = max((int)($product['min_stock'] ?? 0), (int)($product['reorder_level'] ?? 0));

        if ($stock > $threshold) {
            return;
        }

        $alertType = $stock <= 0 ? 'OUT_OF_STOCK' : 'LOW_STOCK';
        $severity = $stock <= 0 ? 'CRITICAL' : 'WARNING';
        $message = $stock <= 0
            ? sprintf('Rupture de stock pour %s (%s)', $product['name'], $product['sku'])
            : sprintf('Stock bas pour %s (%s): %d', $product['name'], $product['sku'], $stock);

        $this->alertRepository->create([
            'alert_type' => $alertType,
            'severity' => $severity,
            'product_id' => $productId,
            'warehouse_id' => $warehouseId,
            'message' => $message,
            'status' => 'OPEN',
        ]);
    }
}
