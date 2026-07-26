SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS product_serials (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    serial_number VARCHAR(120) NOT NULL,
    warehouse_id INT NULL,
    status ENUM('IN_STOCK', 'OUT') NOT NULL DEFAULT 'IN_STOCK',
    notes VARCHAR(255) NULL,
    created_by INT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_product_serials_serial_number (serial_number),
    INDEX idx_product_serials_status (status),
    CONSTRAINT fk_product_serials_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
    CONSTRAINT fk_product_serials_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id) ON DELETE SET NULL,
    CONSTRAINT fk_product_serials_created_by FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;
