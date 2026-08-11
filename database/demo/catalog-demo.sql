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

-- Point de depart de tout le scenario de demo (commandes, livraison,
-- inventaire...). Recalcule a chaque execution du script : la demo semble
-- toujours "recente", quel que soit le jour ou elle est chargee.
SET @demo_base = DATE_SUB(NOW(), INTERVAL 2 DAY);

-- __CURRENT_ADMIN_ID__ est remplace par frontend/demo-data.php avec l'id de
-- l'administrateur actuellement connecte (celui qui clique sur "Charger la
-- demo"), afin que les colonnes obligatoires ordered_by/requester_id/
-- created_by/moved_by/delivered_by/counted_by pointent vers un utilisateur
-- qui existe reellement sur la base du client.

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

-- Tags sur les produits de demo
INSERT INTO product_tags (product_id, tag_id)
SELECT p.id, t.id FROM products p JOIN tags t ON t.name = 'sensible' WHERE p.sku = 'SKU-USB32'
ON DUPLICATE KEY UPDATE product_id = product_id;

INSERT INTO product_tags (product_id, tag_id)
SELECT p.id, t.id FROM products p JOIN tags t ON t.name = 'rotation-rapide' WHERE p.sku = 'SKU-TONER'
ON DUPLICATE KEY UPDATE product_id = product_id;

-- Numeros de serie de demo (2 unites de Toner deja sorties, pour montrer le
-- suivi par numero de serie)
INSERT INTO product_serials (product_id, serial_number, status, created_by, created_at, updated_at)
SELECT p.id, 'SN-000001', 'OUT', __CURRENT_ADMIN_ID__, @demo_base, DATE_ADD(@demo_base, INTERVAL 120 SECOND)
FROM products p WHERE p.sku = 'SKU-TONER'
ON DUPLICATE KEY UPDATE status = VALUES(status);

INSERT INTO product_serials (product_id, serial_number, status, created_by, created_at, updated_at)
SELECT p.id, 'SN-000002', 'OUT', __CURRENT_ADMIN_ID__, @demo_base, DATE_ADD(@demo_base, INTERVAL 120 SECOND)
FROM products p WHERE p.sku = 'SKU-TONER'
ON DUPLICATE KEY UPDATE status = VALUES(status);

-- ============================================================================
-- ACTIVITE DE DEMO : une demande d'achat -> commande fournisseur -> livraison
-- client -> session d'inventaire -> mouvements de stock -> alertes, pour que
-- l'appli ne parte pas d'un catalogue vide mais montre un vrai scenario
-- d'usage. Toutes les dates sont relatives au moment ou ce script est
-- execute (@demo_base), donc toujours "recentes" quel que soit le jour ou
-- le client charge la demo.
-- ============================================================================

-- Demande d'achat n1 : 2 Toners, convertie en commande
INSERT INTO purchase_requests (request_number, requester_id, warehouse_id, status, requested_at, needed_at, notes, created_at, updated_at)
SELECT 'PR-DEMO-0001', __CURRENT_ADMIN_ID__, w.id, 'CONVERTED',
       DATE_ADD(@demo_base, INTERVAL 247 SECOND),
       DATE_ADD(DATE_ADD(@demo_base, INTERVAL 247 SECOND), INTERVAL 19 DAY),
       'Reappro toner', DATE_ADD(@demo_base, INTERVAL 247 SECOND), DATE_ADD(@demo_base, INTERVAL 294 SECOND)
FROM warehouses w WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE status = VALUES(status), updated_at = VALUES(updated_at);

INSERT INTO purchase_request_items (purchase_request_id, product_id, quantity_requested)
SELECT pr.id, p.id, 2
FROM purchase_requests pr, products p
WHERE pr.request_number = 'PR-DEMO-0001' AND p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM purchase_request_items i WHERE i.purchase_request_id = pr.id AND i.product_id = p.id);

