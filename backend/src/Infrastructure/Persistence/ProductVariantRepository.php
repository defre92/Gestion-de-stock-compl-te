<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class ProductVariantRepository extends PdoCrudRepository
{
    protected string $table = 'product_variants';
    protected array $fillable = [
        'product_id',
        'sku',
        'barcode',
        'size',
        'color',
        'vintage',
        'volume_cl',
        // Dimensions libres (texte) : "120 cm", "2 m", "3/4 pouce", "sur
        // mesure"... volontairement non numeriques, voir la migration
        // 202602270014_dimension_variants.sql.
        'width',
        'height',
        'depth',
        'weight',
        // Quatrieme saveur (materiel electrique/mecanique), voir la migration
        // 202602270018_technical_variants.sql. Champs texte libres, comme les
        // dimensions ci-dessus.
        'puissance',
        'marque',
        'type',
        'vitesse',
        'tension',
        'forme',
        'attributes_json',
        'unit_price',
        'is_active',
    ];
    protected array $filterable = ['product_id', 'is_active'];

    /**
     * Mot-cle d'attribut -> colonne. Permet de retrouver "toutes les
     * variantes qui ont un millesime" en tapant "millesime" dans la
     * recherche globale, alors que ce mot n'est JAMAIS stocke en base (seule
     * la valeur l'est, ex: l'annee "2019" dans `vintage`) - il n'apparait
     * qu'a l'affichage (variantDescriptor cote frontend,
     * refreshProductAlert cote backend). Sans cette table, chercher
     * "millesime" ne pouvait remonter qu'une coincidence (une valeur qui
     * contient ces lettres par hasard), jamais les variantes concernees.
     *
     * Cles normalisees (minuscules, sans accents) et testees en
     * "correspondance partielle du mot-cle" : "mill" retrouve deja
     * "millesime" (voir buildWhere), pas besoin de taper le mot en entier.
     *
     * @var array<string, string>
     */
    private const ATTRIBUTE_KEYWORDS = [
        'taille' => 'size',
        'pointure' => 'size',
        'couleur' => 'color',
        'millesime' => 'vintage',
        'contenance' => 'volume_cl',
        'volume' => 'volume_cl',
        'largeur' => 'width',
        'hauteur' => 'height',
        'profondeur' => 'depth',
        'poids' => 'weight',
        'puissance' => 'puissance',
        'marque' => 'marque',
        'type' => 'type',
        'vitesse' => 'vitesse',
        'tension' => 'tension',
        'forme' => 'forme',
    ];

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(200, $perPage));
        $offset = ($page - 1) * $perPage;

        [$whereSql, $params] = $this->buildWhere($filters);

        // INNER JOIN products des le COUNT : le filtre `q` (recherche
        // globale) porte aussi sur le nom/SKU du produit parent, pas
        // seulement sur les colonnes de la variante (voir buildWhere).
        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM product_variants v INNER JOIN products p ON p.id = v.product_id {$whereSql}");
        $countStmt->execute($params);
        $total = (int)$countStmt->fetchColumn();

        // Stock total toutes variantes confondues, comme products.stock_total.
        $sql = "
            SELECT
                v.*,
                p.name AS product_name,
                p.sku AS product_sku,
                COALESCE(SUM(sl.quantity), 0) AS stock_total
            FROM product_variants v
            INNER JOIN products p ON p.id = v.product_id
            LEFT JOIN stock_levels sl ON sl.variant_id = v.id
            {$whereSql}
            GROUP BY v.id
            ORDER BY v.id DESC
            LIMIT :limit OFFSET :offset
        ";

        $stmt = $this->pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value);
        }
        $stmt->bindValue(':limit', $perPage, \PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, \PDO::PARAM_INT);
        $stmt->execute();

        return [
            'data' => $stmt->fetchAll(),
            'meta' => [
                'page' => $page,
                'per_page' => $perPage,
                'total' => $total,
                'last_page' => (int)max(1, ceil($total / $perPage)),
            ],
        ];
    }

    /**
     * Meme signature que la methode parente, prefixe par defaut 'v.'.
     *
     * Le parametre $prefix DOIT figurer ici meme s'il n'est pas utilise :
     * une methode fille dont la signature differe de la methode parente
     * provoque une erreur fatale PHP au CHARGEMENT de la classe - donc sur
     * TOUTES les routes de l'API a la fois, et sans aucun message
     * exploitable cote navigateur.
     */
    protected function buildWhere(array $filters, string $prefix = 'v.'): array
    {
        $clauses = [];
        $params = [];

        foreach ($filters as $key => $value) {
            if ($value === null || $value === '' || !in_array($key, $this->filterable, true)) {
                continue;
            }

            $token = ':f_' . $key;
            $clauses[] = $prefix . $key . ' = ' . $token;
            $params[$token] = $value;
        }

        // Recherche globale (barre en haut, onglet Variantes) : porte sur les
        // colonnes de la variante elle-meme (SKU, code barre, et toutes les
        // "saveurs" - vetement, bouteille, dimensions, materiel) ainsi que le
        // nom/SKU du produit parent (jointure ajoutee dans paginate()).
        if (isset($filters['q']) && trim((string)$filters['q']) !== '') {
            $like = '%' . $filters['q'] . '%';
            $columns = [
                'v.sku', 'v.barcode', 'v.size', 'v.color', 'v.vintage', 'v.volume_cl',
                'v.width', 'v.height', 'v.depth', 'v.weight',
                'v.puissance', 'v.marque', 'v.type', 'v.vitesse', 'v.tension', 'v.forme',
                'p.name', 'p.sku',
            ];
            $searchClauses = [];
            foreach ($columns as $index => $column) {
                $token = ':f_q' . $index;
                $searchClauses[] = "{$column} LIKE {$token}";
                $params[$token] = $like;
            }

            // Recherche par mot-cle d'attribut (voir ATTRIBUTE_KEYWORDS) : en
            // plus de la recherche par valeur ci-dessus, "millesime" retrouve
            // aussi toute variante dont la colonne `vintage` est renseignee,
            // meme si aucune valeur ne contient litteralement ce mot. Les noms
            // de colonnes viennent d'une liste figee dans le code (jamais de
            // la requete HTTP), leur interpolation directe est donc sans
            // risque.
            $normalizedQuery = self::stripAccents(mb_strtolower(trim((string)$filters['q']), 'UTF-8'));
            if ($normalizedQuery !== '') {
                $matchedColumns = [];
                foreach (self::ATTRIBUTE_KEYWORDS as $keyword => $column) {
                    if (str_contains($keyword, $normalizedQuery) && !in_array($column, $matchedColumns, true)) {
                        $matchedColumns[] = $column;
                        $searchClauses[] = "(v.{$column} IS NOT NULL AND v.{$column} <> '')";
                    }
                }
            }

            $clauses[] = '(' . implode(' OR ', $searchClauses) . ')';
        }

        return [$clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '', $params];
    }

    /** Retire les accents (utf8 -> ascii) pour une comparaison insensible : "millésime" et "millesime" doivent matcher le meme mot-cle. */
    private static function stripAccents(string $value): string
    {
        $transliterated = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $value);

        return $transliterated !== false ? $transliterated : $value;
    }
}
