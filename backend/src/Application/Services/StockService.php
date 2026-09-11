<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Infrastructure\Persistence\StockAlertRepository;
use App\Infrastructure\Persistence\StockMovementRepository;
use App\Infrastructure\Persistence\WarehouseRepository;
use App\Shared\Database\Database;
use App\Shared\Http\HttpException;
use Throwable;

final class StockService
{
    public function __construct(
        private readonly ProductRepository $productRepository,
        private readonly WarehouseRepository $warehouseRepository,
        private readonly StockMovementRepository $movementRepository,
        private readonly StockAlertRepository $alertRepository,
        private readonly AuditRepository $auditRepository
    ) {
    }

    public function paginateMovements(int $page, int $perPage, array $filters = []): array
    {
        return $this->movementRepository->paginate($page, $perPage, $filters);
    }

    public function lowStockAlerts(): array
    {
        $low = $this->productRepository->lowStock();
        $delayedPo = Database::connection()->query("SELECT po.id, po.order_number, po.expected_at, s.name supplier_name FROM purchase_orders po INNER JOIN suppliers s ON s.id=po.supplier_id WHERE po.status IN ('PENDING','PARTIAL') AND po.expected_at IS NOT NULL AND po.expected_at < NOW() ORDER BY po.expected_at ASC")->fetchAll();
        $persistent = $this->alertRepository->paginate(1, 200, ['status' => 'OPEN'])['data'];

        return [
            'low_stock' => $low,
            'delayed_po' => $delayedPo,
            'persistent' => $persistent,
        ];
    }

    /**
     * Verifie qu'un emplacement appartient bien a l'entrepot concerne.
     *
     * Sans ce controle, on pourrait ranger un article dans une allee d'un
     * autre entrepot : la ligne de stock existerait, mais son emplacement
     * designerait un endroit ou l'article n'est pas.
     */
    private function assertLocationBelongsTo(?int $locationId, int $warehouseId): void
    {
        if ($locationId === null) {
            return;
        }

        $stmt = Database::connection()->prepare('SELECT warehouse_id FROM warehouse_locations WHERE id = :id LIMIT 1');
        $stmt->execute([':id' => $locationId]);
        $found = $stmt->fetchColumn();

        if ($found === false) {
            throw new HttpException('Emplacement introuvable', 404);
        }

        if ((int)$found !== $warehouseId) {
            throw new HttpException("L'emplacement choisi n'appartient pas a l'entrepot de ce mouvement", 422);
        }
    }

    /**
     * Retire une quantite du stock d'un entrepot.
     *
     * Avec un emplacement precis, on ne pioche que dans celui-la : sortir 5
     * pieces de l'allee B1 doit echouer s'il n'y en a que 3, meme si
     * l'entrepot en contient 40 ailleurs - sinon la quantite de B1 deviendrait
     * fausse.
     *
     * Sans emplacement, on consomme sur l'ensemble de l'entrepot, en
     * commencant par le stock non range puis emplacement par emplacement.
     * C'est ce qui permet aux operations qui ne connaissent pas d'emplacement
     * (livraison, reception, sortie rapide) de continuer a fonctionner
     * exactement comme avant.
     */
    private function consumeFromWarehouse(int $productId, int $warehouseId, ?int $variantId, int $quantity, ?int $locationId, string $errorMessage): void
    {
        if ($locationId !== null) {
            $row = $this->productRepository->stockLevel($productId, $warehouseId, $variantId, true, $locationId);
            $available = (int)($row['quantity'] ?? 0);
            if ($available < $quantity) {
                throw new HttpException(
                    "Stock insuffisant a l'emplacement choisi ({$available} disponible(s) pour {$quantity} demande(s))",
                    422
                );
            }

            $this->productRepository->upsertStockLevel($productId, $warehouseId, $available - $quantity, $variantId, $locationId);
            return;
        }

        $rows = $this->productRepository->stockRowsForWarehouse($productId, $warehouseId, $variantId, true);
        $total = array_sum(array_map(static fn (array $row): int => $row['quantity'], $rows));

        if ($total < $quantity) {
            throw new HttpException($errorMessage, 422);
        }

        $remaining = $quantity;
        foreach ($rows as $row) {
            if ($remaining <= 0) {
                break;
            }
            if ($row['quantity'] <= 0) {
                continue;
            }

            $taken = min($row['quantity'], $remaining);
            $this->productRepository->setStockRowQuantity($row['id'], $row['quantity'] - $taken);
            $remaining -= $taken;
        }

        if ($remaining > 0) {
            // Ne devrait jamais arriver : le total a ete verifie plus haut,
            // sous verrou. On refuse plutot que de laisser passer une sortie
            // partielle silencieuse.
            throw new HttpException($errorMessage, 422);
        }
    }

