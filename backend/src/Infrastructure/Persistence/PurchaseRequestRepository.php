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

    /**
     * Statuts terminaux d'une demande d'achat : elle est convertie en commande
     * ou refusee, il n'y a plus rien a en faire. Ce sont ces demandes que
     * l'ecran range dans "Demandes passees" pour ne pas encombrer la liste de
     * travail au bout de quelques mois d'utilisation.
     */
    private const ARCHIVED_STATUSES = ['CONVERTED', 'REJECTED'];

    /**
     * @param array{scope?: string, status?: string} $filters
     *   scope: 'open' (defaut) = demandes encore a traiter, 'archived' =
     *   converties/refusees, 'all' = tout. status: filtre exact supplementaire.
     */
    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(100, $perPage));
        $offset = ($page - 1) * $perPage;

        $scope = strtolower((string)($filters['scope'] ?? 'all'));
        if (!in_array($scope, ['open', 'archived', 'all'], true)) {
            $scope = 'all';
        }

        $placeholders = [];
        foreach (self::ARCHIVED_STATUSES as $index => $status) {
            $placeholders[':archived' . $index] = $status;
        }
        $inList = implode(', ', array_keys($placeholders));

        $conditions = [];
        $params = [];
        if ($scope === 'open') {
            $conditions[] = "pr.status NOT IN ({$inList})";
            $params += $placeholders;
        } elseif ($scope === 'archived') {
            $conditions[] = "pr.status IN ({$inList})";
            $params += $placeholders;
        }

        $status = trim((string)($filters['status'] ?? ''));
        if ($status !== '') {
            $conditions[] = 'pr.status = :status';
            $params[':status'] = strtoupper($status);
        }

        $whereSql = $conditions === [] ? '' : 'WHERE ' . implode(' AND ', $conditions);

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM purchase_requests pr {$whereSql}");
        $countStmt->execute($params);
        $total = (int)$countStmt->fetchColumn();

        // Compteurs des deux vues, pour que le bouton de bascule puisse
        // annoncer combien de demandes il cache ou revele sans second appel.
        $openTotal = (int)$this->pdo->query(
            'SELECT COUNT(*) FROM purchase_requests WHERE status NOT IN (' . $this->quotedArchivedStatuses() . ')'
        )->fetchColumn();
        $archivedTotal = (int)$this->pdo->query(
            'SELECT COUNT(*) FROM purchase_requests WHERE status IN (' . $this->quotedArchivedStatuses() . ')'
        )->fetchColumn();

        $stmt = $this->pdo->prepare("
            SELECT pr.*, u.full_name AS requester_name, w.name AS warehouse_name
            FROM purchase_requests pr
            INNER JOIN users u ON u.id = pr.requester_id
            INNER JOIN warehouses w ON w.id = pr.warehouse_id
            {$whereSql}
            ORDER BY pr.id DESC
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
                'scope' => $scope,
                'open_total' => $openTotal,
                'archived_total' => $archivedTotal,
            ],
        ];
    }

    /** Liste SQL des statuts terminaux, pour les deux COUNT sans parametres. */
    private function quotedArchivedStatuses(): string
    {
        return implode(', ', array_map(
            fn (string $status): string => $this->pdo->quote($status),
            self::ARCHIVED_STATUSES
        ));
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
            SELECT pri.*, p.sku, p.name AS product_name,
                   v.sku AS variant_sku, v.size AS variant_size, v.color AS variant_color, v.vintage AS variant_vintage, v.volume_cl AS variant_volume_cl, v.width AS variant_width, v.height AS variant_height, v.depth AS variant_depth, v.weight AS variant_weight
            FROM purchase_request_items pri
            INNER JOIN products p ON p.id = pri.product_id
            LEFT JOIN product_variants v ON v.id = pri.variant_id
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
                    (purchase_request_id, product_id, variant_id, quantity_requested, preferred_unit_cost, notes)
                VALUES
                    (:purchase_request_id, :product_id, :variant_id, :quantity_requested, :preferred_unit_cost, :notes)
            ');

            foreach ($payload['items'] as $item) {
                $itemStmt->execute([
                    ':purchase_request_id' => $id,
                    ':product_id' => $item['product_id'],
                    ':variant_id' => $item['variant_id'] ?? null,
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