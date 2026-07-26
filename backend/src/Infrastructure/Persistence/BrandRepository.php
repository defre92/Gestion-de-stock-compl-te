<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class BrandRepository extends PdoCrudRepository
{
    protected string $table = 'brands';
    protected array $fillable = ['name', 'description'];
    protected array $filterable = ['name'];
}