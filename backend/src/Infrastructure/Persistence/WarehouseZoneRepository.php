<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class WarehouseZoneRepository extends PdoCrudRepository
{
    protected string $table = 'warehouse_zones';
    protected array $fillable = ['warehouse_id', 'code', 'name'];
    protected array $filterable = ['warehouse_id', 'code', 'name'];
}