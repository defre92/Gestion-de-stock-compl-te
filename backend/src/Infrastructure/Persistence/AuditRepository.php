<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

final class AuditRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function log(?int $userId, string $action, string $entityType, ?int $entityId, array $payload = [], ?string $ipAddress = null): void
    {
        $stmt = $this->pdo->prepare('
            INSERT INTO audits (user_id, action, entity_type, entity_id, payload_json, ip_address, created_at)
            VALUES (:user_id, :action, :entity_type, :entity_id, :payload_json, :ip_address, NOW())
        ');

        $stmt->execute([
            ':user_id' => $userId,
            ':action' => $action,
            ':entity_type' => $entityType,
            ':entity_id' => $entityId,
            ':payload_json' => $payload !== [] ? json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
            ':ip_address' => $ipAddress,
        ]);
    }

    public function clear(): int
    {
        $count = (int)$this->pdo->query('SELECT COUNT(*) FROM audits')->fetchColumn();
        $this->pdo->exec('DELETE FROM audits');

        return $count;
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(200, $perPage));
        $offset = ($page - 1) * $perPage;

        $clauses = [];
        $params = [];

        if (!empty($filters['user_id'])) {
            $clauses[] = 'a.user_id = :user_id';
            $params[':user_id'] = (int)$filters['user_id'];
        }
        if (!empty($filters['action'])) {
            $clauses[] = 'a.action = :action';
            $params[':action'] = (string)$filters['action'];
        }
        if (!empty($filters['entity_type'])) {
            $clauses[] = 'a.entity_type = :entity_type';
            $params[':entity_type'] = (string)$filters['entity_type'];
        }
        if (!empty($filters['date_from'])) {
            $clauses[] = 'a.created_at >= :date_from';
            $params[':date_from'] = (string)$filters['date_from'];
        }
        if (!empty($filters['date_to'])) {
            $clauses[] = 'a.created_at <= :date_to';
            $params[':date_to'] = (string)$filters['date_to'];
        }

        $whereSql = $clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '';

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM audits a {$whereSql}");
        foreach ($params as $key => $value) {
            $countStmt->bindValue($key, $value);
        }
        $countStmt->execute();
        $total = (int)$countStmt->fetchColumn();

        $stmt = $this->pdo->prepare("
            SELECT a.id, a.user_id, u.full_name AS user_name, u.email AS user_email,
                   a.action, a.entity_type, a.entity_id, a.payload_json, a.ip_address, a.created_at
            FROM audits a
            LEFT JOIN users u ON u.id = a.user_id
            {$whereSql}
            ORDER BY a.id DESC
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
}