-- Commande fournisseur n1, issue de la demande ci-dessus, deja receptionnee
INSERT INTO purchase_orders (order_number, supplier_id, warehouse_id, purchase_request_id, status, ordered_by, ordered_at, expected_at, received_at, notes, created_at, updated_at)
SELECT 'PO-DEMO-0001', s.id, w.id, pr.id, 'RECEIVED', __CURRENT_ADMIN_ID__,
       DATE_ADD(@demo_base, INTERVAL 294 SECOND),
       DATE_ADD(DATE_ADD(@demo_base, INTERVAL 294 SECOND), INTERVAL 16 DAY),
       DATE_ADD(@demo_base, INTERVAL 332 SECOND),
       '', DATE_ADD(@demo_base, INTERVAL 294 SECOND), DATE_ADD(@demo_base, INTERVAL 332 SECOND)
FROM suppliers s
JOIN warehouses w ON w.is_default = 1
JOIN purchase_requests pr ON pr.request_number = 'PR-DEMO-0001'
WHERE s.name = 'OfficePro'
ON DUPLICATE KEY UPDATE status = VALUES(status), received_at = VALUES(received_at);

INSERT INTO purchase_order_items (purchase_order_id, product_id, quantity_ordered, quantity_received, unit_cost, line_total)
SELECT po.id, p.id, 2, 2, p.cost_price, 2 * p.cost_price
FROM purchase_orders po, products p
WHERE po.order_number = 'PO-DEMO-0001' AND p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM purchase_order_items i WHERE i.purchase_order_id = po.id AND i.product_id = p.id);

-- Demande d'achat n2, convertie elle aussi (encore en attente de reception)
INSERT INTO purchase_requests (request_number, requester_id, warehouse_id, status, requested_at, needed_at, notes, created_at, updated_at)
SELECT 'PR-DEMO-0002', __CURRENT_ADMIN_ID__, w.id, 'CONVERTED',
       DATE_ADD(@demo_base, INTERVAL 1327 SECOND),
       DATE_ADD(DATE_ADD(@demo_base, INTERVAL 1327 SECOND), INTERVAL 12 DAY),
       '', DATE_ADD(@demo_base, INTERVAL 1327 SECOND), DATE_ADD(@demo_base, INTERVAL 1451 SECOND)
FROM warehouses w WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE status = VALUES(status), updated_at = VALUES(updated_at);

INSERT INTO purchase_request_items (purchase_request_id, product_id, quantity_requested)
SELECT pr.id, p.id, 10
FROM purchase_requests pr, products p
WHERE pr.request_number = 'PR-DEMO-0002' AND p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM purchase_request_items i WHERE i.purchase_request_id = pr.id AND i.product_id = p.id);

-- Commande fournisseur n2, encore en attente (pour montrer un statut PENDING)
INSERT INTO purchase_orders (order_number, supplier_id, warehouse_id, purchase_request_id, status, ordered_by, ordered_at, expected_at, notes, created_at, updated_at)
SELECT 'PO-DEMO-0002', s.id, w.id, pr.id, 'PENDING', __CURRENT_ADMIN_ID__,
       DATE_ADD(@demo_base, INTERVAL 1451 SECOND),
       DATE_ADD(DATE_ADD(@demo_base, INTERVAL 1451 SECOND), INTERVAL 15 DAY),
       '', DATE_ADD(@demo_base, INTERVAL 1451 SECOND), DATE_ADD(@demo_base, INTERVAL 1451 SECOND)
FROM suppliers s
JOIN warehouses w ON w.is_default = 1
JOIN purchase_requests pr ON pr.request_number = 'PR-DEMO-0002'
WHERE s.name = 'OfficePro'
ON DUPLICATE KEY UPDATE status = VALUES(status);

INSERT INTO purchase_order_items (purchase_order_id, product_id, quantity_ordered, quantity_received, unit_cost, line_total)
SELECT po.id, p.id, 10, 0, p.cost_price, 10 * p.cost_price
FROM purchase_orders po, products p
WHERE po.order_number = 'PO-DEMO-0002' AND p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM purchase_order_items i WHERE i.purchase_order_id = po.id AND i.product_id = p.id);

