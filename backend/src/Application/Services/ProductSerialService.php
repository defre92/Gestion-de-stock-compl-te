<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\ProductSerialRepository;
use App\Shared\Database\Database;
use App\Shared\Http\HttpException;
use Throwable;

final class ProductSerialService
{
    public function __construct(
        private readonly ProductSerialRepository $repository,
        private readonly AuditRepository $auditRepository,
        private readonly StockService $stockService
    ) {
    }

    /**
     * Enregistre le mouvement de stock correspondant a une action sur un
     * numero de serie.
     *
     * Un numero de serie represente UN article physique : le suivre sans
     * toucher aux quantites laissait les deux registres diverger. L'ecran
     * Mouvements, lui, faisait deja les deux (entree + enregistrement des
     * series) - c'est ce comportement-la qui est generalise ici.
     *
     * Le message d'erreur est reformule : "Stock insuffisant" brut n'aurait
     * aucun sens pour quelqu'un qui vient de cliquer sur "Marquer sorti".
     */
    private function moveStock(int $productId, ?int $variantId, ?int $warehouseId, string $type, int $quantity, string $reason, string $notes, int $actorId, ?string $ip, ?int $locationId = null): void
    {
        if ($warehouseId === null || $quantity <= 0) {
            return;
        }

        try {
            $this->stockService->createMovement([
                'product_id' => $productId,
                'variant_id' => $variantId,
                'warehouse_id' => $warehouseId,
                'type' => $type,
                'quantity' => $quantity,
                // Le mouvement vise l'emplacement du numero de serie : ranger
                // l'exemplaire en A1 doit incrementer A1, pas le stock non
                // localise de l'entrepot.
                'source_location_id' => $type === 'OUT' ? $locationId : null,
                'destination_location_id' => $type === 'OUT' ? null : $locationId,
                'reason_code' => $reason,
                'reference_type' => 'PRODUCT_SERIAL',
                'notes' => $notes,
            ], $actorId, $ip);
        } catch (HttpException $exception) {
            if (str_contains($exception->getMessage(), 'Stock insuffisant')) {
                throw new HttpException(
                    'La quantite en stock de ce produit dans cet entrepot est insuffisante : elle ne concorde pas avec les numeros de serie enregistres. Corrige la quantite par un mouvement d\'ajustement, puis recommence.',
                    422
                );
            }

            throw $exception;
        }
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        return $this->repository->paginate($page, $perPage, $filters);
    }

    public function findById(int $id): array
    {
        $serial = $this->repository->findById($id);
        if (!$serial) {
            throw new HttpException('Numero de serie introuvable', 404);
        }

        return $serial;
    }

    /**
     * Recherche un article par son SN exact - c'est le besoin principal:
     * "pouvoir rechercher un article par SN" retrouve directement le produit,
     * son statut, sa localisation actuelle, et l'historique des livraisons
     * (quand et a quel client il a ete vendu, le cas echeant).
     */
    public function search(string $serialNumber): array
    {
        $serialNumber = trim($serialNumber);
        if ($serialNumber === '') {
            throw new HttpException('Numero de serie requis', 422);
        }

        $result = $this->repository->findBySerialNumber($serialNumber);
        if (!$result) {
            throw new HttpException('Aucun article trouve pour ce numero de serie', 404);
        }

        $result['delivery_history'] = $this->repository->findDeliveryHistory((int)$result['id']);

        return $result;
    }

    public function create(array $payload, int $actorId, ?string $ip): array
    {
        $productId = (int)($payload['product_id'] ?? 0);
        $warehouseId = isset($payload['warehouse_id']) && $payload['warehouse_id'] !== ''
            ? (int)$payload['warehouse_id']
            : null;
        $variantId = isset($payload['variant_id']) && $payload['variant_id'] !== ''
            ? (int)$payload['variant_id']
            : null;
        // Un numero de serie designe UN article physique : savoir dans quelle
        // allee il se trouve est precisement ce qu'on cherche quand on va le
        // chercher a la main.
        $locationId = isset($payload['location_id']) && $payload['location_id'] !== ''
            ? (int)$payload['location_id']
            : null;

        // Accepte soit un seul SN (serial_number), soit une liste (serial_numbers,
        // un par ligne cote frontend) pour enregistrer un lot recu d'un coup.
        $serials = [];
        if (!empty($payload['serial_numbers']) && is_array($payload['serial_numbers'])) {
            $serials = $payload['serial_numbers'];
        } elseif (!empty($payload['serial_number'])) {
            $serials = [$payload['serial_number']];
        }

        $serials = array_values(array_unique(array_filter(array_map(
            static fn ($s): string => trim((string)$s),
            $serials
        ), static fn (string $s): bool => $s !== '')));

        if ($productId <= 0) {
            throw new HttpException('Produit requis', 422);
        }
        if ($serials === []) {
            throw new HttpException('Au moins un numero de serie est requis', 422);
        }

        foreach ($serials as $serial) {
            if (strlen($serial) > 120) {
                throw new HttpException("Numero de serie trop long: {$serial}", 422);
            }
            if ($this->repository->findBySerialNumber($serial) !== null) {
                throw new HttpException("Ce numero de serie existe deja: {$serial}", 422);
            }
        }

        // Deux usages legitimes, donc un choix explicite plutot qu'une regle
        // implicite : soit le materiel ARRIVE (il faut donc l'entrer en
        // stock), soit on note apres coup les numeros d'un stock deja compte
        // (aucun mouvement, sinon la quantite doublerait). Par defaut on
        // considere une entree : c'est l'usage courant de cet ecran.
        $createsStockEntry = !array_key_exists('creates_stock_entry', $payload)
            || filter_var($payload['creates_stock_entry'], FILTER_VALIDATE_BOOL);

        if ($createsStockEntry && $warehouseId === null) {
            throw new HttpException("L'entrepot est requis pour enregistrer une entree en stock", 422);
        }

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            $ids = $this->repository->createMany($productId, $warehouseId, $serials, $actorId, $variantId, $locationId);

            if ($createsStockEntry) {
                $this->moveStock(
                    $productId,
                    $variantId,
                    $warehouseId,
                    'IN',
                    count($ids),
                    'SERIAL_IN',
                    'Entree de ' . count($ids) . ' article(s) suivi(s) par numero de serie',
                    $actorId,
                    $ip,
                    $locationId
                );
            }

            $this->auditRepository->log($actorId, 'CREATE', 'product_serial', null, [
                'product_id' => $productId,
                'count' => count($ids),
                'stock_entry' => $createsStockEntry,
            ], $ip);

            if ($ownsTransaction) {
                $pdo->commit();
            }

            return $ids;
        } catch (Throwable $exception) {
            if ($ownsTransaction && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $exception;
        }
    }

