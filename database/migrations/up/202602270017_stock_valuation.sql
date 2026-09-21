-- Rend reel le choix CUMP/FIFO sur la fiche produit (products.valuation_method).
--
-- Avant cette migration, ce champ n'etait qu'une etiquette : products.cost_price
-- etait une valeur saisie a la main, jamais recalculee automatiquement, quelle
-- que soit la methode choisie. Desormais :
--   - CUMP : cost_price est recalcule en moyenne ponderee a chaque entree de
--     stock avec un cout connu (reception de commande, entree manuelle avec
--     cout, stock initial).
--   - FIFO : chaque entree cree une ligne de "lot" (cout, quantite) dans
--     product_cost_layers ; chaque sortie consomme les lots du plus ancien au
--     plus recent ; cost_price refletera alors la valeur moyenne des lots
--     restants (pour rester lisible partout ou cost_price est deja affiche,
--     sans avoir a modifier les ecrans existants).
--
-- stock_movements.unit_cost trace le cout reellement utilise pour CHAQUE
-- mouvement (le cout de reception pour une entree, le cout moyen consomme
-- pour une sortie) : utile pour l'audit et de futurs rapports de marge.

ALTER TABLE stock_movements
    ADD COLUMN unit_cost DECIMAL(14, 2) NULL AFTER quantity;

CREATE TABLE IF NOT EXISTS product_cost_layers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    variant_id BIGINT NULL,
    quantity_remaining INT NOT NULL,
    unit_cost DECIMAL(14, 2) NOT NULL,
    source_type VARCHAR(30) NOT NULL,
    source_id BIGINT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_cost_layers_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT fk_cost_layers_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE CASCADE,
    INDEX idx_cost_layers_product_fifo (product_id, quantity_remaining, id)
) ENGINE=InnoDB;

-- Amorce les lots FIFO sur le stock deja en place, au cout actuellement
-- enregistre sur la fiche produit : sans cette ligne, un produit deja en
-- stock au moment de cette mise a jour n'aurait aucun lot tant qu'aucune
-- nouvelle entree n'aurait lieu, et la toute premiere sortie choisirait entre
-- "refuser faute de lot" ou "consommer a un cout invente". Amorcer pour TOUS
-- les produits (pas seulement ceux deja en FIFO) : un produit qu'on bascule
-- de CUMP vers FIFO plus tard dispose ainsi deja d'un lot de depart coherent.
INSERT INTO product_cost_layers (product_id, variant_id, quantity_remaining, unit_cost, source_type, created_at)
SELECT p.id, NULL, agg.total_qty, p.cost_price, 'INITIAL_BACKFILL', NOW()
FROM products p
INNER JOIN (
    SELECT product_id, SUM(quantity) AS total_qty
    FROM stock_levels
    GROUP BY product_id
    HAVING SUM(quantity) > 0
) agg ON agg.product_id = p.id;
