-- Annulation de 202602270014 : retire les attributs de variante "dimensions".
-- ATTENTION : supprime les largeurs/hauteurs/profondeurs/poids deja saisis
-- sur les variantes. Les variantes elles-memes et leur stock sont conserves.

SET NAMES utf8mb4;

ALTER TABLE product_variants
    DROP COLUMN IF EXISTS weight,
    DROP COLUMN IF EXISTS depth,
    DROP COLUMN IF EXISTS height,
    DROP COLUMN IF EXISTS width;

DELETE FROM app_settings WHERE setting_key = 'dimension_variants_enabled';