-- Livraison client validee (2 Toners au client CLI-001)
INSERT INTO deliveries (delivery_number, customer_id, warehouse_id, status, delivered_by, delivered_at, notes, created_at, updated_at)
SELECT 'BL-DEMO-0001', c.id, w.id, 'VALIDATED', __CURRENT_ADMIN_ID__,
       DATE_ADD(@demo_base, INTERVAL 173 SECOND), '',
       DATE_ADD(@demo_base, INTERVAL 173 SECOND), DATE_ADD(@demo_base, INTERVAL 173 SECOND)
FROM customers c
JOIN warehouses w ON w.is_default = 1
WHERE c.code = 'CLI-001'
ON DUPLICATE KEY UPDATE status = VALUES(status);

INSERT INTO delivery_lines (delivery_id, product_id, quantity, unit_price, line_total)
SELECT d.id, p.id, 2, p.unit_price, 2 * p.unit_price
FROM deliveries d, products p
WHERE d.delivery_number = 'BL-DEMO-0001' AND p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM delivery_lines l WHERE l.delivery_id = d.id AND l.product_id = p.id);

-- Session d'inventaire terminee, avec un ecart constate sur les 2 produits
INSERT INTO inventory_sessions (code, warehouse_id, status, counting_mode, started_at, ended_at, created_by, notes, created_at, updated_at)
SELECT 'INV-DEMO-0001', w.id, 'COMPLETED', 'GLOBAL',
       DATE_ADD(@demo_base, INTERVAL 398 SECOND), DATE_ADD(@demo_base, INTERVAL 446 SECOND),
       __CURRENT_ADMIN_ID__, '',
       DATE_ADD(@demo_base, INTERVAL 398 SECOND), DATE_ADD(@demo_base, INTERVAL 446 SECOND)
FROM warehouses w WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE status = VALUES(status), ended_at = VALUES(ended_at);

INSERT INTO inventory_session_items (session_id, product_id, expected_qty, counted_qty, difference_qty, location_id, counted_by, counted_at)
SELECT i.id, p.id, 6, 2, -4, wl.id, __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 412 SECOND)
FROM inventory_sessions i
JOIN products p ON p.sku = 'SKU-TONER'
LEFT JOIN warehouse_locations wl ON wl.code = 'B1'
WHERE i.code = 'INV-DEMO-0001'
  AND NOT EXISTS (SELECT 1 FROM inventory_session_items x WHERE x.session_id = i.id AND x.product_id = p.id);

INSERT INTO inventory_session_items (session_id, product_id, expected_qty, counted_qty, difference_qty, location_id, counted_by, counted_at)
SELECT i.id, p.id, 118, 100, -18, wl.id, __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 434 SECOND)
FROM inventory_sessions i
JOIN products p ON p.sku = 'SKU-USB32'
LEFT JOIN warehouse_locations wl ON wl.code = 'B1'
WHERE i.code = 'INV-DEMO-0001'
  AND NOT EXISTS (SELECT 1 FROM inventory_session_items x WHERE x.session_id = i.id AND x.product_id = p.id);

-- Historique des mouvements de stock correspondant a ce scenario
INSERT INTO stock_movements (product_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
SELECT p.id, w.id, 'OUT', 2, 118, 'CUSTOMER', c.id, '', '', __CURRENT_ADMIN_ID__, @demo_base
FROM products p JOIN warehouses w ON w.is_default = 1 JOIN customers c ON c.code = 'CLI-002'
WHERE p.sku = 'SKU-USB32'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

INSERT INTO stock_movements (product_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, reason_code, moved_by, created_at)
SELECT p.id, w.id, 'OUT', 2, 6, 'CUSTOMER', c.id, '', __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 120 SECOND)
FROM products p JOIN warehouses w ON w.is_default = 1 JOIN customers c ON c.code = 'CLI-001'
WHERE p.sku = 'SKU-TONER'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

INSERT INTO stock_movements (product_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
SELECT p.id, w.id, 'OUT', 2, 4, 'DELIVERY', d.id, CONCAT('BL ', d.delivery_number), 'DELIVERY', __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 173 SECOND)
FROM products p JOIN warehouses w ON w.is_default = 1 JOIN deliveries d ON d.delivery_number = 'BL-DEMO-0001'
WHERE p.sku = 'SKU-TONER'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

