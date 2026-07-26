<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\PurchaseOrderRepository;
use App\Infrastructure\Persistence\PurchaseRequestRepository;
use App\Shared\Database\Database;
use App\Shared\Http\HttpException;
use Throwable;

final class PurchaseOrderService
{
    public function __construct(
        private readonly PurchaseOrderRepository $repository,
        private readonly StockService $stockService,
        private readonly AuditRepository $auditRepository,
        private readonly PurchaseRequestRepository $purchaseRequestRepository
    ) {
    }

    public function paginate(int $page, int $perPage): array
    {
        return $this->repository->paginate($page, $perPage);
    }

    public function findById(int $id): array
    {
        $order = $this->repository->findById($id);
        if (!$order) {
            throw new HttpException('Purchase order not found', 404);
        }

        return $order;
    }

    public function create(array $payload, int $actorId, ?string $ip): int
    {
        $items = $payload['items'] ?? [];
        $supplierId = (int)($payload['supplier_id'] ?? 0);
        $warehouseId = (int)($payload['warehouse_id'] ?? 0);
        $purchaseRequestId = (int)($payload['purchase_request_id'] ?? 0);

        if (!is_array($items) || $items === []) {
            throw new HttpException('At least one item is required', 422);
        }
        if ($supplierId <= 0 || $warehouseId <= 0) {
            throw new HttpException('Supplier and warehouse are required', 422);
        }

        $purchaseRequest = null;
        if ($purchaseRequestId > 0) {
            $purchaseRequest = $this->purchaseRequestRepository->findById($purchaseRequestId);
            if (!$purchaseRequest) {
                throw new HttpException('Purchase request not found', 404);
            }
            if (!in_array($purchaseRequest['status'], ['SUBMITTED', 'APPROVED'], true)) {
                throw new HttpException('Purchase request cannot be converted in its current status', 422);
            }
        }

        $totalAmount = 0.0;
        foreach ($items as $index => $item) {
            $qty = (int)($item['quantity_ordered'] ?? 0);
            $unitCost = (float)($item['unit_cost'] ?? 0);

            if ($qty <= 0 || $unitCost < 0) {
                throw new HttpException("Invalid item at index {$index}", 422);
            }

            $lineTotal = $qty * $unitCost;
            $items[$index]['line_total'] = $lineTotal;
            $totalAmount += $lineTotal;
        }

        $orderNumber = $payload['order_number'] ?? ('PO-' . date('Ymd') . '-' . strtoupper(substr(bin2hex(random_bytes(4)), 0, 6)));

        $id = $this->repository->create([
            'order_number' => $orderNumber,
            'supplier_id' => $supplierId,
            'warehouse_id' => $warehouseId,
            'purchase_request_id' => $purchaseRequestId > 0 ? $purchaseRequestId : null,
            'status' => strtoupper((string)($payload['status'] ?? 'PENDING')),
            'ordered_by' => $actorId,
            'expected_at' => $payload['expected_at'] ?? null,
            'total_amount' => $totalAmount,
            'notes' => $payload['notes'] ?? null,
            'items' => $items,
        ]);

        $this->auditRepository->log($actorId, 'CREATE', 'purchase_order', $id, ['order_number' => $orderNumber], $ip);

        // La demande d'achat liee passe automatiquement en "Convertie": c'est
        // le statut prevu pour ce cas (une commande a ete generee a partir
        // d'elle), ce qui evite qu'elle soit reutilisee pour une seconde
        // commande par erreur.
        if ($purchaseRequest !== null) {
            $this->purchaseRequestRepository->updateStatus($purchaseRequestId, 'CONVERTED');
            $this->auditRepository->log(
                $actorId,
                'CONVERT',
                'purchase_request',
                $purchaseRequestId,
                ['converted_to_purchase_order' => $id],
                $ip
            );
        }

        return $id;
    }

    public function updateStatus(int $id, array $payload, int $actorId, ?string $ip): void
    {
        $allowed = ['DRAFT', 'PENDING', 'PARTIAL', 'RECEIVED', 'CANCELLED'];
        $status = strtoupper((string)($payload['status'] ?? ''));
        if (!in_array($status, $allowed, true)) {
            throw new HttpException('Invalid status', 422);
        }

        $order = $this->repository->findById($id);
        if (!$order) {
            throw new HttpException('Purchase order not found', 404);
        }

        $this->repository->updateStatus($id, $status);
        $this->auditRepository->log($actorId, 'UPDATE_STATUS', 'purchase_order', $id, ['status' => $status], $ip);
    }

    public function receive(int $id, array $payload, int $actorId, ?string $ip): void
    {
        $order = $this->repository->findById($id);
        if (!$order) {
            throw new HttpException('Purchase order not found', 404);
        }

        if (in_array($order['status'], ['CANCELLED', 'RECEIVED'], true)) {
            throw new HttpException('Purchase order cannot be received in current status', 422);
        }

        $items = $payload['items'] ?? [];
        if (!is_array($items) || $items === []) {
            throw new HttpException('At least one received item is required', 422);
        }

        $indexedItems = [];
        foreach ($order['items'] as $orderItem) {
            $indexedItems[(int)$orderItem['id']] = $orderItem;
        }

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            foreach ($items as $line) {
                $itemId = (int)($line['item_id'] ?? 0);
                $receivedQty = (int)($line['quantity_received'] ?? 0);

                if ($itemId <= 0 || $receivedQty <= 0) {
                    throw new HttpException('Invalid received line payload', 422);
                }

                if (!isset($indexedItems[$itemId])) {
                    throw new HttpException("Unknown PO item: {$itemId}", 422);
                }

                $orderItem = $indexedItems[$itemId];
                $remaining = (int)$orderItem['quantity_ordered'] - (int)$orderItem['quantity_received'];
                if ($receivedQty > $remaining) {
                    throw new HttpException("Received quantity exceeds remaining qty for item {$itemId}", 422);
                }

                $this->stockService->createMovement([
                    'product_id' => (int)$orderItem['product_id'],
                    'warehouse_id' => (int)$order['warehouse_id'],
                    'type' => 'IN',
                    'quantity' => $receivedQty,
                    'reason_code' => 'PO_RECEIPT',
                    'reference_type' => 'PURCHASE_ORDER',
                    'reference_id' => $id,
                    'notes' => 'PO receipt ' . (string)$order['order_number'],
                ], $actorId, $ip);

                $this->repository->receiveItemQuantity($id, $itemId, $receivedQty);
                $indexedItems[$itemId]['quantity_received'] = (int)$orderItem['quantity_received'] + $receivedQty;
            }

            $newStatus = $this->repository->syncOrderStatusFromItems($id);
            $this->auditRepository->log($actorId, 'RECEIVE', 'purchase_order', $id, ['status' => $newStatus], $ip);

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
