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

    /**
     * Annees ou existe au moins une livraison VALIDATED - alimente le
     * selecteur d'annee de la page Statistiques (onglet Rapports). Ordre
     * decroissant : l'annee en cours (ou la plus recente) en premier.
     *
     * @return array<int, int>
     */
    public function salesYears(): array
    {
        $stmt = $this->pdo->query("
            SELECT DISTINCT YEAR(delivered_at) AS y
            FROM deliveries
            WHERE status = 'VALIDATED'
            ORDER BY y DESC
        ");
        return array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));
    }

    /**
     * Statistiques de vente pour la page "Statistiques" de l'onglet Rapports.
     * Se base sur les bons de livraison (deliveries/delivery_lines) : c'est
     * la seule donnee de vente reelle dans l'application (le mouvement de
     * stock "OUT" seul n'a ni client ni prix - une sortie pour casse ou
     * perte n'est pas une vente). Seules les livraisons VALIDATED comptent :
     * une livraison annulee n'a jamais ete une vente effective.
     *
     * @return array<string, mixed>
     */
    public function salesStats(int $year): array
    {
        $summaryStmt = $this->pdo->prepare("
            SELECT
                COALESCE(SUM(d.total_amount), 0) AS revenue,
                COUNT(*) AS deliveries_count,
                COUNT(DISTINCT d.customer_id) AS customers_count
            FROM deliveries d
            WHERE d.status = 'VALIDATED' AND YEAR(d.delivered_at) = :year
        ");
        $summaryStmt->execute([':year' => $year]);
        $summaryRow = $summaryStmt->fetch() ?: ['revenue' => 0, 'deliveries_count' => 0, 'customers_count' => 0];
        $deliveriesCount = (int)$summaryRow['deliveries_count'];
        $revenue = (float)$summaryRow['revenue'];
        $summary = [
            'revenue' => $revenue,
            'deliveries_count' => $deliveriesCount,
            'customers_count' => (int)$summaryRow['customers_count'],
            // Panier moyen : montant moyen d'une livraison cette annee-la.
            // Zero livraison = 0, pas une division par zero.
            'average_basket' => $deliveriesCount > 0 ? $revenue / $deliveriesCount : 0.0,
        ];

        // Chiffre d'affaires mois par mois, les 12 mois presents meme a 0
        // (sinon un graphique "par mois" sauterait les mois sans vente).
        $monthlyStmt = $this->pdo->prepare("
            SELECT MONTH(d.delivered_at) AS month, COALESCE(SUM(d.total_amount), 0) AS revenue
            FROM deliveries d
            WHERE d.status = 'VALIDATED' AND YEAR(d.delivered_at) = :year
            GROUP BY MONTH(d.delivered_at)
        ");
        $monthlyStmt->execute([':year' => $year]);
        $monthlyByMonth = [];
        foreach ($monthlyStmt->fetchAll() as $row) {
            $monthlyByMonth[(int)$row['month']] = (float)$row['revenue'];
        }
        $monthlyRevenue = [];
        for ($month = 1; $month <= 12; $month++) {
            $monthlyRevenue[] = ['month' => $month, 'revenue' => $monthlyByMonth[$month] ?? 0.0];
        }

        // Tendance annuelle (jusqu'a 6 dernieres annees ayant une vente) :
        // vue d'ensemble a cote du detail mensuel de l'annee choisie.
        $yearlyRevenue = $this->pdo->query("
            SELECT YEAR(d.delivered_at) AS year, COALESCE(SUM(d.total_amount), 0) AS revenue
            FROM deliveries d
            WHERE d.status = 'VALIDATED'
            GROUP BY YEAR(d.delivered_at)
            ORDER BY year DESC
            LIMIT 6
        ")->fetchAll();
        $yearlyRevenue = array_reverse(array_map(
            static fn (array $row): array => ['year' => (int)$row['year'], 'revenue' => (float)$row['revenue']],
            $yearlyRevenue
        ));

        $topCustomersStmt = $this->pdo->prepare("
            SELECT c.id AS customer_id, c.name, COALESCE(SUM(d.total_amount), 0) AS revenue, COUNT(*) AS deliveries_count
            FROM deliveries d
            INNER JOIN customers c ON c.id = d.customer_id
            WHERE d.status = 'VALIDATED' AND YEAR(d.delivered_at) = :year
            GROUP BY c.id
            ORDER BY revenue DESC
            LIMIT 10
        ");
        $topCustomersStmt->execute([':year' => $year]);
        $topCustomers = array_map(
            static fn (array $row): array => [
                'customer_id' => (int)$row['customer_id'],
                'name' => (string)$row['name'],
                'revenue' => (float)$row['revenue'],
                'deliveries_count' => (int)$row['deliveries_count'],
            ],
            $topCustomersStmt->fetchAll()
        );

        // Article le plus vendu : classe par quantite (ce qu'on entend
        // spontanement par "le plus vendu"), le CA genere par produit reste
        // affiche a cote a titre d'info.
        $topProductsStmt = $this->pdo->prepare("
            SELECT p.id AS product_id, p.sku, p.name, COALESCE(SUM(dl.quantity), 0) AS qty, COALESCE(SUM(dl.line_total), 0) AS revenue
            FROM delivery_lines dl
            INNER JOIN deliveries d ON d.id = dl.delivery_id
            INNER JOIN products p ON p.id = dl.product_id
            WHERE d.status = 'VALIDATED' AND YEAR(d.delivered_at) = :year
            GROUP BY p.id
            ORDER BY qty DESC
            LIMIT 10
        ");
        $topProductsStmt->execute([':year' => $year]);
        $topProducts = array_map(
            static fn (array $row): array => [
                'product_id' => (int)$row['product_id'],
                'sku' => (string)$row['sku'],
                'name' => (string)$row['name'],
                'qty' => (int)$row['qty'],
                'revenue' => (float)$row['revenue'],
            ],
            $topProductsStmt->fetchAll()
        );

        return [
            'year' => $year,
            'summary' => $summary,
            'monthly_revenue' => $monthlyRevenue,
            'yearly_revenue' => $yearlyRevenue,
            'top_customers' => $topCustomers,
            'top_products' => $topProducts,
        ];
    }

    /**
     * Meme principe que salesStats() mais restreint a un mois donne, avec
     * une repartition jour par jour au lieu de mois par mois - alimente
     * l'export CSV "stats du mois" de la page Statistiques.
     *
     * @return array<string, mixed>
     */
    public function salesStatsMonth(int $year, int $month): array
    {
        $summaryStmt = $this->pdo->prepare("
            SELECT
                COALESCE(SUM(d.total_amount), 0) AS revenue,
                COUNT(*) AS deliveries_count,
                COUNT(DISTINCT d.customer_id) AS customers_count
            FROM deliveries d
            WHERE d.status = 'VALIDATED' AND YEAR(d.delivered_at) = :year AND MONTH(d.delivered_at) = :month
        ");
        $summaryStmt->execute([':year' => $year, ':month' => $month]);
        $summaryRow = $summaryStmt->fetch() ?: ['revenue' => 0, 'deliveries_count' => 0, 'customers_count' => 0];
        $deliveriesCount = (int)$summaryRow['deliveries_count'];
        $revenue = (float)$summaryRow['revenue'];
        $summary = [
            'revenue' => $revenue,
            'deliveries_count' => $deliveriesCount,
            'customers_count' => (int)$summaryRow['customers_count'],
            'average_basket' => $deliveriesCount > 0 ? $revenue / $deliveriesCount : 0.0,
        ];

        // Repartition jour par jour, tous les jours du mois presents meme a
        // 0 (meme raisonnement que la repartition mois par mois de l'annee).
        $daysInMonth = (int)date('t', mktime(0, 0, 0, $month, 1, $year));
        $dailyStmt = $this->pdo->prepare("
            SELECT DAY(d.delivered_at) AS day, COALESCE(SUM(d.total_amount), 0) AS revenue
            FROM deliveries d
            WHERE d.status = 'VALIDATED' AND YEAR(d.delivered_at) = :year AND MONTH(d.delivered_at) = :month
            GROUP BY DAY(d.delivered_at)
        ");
        $dailyStmt->execute([':year' => $year, ':month' => $month]);
        $dailyByDay = [];
        foreach ($dailyStmt->fetchAll() as $row) {
            $dailyByDay[(int)$row['day']] = (float)$row['revenue'];
        }
        $dailyRevenue = [];
        for ($day = 1; $day <= $daysInMonth; $day++) {
            $dailyRevenue[] = ['day' => $day, 'revenue' => $dailyByDay[$day] ?? 0.0];
        }

        $topCustomersStmt = $this->pdo->prepare("
            SELECT c.id AS customer_id, c.name, COALESCE(SUM(d.total_amount), 0) AS revenue, COUNT(*) AS deliveries_count
            FROM deliveries d
            INNER JOIN customers c ON c.id = d.customer_id
            WHERE d.status = 'VALIDATED' AND YEAR(d.delivered_at) = :year AND MONTH(d.delivered_at) = :month
            GROUP BY c.id
            ORDER BY revenue DESC
            LIMIT 10
        ");
        $topCustomersStmt->execute([':year' => $year, ':month' => $month]);
        $topCustomers = array_map(
            static fn (array $row): array => [
                'customer_id' => (int)$row['customer_id'],
                'name' => (string)$row['name'],
                'revenue' => (float)$row['revenue'],
                'deliveries_count' => (int)$row['deliveries_count'],
            ],
            $topCustomersStmt->fetchAll()
        );

        $topProductsStmt = $this->pdo->prepare("
            SELECT p.id AS product_id, p.sku, p.name, COALESCE(SUM(dl.quantity), 0) AS qty, COALESCE(SUM(dl.line_total), 0) AS revenue
            FROM delivery_lines dl
            INNER JOIN deliveries d ON d.id = dl.delivery_id
            INNER JOIN products p ON p.id = dl.product_id
            WHERE d.status = 'VALIDATED' AND YEAR(d.delivered_at) = :year AND MONTH(d.delivered_at) = :month
            GROUP BY p.id
            ORDER BY qty DESC
            LIMIT 10
        ");
        $topProductsStmt->execute([':year' => $year, ':month' => $month]);
        $topProducts = array_map(
            static fn (array $row): array => [
                'product_id' => (int)$row['product_id'],
                'sku' => (string)$row['sku'],
                'name' => (string)$row['name'],
                'qty' => (int)$row['qty'],
                'revenue' => (float)$row['revenue'],
            ],
            $topProductsStmt->fetchAll()
        );

        return [
            'year' => $year,
            'month' => $month,
            'summary' => $summary,
            'daily_revenue' => $dailyRevenue,
            'top_customers' => $topCustomers,
            'top_products' => $topProducts,
        ];
    }
}