<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use PDO;

final class ProductRepository extends PdoCrudRepository
{
    /** @var array<string, bool> */
    private static array $columnExistsCache = [];

    protected string $table = 'products';
    protected array $fillable = [
        'sku',
        'barcode',
        'name',
        'description',
        'category_id',
        'supplier_id',
        'unit_id',
        'brand_id',
        'tax_id',
        'pack_size',
        'weight_kg',
        'width_cm',
        'height_cm',
        'depth_cm',
        'unit_price',
        'cost_price',
        'reorder_level',
        'min_stock',
        'max_stock',
        'safety_stock',
        'valuation_method',
        'status',
        'has_variants',
        'is_active',
    ];
    protected array $filterable = ['category_id', 'supplier_id', 'status', 'is_active', 'brand_id', 'unit_id'];

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(100, $perPage));
        $offset = ($page - 1) * $perPage;

        [$whereSql, $params] = $this->buildWhere($filters);

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM products p {$whereSql}");
        $countStmt->execute($params);
        $total = (int)$countStmt->fetchColumn();

        $sql = "
            SELECT
                p.*,
                c.name AS category_name,
                s.name AS supplier_name,
                u.code AS unit_code,
                b.name AS brand_name,
                t.rate AS tax_rate,
                COALESCE(SUM(sl.quantity), 0) AS stock_total
            FROM products p
            LEFT JOIN categories c ON c.id = p.category_id
            LEFT JOIN suppliers s ON s.id = p.supplier_id
            LEFT JOIN units u ON u.id = p.unit_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN taxes t ON t.id = p.tax_id
            LEFT JOIN stock_levels sl ON sl.product_id = p.id
            {$whereSql}
            GROUP BY p.id
            ORDER BY p.id DESC
            LIMIT :limit OFFSET :offset
        ";

        $stmt = $this->pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value);
        }
        $stmt->bindValue(':limit', $perPage, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();

        $rows = $stmt->fetchAll();
        $this->attachTags($rows);

        return [
            'data' => $rows,
            'meta' => [
                'page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'last_page' => (int)max(1, ceil($total / $perPage)),
            ],
        ];
    }

    public function findById(int $id): ?array
    {
        $stmt = $this->pdo->prepare('
            SELECT p.*, c.name AS category_name, s.name AS supplier_name, u.code AS unit_code,
                   b.name AS brand_name, t.rate AS tax_rate,
                   COALESCE(SUM(sl.quantity), 0) AS stock_total
            FROM products p
            LEFT JOIN categories c ON c.id = p.category_id
            LEFT JOIN suppliers s ON s.id = p.supplier_id
            LEFT JOIN units u ON u.id = p.unit_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN taxes t ON t.id = p.tax_id
            LEFT JOIN stock_levels sl ON sl.product_id = p.id
            WHERE p.id = :id
            GROUP BY p.id
            LIMIT 1
        ');
        $stmt->execute([':id' => $id]);
        $result = $stmt->fetch();

        if (!$result) {
            return null;
        }

        $mediaStmt = $this->pdo->prepare('SELECT * FROM product_media WHERE product_id = :id ORDER BY id DESC');
        $mediaStmt->execute([':id' => $id]);
        $result['media'] = $mediaStmt->fetchAll();

        $whStmt = $this->pdo->prepare('
            SELECT sl.warehouse_id, sl.variant_id, w.code AS warehouse_code, w.name AS warehouse_name,
                   sl.quantity, sl.reserved_quantity,
                   v.sku AS variant_sku, v.size AS variant_size, v.color AS variant_color, v.vintage AS variant_vintage, v.volume_cl AS variant_volume_cl
            FROM stock_levels sl
            INNER JOIN warehouses w ON w.id = sl.warehouse_id
            LEFT JOIN product_variants v ON v.id = sl.variant_id
            WHERE sl.product_id = :id
            ORDER BY w.name ASC, v.size ASC, v.color ASC
        ');
        $whStmt->execute([':id' => $id]);
        $result['stock_by_warehouse'] = array_map(static function (array $row): array {
            $descriptors = array_filter([$row['variant_size'] ?? null, $row['variant_color'] ?? null]);
            $row['variant_label'] = $row['variant_id'] !== null
                ? ($descriptors !== [] ? implode(' / ', $descriptors) : ($row['variant_sku'] ?? '-'))
                : null;
            return $row;
        }, $whStmt->fetchAll());

        $tagStmt = $this->pdo->prepare('
            SELECT t.id, t.name, t.color
            FROM product_tags pt
            INNER JOIN tags t ON t.id = pt.tag_id
            WHERE pt.product_id = :id
            ORDER BY t.name ASC
        ');
        $tagStmt->execute([':id' => $id]);
        $result['tags'] = $tagStmt->fetchAll();

        if ((int)($result['has_variants'] ?? 0) === 1) {
            $variantStmt = $this->pdo->prepare('
                SELECT v.*, COALESCE(SUM(sl.quantity), 0) AS stock_total
                FROM product_variants v
                LEFT JOIN stock_levels sl ON sl.variant_id = v.id
                WHERE v.product_id = :id
                GROUP BY v.id
                ORDER BY v.size ASC, v.color ASC
            ');
            $variantStmt->execute([':id' => $id]);
            $result['variants'] = $variantStmt->fetchAll();
        }

        return $result;
    }

    /**
     * Attache la liste des tags a chaque ligne produit en une seule requete
     * (evite le N+1 quand on affiche un tableau de plusieurs produits).
     *
     * @param array<int, array<string, mixed>> $rows
     */
    private function attachTags(array &$rows): void
    {
        if ($rows === []) {
            return;
        }

        $ids = array_map(static fn (array $row): int => (int)$row['id'], $rows);
        $placeholders = implode(', ', array_fill(0, count($ids), '?'));

        $stmt = $this->pdo->prepare("
            SELECT pt.product_id, t.id, t.name, t.color
            FROM product_tags pt
            INNER JOIN tags t ON t.id = pt.tag_id
            WHERE pt.product_id IN ({$placeholders})
            ORDER BY t.name ASC
        ");
        $stmt->execute($ids);

        $byProduct = [];
        foreach ($stmt->fetchAll() as $tagRow) {
            $byProduct[(int)$tagRow['product_id']][] = [
                'id' => $tagRow['id'],
                'name' => $tagRow['name'],
                'color' => $tagRow['color'],
            ];
        }

        foreach ($rows as &$row) {
            $row['tags'] = $byProduct[(int)$row['id']] ?? [];
        }
        unset($row);
    }

    public function lowStock(): array
    {
        // Requete compatible MySQL/MariaDB avec GROUP BY (MAX dans HAVING).
        $hasMinStock = $this->columnExists('products', 'min_stock');
        $hasIsActive = $this->columnExists('products', 'is_active');

        $where = $hasIsActive ? 'WHERE p.is_active = 1' : '';
        $having = $hasMinStock
            ? 'HAVING stock_total <= GREATEST(MAX(COALESCE(p.min_stock, 0)), MAX(COALESCE(p.reorder_level, 0)))'
            : 'HAVING stock_total <= MAX(COALESCE(p.reorder_level, 0))';

        $sql = "
            SELECT p.id, p.sku, p.name,
                   " . ($hasMinStock ? "MAX(COALESCE(p.min_stock, 0))" : "0") . " AS min_stock,
                   MAX(COALESCE(p.reorder_level, 0)) AS reorder_level,
                   COALESCE(SUM(sl.quantity), 0) AS stock_total
            FROM products p
            LEFT JOIN stock_levels sl ON sl.product_id = p.id
            {$where}
            GROUP BY p.id
            {$having}
            ORDER BY stock_total ASC
        ";

        return $this->pdo->query($sql)->fetchAll();
    }

    public function stockLevel(int $productId, int $warehouseId, ?int $variantId = null): ?array
    {
        $sql = 'SELECT warehouse_id, quantity FROM stock_levels WHERE product_id = :product_id AND warehouse_id = :warehouse_id AND variant_id '
            . ($variantId !== null ? '= :variant_id' : 'IS NULL') . ' LIMIT 1';
        $stmt = $this->pdo->prepare($sql);
        $params = [':product_id' => $productId, ':warehouse_id' => $warehouseId];
        if ($variantId !== null) {
            $params[':variant_id'] = $variantId;
        }
        $stmt->execute($params);
        $row = $stmt->fetch();

        if (!$row) {
            return null;
        }

        return ['warehouse_id' => (int)$row['warehouse_id'], 'quantity' => (int)$row['quantity']];
    }

    public function upsertStockLevel(int $productId, int $warehouseId, int $quantity, ?int $variantId = null): void
    {
        // ON DUPLICATE KEY UPDATE s'appuie sur uq_stock_level (product_id,
        // warehouse_id, variant_id). MySQL ne considere pas deux NULL comme
        // egaux dans un index unique : pour un produit SANS variante
        // (variant_id NULL), on verifie donc d'abord manuellement si une
        // ligne existe deja, plutot que de compter sur ON DUPLICATE KEY.
        if ($variantId === null) {
            $existing = $this->stockLevel($productId, $warehouseId, null);
            if ($existing === null) {
                $stmt = $this->pdo->prepare('
                    INSERT INTO stock_levels (product_id, warehouse_id, variant_id, quantity, updated_at)
                    VALUES (:product_id, :warehouse_id, NULL, :quantity, NOW())
                ');
                $stmt->execute([':product_id' => $productId, ':warehouse_id' => $warehouseId, ':quantity' => $quantity]);
                return;
            }

            $stmt = $this->pdo->prepare('
                UPDATE stock_levels SET quantity = :quantity, updated_at = NOW()
                WHERE product_id = :product_id AND warehouse_id = :warehouse_id AND variant_id IS NULL
            ');
            $stmt->execute([':product_id' => $productId, ':warehouse_id' => $warehouseId, ':quantity' => $quantity]);
            return;
        }

        $stmt = $this->pdo->prepare('
            INSERT INTO stock_levels (product_id, warehouse_id, variant_id, quantity, updated_at)
            VALUES (:product_id, :warehouse_id, :variant_id, :quantity, NOW())
            ON DUPLICATE KEY UPDATE quantity = VALUES(quantity), updated_at = NOW()
        ');
        $stmt->execute([
            ':product_id' => $productId,
            ':warehouse_id' => $warehouseId,
            ':variant_id' => $variantId,
            ':quantity' => $quantity,
        ]);
    }

    public function create(array $payload): int
    {
        $id = parent::create($payload);
        if ($id > 0) {
            $this->syncTags($id, $payload);
        }

        return $id;
    }

    public function update(int $id, array $payload): bool
    {
        $result = parent::update($id, $payload);
        $this->syncTags($id, $payload);

        return $result;
    }

    /**
     * Remplace l'ensemble des tags d'un produit par ceux fournis dans le
     * payload (cle 'tag_ids', tableau d'identifiants). Si la cle est absente
     * du payload, on ne touche pas aux tags existants (formulaire qui ne
     * gere pas les tags, ex: import en masse).
     *
     * @param array<string, mixed> $payload
     */
    private function syncTags(int $productId, array $payload): void
    {
        if (!array_key_exists('tag_ids', $payload)) {
            return;
        }

        $raw = is_array($payload['tag_ids']) ? $payload['tag_ids'] : [];
        $tagIds = array_values(array_unique(array_filter(array_map('intval', $raw), static fn (int $v): bool => $v > 0)));

        $delete = $this->pdo->prepare('DELETE FROM product_tags WHERE product_id = :product_id');
        $delete->execute([':product_id' => $productId]);

        if ($tagIds === []) {
            return;
        }

        $insert = $this->pdo->prepare('INSERT INTO product_tags (product_id, tag_id) VALUES (:product_id, :tag_id)');
        foreach ($tagIds as $tagId) {
            $insert->execute([':product_id' => $productId, ':tag_id' => $tagId]);
        }
    }

    protected function buildWhere(array $filters): array
    {
        $clauses = [];
        $params = [];

        foreach ($filters as $key => $value) {
            if ($value === null || $value === '') {
                continue;
            }

            if ($key === 'tag_id') {
                $clauses[] = 'p.id IN (SELECT product_id FROM product_tags WHERE tag_id = :f_tag_id)';
                $params[':f_tag_id'] = $value;
                continue;
            }

            if ($key === 'q') {
                // Chaque occurrence utilise un placeholder distinct: en mode
                // prepares natifs (PDO::ATTR_EMULATE_PREPARES => false), MySQL
                // ne supporte pas la reutilisation d'un meme parametre nomme
                // plusieurs fois dans la meme requete (erreur SQL au moment
                // de l'execution).
                // On inclut aussi les numeros de serie (product_serials) via
                // une sous-requete EXISTS: chercher un SN dans la barre
                // globale doit remonter le produit auquel il appartient.
                $clauses[] = '(
                    p.sku LIKE :f_q1
                    OR p.barcode LIKE :f_q2
                    OR p.name LIKE :f_q3
                    OR p.description LIKE :f_q4
                    OR EXISTS (
                        SELECT 1 FROM product_serials ps
                        WHERE ps.product_id = p.id AND ps.serial_number LIKE :f_q5
                    )
                )';
                $like = '%' . $value . '%';
                $params[':f_q1'] = $like;
                $params[':f_q2'] = $like;
                $params[':f_q3'] = $like;
                $params[':f_q4'] = $like;
                $params[':f_q5'] = $like;
                continue;
            }

            if (!in_array($key, $this->filterable, true)) {
                continue;
            }

            $token = ':f_' . $key;
            $clauses[] = 'p.' . $key . ' = ' . $token;
            $params[$token] = $value;
        }

        return [$clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '', $params];
    }

    private function columnExists(string $table, string $column): bool
    {
        // Petit cache local pour accelerer les appels repetes.
        $cacheKey = $table . '.' . $column;
        if (array_key_exists($cacheKey, self::$columnExistsCache)) {
            return self::$columnExistsCache[$cacheKey];
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
        self::$columnExistsCache[$cacheKey] = $exists;
        return $exists;
    }
}
