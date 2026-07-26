<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class TagRepository extends PdoCrudRepository
{
    protected string $table = 'tags';
    protected array $fillable = ['name', 'color'];
    protected array $filterable = ['name'];
}