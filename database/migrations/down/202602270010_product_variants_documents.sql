ALTER TABLE product_serials DROP FOREIGN KEY fk_product_serials_variant, DROP COLUMN variant_id;
ALTER TABLE inventory_session_items DROP FOREIGN KEY fk_inventory_session_items_variant, DROP COLUMN variant_id;
ALTER TABLE purchase_request_items DROP FOREIGN KEY fk_purchase_request_items_variant, DROP COLUMN variant_id;
ALTER TABLE purchase_order_items DROP FOREIGN KEY fk_purchase_order_items_variant, DROP COLUMN variant_id;
ALTER TABLE delivery_lines DROP FOREIGN KEY fk_delivery_lines_variant, DROP COLUMN variant_id;
