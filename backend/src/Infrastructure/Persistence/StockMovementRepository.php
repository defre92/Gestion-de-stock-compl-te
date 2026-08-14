<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

final class StockMovementRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function create(array $payload): int
    {
        $stmt = $this->pdo->prepare('
            INSERT INTO stock_movements
                (product_id, variant_id, warehouse_id, destination_warehouse_id, source_location_id, destination_location_id,
                 type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
            VALUES
                (:product_id, :variant_id, :warehouse_id, :destination_warehouse_id, :source_location_id, :destination_location_id,
                 :type, :quantity, :balance_after, :reference_type, :reference_id, :notes, :reason_code, :moved_by, NOW())
        ');

        $stmt->execute([
            ':product_id' => $payload['product_id'],
            ':variant_id' => $payload['variant_id'] ?? null,
            ':warehouse_id' => $payload['warehouse_id'],
            ':destination_warehouse_id' => $payload['destination_warehouse_id'] ?? null,
            ':source_location_id' => $payload['source_location_id'] ?? null,
            ':destination_location_id' => $payload['destination_location_id'] ?? null,
            ':type' => $payload['type'],
            ':quantity' => $payload['quantity'],
            ':balance_after' => $payload['balance_after'],
            ':reference_type' => $payload['reference_type'] ?? null,
            ':reference_id' => $payload['reference_id'] ?? null,
            ':notes' => $payload['notes'] ?? null,
            ':reason_code' => $payload['reason_code'] ?? null,
            ':moved_by' => $payload['moved_by'] ?? null,
        ]);

        return (int)$this->pdo->lastInsertId();
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(100, $perPage));
        $offset = ($page - 1) * $perPage;

        $clauses = [];
        $params = [];

        if (!empty($filters['type'])) {
            $clauses[] = 'sm.type = :type';
            $params[':type'] = (string)$filters['type'];
        }
        if (!empty($filters['product_id'])) {
            $clauses[] = 'sm.product_id = :product_id';
            $params[':product_id'] = (int)$filters['product_id'];
        }
        if (!empty($filters['variant_id'])) {
            $clauses[] = 'sm.variant_id = :variant_id';
            $params[':variant_id'] = (int)$filters['variant_id'];
        }
        if (!empty($filters['warehouse_id'])) {
            $clauses[] = '(sm.warehouse_id = :warehouse_id OR sm.destination_warehouse_id = :warehouse_id)';
            $params[':warehouse_id'] = (int)$filters['warehouse_id'];
        }
        if (!empty($filters['date_from'])) {
            $clauses[] = 'sm.created_at >= :date_from';
            $params[':date_from'] = (string)$filters['date_from'];
        }
        if (!empty($filters['date_to'])) {
            $clauses[] = 'sm.created_at <= :date_to';
            $params[':date_to'] = (string)$filters['date_to'];
        }
        if (!empty($filters['customer_id'])) {
            $clauses[] = "sm.reference_type = 'CUSTOMER' AND sm.reference_id = :customer_id";
            $params[':customer_id'] = (int)$filters['customer_id'];
        }

        $whereSql = $clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '';

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM stock_movements sm {$whereSql}");
        foreach ($params as $key => $value) {
            $countStmt->bindValue($key, $value);
        }
        $countStmt->execute();
        $total = (int)$countStmt->fetchColumn();

        $stmt = $this->pdo->prepare('
            SELECT sm.*, p.sku, p.name AS product_name,
                   v.sku AS variant_sku, v.size AS variant_size, v.color AS variant_color, v.vintage AS variant_vintage, v.volume_cl AS variant_volume_cl,
                   w.name AS warehouse_name,
                   dw.name AS destination_warehouse_name,
                   u.full_name AS moved_by_name,
                   c.name AS customer_name
            FROM stock_movements sm
            INNER JOIN products p ON p.id = sm.product_id
            LEFT JOIN product_variants v ON v.id = sm.variant_id
            INNER JOIN warehouses w ON w.id = sm.warehouse_id
            LEFT JOIN warehouses dw ON dw.id = sm.destination_warehouse_id
            LEFT JOIN users u ON u.id = sm.moved_by
            LEFT JOIN customers c ON sm.reference_type = \'CUSTOMER\' AND c.id = sm.reference_id
            ' . $whereSql . '
            ORDER BY sm.id DESC
            LIMIT :limit OFFSET :offset
        ');
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value);
        }
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
}
