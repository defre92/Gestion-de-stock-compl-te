-- Support optionnel des variantes produit (taille/couleur), pense pour le
-- stock vetement mais reste generique : `attributes_json` absorbe d'autres
-- attributs (pointure, contenance...) sans nouvelle migration.
-- Chaque produit choisit individuellement s'il utilise des variantes
-- (colonne products.has_variants) ; le stock existant (produits sans
-- variante) n'est pas affecte, variant_id reste NULL partout.

ALTER TABLE products
    ADD COLUMN has_variants TINYINT(1) NOT NULL DEFAULT 0 AFTER status;

CREATE TABLE IF NOT EXISTS product_variants (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    sku VARCHAR(80) NOT NULL,
    barcode VARCHAR(80) NULL,
    size VARCHAR(50) NULL,
    color VARCHAR(50) NULL,
    attributes_json JSON NULL,
    unit_price DECIMAL(12,2) NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_product_variant_sku (sku),
    CONSTRAINT fk_product_variants_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Stock, mouvements et alertes deviennent trackables par variante. Nullable
-- partout : un produit sans variante continue de fonctionner exactement
-- comme avant (variant_id NULL).
ALTER TABLE stock_levels
    ADD COLUMN variant_id BIGINT NULL AFTER product_id,
    ADD CONSTRAINT fk_stock_levels_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE CASCADE,
    DROP INDEX uq_stock_level,
    ADD UNIQUE KEY uq_stock_level (product_id, warehouse_id, variant_id);

ALTER TABLE stock_movements
    ADD COLUMN variant_id BIGINT NULL AFTER product_id,
    ADD CONSTRAINT fk_stock_movements_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE SET NULL;

ALTER TABLE stock_alerts
    ADD COLUMN variant_id BIGINT NULL AFTER product_id,
    ADD CONSTRAINT fk_stock_alerts_variant FOREIGN KEY (variant_id) REFERENCES product_variants (id) ON DELETE CASCADE;
