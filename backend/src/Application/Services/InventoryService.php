<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\InventoryRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Shared\Database\Database;
use App\Shared\Http\HttpException;
use Throwable;

final class InventoryService
{
    public function __construct(
        private readonly InventoryRepository $repository,
        private readonly ProductRepository $productRepository,
        private readonly AuditRepository $auditRepository,
        private readonly StockService $stockService
    ) {
    }

    public function paginateSessions(int $page, int $perPage): array
    {
        return $this->repository->paginateSessions($page, $perPage);
    }

    public function findSession(int $id): array
    {
        $session = $this->repository->findSession($id);
        if (!$session) {
            throw new HttpException('Session d\'inventaire introuvable', 404);
        }

        return $session;
    }

    public function createSession(array $payload, int $actorId, ?string $ip): int
    {
        $warehouseId = (int)($payload['warehouse_id'] ?? 0);
        if ($warehouseId <= 0) {
            throw new HttpException('L\'entrepot est requis', 422);
        }

        $code = $payload['code'] ?? ('INV-' . date('Ymd') . '-' . strtoupper(substr(bin2hex(random_bytes(4)), 0, 5)));

        $id = $this->repository->createSession([
            'code' => $code,
            'warehouse_id' => $warehouseId,
            'counting_mode' => strtoupper((string)($payload['counting_mode'] ?? 'GLOBAL')),
            'status' => 'IN_PROGRESS',
            'created_by' => $actorId,
            'notes' => $payload['notes'] ?? null,
        ]);

        $this->auditRepository->log($actorId, 'CREATE', 'inventory_session', $id, ['code' => $code], $ip);

        return $id;
    }

    /**
     * Reste a compter d'une session (mode GLOBAL uniquement).
     *
     * Un inventaire tournant ne porte volontairement que sur une selection de
     * produits : lui presenter la liste de tout l'entrepot n'aurait pas de
     * sens. On renvoie donc une liste vide pour ce mode, avec le drapeau
     * `applicable` pour que le frontend n'affiche simplement pas le panneau.
     */
    public function remainingToCount(int $sessionId): array
    {
        $session = $this->findSession($sessionId);
        $warehouseId = (int)$session['warehouse_id'];

        if (strtoupper((string)($session['counting_mode'] ?? 'GLOBAL')) !== 'GLOBAL') {
            return ['applicable' => false, 'total' => 0, 'counted' => 0, 'items' => []];
        }

        $items = $this->repository->remainingToCount($sessionId, $warehouseId);
        $total = $this->repository->countableLines($warehouseId);

        return [
            'applicable' => true,
            'total' => $total,
            'counted' => max(0, $total - count($items)),
            'items' => $items,
        ];
    }

    public function addCount(int $sessionId, array $payload, int $actorId, ?string $ip): int
    {
        $session = $this->findSession($sessionId);
        if (!in_array($session['status'], ['IN_PROGRESS', 'DRAFT'], true)) {
            throw new HttpException('Cette session n\'est plus modifiable', 422);
        }

        $productId = (int)($payload['product_id'] ?? 0);
        $variantId = !empty($payload['variant_id']) ? (int)$payload['variant_id'] : null;
        $countedQty = (int)($payload['counted_qty'] ?? 0);

        if ($productId <= 0 || $countedQty < 0) {
            throw new HttpException('Donnees de comptage invalides', 422);
        }

        $product = $this->productRepository->findById($productId);
        if ($product && (int)($product['has_variants'] ?? 0) === 1 && $variantId === null) {
            throw new HttpException('Ce produit utilise des variantes : precise laquelle', 422);
        }

        // L'emplacement, quand il est renseigne, restreint le comptage a cet
        // emplacement precis : on compare alors a ce que la base dit de CETTE
        // allee, pas au total de l'entrepot. Sans lui, on compte le produit
        // dans l'entrepot entier, comme avant.
        $locationId = !empty($payload['location_id']) ? (int)$payload['location_id'] : null;

        $expectedQty = $this->repository->expectedQuantity((int)$session['warehouse_id'], $productId, $variantId, $locationId);
        $differenceQty = $countedQty - $expectedQty;

        $id = $this->repository->addCount([
            'session_id' => $sessionId,
            'product_id' => $productId,
            'variant_id' => $variantId,
            'expected_qty' => $expectedQty,
            'counted_qty' => $countedQty,
            'difference_qty' => $differenceQty,
            'location_id' => $locationId,
            'counted_by' => $actorId,
            'notes' => $payload['notes'] ?? null,
        ]);

        $this->auditRepository->log($actorId, 'COUNT', 'inventory_session_item', $id, ['session_id' => $sessionId], $ip);

        return $id;
    }

