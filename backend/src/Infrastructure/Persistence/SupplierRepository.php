<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class SupplierRepository extends PdoCrudRepository
{
    protected string $table = 'suppliers';
    protected array $fillable = [
        'name',
        'contact_name',
        'phone',
        'email',
        'address',
        'lead_time_days',
        'payment_terms',
        'website',
        'status',
    ];
    protected array $filterable = ['name', 'email', 'status'];
}