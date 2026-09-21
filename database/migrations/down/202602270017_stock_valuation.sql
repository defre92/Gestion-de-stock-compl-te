-- Annulation de 202602270017.
--
-- Supprime les lots de cout et la tracabilite du cout par mouvement. Les
-- valeurs de products.cost_price deja recalculees par CUMP/FIFO ne sont PAS
-- restaurees a leur ancienne valeur manuelle : cette ancienne valeur n'a pas
-- ete conservee (comme pour les autres migrations de ce projet qui ne
-- sauvegardent pas l'etat "avant").

DROP TABLE IF EXISTS product_cost_layers;

ALTER TABLE stock_movements
    DROP COLUMN unit_cost;
