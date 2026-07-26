ALTER TABLE stock_movements
    DROP FOREIGN KEY fk_stock_movements_destination_location,
    DROP FOREIGN KEY fk_stock_movements_source_location,
    DROP FOREIGN KEY fk_stock_movements_destination_warehouse,
    DROP COLUMN destination_warehouse_id,
    DROP COLUMN source_location_id,
    DROP COLUMN destination_location_id,
    DROP COLUMN reason_code,
    MODIFY COLUMN type ENUM('IN', 'OUT', 'ADJUSTMENT') NOT NULL;

ALTER TABLE products
    DROP FOREIGN KEY fk_products_unit,
    DROP FOREIGN KEY fk_products_brand,
    DROP FOREIGN KEY fk_products_tax,
    DROP COLUMN barcode,
    DROP COLUMN unit_id,
    DROP COLUMN brand_id,
    DROP COLUMN tax_id,
    DROP COLUMN pack_size,
    DROP COLUMN weight_kg,
    DROP COLUMN width_cm,
    DROP COLUMN height_cm,
    DROP COLUMN depth_cm,
    DROP COLUMN min_stock,
    DROP COLUMN max_stock,
    DROP COLUMN safety_stock,
    DROP COLUMN valuation_method,
    DROP COLUMN is_active;

ALTER TABLE warehouses
    DROP COLUMN code,
    DROP COLUMN status,
    DROP COLUMN updated_at;

ALTER TABLE suppliers
    DROP COLUMN lead_time_days,
    DROP COLUMN payment_terms,
    DROP COLUMN website,
    DROP COLUMN status;

ALTER TABLE categories
    DROP FOREIGN KEY fk_categories_parent,
    DROP FOREIGN KEY fk_categories_default_tax,
    DROP COLUMN parent_id,
    DROP COLUMN default_min_stock,
    DROP COLUMN default_max_stock,
    DROP COLUMN default_tax_id,
    DROP COLUMN tags_json;

DROP TABLE IF EXISTS product_price_history;
DROP TABLE IF EXISTS import_jobs;
DROP TABLE IF EXISTS document_sequences;
DROP TABLE IF EXISTS document_attachments;
DROP TABLE IF EXISTS stock_alerts;
DROP TABLE IF EXISTS inventory_session_items;
DROP TABLE IF EXISTS inventory_sessions;
DROP TABLE IF EXISTS purchase_request_items;
DROP TABLE IF EXISTS purchase_requests;
DROP TABLE IF EXISTS product_media;
DROP TABLE IF EXISTS product_tags;
DROP TABLE IF EXISTS supplier_contacts;
DROP TABLE IF EXISTS warehouse_locations;
DROP TABLE IF EXISTS warehouse_zones;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS brands;
DROP TABLE IF EXISTS taxes;
DROP TABLE IF EXISTS units;
