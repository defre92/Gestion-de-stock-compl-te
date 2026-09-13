<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class WarehouseLocationRepository extends PdoCrudRepository
{
    protected string $table = 'warehouse_locations';
    protected array $fillable = ['warehouse_id', 'zone_id', 'code', 'description', 'capacity', 'is_active'];
    protected array $filterable = ['warehouse_id', 'zone_id', 'code', 'is_active'];
    protected string $lookupOrderColumn = 'code';

    /** Affiche "Entrepot Principal / Zone A" plutot que "1 / 2". */
    protected array $listLookups = [
        'warehouse_id' => ['table' => 'warehouses', 'column' => 'name', 'as' => 'warehouse_name'],
        'zone_id' => ['table' => 'warehouse_zones', 'column' => 'name', 'as' => 'zone_name'],
    ];
}