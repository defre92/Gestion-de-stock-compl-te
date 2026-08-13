-- Complement a 202602270009_product_variants.sql : etend le suivi par
-- variante aux lignes de documents (livraisons, achats, inventaires) et aux
-- numeros de serie. Nullable partout, aucun impact sur les produits sans
-- variante.

ALTER TABLE delivery_lines
    ADD COLUMN variant_id BIGINT NULL AFTER product_id,
    ADD CONSTRAINT fk_delivery_lines_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE SET NULL;

ALTER TABLE purchase_order_items
    ADD COLUMN variant_id BIGINT NULL AFTER product_id,
    ADD CONSTRAINT fk_purchase_order_items_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE SET NULL;

ALTER TABLE purchase_request_items
    ADD COLUMN variant_id BIGINT NULL AFTER product_id,
    ADD CONSTRAINT fk_purchase_request_items_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE SET NULL;

ALTER TABLE inventory_session_items
    ADD COLUMN variant_id BIGINT NULL AFTER product_id,
    ADD CONSTRAINT fk_inventory_session_items_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE SET NULL;

ALTER TABLE product_serials
    ADD COLUMN variant_id BIGINT NULL AFTER product_id,
    ADD CONSTRAINT fk_product_serials_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE SET NULL;
