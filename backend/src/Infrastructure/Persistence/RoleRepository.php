<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

final class RoleRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function idByCode(string $code): ?int
    {
        $stmt = $this->pdo->prepare('SELECT id FROM roles WHERE code = :code LIMIT 1');
        $stmt->execute([':code' => strtoupper($code)]);

        $id = $stmt->fetchColumn();
        return $id === false ? null : (int)$id;
    }

    public function all(): array
    {
        return $this->pdo->query('SELECT id, code, label FROM roles ORDER BY id ASC')->fetchAll();
    }
}