<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;
use Throwable;

final class DeliveryRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(100, $perPage));
        $offset = ($page - 1) * $perPage;

        $clauses = [];
        $params = [];

        if (!empty($filters['customer_id'])) {
            $clauses[] = 'd.customer_id = :customer_id';
            $params[':customer_id'] = (int)$filters['customer_id'];
        }
        if (!empty($filters['status'])) {
            $clauses[] = 'd.status = :status';
            $params[':status'] = (string)$filters['status'];
        }

        $whereSql = $clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '';

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM deliveries d {$whereSql}");
        foreach ($params as $key => $value) {
            $countStmt->bindValue($key, $value);
        }
        $countStmt->execute();
        $total = (int)$countStmt->fetchColumn();

        $stmt = $this->pdo->prepare("
            SELECT d.*, c.name AS customer_name, c.address AS customer_address,
                   w.name AS warehouse_name, u.full_name AS delivered_by_name
            FROM deliveries d
            INNER JOIN customers c ON c.id = d.customer_id
            INNER JOIN warehouses w ON w.id = d.warehouse_id
            LEFT JOIN users u ON u.id = d.delivered_by
            {$whereSql}
            ORDER BY d.id DESC
            LIMIT :limit OFFSET :offset
        ");
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

    public function findById(int $id): ?array
    {
        $stmt = $this->pdo->prepare('
            SELECT d.*, c.name AS customer_name, c.email AS customer_email, c.phone AS customer_phone,
                   c.address AS customer_address, w.name AS warehouse_name, u.full_name AS delivered_by_name
            FROM deliveries d
            INNER JOIN customers c ON c.id = d.customer_id
            INNER JOIN warehouses w ON w.id = d.warehouse_id
            LEFT JOIN users u ON u.id = d.delivered_by
            WHERE d.id = :id
            LIMIT 1
        ');
        $stmt->execute([':id' => $id]);
        $delivery = $stmt->fetch();

        if (!$delivery) {
            return null;
        }

        $lineStmt = $this->pdo->prepare('
            SELECT dl.*, p.sku, p.name AS product_name, ps.serial_number,
                   v.sku AS variant_sku, v.size AS variant_size, v.color AS variant_color, v.vintage AS variant_vintage, v.volume_cl AS variant_volume_cl
            FROM delivery_lines dl
            INNER JOIN products p ON p.id = dl.product_id
            LEFT JOIN product_serials ps ON ps.id = dl.serial_id
            LEFT JOIN product_variants v ON v.id = dl.variant_id
            WHERE dl.delivery_id = :delivery_id
            ORDER BY dl.id ASC
        ');
        $lineStmt->execute([':delivery_id' => $id]);
        $delivery['lines'] = $lineStmt->fetchAll();

        return $delivery;
    }

    public function create(array $payload): int
    {
        $ownsTransaction = !$this->pdo->inTransaction();
        if ($ownsTransaction) {
            $this->pdo->beginTransaction();
        }

        try {
            $stmt = $this->pdo->prepare('
                INSERT INTO deliveries
                    (delivery_number, customer_id, warehouse_id, status, delivered_by, delivered_at, total_amount, notes, created_at, updated_at)
                VALUES
                    (:delivery_number, :customer_id, :warehouse_id, :status, :delivered_by, NOW(), :total_amount, :notes, NOW(), NOW())
            ');
            $stmt->execute([
                ':delivery_number' => $payload['delivery_number'],
                ':customer_id' => $payload['customer_id'],
                ':warehouse_id' => $payload['warehouse_id'],
                ':status' => $payload['status'] ?? 'VALIDATED',
                ':delivered_by' => $payload['delivered_by'] ?? null,
                ':total_amount' => $payload['total_amount'],
                ':notes' => $payload['notes'] ?? null,
            ]);

            $deliveryId = (int)$this->pdo->lastInsertId();

            $lineStmt = $this->pdo->prepare('
                INSERT INTO delivery_lines (delivery_id, product_id, variant_id, serial_id, quantity, unit_price, line_total)
                VALUES (:delivery_id, :product_id, :variant_id, :serial_id, :quantity, :unit_price, :line_total)
            ');

            foreach ($payload['lines'] as $line) {
                $lineStmt->execute([
                    ':delivery_id' => $deliveryId,
                    ':product_id' => $line['product_id'],
                    ':variant_id' => $line['variant_id'] ?? null,
                    ':serial_id' => $line['serial_id'] ?? null,
                    ':quantity' => $line['quantity'],
                    ':unit_price' => $line['unit_price'],
                    ':line_total' => $line['line_total'],
                ]);
            }

            if ($ownsTransaction) {
                $this->pdo->commit();
            }

            return $deliveryId;
        } catch (Throwable $exception) {
            if ($ownsTransaction && $this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }
            throw $exception;
        }
    }

    public function updateStatus(int $id, string $status): void
    {
        $stmt = $this->pdo->prepare('
            UPDATE deliveries
            SET status = :status, updated_at = NOW()
            WHERE id = :id
        ');
        $stmt->execute([':id' => $id, ':status' => $status]);
    }
}
