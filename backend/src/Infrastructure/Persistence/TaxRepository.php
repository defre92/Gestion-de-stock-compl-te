<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class TaxRepository extends PdoCrudRepository
{
    protected string $table = 'taxes';
    protected array $fillable = ['code', 'name', 'rate', 'is_default'];
    protected array $filterable = ['code', 'name', 'is_default'];
}