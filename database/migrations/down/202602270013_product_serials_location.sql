-- Annulation de 202602270013 : les numeros de serie ne portent plus que leur
-- entrepot. L'information "dans quelle allee" est perdue, ce qui est le propre
-- de cette annulation ; aucun numero de serie n'est supprime.

SET NAMES utf8mb4;

ALTER TABLE product_serials
    DROP FOREIGN KEY IF EXISTS fk_product_serials_location;

ALTER TABLE product_serials
    DROP INDEX IF EXISTS idx_product_serials_location;

ALTER TABLE product_serials
    DROP COLUMN IF EXISTS location_id;
