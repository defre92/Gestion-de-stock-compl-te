<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;
use Throwable;

final class PurchaseOrderRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function paginate(int $page, int $perPage): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(100, $perPage));
        $offset = ($page - 1) * $perPage;

        $total = (int)$this->pdo->query('SELECT COUNT(*) FROM purchase_orders')->fetchColumn();

        $sql = '
            SELECT po.*, s.name AS supplier_name, w.name AS warehouse_name, u.full_name AS ordered_by_name,
                   pr.request_number AS purchase_request_number
            FROM purchase_orders po
            INNER JOIN suppliers s ON s.id = po.supplier_id
            INNER JOIN warehouses w ON w.id = po.warehouse_id
            LEFT JOIN users u ON u.id = po.ordered_by
            LEFT JOIN purchase_requests pr ON pr.id = po.purchase_request_id
            ORDER BY po.id DESC
            LIMIT :limit OFFSET :offset
        ';

        $stmt = $this->pdo->prepare($sql);
        $stmt->bindValue(':limit', $perPage, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();

        return [
            'data' => $stmt->fetchAll(),
            'meta' => [
                'page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'last_page' => (int)max(1, ceil($total / $perPage)),
            ],
        ];
    }

    public function findById(int $id): ?array
    {
        $stmt = $this->pdo->prepare('
            SELECT po.*, s.name AS supplier_name, w.name AS warehouse_name, u.full_name AS ordered_by_name,
                   pr.request_number AS purchase_request_number
            FROM purchase_orders po
            INNER JOIN suppliers s ON s.id = po.supplier_id
            INNER JOIN warehouses w ON w.id = po.warehouse_id
            LEFT JOIN users u ON u.id = po.ordered_by
            LEFT JOIN purchase_requests pr ON pr.id = po.purchase_request_id
            WHERE po.id = :id
            LIMIT 1
        ');
        $stmt->execute([':id' => $id]);
        $order = $stmt->fetch();

        if (!$order) {
            return null;
        }

        $itemStmt = $this->pdo->prepare('
            SELECT poi.*, p.sku, p.name AS product_name,
                   v.sku AS variant_sku, v.size AS variant_size, v.color AS variant_color
            FROM purchase_order_items poi
            INNER JOIN products p ON p.id = poi.product_id
            LEFT JOIN product_variants v ON v.id = poi.variant_id
            WHERE poi.purchase_order_id = :order_id
            ORDER BY poi.id ASC
        ');
        $itemStmt->execute([':order_id' => $id]);
        $order['items'] = $itemStmt->fetchAll();

        return $order;
    }

    public function create(array $payload): int
    {
        $this->pdo->beginTransaction();

        try {
            $stmt = $this->pdo->prepare('
                INSERT INTO purchase_orders
                    (order_number, supplier_id, warehouse_id, purchase_request_id, status, ordered_by, ordered_at, expected_at, total_amount, notes, created_at, updated_at)
                VALUES
                    (:order_number, :supplier_id, :warehouse_id, :purchase_request_id, :status, :ordered_by, NOW(), :expected_at, :total_amount, :notes, NOW(), NOW())
            ');
            $stmt->execute([
                ':order_number' => $payload['order_number'],
                ':supplier_id' => $payload['supplier_id'],
                ':warehouse_id' => $payload['warehouse_id'],
                ':purchase_request_id' => $payload['purchase_request_id'] ?? null,
                ':status' => $payload['status'] ?? 'PENDING',
                ':ordered_by' => $payload['ordered_by'] ?? null,
                ':expected_at' => $payload['expected_at'] ?? null,
                ':total_amount' => $payload['total_amount'],
                ':notes' => $payload['notes'] ?? null,
            ]);

            $orderId = (int)$this->pdo->lastInsertId();

            $itemStmt = $this->pdo->prepare('
                INSERT INTO purchase_order_items
                    (purchase_order_id, product_id, variant_id, quantity_ordered, quantity_received, unit_cost, line_total)
                VALUES
                    (:purchase_order_id, :product_id, :variant_id, :quantity_ordered, :quantity_received, :unit_cost, :line_total)
            ');

            foreach ($payload['items'] as $item) {
                $itemStmt->execute([
                    ':purchase_order_id' => $orderId,
                    ':product_id' => $item['product_id'],
                    ':variant_id' => $item['variant_id'] ?? null,
                    ':quantity_ordered' => $item['quantity_ordered'],
                    ':quantity_received' => $item['quantity_received'] ?? 0,
                    ':unit_cost' => $item['unit_cost'],
                    ':line_total' => $item['line_total'],
                ]);
            }

            $this->pdo->commit();
            return $orderId;
        } catch (Throwable $exception) {
            $this->pdo->rollBack();
            throw $exception;
        }
    }

    public function updateStatus(int $id, string $status): void
    {
        $stmt = $this->pdo->prepare('
            UPDATE purchase_orders
            SET status = :status,
                received_at = CASE WHEN :received_marker = \'RECEIVED\' THEN NOW() ELSE received_at END,
                updated_at = NOW()
            WHERE id = :id
        ');
        $stmt->execute([
            ':id' => $id,
            ':status' => $status,
            ':received_marker' => $status,
        ]);
    }

    public function receiveItemQuantity(int $orderId, int $itemId, int $quantity): void
    {
        $stmt = $this->pdo->prepare('
            UPDATE purchase_order_items
            SET quantity_received = LEAST(quantity_ordered, quantity_received + :quantity)
            WHERE id = :item_id
              AND purchase_order_id = :order_id
        ');
        $stmt->execute([
            ':quantity' => $quantity,
            ':item_id' => $itemId,
            ':order_id' => $orderId,
        ]);
    }

    public function syncOrderStatusFromItems(int $orderId): string
    {
        $stmt = $this->pdo->prepare('
            SELECT
                SUM(quantity_ordered) AS total_ordered,
                SUM(quantity_received) AS total_received
            FROM purchase_order_items
            WHERE purchase_order_id = :order_id
        ');
        $stmt->execute([':order_id' => $orderId]);
        $totals = $stmt->fetch() ?: ['total_ordered' => 0, 'total_received' => 0];

        $totalOrdered = (int)($totals['total_ordered'] ?? 0);
        $totalReceived = (int)($totals['total_received'] ?? 0);

        if ($totalOrdered <= 0) {
            $status = 'PENDING';
        } elseif ($totalReceived <= 0) {
            $status = 'PENDING';
        } elseif ($totalReceived < $totalOrdered) {
            $status = 'PARTIAL';
        } else {
            $status = 'RECEIVED';
        }

        $this->updateStatus($orderId, $status);
        return $status;
    }
}