    /**
     * Ajustement d'inventaire : la quantite saisie REMPLACE la quantite en
     * place, elle ne s'y ajoute pas.
     *
     * Sans emplacement precis, l'operation n'a de sens que si le produit tient
     * sur une seule ligne dans cet entrepot. Reparti sur trois emplacements,
     * "le stock vaut 12" ne dit pas lesquels valent quoi : on refuse plutot
     * que d'ecraser arbitrairement.
     */
    private function applyAdjustment(int $productId, int $warehouseId, ?int $variantId, int $quantity, ?int $locationId): void
    {
        $this->assertLocationBelongsTo($locationId, $warehouseId);

        if ($locationId !== null) {
            $this->productRepository->upsertStockLevel($productId, $warehouseId, $quantity, $variantId, $locationId);
            return;
        }

        $rows = $this->productRepository->stockRowsForWarehouse($productId, $warehouseId, $variantId, true);
        $withStock = array_values(array_filter($rows, static fn (array $row): bool => $row['quantity'] !== 0));

        if (count($withStock) > 1) {
            throw new HttpException(
                'Ce produit est reparti sur plusieurs emplacements dans cet entrepot : precise l\'emplacement a ajuster.',
                422
            );
        }

        $target = $withStock[0]['location_id'] ?? ($rows[0]['location_id'] ?? null);
        $this->productRepository->upsertStockLevel($productId, $warehouseId, $quantity, $variantId, $target);
    }

