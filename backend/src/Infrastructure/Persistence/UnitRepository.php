<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class UnitRepository extends PdoCrudRepository
{
    protected string $table = 'units';
    protected array $fillable = ['code', 'name', 'symbol', 'base_unit', 'conversion_factor', 'is_active'];
    protected array $filterable = ['code', 'name', 'is_active'];
}