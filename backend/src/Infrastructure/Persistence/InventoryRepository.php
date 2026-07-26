<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

final class InventoryRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function paginateSessions(int $page, int $perPage): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(100, $perPage));
        $offset = ($page - 1) * $perPage;

        $total = (int)$this->pdo->query('SELECT COUNT(*) FROM inventory_sessions')->fetchColumn();

        $stmt = $this->pdo->prepare('
            SELECT i.*, w.name AS warehouse_name, u.full_name AS creator_name
            FROM inventory_sessions i
            INNER JOIN warehouses w ON w.id = i.warehouse_id
            INNER JOIN users u ON u.id = i.created_by
            ORDER BY i.id DESC
            LIMIT :limit OFFSET :offset
        ');
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

    public function createSession(array $payload): int
    {
        $stmt = $this->pdo->prepare('
            INSERT INTO inventory_sessions
                (code, warehouse_id, status, counting_mode, started_at, created_by, notes, created_at, updated_at)
            VALUES
                (:code, :warehouse_id, :status, :counting_mode, NOW(), :created_by, :notes, NOW(), NOW())
        ');
        $stmt->execute([
            ':code' => $payload['code'],
            ':warehouse_id' => $payload['warehouse_id'],
            ':status' => $payload['status'] ?? 'IN_PROGRESS',
            ':counting_mode' => $payload['counting_mode'] ?? 'GLOBAL',
            ':created_by' => $payload['created_by'],
            ':notes' => $payload['notes'] ?? null,
        ]);

        return (int)$this->pdo->lastInsertId();
    }

    public function findSession(int $id): ?array
    {
        $stmt = $this->pdo->prepare('
            SELECT i.*, w.name AS warehouse_name, u.full_name AS creator_name
            FROM inventory_sessions i
            INNER JOIN warehouses w ON w.id = i.warehouse_id
            INNER JOIN users u ON u.id = i.created_by
            WHERE i.id = :id
            LIMIT 1
        ');
        $stmt->execute([':id' => $id]);
        $session = $stmt->fetch();

        if (!$session) {
            return null;
        }

        $items = $this->pdo->prepare('
            SELECT isi.*, p.sku, p.name AS product_name, l.code AS location_code, u.full_name AS counted_by_name
            FROM inventory_session_items isi
            INNER JOIN products p ON p.id = isi.product_id
            LEFT JOIN warehouse_locations l ON l.id = isi.location_id
            LEFT JOIN users u ON u.id = isi.counted_by
            WHERE isi.session_id = :session_id
            ORDER BY isi.id DESC
        ');
        $items->execute([':session_id' => $id]);
        $session['items'] = $items->fetchAll();

        return $session;
    }

    public function expectedQuantity(int $warehouseId, int $productId): int
    {
        $stmt = $this->pdo->prepare('
            SELECT COALESCE(quantity, 0)
            FROM stock_levels
            WHERE warehouse_id = :warehouse_id AND product_id = :product_id
            LIMIT 1
        ');
        $stmt->execute([':warehouse_id' => $warehouseId, ':product_id' => $productId]);
        return (int)($stmt->fetchColumn() ?: 0);
    }

    public function addCount(array $payload): int
    {
        $stmt = $this->pdo->prepare('
            INSERT INTO inventory_session_items
                (session_id, product_id, expected_qty, counted_qty, difference_qty, location_id, counted_by, counted_at, notes)
            VALUES
                (:session_id, :product_id, :expected_qty, :counted_qty, :difference_qty, :location_id, :counted_by, NOW(), :notes)
        ');
        $stmt->execute([
            ':session_id' => $payload['session_id'],
            ':product_id' => $payload['product_id'],
            ':expected_qty' => $payload['expected_qty'],
            ':counted_qty' => $payload['counted_qty'],
            ':difference_qty' => $payload['difference_qty'],
            ':location_id' => $payload['location_id'] ?? null,
            ':counted_by' => $payload['counted_by'] ?? null,
            ':notes' => $payload['notes'] ?? null,
        ]);

        return (int)$this->pdo->lastInsertId();
    }

    public function markSessionCompleted(int $id): void
    {
        $stmt = $this->pdo->prepare('UPDATE inventory_sessions SET status = :status, ended_at = NOW(), updated_at = NOW() WHERE id = :id');
        $stmt->execute([':status' => 'COMPLETED', ':id' => $id]);
    }
}