    public function markOut(int $id, int $actorId, ?string $ip, ?string $notes): void
    {
        $serial = $this->repository->findById($id);
        if (!$serial) {
            throw new HttpException('Numero de serie introuvable', 404);
        }
        if ($serial['status'] === 'OUT') {
            throw new HttpException('Ce numero de serie est deja sorti', 422);
        }

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            // On lit l'entrepot AVANT le changement de statut : updateStatus le
            // remet a NULL pour une sortie, on ne saurait plus d'ou decrementer.
            $warehouseId = $serial['warehouse_id'] !== null ? (int)$serial['warehouse_id'] : null;
            $locationId = $serial['location_id'] !== null ? (int)$serial['location_id'] : null;

            $this->repository->updateStatus($id, 'OUT', null, $notes, null);
            $this->moveStock(
                (int)$serial['product_id'],
                $serial['variant_id'] !== null ? (int)$serial['variant_id'] : null,
                $warehouseId,
                'OUT',
                1,
                'SERIAL_OUT',
                'Sortie du numero de serie ' . $serial['serial_number'],
                $actorId,
                $ip,
                $locationId
            );

            $this->auditRepository->log($actorId, 'MARK_OUT', 'product_serial', $id, [], $ip);

            if ($ownsTransaction) {
                $pdo->commit();
            }
        } catch (Throwable $exception) {
            if ($ownsTransaction && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $exception;
        }
    }

    public function markInStock(int $id, int $warehouseId, int $actorId, ?string $ip, ?string $notes, ?int $locationId = null): void
    {
        $serial = $this->repository->findById($id);
        if (!$serial) {
            throw new HttpException('Numero de serie introuvable', 404);
        }
        if ($serial['status'] === 'IN_STOCK') {
            throw new HttpException('Ce numero de serie est deja en stock', 422);
        }

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            $this->repository->updateStatus($id, 'IN_STOCK', $warehouseId, $notes, $locationId);
            $this->moveStock(
                (int)$serial['product_id'],
                $serial['variant_id'] !== null ? (int)$serial['variant_id'] : null,
                $warehouseId,
                'IN',
                1,
                'SERIAL_RETURN',
                'Retour en stock du numero de serie ' . $serial['serial_number'],
                $actorId,
                $ip,
                $locationId
            );

            $this->auditRepository->log($actorId, 'MARK_IN_STOCK', 'product_serial', $id, [], $ip);

            if ($ownsTransaction) {
                $pdo->commit();
            }
        } catch (Throwable $exception) {
            if ($ownsTransaction && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $exception;
        }
    }

    /**
     * @param bool $adjustStock Retirer aussi 1 de la quantite en stock.
     *
     * Supprimer un numero de serie couvre deux situations que rien dans les
     * donnees ne permet de distinguer :
     *  - une erreur de saisie (le numero est faux, mais l'article est bien la)
     *    : la quantite ne doit PAS bouger ;
     *  - un article qui n'est plus la (casse, perdu, jamais recu) : la
     *    quantite doit baisser de 1.
     * L'ancien comportement supposait toujours le premier cas en silence, ce
     * qui laissait la quantite trop haute sans que personne ne le sache.
     * C'est donc l'utilisateur qui tranche, au moment de la suppression.
     *
     * Un numero deja sorti (OUT) n'est plus compte dans la quantite : sa
     * suppression ne peut pas la modifier, quel que soit ce parametre.
     */
    public function delete(int $id, int $actorId, ?string $ip, bool $adjustStock = false): void
    {
        $serial = $this->repository->findById($id);
        if (!$serial) {
            throw new HttpException('Numero de serie introuvable', 404);
        }

        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            $movesStock = $adjustStock && $serial['status'] === 'IN_STOCK';

            $this->repository->delete($id);

            if ($movesStock) {
                $this->moveStock(
                    (int)$serial['product_id'],
                    $serial['variant_id'] !== null ? (int)$serial['variant_id'] : null,
                    $serial['warehouse_id'] !== null ? (int)$serial['warehouse_id'] : null,
                    'OUT',
                    1,
                    'SERIAL_DELETED',
                    'Suppression du numero de serie ' . $serial['serial_number'] . ' (article absent du stock)',
                    $actorId,
                    $ip,
                    $serial['location_id'] !== null ? (int)$serial['location_id'] : null
                );
            }

            $this->auditRepository->log($actorId, 'DELETE', 'product_serial', $id, [
                'serial_number' => $serial['serial_number'],
                'stock_adjusted' => $movesStock,
            ], $ip);

            if ($ownsTransaction) {
                $pdo->commit();
            }
        } catch (Throwable $exception) {
            if ($ownsTransaction && $pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $exception;
        }
    }
}
