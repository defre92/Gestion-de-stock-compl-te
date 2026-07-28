SET NAMES utf8mb4;

-- Meme situation que delivery_lines.serial_id: le code (PurchaseOrderRepository)
-- lit/ecrit deja cette colonne pour lier une commande a la demande d'achat
-- dont elle est issue, mais aucune migration versionnee ne la creait.
ALTER TABLE purchase_orders
    ADD COLUMN IF NOT EXISTS purchase_request_id BIGINT NULL AFTER warehouse_id;

ALTER TABLE purchase_orders
    ADD CONSTRAINT fk_purchase_orders_request
    FOREIGN KEY IF NOT EXISTS (purchase_request_id) REFERENCES purchase_requests (id) ON DELETE SET NULL;
