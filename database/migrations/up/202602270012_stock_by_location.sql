-- ============================================================================
-- Suivi du stock PAR EMPLACEMENT (et plus seulement par entrepot)
-- ----------------------------------------------------------------------------
-- Jusqu'ici, zones et emplacements etaient de simples referentiels : on
-- pouvait les creer, mais le stock n'etait suivi qu'a la maille entrepot. On
-- savait "40 unites a Bruxelles", jamais "24 en B1 et 16 en C3".
--
-- location_id est NULLABLE, et c'est volontaire : une ligne a NULL represente
-- du stock present dans l'entrepot sans emplacement precis. C'est l'etat de
-- TOUTES les lignes existantes apres cette migration - rien n'est perdu ni
-- deplace - et c'est aussi le cas normal d'un entrepot ou l'on n'a defini
-- aucun emplacement.
--
-- ATTENTION (piege MySQL rencontre plusieurs fois dans ce projet) : une cle
-- unique n'est PAS appliquee quand l'une de ses colonnes vaut NULL. La cle
-- ci-dessous ne dedoublonne donc pas les lignes "sans emplacement" : le code
-- applicatif (ProductRepository) cible explicitement `location_id IS NULL`
-- dans ce cas au lieu de compter sur ON DUPLICATE KEY UPDATE.
--
-- ON DELETE RESTRICT sur l'emplacement : supprimer un emplacement qui contient
-- encore du stock doit echouer proprement (message metier via le handler
-- PDOException) plutot que de faire disparaitre des quantites en silence ou de
-- les rendre orphelines.
-- ============================================================================

SET NAMES utf8mb4;

ALTER TABLE stock_levels
    ADD COLUMN location_id BIGINT NULL AFTER warehouse_id;

ALTER TABLE stock_levels
    ADD CONSTRAINT fk_stock_levels_location
    FOREIGN KEY (location_id) REFERENCES warehouse_locations (id) ON DELETE RESTRICT;

ALTER TABLE stock_levels
    DROP INDEX uq_stock_level,
    ADD UNIQUE KEY uq_stock_level (product_id, warehouse_id, variant_id, location_id);

-- Retrouver rapidement le contenu d'un emplacement.
ALTER TABLE stock_levels
    ADD INDEX idx_stock_levels_location (location_id, product_id);
