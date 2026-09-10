-- ============================================================================
-- Emplacement des numeros de serie
-- ----------------------------------------------------------------------------
-- Depuis 202602270012 le stock est localise a l'emplacement pres. Un numero de
-- serie, qui designe UN article physique precis, ne portait pourtant que son
-- entrepot : on savait qu'un exemplaire etait a Bruxelles, jamais dans quelle
-- allee - alors que c'est justement l'exemplaire qu'on va chercher a la main.
--
-- Nullable, comme pour stock_levels : les numeros deja enregistres restent
-- "sans emplacement precis", et un entrepot sans emplacements definis
-- fonctionne comme avant.
--
-- ON DELETE RESTRICT, coherent avec stock_levels : supprimer un emplacement
-- ou se trouve encore un exemplaire doit echouer proprement plutot que de
-- perdre sa localisation en silence.
-- ============================================================================

SET NAMES utf8mb4;

ALTER TABLE product_serials
    ADD COLUMN location_id BIGINT NULL AFTER warehouse_id;

ALTER TABLE product_serials
    ADD CONSTRAINT fk_product_serials_location
    FOREIGN KEY (location_id) REFERENCES warehouse_locations (id) ON DELETE RESTRICT;

ALTER TABLE product_serials
    ADD INDEX idx_product_serials_location (location_id);
