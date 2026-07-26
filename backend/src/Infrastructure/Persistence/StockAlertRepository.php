<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class StockAlertRepository extends PdoCrudRepository
{
    protected string $table = 'stock_alerts';
    protected array $fillable = [
        'alert_type',
        'severity',
        'product_id',
        'purchase_order_id',
        'warehouse_id',
        'message',
        'status',
        'resolved_at',
        'resolved_by',
    ];
    protected array $filterable = ['alert_type', 'severity', 'status', 'warehouse_id'];
}