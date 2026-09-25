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
        // Plafond releve de 200 a 5000 (meme valeur que allForLookup() /
        // selectableForLookup() ailleurs dans le code) : les ecrans qui
        // gerent les variantes d'UN produit (onglet Stock, formulaire de
        // mouvement, generateur en lot...) demandent toujours per_page=200
        // pour recuperer "toutes les variantes du produit" en un seul appel,
        // sans jamais regarder meta.last_page - un produit qui depassait 200
        // variantes voyait donc ses variantes les plus anciennes disparaitre
        // silencieusement de ces listes (ORDER BY v.id DESC). 5000 reste une
        // limite technique (protege contre un appel HTTP ?per_page=999999999
        // abusif) mais n'est plus une limite metier atteignable en usage
        // normal.
        $perPage = max(1, min(5000, $perPage));
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
                $paramIndex = 0;
                foreach (self::ATTRIBUTE_KEYWORDS as $keyword => $column) {
                    if (in_array($column, $matchedColumns, true)) {
                        continue;
                    }

                    if (str_contains($keyword, $normalizedQuery)) {
                        // Saisie en cours du mot-cle lui-meme ("mill" -> "millesime") :
                        // on retrouve deja toute variante ou la colonne est renseignee,
                        // sans attendre la valeur.
                        $matchedColumns[] = $column;
                        $searchClauses[] = "(v.{$column} IS NOT NULL AND v.{$column} <> '')";
                        continue;
                    }

                    if (str_contains($normalizedQuery, $keyword)) {
                        // Le mot-cle est complet et suivi d'autre chose ("millesime 2022",
                        // "couleur noir") : on filtre alors sur la VALEUR qui suit, sur la
                        // colonne correspondante - sinon taper une valeur apres le mot-cle
                        // ne retrouvait plus rien (ni la recherche par valeur brute
                        // ci-dessus, qui ne trouve pas "millesime 2022" tel quel dans une
                        // colonne, ni la recherche par mot-cle seule, prevue pour la saisie
                        // partielle du mot-cle et non pour un mot-cle deja complet).
                        $remainder = trim(str_replace($keyword, '', $normalizedQuery));
                        if ($remainder !== '') {
                            $matchedColumns[] = $column;
                            $token = ':f_qkw' . $paramIndex++;
                            $searchClauses[] = "v.{$column} LIKE {$token}";
                            $params[$token] = '%' . $remainder . '%';
                        }
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
