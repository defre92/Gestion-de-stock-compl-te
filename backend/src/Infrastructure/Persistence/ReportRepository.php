<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

final class ReportRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function stockSnapshot(): array
    {
        return $this->pdo->query('
            SELECT p.sku, p.name, c.name AS category, w.code AS warehouse_code, w.name AS warehouse_name,
                   sl.quantity, p.cost_price, (sl.quantity * p.cost_price) AS stock_value
            FROM stock_levels sl
            INNER JOIN products p ON p.id = sl.product_id
            LEFT JOIN categories c ON c.id = p.category_id
            INNER JOIN warehouses w ON w.id = sl.warehouse_id
            ORDER BY p.name ASC
        ')->fetchAll();
    }

    public function movementJournal(): array
    {
        return $this->pdo->query('
            SELECT sm.created_at, sm.type, sm.reason_code, p.sku, p.name AS product_name,
                   w.code AS source_warehouse, dw.code AS destination_warehouse,
                   sm.quantity, sm.balance_after, u.full_name AS moved_by
            FROM stock_movements sm
            INNER JOIN products p ON p.id = sm.product_id
            INNER JOIN warehouses w ON w.id = sm.warehouse_id
            LEFT JOIN warehouses dw ON dw.id = sm.destination_warehouse_id
            LEFT JOIN users u ON u.id = sm.moved_by
            ORDER BY sm.id DESC
        ')->fetchAll();
    }

    public function purchaseSummary(): array
    {
        return $this->pdo->query('
            SELECT po.order_number, po.status, po.ordered_at, po.expected_at, po.total_amount,
                   s.name AS supplier_name, w.name AS warehouse_name
            FROM purchase_orders po
            INNER JOIN suppliers s ON s.id = po.supplier_id
            INNER JOIN warehouses w ON w.id = po.warehouse_id
            ORDER BY po.id DESC
        ')->fetchAll();
    }
}