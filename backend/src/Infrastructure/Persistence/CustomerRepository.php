<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class CustomerRepository extends PdoCrudRepository
{
    protected string $table = 'customers';
    protected array $fillable = ['code', 'name', 'email', 'phone', 'address', 'status'];
    protected array $filterable = ['code', 'name', 'email', 'status'];
}