-- Annulation de 202602270008 : retire le lien entre une commande d'achat et la
-- demande d'achat dont elle est issue.
-- (Ce fichier contenait auparavant une copie du "up".)

SET NAMES utf8mb4;

ALTER TABLE purchase_orders
    DROP FOREIGN KEY IF EXISTS fk_purchase_orders_request;

ALTER TABLE purchase_orders
    DROP COLUMN IF EXISTS purchase_request_id;