INSERT INTO stock_movements (product_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
SELECT p.id, w.id, 'IN', 2, 6, 'PURCHASE_ORDER', po.id, CONCAT('PO receipt ', po.order_number), 'PO_RECEIPT', __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 332 SECOND)
FROM products p JOIN warehouses w ON w.is_default = 1 JOIN purchase_orders po ON po.order_number = 'PO-DEMO-0001'
WHERE p.sku = 'SKU-TONER'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

INSERT INTO stock_movements (product_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
SELECT p.id, w.id, 'ADJUSTMENT', 100, 100, 'INVENTORY_SESSION', i.id, 'Inventory adjustment generated from session', 'INVENTORY', __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 446 SECOND)
FROM products p JOIN warehouses w ON w.is_default = 1 JOIN inventory_sessions i ON i.code = 'INV-DEMO-0001'
WHERE p.sku = 'SKU-USB32'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

INSERT INTO stock_movements (product_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
SELECT p.id, w.id, 'ADJUSTMENT', 2, 2, 'INVENTORY_SESSION', i.id, 'Inventory adjustment generated from session', 'INVENTORY', __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 446 SECOND)
FROM products p JOIN warehouses w ON w.is_default = 1 JOIN inventory_sessions i ON i.code = 'INV-DEMO-0001'
WHERE p.sku = 'SKU-TONER'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

-- Alertes de stock bas generees le long du scenario
INSERT INTO stock_alerts (alert_type, severity, product_id, warehouse_id, message, status, created_at)
SELECT 'LOW_STOCK', 'WARNING', p.id, w.id, 'Stock bas pour Toner Laser XL (SKU-TONER): 6', 'OPEN', DATE_ADD(@demo_base, INTERVAL 120 SECOND)
FROM products p JOIN warehouses w ON w.is_default = 1 WHERE p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM stock_alerts a WHERE a.message = 'Stock bas pour Toner Laser XL (SKU-TONER): 6' AND a.created_at = DATE_ADD(@demo_base, INTERVAL 120 SECOND));

INSERT INTO stock_alerts (alert_type, severity, product_id, warehouse_id, message, status, created_at)
SELECT 'LOW_STOCK', 'WARNING', p.id, w.id, 'Stock bas pour Toner Laser XL (SKU-TONER): 4', 'OPEN', DATE_ADD(@demo_base, INTERVAL 173 SECOND)
FROM products p JOIN warehouses w ON w.is_default = 1 WHERE p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM stock_alerts a WHERE a.message = 'Stock bas pour Toner Laser XL (SKU-TONER): 4' AND a.created_at = DATE_ADD(@demo_base, INTERVAL 173 SECOND));

INSERT INTO stock_alerts (alert_type, severity, product_id, warehouse_id, message, status, created_at)
SELECT 'LOW_STOCK', 'WARNING', p.id, w.id, 'Stock bas pour Toner Laser XL (SKU-TONER): 2', 'OPEN', DATE_ADD(@demo_base, INTERVAL 446 SECOND)
FROM products p JOIN warehouses w ON w.is_default = 1 WHERE p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM stock_alerts a WHERE a.message = 'Stock bas pour Toner Laser XL (SKU-TONER): 2' AND a.created_at = DATE_ADD(@demo_base, INTERVAL 446 SECOND));

-- Quantites finales en stock, coherentes avec l'historique de mouvements
-- ci-dessus (120 -> 100 pour la cle USB apres ajustement d'inventaire ;
-- 8 -> 2 pour le toner apres ventes + reception + ajustement).
UPDATE stock_levels sl
JOIN products p ON p.id = sl.product_id
SET sl.quantity = 100
WHERE p.sku = 'SKU-USB32';

UPDATE stock_levels sl
JOIN products p ON p.id = sl.product_id
SET sl.quantity = 2
WHERE p.sku = 'SKU-TONER';

