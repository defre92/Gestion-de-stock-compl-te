-- Troisieme "saveur" de variantes (materiel / mobilier / decoupe) : largeur,
-- hauteur, profondeur et poids. Meme principe que 202602270009 (vetement) et
-- 202602270011 (bouteille) : on reutilise la MEME table product_variants,
-- puisque le stock, les mouvements, les alertes, les livraisons, les achats et
-- les inventaires ne raisonnent qu'en variant_id et sont deja agnostiques du
-- type d'attribut. Seuls l'affichage et le formulaire changent cote frontend.
--
-- VARCHAR et non DECIMAL : les dimensions sont volontairement LIBRES. Un
-- utilisateur doit pouvoir saisir "120 cm", "2 m", "1,20 x 0,80", "3/4 pouce"
-- ou "sur mesure" sans etre bloque par une unite imposee. La valeur est un
-- libelle de variante, pas une donnee de calcul : les champs numeriques du
-- produit (products.width_cm / height_cm / depth_cm / weight_kg) restent la
-- pour les dimensions calculables d'un article sans variante, et les deux
-- coexistent (un produit peut avoir ses cotes ET des variantes de decoupe).

ALTER TABLE product_variants
    ADD COLUMN width VARCHAR(60) NULL AFTER volume_cl,
    ADD COLUMN height VARCHAR(60) NULL AFTER width,
    ADD COLUMN depth VARCHAR(60) NULL AFTER height,
    ADD COLUMN weight VARCHAR(60) NULL AFTER depth;

-- Option desactivee par defaut : rien ne change pour les installations
-- existantes tant qu'elle n'est pas passee a 1 dans l'ecran Parametres.
-- setting_key est UNIQUE et NOT NULL, ON DUPLICATE KEY est donc fiable ici
-- (contrairement aux cles uniques contenant une colonne nullable).
INSERT INTO app_settings (setting_key, setting_value)
VALUES ('dimension_variants_enabled', '0')
ON DUPLICATE KEY UPDATE setting_key = setting_key;
