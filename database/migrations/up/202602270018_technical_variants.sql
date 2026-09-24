-- Quatrieme "saveur" de variantes (materiel electrique / mecanique) :
-- Puissance, Marque, Type, Vitesse, Tension, Forme. Meme principe que
-- 202602270009 (vetement), 202602270011 (bouteille) et 202602270014
-- (dimensions) : on reutilise la MEME table product_variants, puisque le
-- stock, les mouvements, les alertes, les livraisons, les achats et les
-- inventaires ne raisonnent qu'en variant_id et sont deja agnostiques du
-- type d'attribut. Seuls l'affichage et le formulaire changent cote frontend.
--
-- VARCHAR et non DECIMAL/ENUM : comme pour les dimensions, ce sont des
-- libelles de variante saisis librement, unite comprise ("1200 W", "230 V",
-- "3000 tr/min"), pas des donnees de calcul. "Marque" est ici un champ texte
-- propre a LA VARIANTE (ex: deux variantes du meme produit generique peuvent
-- venir de marques differentes) : volontairement PAS relie a la table
-- brands/products.brand_id, pour rester coherent avec les 3 autres saveurs
-- qui ne referencent aucune table de reference.

ALTER TABLE product_variants
    ADD COLUMN puissance VARCHAR(60) NULL AFTER weight,
    ADD COLUMN marque VARCHAR(100) NULL AFTER puissance,
    ADD COLUMN type VARCHAR(100) NULL AFTER marque,
    ADD COLUMN vitesse VARCHAR(60) NULL AFTER type,
    ADD COLUMN tension VARCHAR(60) NULL AFTER vitesse,
    ADD COLUMN forme VARCHAR(100) NULL AFTER tension;

-- Option desactivee par defaut : rien ne change pour les installations
-- existantes tant qu'elle n'est pas passee a 1 dans l'ecran Parametres.
INSERT INTO app_settings (setting_key, setting_value)
VALUES ('technical_variants_enabled', '0')
ON DUPLICATE KEY UPDATE setting_key = setting_key;
