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

    public function productCatalog(): array
    {
        return $this->pdo->query('
            SELECT p.sku, p.barcode, p.name, c.name AS category, b.name AS brand,
                   s.name AS supplier, u.name AS unit, p.unit_price, p.cost_price,
                   p.reorder_level, p.min_stock, p.max_stock, p.status, p.is_active
            FROM products p
            LEFT JOIN categories c ON c.id = p.category_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN suppliers s ON s.id = p.supplier_id
            LEFT JOIN units u ON u.id = p.unit_id
            ORDER BY p.name ASC
        ')->fetchAll();
    }

    public function supplierList(): array
    {
        return $this->pdo->query('
            SELECT name, contact_name, phone, email, address, lead_time_days, payment_terms, website, status
            FROM suppliers
            ORDER BY name ASC
        ')->fetchAll();
    }

    public function customerList(): array
    {
        return $this->pdo->query('
            SELECT code, name, email, phone, address, status
            FROM customers
            ORDER BY name ASC
        ')->fetchAll();
    }

    public function deliveryJournal(): array
    {
        return $this->pdo->query('
            SELECT d.delivery_number, c.name AS customer_name, w.name AS warehouse_name,
                   d.status, d.total_amount, d.delivered_at
            FROM deliveries d
            INNER JOIN customers c ON c.id = d.customer_id
            INNER JOIN warehouses w ON w.id = d.warehouse_id
            ORDER BY d.id DESC
        ')->fetchAll();
    }

    public function inventorySessions(): array
    {
        return $this->pdo->query('
            SELECT i.code, w.name AS warehouse_name, i.status, i.counting_mode,
                   i.started_at, i.ended_at, u.full_name AS created_by
            FROM inventory_sessions i
            INNER JOIN warehouses w ON w.id = i.warehouse_id
            INNER JOIN users u ON u.id = i.created_by
            ORDER BY i.id DESC
        ')->fetchAll();
    }
}