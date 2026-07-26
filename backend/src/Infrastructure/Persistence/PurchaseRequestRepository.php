<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;
use Throwable;

final class PurchaseRequestRepository
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

        $total = (int)$this->pdo->query('SELECT COUNT(*) FROM purchase_requests')->fetchColumn();

        $stmt = $this->pdo->prepare('
            SELECT pr.*, u.full_name AS requester_name, w.name AS warehouse_name
            FROM purchase_requests pr
            INNER JOIN users u ON u.id = pr.requester_id
            INNER JOIN warehouses w ON w.id = pr.warehouse_id
            ORDER BY pr.id DESC
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

    public function findById(int $id): ?array
    {
        $stmt = $this->pdo->prepare('
            SELECT pr.*, u.full_name AS requester_name, w.name AS warehouse_name
            FROM purchase_requests pr
            INNER JOIN users u ON u.id = pr.requester_id
            INNER JOIN warehouses w ON w.id = pr.warehouse_id
            WHERE pr.id = :id
            LIMIT 1
        ');
        $stmt->execute([':id' => $id]);
        $row = $stmt->fetch();

        if (!$row) {
            return null;
        }

        $items = $this->pdo->prepare('
            SELECT pri.*, p.sku, p.name AS product_name
            FROM purchase_request_items pri
            INNER JOIN products p ON p.id = pri.product_id
            WHERE pri.purchase_request_id = :id
            ORDER BY pri.id ASC
        ');
        $items->execute([':id' => $id]);
        $row['items'] = $items->fetchAll();

        return $row;
    }

    public function create(array $payload): int
    {
        $this->pdo->beginTransaction();

        try {
            $stmt = $this->pdo->prepare('
                INSERT INTO purchase_requests
                    (request_number, requester_id, warehouse_id, status, requested_at, needed_at, notes, created_at, updated_at)
                VALUES
                    (:request_number, :requester_id, :warehouse_id, :status, NOW(), :needed_at, :notes, NOW(), NOW())
            ');
            $stmt->execute([
                ':request_number' => $payload['request_number'],
                ':requester_id' => $payload['requester_id'],
                ':warehouse_id' => $payload['warehouse_id'],
                ':status' => $payload['status'] ?? 'SUBMITTED',
                ':needed_at' => $payload['needed_at'] ?? null,
                ':notes' => $payload['notes'] ?? null,
            ]);

            $id = (int)$this->pdo->lastInsertId();

            $itemStmt = $this->pdo->prepare('
                INSERT INTO purchase_request_items
                    (purchase_request_id, product_id, quantity_requested, preferred_unit_cost, notes)
                VALUES
                    (:purchase_request_id, :product_id, :quantity_requested, :preferred_unit_cost, :notes)
            ');

            foreach ($payload['items'] as $item) {
                $itemStmt->execute([
                    ':purchase_request_id' => $id,
                    ':product_id' => $item['product_id'],
                    ':quantity_requested' => $item['quantity_requested'],
                    ':preferred_unit_cost' => $item['preferred_unit_cost'] ?? null,
                    ':notes' => $item['notes'] ?? null,
                ]);
            }

            $this->pdo->commit();
            return $id;
        } catch (Throwable $exception) {
            $this->pdo->rollBack();
            throw $exception;
        }
    }

    public function updateStatus(int $id, string $status): void
    {
        $stmt = $this->pdo->prepare('UPDATE purchase_requests SET status = :status, updated_at = NOW() WHERE id = :id');
        $stmt->execute([':status' => $status, ':id' => $id]);
    }
}