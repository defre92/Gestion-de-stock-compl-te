SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS units (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(30) NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL,
    symbol VARCHAR(20) NULL,
    base_unit VARCHAR(30) NULL,
    conversion_factor DECIMAL(18,6) NOT NULL DEFAULT 1,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS taxes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(30) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    rate DECIMAL(6,3) NOT NULL DEFAULT 0,
    is_default TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS brands (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE,
    description TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS tags (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE,
    color VARCHAR(20) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

ALTER TABLE categories
    ADD COLUMN parent_id INT NULL AFTER id,
    ADD COLUMN default_min_stock INT NULL AFTER description,
    ADD COLUMN default_max_stock INT NULL AFTER default_min_stock,
    ADD COLUMN default_tax_id INT NULL AFTER default_max_stock,
    ADD COLUMN tags_json JSON NULL AFTER default_tax_id;

ALTER TABLE categories
    ADD INDEX idx_categories_parent (parent_id),
    ADD INDEX idx_categories_default_tax (default_tax_id);

ALTER TABLE categories
    ADD CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id) REFERENCES categories (id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_categories_default_tax FOREIGN KEY (default_tax_id) REFERENCES taxes (id) ON DELETE SET NULL;

ALTER TABLE suppliers
    ADD COLUMN lead_time_days INT NULL AFTER address,
    ADD COLUMN payment_terms VARCHAR(160) NULL AFTER lead_time_days,
    ADD COLUMN website VARCHAR(180) NULL AFTER payment_terms,
    ADD COLUMN status ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE' AFTER website;

CREATE TABLE IF NOT EXISTS supplier_contacts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    supplier_id INT NOT NULL,
    full_name VARCHAR(120) NOT NULL,
    email VARCHAR(150) NULL,
    phone VARCHAR(40) NULL,
    role_title VARCHAR(100) NULL,
    is_primary TINYINT(1) NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_supplier_contacts_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers (id) ON DELETE CASCADE
) ENGINE=InnoDB;

ALTER TABLE warehouses
    ADD COLUMN code VARCHAR(40) NULL AFTER id,
    ADD COLUMN status ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE' AFTER is_default,
    ADD COLUMN updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at;

ALTER TABLE warehouses
    ADD UNIQUE KEY uq_warehouse_code (code);

CREATE TABLE IF NOT EXISTS warehouse_zones (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    warehouse_id INT NOT NULL,
    code VARCHAR(40) NOT NULL,
    name VARCHAR(120) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_zone_code (warehouse_id, code),
    CONSTRAINT fk_warehouse_zones_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS warehouse_locations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    warehouse_id INT NOT NULL,
    zone_id BIGINT NULL,
    code VARCHAR(60) NOT NULL,
    description VARCHAR(180) NULL,
    capacity DECIMAL(14,2) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_location_code (warehouse_id, code),
    CONSTRAINT fk_locations_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id) ON DELETE CASCADE,
    CONSTRAINT fk_locations_zone FOREIGN KEY (zone_id) REFERENCES warehouse_zones (id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(40) NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NULL,
    phone VARCHAR(40) NULL,
    address TEXT NULL,
    status ENUM('ACTIVE', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

ALTER TABLE products
    ADD COLUMN barcode VARCHAR(80) NULL AFTER sku,
    ADD COLUMN unit_id INT NULL AFTER supplier_id,
    ADD COLUMN brand_id INT NULL AFTER unit_id,
    ADD COLUMN tax_id INT NULL AFTER brand_id,
    ADD COLUMN pack_size VARCHAR(80) NULL AFTER tax_id,
    ADD COLUMN weight_kg DECIMAL(12,3) NULL AFTER pack_size,
    ADD COLUMN width_cm DECIMAL(12,2) NULL AFTER weight_kg,
    ADD COLUMN height_cm DECIMAL(12,2) NULL AFTER width_cm,
    ADD COLUMN depth_cm DECIMAL(12,2) NULL AFTER height_cm,
    ADD COLUMN min_stock INT NOT NULL DEFAULT 0 AFTER reorder_level,
    ADD COLUMN max_stock INT NULL AFTER min_stock,
    ADD COLUMN safety_stock INT NOT NULL DEFAULT 0 AFTER max_stock,
    ADD COLUMN valuation_method ENUM('FIFO', 'CUMP') NOT NULL DEFAULT 'CUMP' AFTER safety_stock,
    ADD COLUMN is_active TINYINT(1) NOT NULL DEFAULT 1 AFTER status;

ALTER TABLE products
    ADD INDEX idx_products_barcode (barcode),
    ADD INDEX idx_products_unit (unit_id),
    ADD INDEX idx_products_brand (brand_id),
    ADD INDEX idx_products_tax (tax_id);

ALTER TABLE products
    ADD CONSTRAINT fk_products_unit FOREIGN KEY (unit_id) REFERENCES units (id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_products_brand FOREIGN KEY (brand_id) REFERENCES brands (id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_products_tax FOREIGN KEY (tax_id) REFERENCES taxes (id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS product_tags (
    product_id INT NOT NULL,
    tag_id INT NOT NULL,
    PRIMARY KEY (product_id, tag_id),
    CONSTRAINT fk_product_tags_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT fk_product_tags_tag FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS product_media (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    media_type ENUM('IMAGE', 'DOCUMENT') NOT NULL DEFAULT 'IMAGE',
    file_name VARCHAR(180) NOT NULL,
    file_path VARCHAR(255) NOT NULL,
    mime_type VARCHAR(120) NULL,
    uploaded_by INT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_product_media_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT fk_product_media_user FOREIGN KEY (uploaded_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;

ALTER TABLE stock_movements
    MODIFY COLUMN type ENUM('IN', 'OUT', 'ADJUSTMENT', 'TRANSFER') NOT NULL,
    ADD COLUMN destination_warehouse_id INT NULL AFTER warehouse_id,
    ADD COLUMN source_location_id BIGINT NULL AFTER destination_warehouse_id,
    ADD COLUMN destination_location_id BIGINT NULL AFTER source_location_id,
    ADD COLUMN reason_code VARCHAR(80) NULL AFTER notes;

ALTER TABLE stock_movements
    ADD INDEX idx_stock_movements_destination_warehouse (destination_warehouse_id),
    ADD INDEX idx_stock_movements_reason_code (reason_code);

ALTER TABLE stock_movements
    ADD CONSTRAINT fk_stock_movements_destination_warehouse FOREIGN KEY (destination_warehouse_id) REFERENCES warehouses (id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_stock_movements_source_location FOREIGN KEY (source_location_id) REFERENCES warehouse_locations (id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_stock_movements_destination_location FOREIGN KEY (destination_location_id) REFERENCES warehouse_locations (id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS purchase_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_number VARCHAR(40) NOT NULL UNIQUE,
    requester_id INT NOT NULL,
    warehouse_id INT NOT NULL,
    status ENUM('DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'CONVERTED') NOT NULL DEFAULT 'DRAFT',
    requested_at DATETIME NOT NULL,
    needed_at DATETIME NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_purchase_requests_requester FOREIGN KEY (requester_id) REFERENCES users (id),
    CONSTRAINT fk_purchase_requests_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS purchase_request_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    purchase_request_id BIGINT NOT NULL,
    product_id INT NOT NULL,
    quantity_requested INT NOT NULL,
    preferred_unit_cost DECIMAL(14,2) NULL,
    notes VARCHAR(255) NULL,
    CONSTRAINT fk_purchase_request_items_request FOREIGN KEY (purchase_request_id) REFERENCES purchase_requests (id) ON DELETE CASCADE,
    CONSTRAINT fk_purchase_request_items_product FOREIGN KEY (product_id) REFERENCES products (id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS inventory_sessions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    warehouse_id INT NOT NULL,
    status ENUM('DRAFT', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED') NOT NULL DEFAULT 'DRAFT',
    counting_mode ENUM('GLOBAL', 'CYCLE') NOT NULL DEFAULT 'GLOBAL',
    started_at DATETIME NULL,
    ended_at DATETIME NULL,
    created_by INT NOT NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_inventory_sessions_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id),
    CONSTRAINT fk_inventory_sessions_user FOREIGN KEY (created_by) REFERENCES users (id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS inventory_session_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id BIGINT NOT NULL,
    product_id INT NOT NULL,
    expected_qty INT NOT NULL,
    counted_qty INT NOT NULL,
    difference_qty INT NOT NULL,
    location_id BIGINT NULL,
    counted_by INT NULL,
    counted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes VARCHAR(255) NULL,
    CONSTRAINT fk_inventory_session_items_session FOREIGN KEY (session_id) REFERENCES inventory_sessions (id) ON DELETE CASCADE,
    CONSTRAINT fk_inventory_session_items_product FOREIGN KEY (product_id) REFERENCES products (id),
    CONSTRAINT fk_inventory_session_items_location FOREIGN KEY (location_id) REFERENCES warehouse_locations (id) ON DELETE SET NULL,
    CONSTRAINT fk_inventory_session_items_user FOREIGN KEY (counted_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS stock_alerts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    alert_type ENUM('LOW_STOCK', 'OUT_OF_STOCK', 'OVERSTOCK', 'PO_DELAY') NOT NULL,
    severity ENUM('INFO', 'WARNING', 'CRITICAL') NOT NULL DEFAULT 'WARNING',
    product_id INT NULL,
    purchase_order_id BIGINT NULL,
    warehouse_id INT NULL,
    message VARCHAR(255) NOT NULL,
    status ENUM('OPEN', 'ACKNOWLEDGED', 'RESOLVED') NOT NULL DEFAULT 'OPEN',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at DATETIME NULL,
    resolved_by INT NULL,
    CONSTRAINT fk_stock_alerts_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE SET NULL,
    CONSTRAINT fk_stock_alerts_po FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders (id) ON DELETE SET NULL,
    CONSTRAINT fk_stock_alerts_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id) ON DELETE SET NULL,
    CONSTRAINT fk_stock_alerts_resolved_by FOREIGN KEY (resolved_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS document_attachments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    entity_type VARCHAR(80) NOT NULL,
    entity_id BIGINT NOT NULL,
    file_name VARCHAR(180) NOT NULL,
    file_path VARCHAR(255) NOT NULL,
    mime_type VARCHAR(120) NULL,
    file_size BIGINT NULL,
    uploaded_by INT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_document_attachments_entity (entity_type, entity_id),
    CONSTRAINT fk_document_attachments_user FOREIGN KEY (uploaded_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS document_sequences (
    id INT AUTO_INCREMENT PRIMARY KEY,
    document_type VARCHAR(40) NOT NULL UNIQUE,
    prefix VARCHAR(20) NOT NULL,
    current_value INT NOT NULL DEFAULT 0,
    year_based TINYINT(1) NOT NULL DEFAULT 1,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS import_jobs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    entity_type VARCHAR(40) NOT NULL,
    file_name VARCHAR(180) NOT NULL,
    status ENUM('PENDING', 'RUNNING', 'DONE', 'FAILED') NOT NULL DEFAULT 'PENDING',
    total_rows INT NOT NULL DEFAULT 0,
    success_rows INT NOT NULL DEFAULT 0,
    failed_rows INT NOT NULL DEFAULT 0,
    error_log TEXT NULL,
    started_by INT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_import_jobs_user FOREIGN KEY (started_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS product_price_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    old_cost_price DECIMAL(14,2) NULL,
    new_cost_price DECIMAL(14,2) NULL,
    old_unit_price DECIMAL(14,2) NULL,
    new_unit_price DECIMAL(14,2) NULL,
    changed_by INT NULL,
    changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_product_price_history_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT fk_product_price_history_user FOREIGN KEY (changed_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;
