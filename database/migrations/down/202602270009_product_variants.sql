-- Annulation de 202602270009 : retire completement le support des variantes.
-- ATTENTION : supprime la table product_variants et donc TOUTES les variantes
-- enregistrees, ainsi que les lignes de stock qui leur sont rattachees.
-- (Ce fichier contenait auparavant une copie du "up", ce qui rendait
-- l'annulation inoperante.)
--
-- Jouer d'abord l'annulation de 202602270010 et 202602270011, qui dependent de
-- cette table.

SET NAMES utf8mb4;

-- Les lignes de stock propres a une variante n'ont plus de sens sans elle.
DELETE FROM stock_levels WHERE variant_id IS NOT NULL;

ALTER TABLE stock_alerts
    DROP FOREIGN KEY IF EXISTS fk_stock_alerts_variant;
ALTER TABLE stock_alerts
    DROP COLUMN IF EXISTS variant_id;

ALTER TABLE stock_movements
    DROP FOREIGN KEY IF EXISTS fk_stock_movements_variant;
ALTER TABLE stock_movements
    DROP COLUMN IF EXISTS variant_id;

ALTER TABLE stock_levels
    DROP FOREIGN KEY IF EXISTS fk_stock_levels_variant;
ALTER TABLE stock_levels
    DROP INDEX IF EXISTS uq_stock_level,
    DROP COLUMN IF EXISTS variant_id,
    ADD UNIQUE KEY uq_stock_level (product_id, warehouse_id);

DROP TABLE IF EXISTS product_variants;

ALTER TABLE products
    DROP COLUMN IF EXISTS has_variants;
