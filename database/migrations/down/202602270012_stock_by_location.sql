-- Annulation de 202602270012 : revient a un stock suivi par entrepot.
--
-- Les quantites eclatees sur plusieurs emplacements d'un meme entrepot sont
-- REGROUPEES sur une seule ligne (aucune quantite perdue), puis la colonne est
-- supprimee. L'information "dans quel emplacement" est definitivement perdue,
-- ce qui est le propre de cette annulation.

SET NAMES utf8mb4;

-- 1. Regroupe les quantites par produit/variante/entrepot dans une table de travail.
CREATE TEMPORARY TABLE tmp_stock_merge AS
SELECT product_id, warehouse_id, variant_id,
       SUM(quantity) AS quantity,
       SUM(reserved_quantity) AS reserved_quantity
FROM stock_levels
GROUP BY product_id, warehouse_id, variant_id;

-- 2. Vide la table et retire la colonne.
DELETE FROM stock_levels;

ALTER TABLE stock_levels
    DROP FOREIGN KEY IF EXISTS fk_stock_levels_location;

ALTER TABLE stock_levels
    DROP INDEX IF EXISTS idx_stock_levels_location;

ALTER TABLE stock_levels
    DROP INDEX IF EXISTS uq_stock_level,
    DROP COLUMN IF EXISTS location_id,
    ADD UNIQUE KEY uq_stock_level (product_id, warehouse_id, variant_id);

-- 3. Reinjecte les quantites regroupees.
INSERT INTO stock_levels (product_id, warehouse_id, variant_id, quantity, reserved_quantity)
SELECT product_id, warehouse_id, variant_id, quantity, reserved_quantity FROM tmp_stock_merge;

DROP TEMPORARY TABLE tmp_stock_merge;
