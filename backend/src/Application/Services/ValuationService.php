<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\CostLayerRepository;
use App\Infrastructure\Persistence\ProductRepository;

/**
 * Rend reel le choix CUMP/FIFO de la fiche produit (products.valuation_method) :
 * jusqu'ici ce champ ne servait qu'a pre-remplir un menu deroulant, cost_price
 * restait une valeur saisie a la main, jamais recalculee.
 *
 * Appele par StockService::createMovement (voir la-bas pour le detail des
 * branchements par type de mouvement) - jamais par les controleurs
 * directement.
 *
 * CUMP (cout unitaire moyen pondere) : a chaque entree, le nouveau cost_price
 * est la moyenne du stock existant et de l'entree, ponderee par les
 * quantites. Aucune trace par lot n'est necessaire : un seul nombre suffit,
 * et il ne change jamais a une sortie (elle consomme au cout moyen courant,
 * qui reste courant).
 *
 * FIFO (premier entre, premier sorti) : chaque entree cree un lot distinct
 * (product_cost_layers). Chaque sortie consomme les lots du plus ancien au
 * plus recent. cost_price est ensuite recalcule comme la moyenne ponderee
 * des lots ENCORE en stock, pour rester affichable partout ou cost_price est
 * deja utilise (rapports, fiche produit...) sans reecrire ces ecrans.
 */
final class ValuationService
{
    public function __construct(
        private readonly ProductRepository $productRepository,
        private readonly CostLayerRepository $costLayerRepository
    ) {
    }

    /**
     * Entree de stock. $unitCost absent (reception manuelle sans cout
     * saisi) : on reprend le cost_price actuel du produit - c'est deja la
     * meilleure estimation disponible, et pour du CUMP la moyenne ponderee
     * reste alors inchangee (une entree "au cout actuel" ne peut pas la
     * deplacer).
     *
     * Retourne le cout unitaire effectivement utilise, pour l'inscrire sur
     * le mouvement de stock (tracabilite).
     */
    public function receiveStock(int $productId, ?int $variantId, int $quantity, ?float $unitCost, string $sourceType, ?int $sourceId): float
    {
        $product = $this->productRepository->lockForValuation($productId);
        if (!$product) {
            return $unitCost ?? 0.0;
        }

        $currentCost = (float)$product['cost_price'];
        $costUsed = $unitCost ?? $currentCost;

        if (strtoupper((string)$product['valuation_method']) === 'FIFO') {
            $this->costLayerRepository->addLayer($productId, $variantId, $quantity, $costUsed, $sourceType, $sourceId);
            $this->syncFifoCostPrice($productId);

            return $costUsed;
        }

        // CUMP : quantite AVANT cette entree (le mouvement de stock qui
        // l'ajoute n'a pas encore ete applique a cet instant - StockService
        // appelle receiveStock() avant d'ecrire la nouvelle quantite).
        $qtyBefore = $this->productRepository->totalQuantity($productId);
        $newQty = $qtyBefore + $quantity;
        $newCost = $newQty > 0
            ? (($qtyBefore * $currentCost) + ($quantity * $costUsed)) / $newQty
            : $costUsed;

        $this->productRepository->updateCostPrice($productId, round($newCost, 2));
        // Un lot est cree meme en CUMP (cout courant inutilise au quotidien) :
        // si ce produit passe un jour en FIFO, son historique de lots est deja
        // coherent plutot que de repartir de zero a partir de ce moment-la.
        $this->costLayerRepository->addLayer($productId, $variantId, $quantity, $costUsed, $sourceType, $sourceId);

        return $costUsed;
    }

    /**
     * Sortie de stock (vente/livraison, sortie manuelle, retrait
     * d'inventaire). Retourne le cout unitaire moyen effectivement consommee
     * (utile pour la tracabilite du mouvement, et plus tard un rapport de
     * marge) - en CUMP c'est simplement le cost_price courant, qui ne change
     * pas a une sortie.
     */
    public function consumeStock(int $productId, ?int $variantId, int $quantity): float
    {
        $product = $this->productRepository->lockForValuation($productId);
        if (!$product) {
            return 0.0;
        }

        $currentCost = (float)$product['cost_price'];

        if (strtoupper((string)$product['valuation_method']) !== 'FIFO') {
            return $currentCost;
        }

        [$consumed, $totalCost] = $this->costLayerRepository->consumeFifo($productId, $quantity);

        $shortfall = $quantity - $consumed;
        if ($shortfall > 0) {
            // Lots insuffisants (donnee historique incomplete - ex. stock
            // ajoute avant cette fonctionnalite, ou importe en masse sans
            // passer par un mouvement). On ne bloque pas la sortie pour
            // autant : le manque est valorise au dernier cost_price connu,
            // moins precis mais jamais bloquant.
            $totalCost += $shortfall * $currentCost;
        }

        $this->syncFifoCostPrice($productId);

        return $quantity > 0 ? round($totalCost / $quantity, 2) : $currentCost;
    }

    /** Recalcule cost_price = moyenne ponderee des lots FIFO encore en stock. */
    private function syncFifoCostPrice(int $productId): void
    {
        $remaining = $this->costLayerRepository->remainingValuation($productId);
        if ($remaining['quantity'] > 0) {
            $this->productRepository->updateCostPrice($productId, round($remaining['value'] / $remaining['quantity'], 2));
        }
        // Plus aucun lot (stock a zero) : on garde le dernier cost_price
        // connu plutot que de le remettre a 0 - c'est la meilleure
        // estimation pour la prochaine entree si aucun cout n'est saisi.
    }
}