    public function createMovement(array $payload, int $actorId, ?string $ip): int
    {
        $productId = (int)($payload['product_id'] ?? 0);
        $variantId = !empty($payload['variant_id']) ? (int)$payload['variant_id'] : null;
        $warehouseId = (int)($payload['warehouse_id'] ?? 0);
        $type = strtoupper((string)($payload['type'] ?? ''));
        $quantity = (int)($payload['quantity'] ?? 0);
        $destinationWarehouseId = isset($payload['destination_warehouse_id']) ? (int)$payload['destination_warehouse_id'] : null;
        $sourceLocationId = !empty($payload['source_location_id']) ? (int)$payload['source_location_id'] : null;
        $destinationLocationId = !empty($payload['destination_location_id']) ? (int)$payload['destination_location_id'] : null;

        if ($productId <= 0 || $warehouseId <= 0 || $quantity <= 0 || !in_array($type, ['IN', 'OUT', 'ADJUSTMENT', 'TRANSFER'], true)) {
            throw new HttpException('Donnees de mouvement de stock invalides', 422);
        }

        $product = $this->productRepository->findById($productId);
        if (!$product) {
            throw new HttpException('Produit introuvable', 404);
        }

        if ((int)($product['has_variants'] ?? 0) === 1 && $variantId === null) {
            throw new HttpException('Ce produit utilise des variantes : precise laquelle (variant_id)', 422);
        }

        $warehouse = $this->warehouseRepository->findById($warehouseId);
        if (!$warehouse) {
            throw new HttpException('Entrepot introuvable', 404);
        }

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            // Le stock est suivi par EMPLACEMENT depuis la migration
            // 202602270012. Une "ligne de stock" est donc identifiee par
            // produit + variante + entrepot + emplacement, l'emplacement NULL
            // representant le stock present dans l'entrepot sans rangement
            // precis. Toutes les lectures posent un verrou (FOR UPDATE) : sans
            // lui, deux mouvements simultanes sur le meme article lisent la
            // meme quantite et le second ecrase le premier.
            if ($type === 'IN') {
                // Pour une entree, l'emplacement pertinent est celui ou l'on
                // range : la destination, ou a defaut la source si l'operateur
                // n'a rempli que ce champ.
                $target = $destinationLocationId ?? $sourceLocationId;
                $this->assertLocationBelongsTo($target, $warehouseId);

                $current = $this->productRepository->stockLevel($productId, $warehouseId, $variantId, true, $target);
                $this->productRepository->upsertStockLevel($productId, $warehouseId, ($current['quantity'] ?? 0) + $quantity, $variantId, $target);
            } elseif ($type === 'OUT') {
                $this->assertLocationBelongsTo($sourceLocationId, $warehouseId);
                $this->consumeFromWarehouse($productId, $warehouseId, $variantId, $quantity, $sourceLocationId, 'Stock insuffisant');
            } elseif ($type === 'ADJUSTMENT') {
                $this->applyAdjustment($productId, $warehouseId, $variantId, $quantity, $destinationLocationId ?? $sourceLocationId);
            } else {
                // Deux transferts possibles depuis que le stock est suivi par
                // emplacement :
                //  - EXTERNE : d'un entrepot vers un autre ;
                //  - INTERNE : dans le MEME entrepot, d'un emplacement vers un
                //    autre (ranger une palette de l'allee A1 vers A2). Le cas
                //    interne etait refuse : l'ecran exigeait un entrepot de
                //    destination different, alors qu'il n'y en a pas - on ne
                //    pouvait donc pas deplacer un article dans son propre
                //    entrepot autrement qu'en enchainant une sortie et une
                //    entree, avec un historique faux et un risque d'ecart.
                $isInternal = !$destinationWarehouseId || $destinationWarehouseId === $warehouseId;

                if ($isInternal) {
                    // Pas de second entrepot : la colonne destination reste
                    // vide, le mouvement se lit "A1 -> A2 dans l'entrepot X".
                    $destinationWarehouseId = null;

                    if ($destinationLocationId === null) {
                        throw new HttpException(
                            'Transfert dans le meme entrepot : precise l\'emplacement de destination (sinon rien ne bouge).',
                            422
                        );
                    }

                    if ($destinationLocationId === $sourceLocationId) {
                        throw new HttpException(
                            'L\'emplacement de destination est identique a l\'emplacement source : il n\'y a rien a transferer.',
                            422
                        );
                    }

                    $this->assertLocationBelongsTo($sourceLocationId, $warehouseId);
                    $this->assertLocationBelongsTo($destinationLocationId, $warehouseId);

                    $this->consumeFromWarehouse($productId, $warehouseId, $variantId, $quantity, $sourceLocationId, 'Stock insuffisant pour ce transfert');

                    $destinationCurrent = $this->productRepository->stockLevel($productId, $warehouseId, $variantId, true, $destinationLocationId);
                    $this->productRepository->upsertStockLevel(
                        $productId,
                        $warehouseId,
                        ($destinationCurrent['quantity'] ?? 0) + $quantity,
                        $variantId,
                        $destinationLocationId
                    );
                } else {
                    $destinationWarehouse = $this->warehouseRepository->findById($destinationWarehouseId);
                    if (!$destinationWarehouse) {
                        throw new HttpException('Entrepot de destination introuvable', 404);
                    }

                    $this->assertLocationBelongsTo($sourceLocationId, $warehouseId);
                    $this->assertLocationBelongsTo($destinationLocationId, $destinationWarehouseId);

                    $this->consumeFromWarehouse($productId, $warehouseId, $variantId, $quantity, $sourceLocationId, 'Stock insuffisant pour ce transfert');

                    $destinationCurrent = $this->productRepository->stockLevel($productId, $destinationWarehouseId, $variantId, true, $destinationLocationId);
                    $this->productRepository->upsertStockLevel(
                        $productId,
                        $destinationWarehouseId,
                        ($destinationCurrent['quantity'] ?? 0) + $quantity,
                        $variantId,
                        $destinationLocationId
                    );
                }
            }

            // balance_after devient le total de l'entrepot apres l'operation,
            // et non plus celui d'une seule ligne : avec plusieurs
            // emplacements, la quantite d'une ligne isolee ne veut plus dire
            // grand-chose dans un historique.
            $nextQty = $this->productRepository->warehouseQuantity($productId, $warehouseId, $variantId);

            $movementId = $this->movementRepository->create([
                'product_id' => $productId,
                'variant_id' => $variantId,
                'warehouse_id' => $warehouseId,
                'destination_warehouse_id' => $destinationWarehouseId,
                'source_location_id' => $sourceLocationId,
                'destination_location_id' => $destinationLocationId,
                'type' => $type,
                'quantity' => $quantity,
                'balance_after' => $nextQty,
                'reference_type' => $payload['reference_type'] ?? null,
                'reference_id' => isset($payload['reference_id']) ? (int)$payload['reference_id'] : null,
                'notes' => $payload['notes'] ?? null,
                'reason_code' => $payload['reason_code'] ?? null,
                'moved_by' => $actorId,
            ]);

            if ($type === 'TRANSFER' && $destinationWarehouseId) {
                $this->movementRepository->create([
                    'product_id' => $productId,
                    'variant_id' => $variantId,
                    'warehouse_id' => $destinationWarehouseId,
                    'destination_warehouse_id' => null,
                    'destination_location_id' => $destinationLocationId,
                    'type' => 'IN',
                    'quantity' => $quantity,
                    // Total de l'entrepot de destination, et non la quantite
                    // d'une seule ligne : le stock transfere peut arriver dans
                    // un emplacement precis, auquel cas la ligne "sans
                    // emplacement" vaut 0 et l'historique afficherait un solde
                    // faux.
                    'balance_after' => $this->productRepository->warehouseQuantity($productId, $destinationWarehouseId, $variantId),
                    'reference_type' => 'TRANSFER',
                    'reference_id' => $movementId,
                    'notes' => 'Mouvement d\'entree genere automatiquement par le transfert',
                    'reason_code' => $payload['reason_code'] ?? 'TRANSFER',
                    'moved_by' => $actorId,
                ]);
            }

            $this->auditRepository->log($actorId, 'CREATE', 'stock_movement', $movementId, $payload, $ip);
            $this->refreshProductAlert($productId, $warehouseId, $variantId);
            if ($ownsTransaction) {
                $pdo->commit();
            }

            return $movementId;
        } catch (Throwable $exception) {
            if ($ownsTransaction && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $exception;
        }
    }

