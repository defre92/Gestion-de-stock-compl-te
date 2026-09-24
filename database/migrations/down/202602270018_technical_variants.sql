-- Annulation de 202602270018 : retire les attributs de variante "materiel".
-- ATTENTION : supprime les puissances/marques/types/vitesses/tensions/formes
-- deja saisis sur les variantes. Les variantes elles-memes et leur stock sont
-- conserves.

SET NAMES utf8mb4;

ALTER TABLE product_variants
    DROP COLUMN IF EXISTS forme,
    DROP COLUMN IF EXISTS tension,
    DROP COLUMN IF EXISTS vitesse,
    DROP COLUMN IF EXISTS type,
    DROP COLUMN IF EXISTS marque,
    DROP COLUMN IF EXISTS puissance;

DELETE FROM app_settings WHERE setting_key = 'technical_variants_enabled';
