<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

final class WarehouseZoneRepository extends PdoCrudRepository
{
    protected string $table = 'warehouse_zones';
    protected array $fillable = ['warehouse_id', 'code', 'name'];
    protected array $filterable = ['warehouse_id', 'code', 'name'];
    protected array $searchable = ['code', 'name'];
    protected string $lookupOrderColumn = 'name';

    /** Affiche le nom de l'entrepot plutot que son identifiant. */
    protected array $listLookups = [
        'warehouse_id' => ['table' => 'warehouses', 'column' => 'name', 'as' => 'warehouse_name'],
    ];

    /**
     * Ajoute le nombre d'emplacements de chaque zone.
     *
     * Une zone ne stocke rien par elle-meme : c'est l'emplacement qui porte le
     * stock, les numeros de serie et les mouvements. Une zone sans aucun
     * emplacement n'est donc utilisable nulle part, et rien ne le disait -
     * on croyait avoir range son entrepot alors qu'aucun choix n'etait
     * proposable a la saisie. La colonne rend le probleme visible d'un coup
     * d'oeil.
     */
    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        $result = parent::paginate($page, $perPage, $filters);

        if ($result['data'] === []) {
            return $result;
        }

        $ids = array_map(static fn (array $row): int => (int)$row['id'], $result['data']);
        $placeholders = implode(', ', array_fill(0, count($ids), '?'));
        $stmt = $this->pdo->prepare(
            "SELECT zone_id, COUNT(*) AS total FROM warehouse_locations WHERE zone_id IN ({$placeholders}) GROUP BY zone_id"
        );
        $stmt->execute($ids);

        $counts = [];
        foreach ($stmt->fetchAll() as $row) {
            $counts[(int)$row['zone_id']] = (int)$row['total'];
        }

        foreach ($result['data'] as &$row) {
            $row['location_count'] = $counts[(int)$row['id']] ?? 0;
        }
        unset($row);

        return $result;
    }
}