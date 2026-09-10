-- Annulation de 202602270011 : retire les attributs de variante "bouteille".
-- ATTENTION : supprime les millesimes et contenances deja saisis.
-- (Ce fichier contenait auparavant une copie du "up".)

SET NAMES utf8mb4;

ALTER TABLE product_variants
    DROP COLUMN IF EXISTS volume_cl,
    DROP COLUMN IF EXISTS vintage;
