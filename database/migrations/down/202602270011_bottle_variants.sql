-- Deuxieme "saveur" de variantes, sur le meme principe que taille/couleur
-- (voir 202602270009_product_variants.sql) : reutilise la MEME table
-- product_variants plutot que d'en creer une deuxieme, puisque le stock, les
-- mouvements, les alertes, les livraisons, les achats et les inventaires
-- sont deja entierement agnostiques du type d'attribut (ils ne
-- raisonnent qu'en variant_id). Seuls l'affichage et le formulaire cote
-- frontend changent selon l'option activee.
--
-- Millesime (annee) et contenance (en cl, ex: 75 pour une bouteille de
-- 75cl, 150 pour un magnum) : nullables, un produit "vetement" n'est pas
-- affecte.

ALTER TABLE product_variants
    ADD COLUMN vintage SMALLINT NULL AFTER color,
    ADD COLUMN volume_cl SMALLINT NULL AFTER vintage;