    public function finalize(int $sessionId, int $actorId, ?string $ip): void
    {
        $session = $this->findSession($sessionId);

        if ($session['status'] === 'COMPLETED') {
            throw new HttpException('Session deja cloturee', 422);
        }

        // Un meme produit peut avoir ete compte plusieurs fois dans la session
        // (recomptage volontaire apres une erreur de saisie). Seul le dernier
        // comptage saisi pour chaque produit doit generer l'ajustement de
        // stock final - les entrees precedentes pour ce produit sont
        // ignorees ici (elles restent visibles dans l'historique des
        // comptages, juste pas appliquees).
        $latestPerProduct = [];
        foreach ($session['items'] as $item) {
            // Cle produit+variante: sans le variant_id ici, deux variantes
            // du meme produit comptees dans la meme session s'ecraseraient
            // l'une l'autre et une seule generait un ajustement.
            // La cle inclut l'emplacement : deux allees du meme produit comptees
            // dans la meme session sont deux comptages distincts, chacun
            // generant son propre ajustement.
            $key = $item['product_id'] . '-' . ($item['variant_id'] ?? '0') . '-' . ($item['location_id'] ?? '0');
            $isNewer = !isset($latestPerProduct[$key])
                || (int)$item['id'] > (int)$latestPerProduct[$key]['id'];
            if ($isNewer) {
                $latestPerProduct[$key] = $item;
            }
        }

        // Transaction englobante : sans elle, chaque ajustement etait commite
        // individuellement par createMovement(). Un echec au 5e produit d'une
        // session de 10 laissait 4 ajustements de stock appliques, la session
        // toujours ouverte et aucun moyen simple de savoir ou l'operation
        // s'etait arretee. C'est tout ou rien.
        $pdo = Database::connection();
        $ownsTransaction = !$pdo->inTransaction();
        if ($ownsTransaction) {
            $pdo->beginTransaction();
        }

        try {
            foreach ($latestPerProduct as $item) {
                $diff = (int)$item['difference_qty'];
                if ($diff === 0) {
                    continue;
                }

                $this->stockService->createMovement([
                    'product_id' => (int)$item['product_id'],
                    'variant_id' => $item['variant_id'] ?? null,
                    'warehouse_id' => (int)$session['warehouse_id'],
                    'type' => 'ADJUSTMENT',
                    'quantity' => (int)$item['counted_qty'],
                    'reason_code' => 'INVENTORY',
                    'reference_type' => 'INVENTORY_SESSION',
                    'reference_id' => $sessionId,
                    // L'ajustement doit viser l'emplacement qui a ete compte,
                    // sinon un produit reparti sur plusieurs allees serait
                    // rejete ("precise l'emplacement") ou ajuste au mauvais
                    // endroit.
                    'destination_location_id' => $item['location_id'] ?? null,
                    'notes' => 'Ajustement genere par la session d\'inventaire',
                ], $actorId, $ip);
            }

            $this->repository->markSessionCompleted($sessionId);
            $this->auditRepository->log($actorId, 'FINALIZE', 'inventory_session', $sessionId, [], $ip);

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
