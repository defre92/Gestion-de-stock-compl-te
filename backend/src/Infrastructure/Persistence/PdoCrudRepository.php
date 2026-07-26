<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Contracts\CrudRepositoryInterface;
use App\Shared\Database\Database;
use PDO;

abstract class PdoCrudRepository implements CrudRepositoryInterface
{
    protected PDO $pdo;
    protected string $table;

    /** @var array<int, string> */
    protected array $fillable = [];

    /** @var array<int, string> */
    protected array $filterable = [];

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(100, $perPage));
        $offset = ($page - 1) * $perPage;

        [$whereSql, $params] = $this->buildWhere($filters);

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM {$this->table} {$whereSql}");
        $countStmt->execute($params);
        $total = (int)$countStmt->fetchColumn();

        $stmt = $this->pdo->prepare("SELECT * FROM {$this->table} {$whereSql} ORDER BY id DESC LIMIT :limit OFFSET :offset");
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
        $stmt = $this->pdo->prepare("SELECT * FROM {$this->table} WHERE id = :id LIMIT 1");
        $stmt->execute([':id' => $id]);

        $result = $stmt->fetch();
        return $result ?: null;
    }

    public function create(array $payload): int
    {
        $data = $this->sanitizePayload($payload);
        if ($data === []) {
            return 0;
        }

        $columns = implode(', ', array_keys($data));
        $tokens = implode(', ', array_map(static fn (string $key): string => ':' . $key, array_keys($data)));
        $sql = "INSERT INTO {$this->table} ({$columns}) VALUES ({$tokens})";

        $stmt = $this->pdo->prepare($sql);
        $stmt->execute($this->prefixKeys($data));

        return (int)$this->pdo->lastInsertId();
    }

    public function update(int $id, array $payload): bool
    {
        $data = $this->sanitizePayload($payload);
        if ($data === []) {
            return false;
        }

        $sets = implode(', ', array_map(static fn (string $key): string => $key . ' = :' . $key, array_keys($data)));
        $sql = "UPDATE {$this->table} SET {$sets} WHERE id = :id";

        $stmt = $this->pdo->prepare($sql);
        return $stmt->execute(array_merge($this->prefixKeys($data), [':id' => $id]));
    }

    public function delete(int $id): bool
    {
        $stmt = $this->pdo->prepare("DELETE FROM {$this->table} WHERE id = :id");
        return $stmt->execute([':id' => $id]);
    }

    /** @return array{0: string, 1: array<string, mixed>} */
    protected function buildWhere(array $filters): array
    {
        $clauses = [];
        $params = [];

        foreach ($filters as $key => $value) {
            if ($value === null || $value === '' || !in_array($key, $this->filterable, true)) {
                continue;
            }

            $token = ':f_' . $key;
            $clauses[] = "{$key} = {$token}";
            $params[$token] = $value;
        }

        $whereSql = $clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '';
        return [$whereSql, $params];
    }

    /** @return array<string, mixed> */
    protected function sanitizePayload(array $payload): array
    {
        $data = [];
        foreach ($this->fillable as $key) {
            if (array_key_exists($key, $payload)) {
                // Un champ optionnel laisse vide (select non renseigne, date vide, etc.)
                // est omis plutot qu'envoye tel quel: cela laisse MySQL appliquer sa
                // valeur par defaut (colonne NOT NULL DEFAULT ...) ou NULL (colonne
                // nullable), au lieu de plainter avec une erreur SQL brute ('' dans une
                // colonne INT/DATE/ENUM, ou NULL explicite dans une colonne NOT NULL).
                if ($payload[$key] === '') {
                    continue;
                }
                $data[$key] = $payload[$key];
            }
        }

        return $data;
    }

    /** @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    protected function prefixKeys(array $data): array
    {
        $prefixed = [];
        foreach ($data as $key => $value) {
            $prefixed[':' . $key] = $value;
        }

        return $prefixed;
    }
}