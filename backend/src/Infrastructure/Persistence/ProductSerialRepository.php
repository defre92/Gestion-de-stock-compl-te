<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;
use Throwable;

final class ProductSerialRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    /**
     * Recherche/liste paginee. Le filtre 'q' fait une recherche partielle sur
     * le numero de serie (c'est le point d'entree pour "rechercher un article
     * par SN"); les autres filtres sont des correspondances exactes.
     */
    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(200, $perPage));
        $offset = ($page - 1) * $perPage;

        $clauses = [];
        $params = [];

        if (!empty($filters['q'])) {
            $clauses[] = 'ps.serial_number LIKE :q';
            $params[':q'] = '%' . $filters['q'] . '%';
        }
        if (!empty($filters['product_id'])) {
            $clauses[] = 'ps.product_id = :product_id';
            $params[':product_id'] = (int)$filters['product_id'];
        }
        if (!empty($filters['warehouse_id'])) {
            $clauses[] = 'ps.warehouse_id = :warehouse_id';
            $params[':warehouse_id'] = (int)$filters['warehouse_id'];
        }
        if (!empty($filters['status'])) {
            $clauses[] = 'ps.status = :status';
            $params[':status'] = strtoupper((string)$filters['status']);
        }

        $where = $clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '';

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM product_serials ps {$where}");
        $countStmt->execute($params);
        $total = (int)$countStmt->fetchColumn();

        $sql = "
            SELECT ps.*, p.sku, p.name AS product_name, w.name AS warehouse_name
            FROM product_serials ps
            INNER JOIN products p ON p.id = ps.product_id
            LEFT JOIN warehouses w ON w.id = ps.warehouse_id
            {$where}
            ORDER BY ps.id DESC
            LIMIT :limit OFFSET :offset
        ";

        $stmt = $this->pdo->prepare($sql);
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
            SELECT ps.*, p.sku, p.name AS product_name, w.name AS warehouse_name
            FROM product_serials ps
            INNER JOIN products p ON p.id = ps.product_id
            LEFT JOIN warehouses w ON w.id = ps.warehouse_id
            WHERE ps.id = :id
            LIMIT 1
        ');
        $stmt->execute([':id' => $id]);
        $row = $stmt->fetch();

        return $row ?: null;
    }

    public function findBySerialNumber(string $serialNumber): ?array
    {
        $stmt = $this->pdo->prepare('
            SELECT ps.*, p.sku, p.name AS product_name, w.name AS warehouse_name
            FROM product_serials ps
            INNER JOIN products p ON p.id = ps.product_id
            LEFT JOIN warehouses w ON w.id = ps.warehouse_id
            WHERE ps.serial_number = :serial_number
            LIMIT 1
        ');
        $stmt->execute([':serial_number' => $serialNumber]);
        $row = $stmt->fetch();

        return $row ?: null;
    }

    /**
     * Historique des livraisons associees a un numero de serie: repond a
     * "quand et a quel client a ete vendu l'article portant ce SN". Un SN
     * peut apparaitre plusieurs fois (vendu, retourne/remis en stock, revendu).
     *
     * @return array<int, array<string, mixed>>
     */
    public function findDeliveryHistory(int $serialId): array
    {
        $stmt = $this->pdo->prepare('
            SELECT d.id AS delivery_id, d.delivery_number, d.delivered_at, d.status AS delivery_status,
                   c.id AS customer_id, c.name AS customer_name
            FROM delivery_lines dl
            INNER JOIN deliveries d ON d.id = dl.delivery_id
            INNER JOIN customers c ON c.id = d.customer_id
            WHERE dl.serial_id = :serial_id
            ORDER BY d.delivered_at DESC
        ');
        $stmt->execute([':serial_id' => $serialId]);

        return $stmt->fetchAll();
    }

    /**
     * Enregistre plusieurs SN d'un coup (reception d'un lot), pour le meme
     * produit/entrepot. Retourne les ids crees. Toute la liste echoue en bloc
     * si un seul SN est deja utilise (evite un enregistrement partiel silencieux).
     */
    public function createMany(int $productId, ?int $warehouseId, array $serialNumbers, ?int $createdBy): array
    {
        $this->pdo->beginTransaction();

        try {
            $stmt = $this->pdo->prepare('
                INSERT INTO product_serials (product_id, serial_number, warehouse_id, status, created_by, created_at, updated_at)
                VALUES (:product_id, :serial_number, :warehouse_id, \'IN_STOCK\', :created_by, NOW(), NOW())
            ');

            $ids = [];
            foreach ($serialNumbers as $serialNumber) {
                $stmt->execute([
                    ':product_id' => $productId,
                    ':serial_number' => $serialNumber,
                    ':warehouse_id' => $warehouseId,
                    ':created_by' => $createdBy,
                ]);
                $ids[] = (int)$this->pdo->lastInsertId();
            }

            $this->pdo->commit();
            return $ids;
        } catch (Throwable $exception) {
            $this->pdo->rollBack();
            throw $exception;
        }
    }

    public function updateStatus(int $id, string $status, ?int $warehouseId, ?string $notes): void
    {
        $stmt = $this->pdo->prepare('
            UPDATE product_serials
            SET status = :status,
                warehouse_id = :warehouse_id,
                notes = COALESCE(:notes, notes),
                updated_at = NOW()
            WHERE id = :id
        ');
        $stmt->execute([
            ':id' => $id,
            ':status' => $status,
            ':warehouse_id' => $warehouseId,
            ':notes' => $notes,
        ]);
    }

    public function delete(int $id): void
    {
        $stmt = $this->pdo->prepare('DELETE FROM product_serials WHERE id = :id');
        $stmt->execute([':id' => $id]);
    }
}
