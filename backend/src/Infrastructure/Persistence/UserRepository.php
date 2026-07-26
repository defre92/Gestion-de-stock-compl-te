<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Contracts\UserRepositoryInterface;
use PDO;

final class UserRepository extends PdoCrudRepository implements UserRepositoryInterface
{
    protected string $table = 'users';
    protected array $fillable = ['full_name', 'email', 'password_hash', 'role_id', 'is_active'];
    protected array $filterable = ['email', 'role_id', 'is_active'];

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(100, $perPage));
        $offset = ($page - 1) * $perPage;

        [$whereSql, $params] = $this->buildWhere($filters);

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM users u {$whereSql}");
        $countStmt->execute($params);
        $total = (int)$countStmt->fetchColumn();

        $stmt = $this->pdo->prepare("
            SELECT u.id, u.full_name, u.email, u.is_active, u.created_at, r.code AS role_code
            FROM users u
            INNER JOIN roles r ON r.id = u.role_id
            {$whereSql}
            ORDER BY u.id DESC
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
        $stmt = $this->pdo->prepare("
            SELECT u.id, u.full_name, u.email, u.password_hash, u.role_id, u.is_active, u.created_at, r.code AS role_code
            FROM users u
            INNER JOIN roles r ON r.id = u.role_id
            WHERE u.id = :id
            LIMIT 1
        ");
        $stmt->execute([':id' => $id]);
        $result = $stmt->fetch();

        return $result ?: null;
    }

    public function findByEmail(string $email): ?array
    {
        $stmt = $this->pdo->prepare("
            SELECT u.id, u.full_name, u.email, u.password_hash, u.role_id, u.is_active, r.code AS role_code
            FROM users u
            INNER JOIN roles r ON r.id = u.role_id
            WHERE u.email = :email
            LIMIT 1
        ");
        $stmt->execute([':email' => $email]);
        $result = $stmt->fetch();

        return $result ?: null;
    }

    public function findByTokenHash(string $tokenHash): ?array
    {
        $sql = "
            SELECT u.id, u.full_name, u.email, u.role_id, u.is_active, r.code AS role_code,
                   t.id AS token_id, t.token_hash, t.expires_at
            FROM personal_access_tokens t
            INNER JOIN users u ON u.id = t.user_id
            INNER JOIN roles r ON r.id = u.role_id
            WHERE t.token_hash = :token_hash
              AND (t.expires_at IS NULL OR t.expires_at > NOW())
            LIMIT 1
        ";

        $stmt = $this->pdo->prepare($sql);
        $stmt->execute([':token_hash' => $tokenHash]);
        $result = $stmt->fetch();

        return $result ?: null;
    }

    protected function buildWhere(array $filters): array
    {
        $clauses = [];
        $params = [];

        foreach ($filters as $key => $value) {
            if ($value === null || $value === '' || !in_array($key, $this->filterable, true)) {
                continue;
            }

            $token = ':f_' . $key;
            $clauses[] = 'u.' . $key . ' = ' . $token;
            $params[$token] = $value;
        }

        return [$clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '', $params];
    }
}