<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class WarehouseRepository extends PdoCrudRepository
{
    protected string $table = 'warehouses';
    protected array $fillable = ['code', 'name', 'location', 'is_default', 'status'];
    protected array $filterable = ['code', 'name', 'is_default', 'status'];

    public function defaultWarehouseId(): ?int
    {
        $stmt = $this->pdo->query('SELECT id FROM warehouses WHERE is_default = 1 ORDER BY id ASC LIMIT 1');
        $id = $stmt->fetchColumn();

        return $id === false ? null : (int)$id;
    }
}