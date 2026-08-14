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
        'attributes_json',
        'unit_price',
        'is_active',
    ];
    protected array $filterable = ['product_id', 'is_active'];

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $page = max(1, $page);
        $perPage = max(1, min(200, $perPage));
        $offset = ($page - 1) * $perPage;

        [$whereSql, $params] = $this->buildWhere($filters);

        $countStmt = $this->pdo->prepare("SELECT COUNT(*) FROM product_variants v {$whereSql}");
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

    protected function buildWhere(array $filters): array
    {
        $clauses = [];
        $params = [];

        foreach ($filters as $key => $value) {
            if ($value === null || $value === '' || !in_array($key, $this->filterable, true)) {
                continue;
            }

            $token = ':f_' . $key;
            $clauses[] = 'v.' . $key . ' = ' . $token;
            $params[$token] = $value;
        }

        return [$clauses !== [] ? 'WHERE ' . implode(' AND ', $clauses) : '', $params];
    }
}
