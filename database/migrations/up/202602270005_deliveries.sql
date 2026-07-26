SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS deliveries (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    delivery_number VARCHAR(40) NOT NULL UNIQUE,
    customer_id INT NOT NULL,
    warehouse_id INT NOT NULL,
    status ENUM('VALIDATED', 'CANCELLED') NOT NULL DEFAULT 'VALIDATED',
    delivered_by INT NULL,
    delivered_at DATETIME NOT NULL,
    total_amount DECIMAL(14,2) NOT NULL DEFAULT 0,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_deliveries_customer FOREIGN KEY (customer_id) REFERENCES customers (id),
    CONSTRAINT fk_deliveries_warehouse FOREIGN KEY (warehouse_id) REFERENCES warehouses (id),
    CONSTRAINT fk_deliveries_user FOREIGN KEY (delivered_by) REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS delivery_lines (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    delivery_id BIGINT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(14,2) NOT NULL DEFAULT 0,
    line_total DECIMAL(14,2) NOT NULL DEFAULT 0,
    CONSTRAINT fk_delivery_lines_delivery FOREIGN KEY (delivery_id) REFERENCES deliveries (id) ON DELETE CASCADE,
    CONSTRAINT fk_delivery_lines_product FOREIGN KEY (product_id) REFERENCES products (id)
) ENGINE=InnoDB;
