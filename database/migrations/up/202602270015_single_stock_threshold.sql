-- Un seul seuil pilote desormais l'alerte de stock bas : products.reorder_level.
--
-- Avant cette migration, le formulaire produit demandait QUATRE valeurs :
-- "Seuil alerte" (reorder_level), "Stock mini" (min_stock), "Stock maxi"
-- (max_stock) et "Stock securite" (safety_stock). Dans les faits :
--   - reorder_level et min_stock faisaient LA MEME CHOSE, l'alerte se
--     declenchant sous le PLUS ELEVE des deux (GREATEST) ;
--   - max_stock et safety_stock n'etaient lus NULLE PART : stockes, affiches,
--     jamais utilises par une alerte, un rapport ou un controle. Saisir un
--     "stock de securite" en croyant se proteger n'avait aucun effet.
--
-- Le formulaire ne propose plus qu'un seuil, et le code ne lit plus que
-- reorder_level. Pour qu'AUCUN produit ne voie son alerte se desactiver au
-- passage, on remonte ici reorder_level au plus eleve des deux valeurs
-- existantes : un article qui alertait a 10 via min_stock continue d'alerter
-- a 10, desormais visible dans le champ unique.
--
-- Les colonnes min_stock, max_stock et safety_stock RESTENT en base : aucune
-- donnee saisie n'est perdue, et une installation qui les exploiterait par
-- ailleurs (export, requete maison) continue de les voir. Elles ne sont
-- simplement plus demandees ni lues par l'application.

UPDATE products
SET reorder_level = GREATEST(COALESCE(reorder_level, 0), COALESCE(min_stock, 0))
WHERE COALESCE(min_stock, 0) > COALESCE(reorder_level, 0);
