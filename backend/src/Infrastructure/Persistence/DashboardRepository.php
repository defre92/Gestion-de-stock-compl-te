<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

final class DashboardRepository
{
    private PDO $pdo;
    /** @var array<string, bool> */
    private array $tableExistsCache = [];
    /** @var array<string, bool> */
    private array $columnExistsCache = [];

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function stats(): array
    {
        // On calcule les KPI avec des garde-fous pour eviter les erreurs SQL
        // si certaines tables/colonnes ne sont pas encore migrees.
        $totals = [
            'products' => $this->tableExists('products') ? $this->safeScalar('SELECT COUNT(*) FROM products', 0) : 0,
            'categories' => $this->tableExists('categories') ? $this->safeScalar('SELECT COUNT(*) FROM categories', 0) : 0,
            'suppliers' => $this->tableExists('suppliers') ? $this->safeScalar('SELECT COUNT(*) FROM suppliers', 0) : 0,
            'warehouses' => $this->tableExists('warehouses') ? $this->safeScalar('SELECT COUNT(*) FROM warehouses', 0) : 0,
            'users' => $this->tableExists('users') ? $this->safeScalar('SELECT COUNT(*) FROM users WHERE is_active = 1', 0) : 0,
            'purchase_orders_pending' => $this->tableExists('purchase_orders')
                ? $this->safeScalar("SELECT COUNT(*) FROM purchase_orders WHERE status IN ('PENDING', 'PARTIAL')", 0)
                : 0,
            'purchase_requests_open' => $this->tableExists('purchase_requests')
                ? $this->safeScalar("SELECT COUNT(*) FROM purchase_requests WHERE status IN ('DRAFT', 'SUBMITTED', 'APPROVED')", 0)
                : 0,
        ];

        $totals['stock_value'] = ($this->tableExists('stock_levels') && $this->tableExists('products'))
            ? (float)$this->safeScalar('SELECT COALESCE(SUM(sl.quantity * p.cost_price),0) FROM stock_levels sl INNER JOIN products p ON p.id = sl.product_id', 0)
            : 0.0;
        $totals['out_of_stock'] = ($this->tableExists('stock_levels') && $this->tableExists('products'))
            ? $this->safeScalar('SELECT COUNT(*) FROM (SELECT p.id, COALESCE(SUM(sl.quantity),0) qty FROM products p LEFT JOIN stock_levels sl ON sl.product_id=p.id GROUP BY p.id HAVING qty <= 0) t', 0)
            : 0;
        $hasMinStock = $this->columnExists('products', 'min_stock');
        if ($this->tableExists('stock_levels') && $this->tableExists('products')) {
            $lowStockSql = $hasMinStock
                ? 'SELECT COUNT(*) FROM (SELECT p.id, COALESCE(SUM(sl.quantity),0) qty FROM products p LEFT JOIN stock_levels sl ON sl.product_id=p.id GROUP BY p.id HAVING qty <= GREATEST(MAX(COALESCE(p.min_stock,0)), MAX(COALESCE(p.reorder_level,0)))) t'
                : 'SELECT COUNT(*) FROM (SELECT p.id, COALESCE(SUM(sl.quantity),0) qty FROM products p LEFT JOIN stock_levels sl ON sl.product_id=p.id GROUP BY p.id HAVING qty <= MAX(COALESCE(p.reorder_level,0))) t';
            $totals['low_stock'] = $this->safeScalar($lowStockSql, 0);
        } else {
            $totals['low_stock'] = 0;
        }
        $totals['delayed_po'] = $this->tableExists('purchase_orders')
            ? $this->safeScalar("SELECT COUNT(*) FROM purchase_orders WHERE status IN ('PENDING','PARTIAL') AND expected_at IS NOT NULL AND expected_at < NOW()", 0)
            : 0;

        $recentMovements = [];
        if ($this->tableExists('stock_movements') && $this->tableExists('products') && $this->tableExists('warehouses')) {
            $hasDestinationWarehouse = $this->columnExists('stock_movements', 'destination_warehouse_id');
            $hasWarehouseCode = $this->columnExists('warehouses', 'code');
            $warehouseLabel = $hasWarehouseCode ? 'w.code' : 'w.name';
            $destinationWarehouseLabel = $hasWarehouseCode ? 'dw.code' : 'dw.name';
            $destinationJoin = $hasDestinationWarehouse ? 'LEFT JOIN warehouses dw ON dw.id = sm.destination_warehouse_id' : '';
            $destinationColumn = $hasDestinationWarehouse ? "{$destinationWarehouseLabel} AS destination_warehouse_code" : "'' AS destination_warehouse_code";

            $recentMovements = $this->safeRows("
                SELECT sm.id, sm.type, sm.quantity, sm.created_at, p.sku, p.name AS product_name,
                       {$warehouseLabel} AS warehouse_code, {$destinationColumn}
                FROM stock_movements sm
                INNER JOIN products p ON p.id = sm.product_id
                INNER JOIN warehouses w ON w.id = sm.warehouse_id
                {$destinationJoin}
                ORDER BY sm.id DESC
                LIMIT 12
            ");
        }

        $topOutgoing = [];
        if ($this->tableExists('stock_movements') && $this->tableExists('products')) {
            $topOutgoing = $this->safeRows("
                SELECT p.sku, p.name, COALESCE(SUM(sm.quantity),0) AS qty_out
                FROM stock_movements sm
                INNER JOIN products p ON p.id = sm.product_id
                WHERE sm.type IN ('OUT', 'TRANSFER')
                GROUP BY p.id
                ORDER BY qty_out DESC
                LIMIT 10
            ");
        }

        return [
            'totals' => $totals,
            'recent_movements' => $recentMovements,
            'low_stock' => $this->tableExists('products') ? (new ProductRepository())->lowStock() : [],
            'top_outgoing' => $topOutgoing,
        ];
    }

    private function safeScalar(string $sql, int|float $default): int|float
    {
        try {
            $value = $this->pdo->query($sql)->fetchColumn();
            if (is_int($default)) {
                return (int)$value;
            }
            return (float)$value;
        } catch (\Throwable) {
            return $default;
        }
    }

    /** @return array<int, array<string, mixed>> */
    private function safeRows(string $sql): array
    {
        // Retourne une liste vide en cas d'erreur: l'ecran reste utilisable.
        try {
            return $this->pdo->query($sql)->fetchAll();
        } catch (\Throwable) {
            return [];
        }
    }

    private function tableExists(string $table): bool
    {
        // Cache memo pour ne pas re-interroger information_schema a chaque appel.
        if (array_key_exists($table, $this->tableExistsCache)) {
            return $this->tableExistsCache[$table];
        }

        $stmt = $this->pdo->prepare('
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
              AND table_name = :table_name
        ');
        $stmt->execute([':table_name' => $table]);
        $exists = (int)$stmt->fetchColumn() > 0;
        $this->tableExistsCache[$table] = $exists;
        return $exists;
    }

    private function columnExists(string $table, string $column): bool
    {
        // Meme logique de cache pour les colonnes.
        $key = $table . '.' . $column;
        if (array_key_exists($key, $this->columnExistsCache)) {
            return $this->columnExistsCache[$key];
        }

        if (!$this->tableExists($table)) {
            $this->columnExistsCache[$key] = false;
            return false;
        }

        $stmt = $this->pdo->prepare('
            SELECT COUNT(*)
            FROM information_schema.columns
            WHERE table_schema = DATABASE()
              AND table_name = :table_name
              AND column_name = :column_name
        ');
        $stmt->execute([
            ':table_name' => $table,
            ':column_name' => $column,
        ]);

        $exists = (int)$stmt->fetchColumn() > 0;
        $this->columnExistsCache[$key] = $exists;
        return $exists;
    }
}
