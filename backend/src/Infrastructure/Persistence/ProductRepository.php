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

        // warehouse_id n'est pas une colonne de `products` : il ne peut pas
        // passer par buildWhere(). Il restreint la liste aux produits presents
        // dans cet entrepot, et la colonne stock_total n'y compte alors que le
        // stock de cet entrepot - sinon on afficherait un total tous entrepots
        // confondus a cote d'un filtre "entrepot X", ce qui serait trompeur.
        $warehouseId = isset($filters['warehouse_id']) && $filters['warehouse_id'] !== ''
            ? (int)$filters['warehouse_id']
            : null;
        unset($filters['warehouse_id']);

        [$whereSql, $params] = $this->buildWhere($filters);

        $stockJoin = 'LEFT JOIN stock_levels sl ON sl.product_id = p.id';
        if ($warehouseId !== null) {
            $stockJoin = 'INNER JOIN stock_levels sl ON sl.product_id = p.id AND sl.warehouse_id = :f_warehouse_id';
            $params[':f_warehouse_id'] = $warehouseId;
        }

        // Resume "ou est ce produit" directement dans la liste : sans lui, il
        // fallait ouvrir la fiche puis l'onglet Stock pour savoir dans quelle
        // allee aller le chercher. Les lignes a quantite nulle et le stock non
        // range sont ecartes : on ne liste que les endroits ou il y a
        // reellement quelque chose.
        // La colonne location_id vient de la migration 202602270012 : sur une
        // base qui ne l'a pas encore jouee, on renvoie une chaine vide plutot
        // que de casser toute la liste des produits.
        if ($this->columnExists('stock_levels', 'location_id')) {
            $locationJoin = 'LEFT JOIN warehouse_locations sl_loc ON sl_loc.id = sl.location_id';
            $locationSummary = "GROUP_CONCAT(DISTINCT CASE WHEN sl.quantity <> 0 AND sl.location_id IS NOT NULL
                                   THEN CONCAT(sl_loc.code, ' (', sl.quantity, ')') END
                                   ORDER BY sl_loc.code SEPARATOR ', ') AS location_summary";
        } else {
            $locationJoin = '';
            $locationSummary = "'' AS location_summary";
        }

        $countSql = $warehouseId !== null
            ? "SELECT COUNT(DISTINCT p.id) FROM products p {$stockJoin} {$whereSql}"
            : "SELECT COUNT(*) FROM products p {$whereSql}";

        $countStmt = $this->pdo->prepare($countSql);
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
                COALESCE(SUM(sl.quantity), 0) AS stock_total,
                {$locationSummary}
            FROM products p
            LEFT JOIN categories c ON c.id = p.category_id
            LEFT JOIN suppliers s ON s.id = p.supplier_id
            LEFT JOIN units u ON u.id = p.unit_id
            LEFT JOIN brands b ON b.id = p.brand_id
            LEFT JOIN taxes t ON t.id = p.tax_id
            {$stockJoin}
            {$locationJoin}
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

        // Colonnes listees explicitement : `SELECT *` renvoyait file_path,
        // c'est-a-dire le chemin ABSOLU du fichier sur le serveur
        // (/home/.../backend/public/uploads/...). Le frontend ne s'en sert
        // pas - il telecharge via /product-media/{id}/download - et cela
        // renseignait l'arborescence du serveur a tout utilisateur connecte.
        $mediaStmt = $this->pdo->prepare('
            SELECT id, product_id, media_type, file_name, mime_type, uploaded_by, created_at
            FROM product_media WHERE product_id = :id ORDER BY id DESC
        ');
        $mediaStmt->execute([':id' => $id]);
        $result['media'] = $mediaStmt->fetchAll();

        // last_location_code : dernier emplacement connu dans cet entrepot,
        // deduit du mouvement de stock le plus recent qui en mentionne un.
        // stock_levels ne porte pas d'emplacement (le stock est suivi par
        // entrepot, pas par allee) : c'est donc une information indicative,
        // "ou cet article a ete range la derniere fois", pas un inventaire
        // par emplacement.
        $whStmt = $this->pdo->prepare('
            SELECT sl.warehouse_id, sl.variant_id, sl.location_id,
                   w.code AS warehouse_code, w.name AS warehouse_name,
                   loc.code AS location_code, loc.description AS location_description,
                   zone.code AS zone_code, zone.name AS zone_name,
                   sl.quantity, sl.reserved_quantity,
                   v.sku AS variant_sku, v.size AS variant_size, v.color AS variant_color, v.vintage AS variant_vintage, v.volume_cl AS variant_volume_cl, v.width AS variant_width, v.height AS variant_height, v.depth AS variant_depth, v.weight AS variant_weight,
                   (
                       SELECT COALESCE(dloc.code, sloc.code)
                       FROM stock_movements sm
                       LEFT JOIN warehouse_locations dloc ON dloc.id = sm.destination_location_id
                       LEFT JOIN warehouse_locations sloc ON sloc.id = sm.source_location_id
                       WHERE sm.product_id = sl.product_id
                         AND (sm.warehouse_id = sl.warehouse_id OR sm.destination_warehouse_id = sl.warehouse_id)
                         AND (sm.source_location_id IS NOT NULL OR sm.destination_location_id IS NOT NULL)
                       ORDER BY sm.id DESC
                       LIMIT 1
                   ) AS last_location_code
            FROM stock_levels sl
            INNER JOIN warehouses w ON w.id = sl.warehouse_id
            LEFT JOIN warehouse_locations loc ON loc.id = sl.location_id
            LEFT JOIN warehouse_zones zone ON zone.id = loc.zone_id
            LEFT JOIN product_variants v ON v.id = sl.variant_id
            WHERE sl.product_id = :id
            ORDER BY w.name ASC, (sl.location_id IS NOT NULL) ASC, loc.code ASC, v.size ASC, v.color ASC
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

    /**
     * @param bool $forUpdate Pose un verrou de ligne (SELECT ... FOR UPDATE).
     *
     * Indispensable des qu'on lit un stock pour le recalculer et le reecrire :
     * sans verrou, deux sorties simultanees sur le meme article lisent toutes
     * les deux l'ancienne quantite, et la seconde ecrase la premiere - le
     * stock ne descend que d'une sortie au lieu de deux, et le controle
     * "stock insuffisant" peut laisser passer une quantite indisponible.
     * Sans effet hors transaction, ce qui est le cas des simples lectures.
     */
    public function stockLevel(int $productId, int $warehouseId, ?int $variantId = null, bool $forUpdate = false, ?int $locationId = null): ?array
    {
        // Depuis le suivi par emplacement, une ligne de stock est identifiee
        // par produit + variante + entrepot + EMPLACEMENT. $locationId a NULL
        // ne veut pas dire "n'importe lequel" mais bien "l'emplacement non
        // precise" : c'est une ligne a part entiere, celle du stock present
        // dans l'entrepot sans rangement connu.
        $sql = 'SELECT warehouse_id, location_id, quantity FROM stock_levels WHERE product_id = :product_id AND warehouse_id = :warehouse_id AND variant_id '
            . ($variantId !== null ? '= :variant_id' : 'IS NULL')
            . ' AND location_id ' . ($locationId !== null ? '= :location_id' : 'IS NULL')
            . ' LIMIT 1'
            . ($forUpdate ? ' FOR UPDATE' : '');
        $stmt = $this->pdo->prepare($sql);
        $params = [':product_id' => $productId, ':warehouse_id' => $warehouseId];
        if ($variantId !== null) {
            $params[':variant_id'] = $variantId;
        }
        if ($locationId !== null) {
            $params[':location_id'] = $locationId;
        }
        $stmt->execute($params);
        $row = $stmt->fetch();

        if (!$row) {
            return null;
        }

        return [
            'warehouse_id' => (int)$row['warehouse_id'],
            'location_id' => $row['location_id'] !== null ? (int)$row['location_id'] : null,
            'quantity' => (int)$row['quantity'],
        ];
    }

    /**
     * Toutes les lignes de stock d'un produit dans un entrepot, une par
     * emplacement.
     *
     * Triees emplacement non precise d'abord, puis par emplacement : c'est
     * l'ordre dans lequel une sortie sans emplacement pioche (on consomme
     * d'abord ce qui n'est range nulle part, avant d'aller defaire un
     * rangement).
     *
     * @return array<int, array{id:int, location_id:int|null, quantity:int}>
     */
    public function stockRowsForWarehouse(int $productId, int $warehouseId, ?int $variantId = null, bool $forUpdate = false): array
    {
        $sql = 'SELECT id, location_id, quantity FROM stock_levels
                WHERE product_id = :product_id AND warehouse_id = :warehouse_id AND variant_id '
            . ($variantId !== null ? '= :variant_id' : 'IS NULL')
            . ' ORDER BY (location_id IS NOT NULL) ASC, location_id ASC'
            . ($forUpdate ? ' FOR UPDATE' : '');

        $stmt = $this->pdo->prepare($sql);
        $params = [':product_id' => $productId, ':warehouse_id' => $warehouseId];
        if ($variantId !== null) {
            $params[':variant_id'] = $variantId;
        }
        $stmt->execute($params);

        return array_map(static fn (array $row): array => [
            'id' => (int)$row['id'],
            'location_id' => $row['location_id'] !== null ? (int)$row['location_id'] : null,
            'quantity' => (int)$row['quantity'],
        ], $stmt->fetchAll());
    }

    /** Quantite totale d'un produit dans un entrepot, tous emplacements confondus. */
    public function warehouseQuantity(int $productId, int $warehouseId, ?int $variantId = null): int
    {
        $sql = 'SELECT COALESCE(SUM(quantity), 0) FROM stock_levels
                WHERE product_id = :product_id AND warehouse_id = :warehouse_id AND variant_id '
            . ($variantId !== null ? '= :variant_id' : 'IS NULL');

        $stmt = $this->pdo->prepare($sql);
        $params = [':product_id' => $productId, ':warehouse_id' => $warehouseId];
        if ($variantId !== null) {
            $params[':variant_id'] = $variantId;
        }
        $stmt->execute($params);

        return (int)$stmt->fetchColumn();
    }

    /**
     * Ecrit la quantite d'UNE ligne de stock (produit + variante + entrepot +
     * emplacement), en la creant si elle n'existe pas.
     *
     * On n'utilise volontairement pas ON DUPLICATE KEY UPDATE : la cle unique
     * contient `variant_id` et `location_id`, tous deux nullables, et MySQL
     * n'applique pas l'unicite des qu'une colonne de la cle vaut NULL. S'y
     * fier creerait des lignes en double a chaque ecriture - le piege a deja
     * coute plusieurs bugs dans ce projet (import de stock, donnees de demo).
     * On cible donc explicitement la ligne existante.
     */
    public function upsertStockLevel(int $productId, int $warehouseId, int $quantity, ?int $variantId = null, ?int $locationId = null): void
    {
        $variantSql = $variantId !== null ? '= :variant_id' : 'IS NULL';
        $locationSql = $locationId !== null ? '= :location_id' : 'IS NULL';

        $params = [':product_id' => $productId, ':warehouse_id' => $warehouseId];
        if ($variantId !== null) {
            $params[':variant_id'] = $variantId;
        }
        if ($locationId !== null) {
            $params[':location_id'] = $locationId;
        }

        $find = $this->pdo->prepare("
            SELECT id FROM stock_levels
            WHERE product_id = :product_id AND warehouse_id = :warehouse_id
              AND variant_id {$variantSql} AND location_id {$locationSql}
            LIMIT 1
        ");
        $find->execute($params);
        $existingId = $find->fetchColumn();

        if ($existingId) {
            $stmt = $this->pdo->prepare('UPDATE stock_levels SET quantity = :quantity, updated_at = NOW() WHERE id = :id');
            $stmt->execute([':quantity' => $quantity, ':id' => (int)$existingId]);
            return;
        }

        $stmt = $this->pdo->prepare('
            INSERT INTO stock_levels (product_id, warehouse_id, variant_id, location_id, quantity, updated_at)
            VALUES (:product_id, :warehouse_id, :variant_id, :location_id, :quantity, NOW())
        ');
        $stmt->execute([
            ':product_id' => $productId,
            ':warehouse_id' => $warehouseId,
            ':variant_id' => $variantId,
            ':location_id' => $locationId,
            ':quantity' => $quantity,
        ]);
    }

    /** Met a jour une ligne de stock deja identifiee par son id. */
    public function setStockRowQuantity(int $stockLevelId, int $quantity): void
    {
        $stmt = $this->pdo->prepare('UPDATE stock_levels SET quantity = :quantity, updated_at = NOW() WHERE id = :id');
        $stmt->execute([':quantity' => $quantity, ':id' => $stockLevelId]);
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

    /**
     * Produits proposables a la saisie (mouvements, livraisons, achats).
     *
     * Un produit desactive (`is_active = 0`) reste visible et modifiable dans
     * l'ecran Produits, mais disparait des listes deroulantes : on ne peut plus
     * lui passer de mouvement ni le commander, sans pour autant toucher a son
     * historique. C'est exactement le comportement deja applique aux variantes
     * (`ProductVariantRepository`, filtre `is_active=1` cote frontend).
     *
     * La colonne `is_active` vient d'une migration posterieure au schema
     * initial : on verifie sa presence pour ne pas casser une base qui ne
     * l'aurait pas encore (meme precaution que lowStock()).
     */
    public function selectableForLookup(int $limit = 2000): array
    {
        // Requete dediee plutot que paginate() : celui-ci plafonne a 100 lignes
        // (garde-fou anti-abus sur ?per_page), ce qui tronquait silencieusement
        // les listes deroulantes au-dela de 100 produits. On ne selectionne ici
        // que les colonnes reellement utilisees par les formulaires, sans les
        // jointures de stock ni les tags : c'est aussi nettement plus leger.
        $where = $this->columnExists('products', 'is_active') ? 'WHERE p.is_active = 1' : '';
        // Meme precaution pour has_variants (migration 202602270009).
        $variantsColumn = $this->columnExists('products', 'has_variants')
            ? 'p.has_variants'
            : '0 AS has_variants';
        $limit = max(1, min(5000, $limit));

        $stmt = $this->pdo->prepare("
            SELECT p.id, p.sku, p.name, p.unit_price, p.cost_price, {$variantsColumn}
            FROM products p
            {$where}
            ORDER BY p.name ASC
            LIMIT :limit
        ");
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->execute();

        return $stmt->fetchAll();
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
