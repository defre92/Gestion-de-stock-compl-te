<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class WarehouseLocationRepository extends PdoCrudRepository
{
    protected string $table = 'warehouse_locations';
    protected array $fillable = ['warehouse_id', 'zone_id', 'code', 'description', 'capacity', 'is_active'];
    protected array $filterable = ['warehouse_id', 'zone_id', 'code', 'is_active'];
}