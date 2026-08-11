-- ============================================================================
-- DONNEES DE DEMO CATALOGUE - LIVRABLE CLIENT (contrairement a
-- database/seeders/pro/, ce fichier ne contient ni compte ni mot de passe et
-- PEUT etre inclus dans les livraisons clients). Utilise par
-- frontend/demo-data.php.
-- Genere a partir de 202602270001_seed_core_data.sql et
-- 202602270002_seed_advanced_data.sql, en retirant :
--   - la creation/mise a jour du compte admin demo (stock@lm-code.be)
--   - les roles (ADMIN, MANAGER, SUPER_ADMIN, BUYER, VIEWER, ...)
--   - les UPDATE globaux qui touchaient TOUTES les lignes existantes de
--     suppliers / warehouses / products (risque de modifier des donnees
--     deja en prod)
--   - document_sequences et app_settings (risque d'ecraser des reglages
--     ou de reinitialiser des compteurs PO/PR/INV deja utilises)
-- Toutes les requetes ci-dessous sont idempotentes (ON DUPLICATE KEY UPDATE
-- ou NOT EXISTS) : tu peux relancer ce fichier plusieurs fois sans doublon.
-- ============================================================================

SET NAMES utf8mb4;

-- Entrepot par defaut : cree seulement si aucun entrepot par defaut n'existe
-- deja chez toi (n'ecrase jamais un entrepot existant).
INSERT INTO warehouses (name, location, is_default)
SELECT 'Entrepot Principal', 'Bruxelles', 1
WHERE NOT EXISTS (SELECT 1 FROM warehouses WHERE is_default = 1);

-- Categories de demo
INSERT INTO categories (name, description) VALUES
('Informatique', 'Materiel informatique et accessoires'),
('Bureau', 'Fournitures de bureau et consommables'),
('Entretien', 'Produits d entretien et maintenance')
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- Fournisseurs de demo
INSERT INTO suppliers (name, contact_name, phone, email, address) VALUES
('OfficePro', 'Jean Martin', '0123456789', 'contact@officepro.com', 'Rue du Bureau 10, Bruxelles'),
('TechSupply', 'Laura Dupont', '0234567890', 'laura@techsupply.com', 'Rue du Circuit 22, Namur')
ON DUPLICATE KEY UPDATE contact_name = VALUES(contact_name), phone = VALUES(phone), email = VALUES(email), address = VALUES(address);

-- Produits de demo
INSERT INTO products (sku, name, description, category_id, supplier_id, unit_price, cost_price, reorder_level, status)
SELECT 'SKU-USB32', 'Cle USB 32Go', 'Stockage USB haute vitesse', c.id, s.id, 12.90, 8.40, 15, 'ACTIVE'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price), reorder_level = VALUES(reorder_level);

INSERT INTO products (sku, name, description, category_id, supplier_id, unit_price, cost_price, reorder_level, status)
SELECT 'SKU-TONER', 'Toner Laser XL', 'Toner noir imprimante laser', c.id, s.id, 79.00, 52.00, 6, 'ACTIVE'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price), reorder_level = VALUES(reorder_level);

-- Stock initial, sur l'entrepot par defaut existant (le tien ou celui cree ci-dessus)
INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 120, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'SKU-USB32'
ON DUPLICATE KEY UPDATE quantity = VALUES(quantity), reserved_quantity = VALUES(reserved_quantity);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 8, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'SKU-TONER'
ON DUPLICATE KEY UPDATE quantity = VALUES(quantity), reserved_quantity = VALUES(reserved_quantity);

-- Referentiels annexes (unites, taxes, marques, tags) : nouveaux codes,
-- collision peu probable, mais verifie les valeurs si tu as deja des taux
-- de TVA ou des unites configures avec les memes codes.
INSERT INTO units (code, name, symbol, base_unit, conversion_factor, is_active) VALUES
('PIECE', 'Piece', 'pc', 'PIECE', 1, 1),
('KG', 'Kilogramme', 'kg', 'KG', 1, 1),
('PACK6', 'Pack de 6', 'pack6', 'PIECE', 6, 1)
ON DUPLICATE KEY UPDATE name = VALUES(name), symbol = VALUES(symbol), conversion_factor = VALUES(conversion_factor), is_active = VALUES(is_active);

INSERT INTO taxes (code, name, rate, is_default) VALUES
('TVA_0', 'TVA 0%', 0.000, 0),
('TVA_10', 'TVA 10%', 10.000, 0),
('TVA_20', 'TVA 20%', 20.000, 1)
ON DUPLICATE KEY UPDATE name = VALUES(name), rate = VALUES(rate);

INSERT INTO brands (name, description) VALUES
('Generic', 'Marque generique'),
('ProLine', 'Marque professionnelle')
ON DUPLICATE KEY UPDATE description = VALUES(description);

INSERT INTO tags (name, color) VALUES
('critique', '#d64545'),
('rotation-rapide', '#2c7a7b'),
('sensible', '#6b46c1')
ON DUPLICATE KEY UPDATE color = VALUES(color);

-- Deuxieme entrepot de demo (nouveau, ne touche pas le tien)
INSERT INTO warehouses (name, code, location, is_default, status)
VALUES ('Entrepot Secondaire', 'WH-002', 'Namur', 0, 'ACTIVE')
ON DUPLICATE KEY UPDATE location = VALUES(location), status = VALUES(status);

INSERT INTO warehouse_zones (warehouse_id, code, name)
SELECT w.id, 'B', 'Zone B' FROM warehouses w WHERE w.code = 'WH-002'
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO warehouse_locations (warehouse_id, zone_id, code, description, capacity, is_active)
SELECT w.id, z.id, 'B1', 'Rayon B1', 300, 1
FROM warehouses w
JOIN warehouse_zones z ON z.warehouse_id = w.id AND z.code = 'B'
WHERE w.code = 'WH-002'
ON DUPLICATE KEY UPDATE description = VALUES(description), capacity = VALUES(capacity), is_active = VALUES(is_active);

-- Clients de demo
INSERT INTO customers (code, name, email, phone, address, status) VALUES
('CLI-001', 'Client Interne RH', 'rh@societe.local', '0101010101', 'Siege Bruxelles', 'ACTIVE'),
('CLI-002', 'Client Interne IT', 'it@societe.local', '0202020202', 'Site Namur', 'ACTIVE')
ON DUPLICATE KEY UPDATE name = VALUES(name), email = VALUES(email), phone = VALUES(phone), address = VALUES(address), status = VALUES(status);

-- Rattachement unite/marque/taxe UNIQUEMENT sur les 2 produits de demo
-- crees ci-dessus (jamais sur le reste de ton catalogue existant).
UPDATE products p
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN taxes t ON t.code = 'TVA_20'
SET p.unit_id = COALESCE(p.unit_id, u.id),
    p.brand_id = COALESCE(p.brand_id, b.id),
    p.tax_id = COALESCE(p.tax_id, t.id),
    p.min_stock = COALESCE(p.min_stock, p.reorder_level),
    p.safety_stock = COALESCE(p.safety_stock, 5),
    p.valuation_method = COALESCE(p.valuation_method, 'CUMP'),
    p.is_active = 1
WHERE p.sku IN ('SKU-USB32', 'SKU-TONER');
