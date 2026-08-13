<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\DeliveryRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Infrastructure\Persistence\ProductSerialRepository;
use App\Shared\Database\Database;
use App\Shared\Http\HttpException;
use Throwable;

final class DeliveryService
{
    public function __construct(
        private readonly DeliveryRepository $repository,
        private readonly StockService $stockService,
        private readonly AuditRepository $auditRepository,
        private readonly ProductSerialRepository $productSerialRepository,
        private readonly ProductRepository $productRepository
    ) {
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        return $this->repository->paginate($page, $perPage, $filters);
    }

    public function findById(int $id): array
    {
        $delivery = $this->repository->findById($id);
        if (!$delivery) {
            throw new HttpException('Delivery not found', 404);
        }

        return $delivery;
    }

    public function create(array $payload, int $actorId, ?string $ip): int
    {
        $lines = $payload['lines'] ?? [];
        $customerId = (int)($payload['customer_id'] ?? 0);
        $warehouseId = (int)($payload['warehouse_id'] ?? 0);

        if (!is_array($lines) || $lines === []) {
            throw new HttpException('At least one line is required', 422);
        }
        if ($customerId <= 0 || $warehouseId <= 0) {
            throw new HttpException('Customer and warehouse are required', 422);
        }

        $totalAmount = 0.0;
        foreach ($lines as $index => $line) {
            $productId = (int)($line['product_id'] ?? 0);
            $variantId = !empty($line['variant_id']) ? (int)$line['variant_id'] : null;
            $qty = (int)($line['quantity'] ?? 0);
            $unitPrice = (float)($line['unit_price'] ?? 0);
            $serialId = isset($line['serial_id']) && $line['serial_id'] !== '' && $line['serial_id'] !== null
                ? (int)$line['serial_id']
                : null;

            if ($productId <= 0 || $qty <= 0 || $unitPrice < 0) {
                throw new HttpException("Invalid line at index {$index}", 422);
            }

            $product = $this->productRepository->findById($productId);
            if ($product && (int)($product['has_variants'] ?? 0) === 1 && $variantId === null) {
                throw new HttpException("Ce produit utilise des variantes : precise laquelle a la ligne {$index}", 422);
            }
            $lines[$index]['variant_id'] = $variantId;

            if ($serialId !== null) {
                $serial = $this->productSerialRepository->findById($serialId);
                if (!$serial) {
                    throw new HttpException("Numero de serie introuvable a la ligne {$index}", 422);
                }
                if ((int)$serial['product_id'] !== $productId) {
                    throw new HttpException("Le numero de serie selectionne ne correspond pas au produit de la ligne {$index}", 422);
                }
                if ($serial['status'] !== 'IN_STOCK') {
                    throw new HttpException("Le numero de serie {$serial['serial_number']} n'est plus en stock", 422);
                }
                if ($qty !== 1) {
                    throw new HttpException("Un numero de serie ne peut etre associe qu'a une ligne de quantite 1 (ligne {$index})", 422);
                }
                $lines[$index]['serial_id'] = $serialId;
            }

            $lineTotal = $qty * $unitPrice;
            $lines[$index]['line_total'] = $lineTotal;
            $totalAmount += $lineTotal;
        }

        $deliveryNumber = $payload['delivery_number'] ?? ('BL-' . date('Ymd') . '-' . strtoupper(substr(bin2hex(random_bytes(4)), 0, 6)));

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            $deliveryId = $this->repository->create([
                'delivery_number' => $deliveryNumber,
                'customer_id' => $customerId,
                'warehouse_id' => $warehouseId,
                'status' => 'VALIDATED',
                'delivered_by' => $actorId,
                'total_amount' => $totalAmount,
                'notes' => $payload['notes'] ?? null,
                'lines' => $lines,
            ]);

            foreach ($lines as $line) {
                $this->stockService->createMovement([
                    'product_id' => (int)$line['product_id'],
                    'variant_id' => $line['variant_id'] ?? null,
                    'warehouse_id' => $warehouseId,
                    'type' => 'OUT',
                    'quantity' => (int)$line['quantity'],
                    'reason_code' => 'DELIVERY',
                    'reference_type' => 'DELIVERY',
                    'reference_id' => $deliveryId,
                    'notes' => 'BL ' . $deliveryNumber,
                ], $actorId, $ip);

                if (!empty($line['serial_id'])) {
                    $this->productSerialRepository->updateStatus((int)$line['serial_id'], 'OUT', null, 'BL ' . $deliveryNumber);
                }
            }

            $this->auditRepository->log($actorId, 'CREATE', 'delivery', $deliveryId, ['delivery_number' => $deliveryNumber], $ip);

            if ($ownsTransaction) {
                $pdo->commit();
            }

            return $deliveryId;
        } catch (Throwable $exception) {
            if ($ownsTransaction && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $exception;
        }
    }

    public function cancel(int $id, int $actorId, ?string $ip): void
    {
        $delivery = $this->repository->findById($id);
        if (!$delivery) {
            throw new HttpException('Delivery not found', 404);
        }
        if ($delivery['status'] === 'CANCELLED') {
            throw new HttpException('Delivery already cancelled', 422);
        }

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            foreach ($delivery['lines'] as $line) {
                $this->stockService->createMovement([
                    'product_id' => (int)$line['product_id'],
                    'variant_id' => $line['variant_id'] ?? null,
                    'warehouse_id' => (int)$delivery['warehouse_id'],
                    'type' => 'IN',
                    'quantity' => (int)$line['quantity'],
                    'reason_code' => 'DELIVERY_CANCEL',
                    'reference_type' => 'DELIVERY',
                    'reference_id' => $id,
                    'notes' => 'Annulation BL ' . $delivery['delivery_number'],
                ], $actorId, $ip);

                if (!empty($line['serial_id'])) {
                    $this->productSerialRepository->updateStatus(
                        (int)$line['serial_id'],
                        'IN_STOCK',
                        (int)$delivery['warehouse_id'],
                        'Annulation BL ' . $delivery['delivery_number']
                    );
                }
            }

            $this->repository->updateStatus($id, 'CANCELLED');
            $this->auditRepository->log($actorId, 'CANCEL', 'delivery', $id, ['delivery_number' => $delivery['delivery_number']], $ip);

            if ($ownsTransaction) {
                $pdo->commit();
            }
        } catch (Throwable $exception) {
            if ($ownsTransaction && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $exception;
        }
    }
}
