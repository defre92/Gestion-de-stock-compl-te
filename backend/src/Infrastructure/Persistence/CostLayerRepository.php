<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

/**
 * Lots de cout FIFO (product_cost_layers). Chaque entree de stock avec un
 * cout connu cree un lot ; chaque sortie consomme les lots du plus ancien au
 * plus recent (premier entre, premier sorti). Un produit en CUMP n'utilise
 * pas cette table pour son cout courant (moyenne ponderee, un seul nombre
 * suffit - voir ValuationService), mais un lot y est quand meme cree pour lui
 * a chaque entree : si le produit passe un jour en FIFO, l'historique est
 * deja coherent plutot que de repartir de zero.
 */
final class CostLayerRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function addLayer(int $productId, ?int $variantId, int $quantity, float $unitCost, string $sourceType, ?int $sourceId): void
    {
        $stmt = $this->pdo->prepare('
            INSERT INTO product_cost_layers (product_id, variant_id, quantity_remaining, unit_cost, source_type, source_id, created_at)
            VALUES (:product_id, :variant_id, :quantity, :unit_cost, :source_type, :source_id, NOW())
        ');
        $stmt->execute([
            ':product_id' => $productId,
            ':variant_id' => $variantId,
            ':quantity' => $quantity,
            ':unit_cost' => $unitCost,
            ':source_type' => $sourceType,
            ':source_id' => $sourceId,
        ]);
    }

    /**
     * Consomme jusqu'a $quantity unites dans les lots les plus anciens
     * (ORDER BY id ASC = ordre d'entree). Verrouille les lots lus (FOR
     * UPDATE) pour qu'une sortie concurrente sur le meme produit ne puise pas
     * dans les memes unites.
     *
     * Retourne [quantite_consommee_depuis_des_lots, cout_total_de_ces_lots].
     * Si les lots ne couvrent pas toute la quantite demandee (donnee
     * historique incomplete, ecart), la quantite manquante n'est PAS
     * inventee ici : l'appelant (ValuationService) comble avec le dernier
     * cout connu plutot que de faire echouer un mouvement de stock pour une
     * imprecision de valorisation.
     *
     * @return array{0: int, 1: float}
     */
    public function consumeFifo(int $productId, int $quantity): array
    {
        $stmt = $this->pdo->prepare('
            SELECT id, quantity_remaining, unit_cost
            FROM product_cost_layers
            WHERE product_id = :product_id AND quantity_remaining > 0
            ORDER BY id ASC
            FOR UPDATE
        ');
        $stmt->execute([':product_id' => $productId]);
        $layers = $stmt->fetchAll();

        $remaining = $quantity;
        $totalCost = 0.0;
        $consumed = 0;

        foreach ($layers as $layer) {
            if ($remaining <= 0) {
                break;
            }

            $take = min((int)$layer['quantity_remaining'], $remaining);
            $update = $this->pdo->prepare('UPDATE product_cost_layers SET quantity_remaining = quantity_remaining - :take WHERE id = :id');
            $update->execute([':take' => $take, ':id' => $layer['id']]);

            $totalCost += $take * (float)$layer['unit_cost'];
            $consumed += $take;
            $remaining -= $take;
        }

        return [$consumed, $totalCost];
    }

    /**
     * Valeur restante des lots d'un produit : quantite totale et valeur
     * totale (quantite * cout) des lots dont il reste des unites. Sert a
     * recalculer le cost_price affiche d'un produit en FIFO (moyenne des
     * unites encore en stock).
     *
     * @return array{quantity: int, value: float}
     */
    public function remainingValuation(int $productId): array
    {
        $stmt = $this->pdo->prepare('
            SELECT COALESCE(SUM(quantity_remaining), 0) AS qty,
                   COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value
            FROM product_cost_layers
            WHERE product_id = :product_id AND quantity_remaining > 0
        ');
        $stmt->execute([':product_id' => $productId]);
        $row = $stmt->fetch();

        return ['quantity' => (int)($row['qty'] ?? 0), 'value' => (float)($row['value'] ?? 0)];
    }

    /** Lots restants d'un produit, du plus ancien au plus recent (ecran de detail produit). */
    public function listRemaining(int $productId): array
    {
        $stmt = $this->pdo->prepare('
            SELECT id, quantity_remaining, unit_cost, source_type, source_id, created_at
            FROM product_cost_layers
            WHERE product_id = :product_id AND quantity_remaining > 0
            ORDER BY id ASC
        ');
        $stmt->execute([':product_id' => $productId]);

        return $stmt->fetchAll();
    }
}