    private function refreshProductAlert(int $productId, int $warehouseId, ?int $variantId = null): void
    {
        $product = $this->productRepository->findById($productId);
        if (!$product) {
            return;
        }

        $variantLabel = '';
        if ($variantId !== null) {
            $variant = Database::connection()->prepare('SELECT sku, size, color, vintage, volume_cl, width, height, depth, weight FROM product_variants WHERE id = :id');
            $variant->execute([':id' => $variantId]);
            $variantRow = $variant->fetch();
            if ($variantRow) {
                // Meme ordre de priorite que variantDescriptor() cote frontend :
                // vetement, puis bouteille, puis dimensions, puis le SKU.
                $descriptors = array_filter([$variantRow['size'] ?? null, $variantRow['color'] ?? null]);
                if ($descriptors === []) {
                    $bottleDescriptors = [];
                    if (!empty($variantRow['vintage'])) {
                        $bottleDescriptors[] = 'Millesime ' . $variantRow['vintage'];
                    }
                    if (!empty($variantRow['volume_cl'])) {
                        $bottleDescriptors[] = $variantRow['volume_cl'] . 'cl';
                    }
                    $descriptors = $bottleDescriptors;
                }
                if ($descriptors === []) {
                    $dimensionDescriptors = [];
                    foreach (['width' => 'L', 'height' => 'H', 'depth' => 'P'] as $column => $prefix) {
                        if (!empty($variantRow[$column])) {
                            $dimensionDescriptors[] = $prefix . ' ' . $variantRow[$column];
                        }
                    }
                    if (!empty($variantRow['weight'])) {
                        $dimensionDescriptors[] = 'Poids ' . $variantRow['weight'];
                    }
                    $descriptors = $dimensionDescriptors;
                }
                $variantLabel = $descriptors !== [] ? ' (' . implode('/', $descriptors) . ')' : ' (' . $variantRow['sku'] . ')';
            }

            $stockStmt = Database::connection()->prepare('SELECT COALESCE(SUM(quantity), 0) FROM stock_levels WHERE variant_id = :variant_id');
            $stockStmt->execute([':variant_id' => $variantId]);
            $stock = (int)$stockStmt->fetchColumn();
        } else {
            $stock = (int)($product['stock_total'] ?? 0);
        }

        // Un seul seuil : products.reorder_level (migration 202602270015).
        // min_stock faisait doublon - meme role, valeur concurrente.
        $threshold = (int)($product['reorder_level'] ?? 0);

        if ($stock > $threshold) {
            return;
        }

        $alertType = $stock <= 0 ? 'OUT_OF_STOCK' : 'LOW_STOCK';
        $severity = $stock <= 0 ? 'CRITICAL' : 'WARNING';
        $message = $stock <= 0
            ? sprintf('Rupture de stock pour %s%s (%s)', $product['name'], $variantLabel, $product['sku'])
            : sprintf('Stock bas pour %s%s (%s): %d', $product['name'], $variantLabel, $product['sku'], $stock);

        $this->alertRepository->create([
            'alert_type' => $alertType,
            'severity' => $severity,
            'product_id' => $productId,
            'variant_id' => $variantId,
            'warehouse_id' => $warehouseId,
            'message' => $message,
            'status' => 'OPEN',
        ]);
    }
}
