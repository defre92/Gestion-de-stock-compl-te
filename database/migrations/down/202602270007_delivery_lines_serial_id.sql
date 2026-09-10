-- Annulation de 202602270007 : retire le lien entre une ligne de livraison et
-- un numero de serie.
--
-- Ce fichier contenait auparavant une COPIE du "up" (des ADD COLUMN) : jouer
-- l'annulation echouait sur une colonne deja existante, ou pire, laissait la
-- base dans un etat different de celui attendu. Le bouton "Annuler le dernier
-- lot" de frontend/migrate.php s'appuie sur ces fichiers.

SET NAMES utf8mb4;

ALTER TABLE delivery_lines
    DROP FOREIGN KEY IF EXISTS fk_delivery_lines_serial;

ALTER TABLE delivery_lines
    DROP COLUMN IF EXISTS serial_id;
