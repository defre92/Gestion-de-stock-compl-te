<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class CategoryRepository extends PdoCrudRepository
{
    protected string $table = 'categories';
    protected array $fillable = [
        'parent_id',
        'name',
        'description',
        'default_min_stock',
        'default_max_stock',
        'default_tax_id',
        'tags_json',
    ];
    protected array $filterable = ['name', 'parent_id', 'default_tax_id'];
}