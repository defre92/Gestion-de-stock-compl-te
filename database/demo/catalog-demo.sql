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
-- NOT EXISTS et non ON DUPLICATE KEY UPDATE : variant_id vaut NULL ici, et
-- MySQL n'applique pas l'unicite de (product_id, warehouse_id, variant_id)
-- quand une colonne de la cle est NULL. Avec ON DUPLICATE KEY, relancer le
-- script creait une deuxieme ligne de stock pour le meme produit.
INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 120, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'SKU-USB32'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

-- NOT EXISTS et non ON DUPLICATE KEY UPDATE : variant_id vaut NULL ici, et
-- MySQL n'applique pas l'unicite de (product_id, warehouse_id, variant_id)
-- quand une colonne de la cle est NULL. Avec ON DUPLICATE KEY, relancer le
-- script creait une deuxieme ligne de stock pour le meme produit.
INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 8, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'SKU-TONER'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

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

-- Zones et emplacements de l'entrepot PRINCIPAL.
-- Ils manquaient : la demo ne definissait d'emplacement que dans l'entrepot
-- secondaire, alors que tout le stock est dans le principal. Resultat, en
-- choisissant "Entrepot Principal" dans un mouvement, la liste des
-- emplacements etait vide et la fonctionnalite semblait cassee alors qu'il n'y
-- avait simplement rien a proposer.
INSERT INTO warehouse_zones (warehouse_id, code, name)
SELECT w.id, 'A', 'Zone A - Picking' FROM warehouses w WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO warehouse_zones (warehouse_id, code, name)
SELECT w.id, 'C', 'Zone C - Reserve' FROM warehouses w WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO warehouse_locations (warehouse_id, zone_id, code, description, capacity, is_active)
SELECT w.id, z.id, 'A1', 'Allee A - niveau 1', 200, 1
FROM warehouses w
JOIN warehouse_zones z ON z.warehouse_id = w.id AND z.code = 'A'
WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE description = VALUES(description), capacity = VALUES(capacity), is_active = VALUES(is_active);

INSERT INTO warehouse_locations (warehouse_id, zone_id, code, description, capacity, is_active)
SELECT w.id, z.id, 'A2', 'Allee A - niveau 2', 200, 1
FROM warehouses w
JOIN warehouse_zones z ON z.warehouse_id = w.id AND z.code = 'A'
WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE description = VALUES(description), capacity = VALUES(capacity), is_active = VALUES(is_active);

INSERT INTO warehouse_locations (warehouse_id, zone_id, code, description, capacity, is_active)
SELECT w.id, z.id, 'A3', 'Allee A - niveau 3', 200, 1
FROM warehouses w
JOIN warehouse_zones z ON z.warehouse_id = w.id AND z.code = 'A'
WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE description = VALUES(description), capacity = VALUES(capacity), is_active = VALUES(is_active);

INSERT INTO warehouse_locations (warehouse_id, zone_id, code, description, capacity, is_active)
SELECT w.id, z.id, 'C1', 'Reserve - palettier 1', 800, 1
FROM warehouses w
JOIN warehouse_zones z ON z.warehouse_id = w.id AND z.code = 'C'
WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE description = VALUES(description), capacity = VALUES(capacity), is_active = VALUES(is_active);

INSERT INTO warehouse_locations (warehouse_id, zone_id, code, description, capacity, is_active)
SELECT w.id, z.id, 'C2', 'Reserve - palettier 2', 800, 1
FROM warehouses w
JOIN warehouse_zones z ON z.warehouse_id = w.id AND z.code = 'C'
WHERE w.is_default = 1
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


-- ============================================================================
-- CATALOGUE ETENDU (ajoute au scenario de demo ci-dessus)
-- ----------------------------------------------------------------------------
-- Objectif : disposer d'un volume realiste pour tester la pagination, les
-- variantes (vetement ET bouteille), les taxes, les marques, les unites, les
-- tags, les produits actifs/inactifs et les deux methodes de valorisation.
--
-- Comme le reste du fichier, tout est idempotent (ON DUPLICATE KEY UPDATE sur
-- des cles uniques) : relancer "Charger les donnees de demo" ne cree aucun
-- doublon. Et tout est supprime par le bouton "Reinitialiser les donnees".
-- ============================================================================

-- Categories supplementaires
INSERT INTO categories (name, description) VALUES
('Vetements', 'Pret-a-porter, tailles et couleurs'),
('Chaussures', 'Chaussures, pointures'),
('Vins et spiritueux', 'Bouteilles, millesimes et contenances'),
('Electromenager', 'Petit et gros electromenager'),
('Papeterie', 'Papier, classement, ecriture'),
('Securite', 'Equipements de protection individuelle')
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- Fournisseurs supplementaires
INSERT INTO suppliers (name, contact_name, phone, email, address) VALUES
('Textile Nord', 'Sophie Legrand', '0320114455', 'contact@textilenord.fr', 'Rue des Tisserands 8, Lille'),
('Cave Bertrand', 'Paul Bertrand', '0556223344', 'paul@cavebertrand.fr', 'Route des Vignes 45, Bordeaux'),
('ElectroDis', 'Karim Benali', '0472889911', 'karim@electrodis.fr', 'Avenue des Halles 3, Lyon'),
('Papeterie Centrale', 'Claire Moreau', '0141556677', 'claire@papcentrale.fr', 'Boulevard Voltaire 120, Paris'),
('SecuPro', 'Marc Vasseur', '0388114422', 'marc@secupro.fr', 'Zone Industrielle Est, Strasbourg')
ON DUPLICATE KEY UPDATE contact_name = VALUES(contact_name), phone = VALUES(phone), email = VALUES(email), address = VALUES(address);

-- Marques supplementaires
INSERT INTO brands (name, description) VALUES
('NordWear', 'Marque textile du fournisseur Textile Nord'),
('Domaine Bertrand', 'Vins du domaine Bertrand'),
('ElectroDis', 'Electromenager d entree de gamme'),
('Papyrus', 'Papeterie et classement'),
('SecuPro', 'Equipements de protection')
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- Tags supplementaires
INSERT INTO tags (name, color) VALUES
('saisonnier', '#f59e0b'),
('fragile', '#ef4444'),
('promo', '#22c55e'),
('gros-volume', '#6366f1')
ON DUPLICATE KEY UPDATE color = VALUES(color);


-- Produits sans variantes

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-001', 'Clavier mecanique', 'Clavier mecanique - article de demonstration', c.id, s.id, b.id, u.id, t.id, 24.54, 18.12, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-002', 'Souris sans fil', 'Souris sans fil - article de demonstration', c.id, s.id, b.id, u.id, t.id, 30.34, 24.11, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-003', 'Ecran 24 pouces', 'Ecran 24 pouces - article de demonstration', c.id, s.id, b.id, u.id, t.id, 79.81, 44.34, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-004', 'Casque USB', 'Casque USB - article de demonstration', c.id, s.id, b.id, u.id, t.id, 128.92, 85.96, 8, 8, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-005', 'Webcam HD', 'Webcam HD - article de demonstration', c.id, s.id, b.id, u.id, t.id, 44.96, 30.26, 15, 15, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-006', 'Disque SSD 500Go', 'Disque SSD 500Go - article de demonstration', c.id, s.id, b.id, u.id, t.id, 57.97, 36.83, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-007', 'Hub USB-C', 'Hub USB-C - article de demonstration', c.id, s.id, b.id, u.id, t.id, 155.13, 104.45, 8, 8, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-008', 'Cable HDMI 2m', 'Cable HDMI 2m - article de demonstration', c.id, s.id, b.id, u.id, t.id, 157.47, 86.05, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-009', 'Routeur Wi-Fi', 'Routeur Wi-Fi - article de demonstration', c.id, s.id, b.id, u.id, t.id, 153.94, 89.08, 8, 8, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-010', 'Onduleur 650VA', 'Onduleur 650VA - article de demonstration', c.id, s.id, b.id, u.id, t.id, 24.01, 13.04, 15, 15, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-011', 'Station d accueil', 'Station d accueil - article de demonstration', c.id, s.id, b.id, u.id, t.id, 93.98, 56.99, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-012', 'Adaptateur secteur', 'Adaptateur secteur - article de demonstration', c.id, s.id, b.id, u.id, t.id, 243.44, 140.36, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-013', 'Rallonge reseau 5m', 'Rallonge reseau 5m - article de demonstration', c.id, s.id, b.id, u.id, t.id, 189.59, 141.83, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-014', 'Support ecran', 'Support ecran - article de demonstration', c.id, s.id, b.id, u.id, t.id, 191.3, 140.01, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-015', 'Tapis de souris', 'Tapis de souris - article de demonstration', c.id, s.id, b.id, u.id, t.id, 133.25, 86.96, 20, 20, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-001', 'Chaise de bureau', 'Chaise de bureau - article de demonstration', c.id, s.id, b.id, u.id, t.id, 270.27, 164.02, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-002', 'Lampe de bureau', 'Lampe de bureau - article de demonstration', c.id, s.id, b.id, u.id, t.id, 17.01, 12.14, 10, 10, 'ACTIVE', 0, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-003', 'Corbeille a papier', 'Corbeille a papier - article de demonstration', c.id, s.id, b.id, u.id, t.id, 236.29, 160.58, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-004', 'Tableau blanc', 'Tableau blanc - article de demonstration', c.id, s.id, b.id, u.id, t.id, 52.77, 38.56, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-005', 'Porte-revues', 'Porte-revues - article de demonstration', c.id, s.id, b.id, u.id, t.id, 178.37, 97.3, 10, 10, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-006', 'Repose-pieds', 'Repose-pieds - article de demonstration', c.id, s.id, b.id, u.id, t.id, 68.82, 44.12, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-007', 'Horloge murale', 'Horloge murale - article de demonstration', c.id, s.id, b.id, u.id, t.id, 282.13, 176.33, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-008', 'Destructeur de documents', 'Destructeur de documents - article de demonstration', c.id, s.id, b.id, u.id, t.id, 63.62, 45.94, 8, 8, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-001', 'Detergent multi-usage 5L', 'Detergent multi-usage 5L - article de demonstration', c.id, s.id, b.id, u.id, t.id, 138.4, 91.99, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-002', 'Lingettes desinfectantes', 'Lingettes desinfectantes - article de demonstration', c.id, s.id, b.id, u.id, t.id, 53.77, 29.95, 10, 10, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-003', 'Sac poubelle 100L', 'Sac poubelle 100L - article de demonstration', c.id, s.id, b.id, u.id, t.id, 266.41, 148.64, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-004', 'Balai microfibre', 'Balai microfibre - article de demonstration', c.id, s.id, b.id, u.id, t.id, 120.53, 72.95, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-005', 'Gel hydroalcoolique 1L', 'Gel hydroalcoolique 1L - article de demonstration', c.id, s.id, b.id, u.id, t.id, 119.97, 92.09, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-006', 'Essuie-mains rouleau', 'Essuie-mains rouleau - article de demonstration', c.id, s.id, b.id, u.id, t.id, 127.5, 89.11, 8, 8, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-007', 'Nettoyant vitres 750ml', 'Nettoyant vitres 750ml - article de demonstration', c.id, s.id, b.id, u.id, t.id, 78.34, 41.79, 5, 5, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-001', 'Ramette A4 80g', 'Ramette A4 80g - article de demonstration', c.id, s.id, b.id, u.id, t.id, 46.99, 31.63, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-002', 'Stylo bille bleu', 'Stylo bille bleu - article de demonstration', c.id, s.id, b.id, u.id, t.id, 116.81, 87.47, 8, 8, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-003', 'Classeur levier 8cm', 'Classeur levier 8cm - article de demonstration', c.id, s.id, b.id, u.id, t.id, 208.02, 136.88, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-004', 'Pochette plastique A4', 'Pochette plastique A4 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 205.39, 137.92, 10, 10, 'ACTIVE', 0, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-005', 'Bloc-notes A5', 'Bloc-notes A5 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 106.38, 82.14, 8, 8, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-006', 'Agrafeuse metal', 'Agrafeuse metal - article de demonstration', c.id, s.id, b.id, u.id, t.id, 217.08, 139.57, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-007', 'Ruban adhesif', 'Ruban adhesif - article de demonstration', c.id, s.id, b.id, u.id, t.id, 184.2, 106.59, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-008', 'Marqueur permanent', 'Marqueur permanent - article de demonstration', c.id, s.id, b.id, u.id, t.id, 16.15, 10.42, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-009', 'Post-it 76x76', 'Post-it 76x76 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 216.4, 136.24, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-010', 'Enveloppe C4', 'Enveloppe C4 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 191.13, 107.95, 10, 10, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-011', 'Cahier spirale A4', 'Cahier spirale A4 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 115.58, 69.91, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-012', 'Chemise cartonnee', 'Chemise cartonnee - article de demonstration', c.id, s.id, b.id, u.id, t.id, 56.96, 40.87, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-001', 'Casque de chantier', 'Casque de chantier - article de demonstration', c.id, s.id, b.id, u.id, t.id, 200.71, 147.22, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-002', 'Gants anti-coupure', 'Gants anti-coupure - article de demonstration', c.id, s.id, b.id, u.id, t.id, 10.8, 7.76, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-003', 'Lunettes de protection', 'Lunettes de protection - article de demonstration', c.id, s.id, b.id, u.id, t.id, 225.18, 168.91, 5, 5, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-004', 'Gilet haute visibilite', 'Gilet haute visibilite - article de demonstration', c.id, s.id, b.id, u.id, t.id, 56.55, 34.0, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-005', 'Masque FFP2', 'Masque FFP2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 193.26, 125.49, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-006', 'Chaussures de securite S3', 'Chaussures de securite S3 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 161.33, 85.39, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-007', 'Bouchons d oreilles', 'Bouchons d oreilles - article de demonstration', c.id, s.id, b.id, u.id, t.id, 149.71, 85.53, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-008', 'Harnais antichute', 'Harnais antichute - article de demonstration', c.id, s.id, b.id, u.id, t.id, 311.94, 172.14, 10, 10, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-001', 'Bouilloire 1.7L', 'Bouilloire 1.7L - article de demonstration', c.id, s.id, b.id, u.id, t.id, 6.06, 4.27, 15, 15, 'ACTIVE', 0, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-002', 'Micro-ondes 20L', 'Micro-ondes 20L - article de demonstration', c.id, s.id, b.id, u.id, t.id, 3.55, 2.11, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-003', 'Cafetiere filtre', 'Cafetiere filtre - article de demonstration', c.id, s.id, b.id, u.id, t.id, 95.47, 68.87, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-004', 'Grille-pain 2 fentes', 'Grille-pain 2 fentes - article de demonstration', c.id, s.id, b.id, u.id, t.id, 64.56, 35.61, 15, 15, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-005', 'Aspirateur traineau', 'Aspirateur traineau - article de demonstration', c.id, s.id, b.id, u.id, t.id, 199.67, 120.52, 20, 20, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-006', 'Ventilateur colonne', 'Ventilateur colonne - article de demonstration', c.id, s.id, b.id, u.id, t.id, 5.46, 3.56, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-007', 'Radiateur soufflant', 'Radiateur soufflant - article de demonstration', c.id, s.id, b.id, u.id, t.id, 128.36, 79.52, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-008', 'Robot menager', 'Robot menager - article de demonstration', c.id, s.id, b.id, u.id, t.id, 305.35, 168.6, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);


-- Produits a variantes (has_variants = 1)

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-001', 'T-shirt col rond', 'T-shirt col rond - article de demonstration', c.id, s.id, b.id, u.id, t.id, 46.3, 25.72, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-002', 'Polo pique', 'Polo pique - article de demonstration', c.id, s.id, b.id, u.id, t.id, 36.31, 20.17, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-003', 'Sweat capuche', 'Sweat capuche - article de demonstration', c.id, s.id, b.id, u.id, t.id, 20.9, 11.61, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-004', 'Chemise oxford', 'Chemise oxford - article de demonstration', c.id, s.id, b.id, u.id, t.id, 41.47, 23.04, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-005', 'Pantalon chino', 'Pantalon chino - article de demonstration', c.id, s.id, b.id, u.id, t.id, 35.51, 19.73, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-006', 'Veste softshell', 'Veste softshell - article de demonstration', c.id, s.id, b.id, u.id, t.id, 21.8, 12.11, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-007', 'Blouson de travail', 'Blouson de travail - article de demonstration', c.id, s.id, b.id, u.id, t.id, 59.69, 33.16, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-008', 'Pull col V', 'Pull col V - article de demonstration', c.id, s.id, b.id, u.id, t.id, 79.13, 43.96, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-009', 'Short cargo', 'Short cargo - article de demonstration', c.id, s.id, b.id, u.id, t.id, 40.03, 22.24, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-010', 'Parka doublee', 'Parka doublee - article de demonstration', c.id, s.id, b.id, u.id, t.id, 74.43, 41.35, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-011', 'Gilet sans manches', 'Gilet sans manches - article de demonstration', c.id, s.id, b.id, u.id, t.id, 58.91, 32.73, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VET-012', 'Combinaison atelier', 'Combinaison atelier - article de demonstration', c.id, s.id, b.id, u.id, t.id, 81.85, 45.47, 10, 10, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vetements'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-CHA-001', 'Basket running', 'Basket running - article de demonstration', c.id, s.id, b.id, u.id, t.id, 112.64, 66.26, 6, 6, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Chaussures'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-CHA-002', 'Chaussure de ville', 'Chaussure de ville - article de demonstration', c.id, s.id, b.id, u.id, t.id, 108.72, 63.95, 6, 6, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Chaussures'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-CHA-003', 'Botte de pluie', 'Botte de pluie - article de demonstration', c.id, s.id, b.id, u.id, t.id, 41.14, 24.2, 6, 6, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Chaussures'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-CHA-004', 'Sandale reglable', 'Sandale reglable - article de demonstration', c.id, s.id, b.id, u.id, t.id, 62.97, 37.04, 6, 6, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Textile Nord'
LEFT JOIN brands b ON b.name = 'NordWear'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Chaussures'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VIN-001', 'Bordeaux rouge', 'Bordeaux rouge - article de demonstration', c.id, s.id, b.id, u.id, t.id, 44.18, 21.04, 12, 12, 'ACTIVE', 1, 1, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Cave Bertrand'
LEFT JOIN brands b ON b.name = 'Domaine Bertrand'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vins et spiritueux'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VIN-002', 'Bourgogne blanc', 'Bourgogne blanc - article de demonstration', c.id, s.id, b.id, u.id, t.id, 16.19, 7.71, 12, 12, 'ACTIVE', 1, 1, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Cave Bertrand'
LEFT JOIN brands b ON b.name = 'Domaine Bertrand'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vins et spiritueux'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VIN-003', 'Cotes du Rhone', 'Cotes du Rhone - article de demonstration', c.id, s.id, b.id, u.id, t.id, 34.84, 16.59, 12, 12, 'ACTIVE', 1, 1, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Cave Bertrand'
LEFT JOIN brands b ON b.name = 'Domaine Bertrand'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vins et spiritueux'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VIN-004', 'Champagne brut', 'Champagne brut - article de demonstration', c.id, s.id, b.id, u.id, t.id, 42.78, 20.37, 12, 12, 'ACTIVE', 1, 1, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Cave Bertrand'
LEFT JOIN brands b ON b.name = 'Domaine Bertrand'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vins et spiritueux'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VIN-005', 'Chablis', 'Chablis - article de demonstration', c.id, s.id, b.id, u.id, t.id, 45.0, 21.43, 12, 12, 'ACTIVE', 1, 1, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Cave Bertrand'
LEFT JOIN brands b ON b.name = 'Domaine Bertrand'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vins et spiritueux'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VIN-006', 'Sancerre blanc', 'Sancerre blanc - article de demonstration', c.id, s.id, b.id, u.id, t.id, 99.37, 47.32, 12, 12, 'ACTIVE', 1, 1, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Cave Bertrand'
LEFT JOIN brands b ON b.name = 'Domaine Bertrand'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vins et spiritueux'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VIN-007', 'Saint-Emilion', 'Saint-Emilion - article de demonstration', c.id, s.id, b.id, u.id, t.id, 115.27, 54.89, 12, 12, 'ACTIVE', 1, 1, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Cave Bertrand'
LEFT JOIN brands b ON b.name = 'Domaine Bertrand'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vins et spiritueux'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-VIN-008', 'Muscadet', 'Muscadet - article de demonstration', c.id, s.id, b.id, u.id, t.id, 73.81, 35.15, 12, 12, 'ACTIVE', 1, 1, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Cave Bertrand'
LEFT JOIN brands b ON b.name = 'Domaine Bertrand'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Vins et spiritueux'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), has_variants = VALUES(has_variants),
  valuation_method = VALUES(valuation_method), brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

-- Series complementaires (volume pour tester la pagination)

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S11', 'Ramette couleur modele 1', 'Ramette couleur modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 29.18, 18.04, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S12', 'Ramette couleur modele 2', 'Ramette couleur modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 10.92, 6.87, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S21', 'Intercalaire modele 1', 'Intercalaire modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 84.35, 49.23, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S22', 'Intercalaire modele 2', 'Intercalaire modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 16.07, 10.65, 10, 10, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S31', 'Etiquette adhesive modele 1', 'Etiquette adhesive modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 47.55, 28.48, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S32', 'Etiquette adhesive modele 2', 'Etiquette adhesive modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 4.44, 2.82, 25, 25, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S41', 'Rouleau kraft modele 1', 'Rouleau kraft modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 26.29, 19.76, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S42', 'Rouleau kraft modele 2', 'Rouleau kraft modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 78.22, 54.73, 20, 20, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S51', 'Boite archive modele 1', 'Boite archive modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 41.57, 23.5, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-PAP-S52', 'Boite archive modele 2', 'Boite archive modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 128.0, 79.64, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'Papeterie Centrale'
LEFT JOIN brands b ON b.name = 'Papyrus'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Papeterie'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S11', 'Cordon alimentation modele 1', 'Cordon alimentation modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 63.12, 42.57, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S12', 'Cordon alimentation modele 2', 'Cordon alimentation modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 99.74, 71.67, 12, 12, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S21', 'Adaptateur video modele 1', 'Adaptateur video modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 136.64, 83.15, 25, 25, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S22', 'Adaptateur video modele 2', 'Adaptateur video modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 46.7, 32.68, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S31', 'Batterie externe modele 1', 'Batterie externe modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 127.44, 85.99, 25, 25, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S32', 'Batterie externe modele 2', 'Batterie externe modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 120.02, 79.78, 20, 20, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S41', 'Carte memoire modele 1', 'Carte memoire modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 114.69, 88.02, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S42', 'Carte memoire modele 2', 'Carte memoire modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 143.35, 87.07, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S51', 'Filtre ecran modele 1', 'Filtre ecran modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 96.39, 72.81, 12, 12, 'ACTIVE', 0, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-INF-S52', 'Filtre ecran modele 2', 'Filtre ecran modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 68.76, 39.64, 5, 5, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'TechSupply'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Informatique'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S11', 'Caisson mobile modele 1', 'Caisson mobile modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 125.55, 70.49, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S12', 'Caisson mobile modele 2', 'Caisson mobile modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 109.01, 71.21, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S21', 'Separateur tiroir modele 1', 'Separateur tiroir modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 31.84, 18.34, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S22', 'Separateur tiroir modele 2', 'Separateur tiroir modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 47.94, 29.66, 25, 25, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S31', 'Plateau courrier modele 1', 'Plateau courrier modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 32.44, 18.58, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S32', 'Plateau courrier modele 2', 'Plateau courrier modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 50.53, 30.5, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S41', 'Cadre affichage modele 1', 'Cadre affichage modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 114.75, 65.7, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S42', 'Cadre affichage modele 2', 'Cadre affichage modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 116.54, 64.28, 20, 20, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S51', 'Tabouret atelier modele 1', 'Tabouret atelier modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 44.01, 28.08, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-BUR-S52', 'Tabouret atelier modele 2', 'Tabouret atelier modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 126.19, 81.85, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Bureau'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S11', 'Recharge savon modele 1', 'Recharge savon modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 21.17, 13.68, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S12', 'Recharge savon modele 2', 'Recharge savon modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 129.5, 76.38, 5, 5, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S21', 'Balai brosse modele 1', 'Balai brosse modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 23.77, 16.83, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S22', 'Balai brosse modele 2', 'Balai brosse modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 128.65, 88.57, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S31', 'Seau gradue modele 1', 'Seau gradue modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 95.59, 69.05, 25, 25, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S32', 'Seau gradue modele 2', 'Seau gradue modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 12.81, 7.2, 12, 12, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S41', 'Chiffon absorbant modele 1', 'Chiffon absorbant modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 53.55, 35.06, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S42', 'Chiffon absorbant modele 2', 'Chiffon absorbant modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 3.89, 2.3, 12, 12, 'ACTIVE', 0, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S51', 'Gant menage modele 1', 'Gant menage modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 132.97, 80.12, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ENT-S52', 'Gant menage modele 2', 'Gant menage modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 9.01, 5.0, 10, 10, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'OfficePro'
LEFT JOIN brands b ON b.name = 'Generic'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Entretien'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S11', 'Cone signalisation modele 1', 'Cone signalisation modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 77.43, 52.4, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S12', 'Cone signalisation modele 2', 'Cone signalisation modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 39.2, 28.43, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S21', 'Trousse secours modele 1', 'Trousse secours modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 130.47, 78.9, 25, 25, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S22', 'Trousse secours modele 2', 'Trousse secours modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 159.13, 90.71, 25, 25, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S31', 'Extincteur 2kg modele 1', 'Extincteur 2kg modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 139.58, 78.42, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S32', 'Extincteur 2kg modele 2', 'Extincteur 2kg modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 59.92, 39.02, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S41', 'Panneau consigne modele 1', 'Panneau consigne modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 86.47, 65.02, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S42', 'Panneau consigne modele 2', 'Panneau consigne modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 141.2, 77.7, 12, 12, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S51', 'Ruban baliseur modele 1', 'Ruban baliseur modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 30.39, 21.9, 10, 10, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-SEC-S52', 'Ruban baliseur modele 2', 'Ruban baliseur modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 12.01, 7.04, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'SecuPro'
LEFT JOIN brands b ON b.name = 'SecuPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Securite'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S11', 'Filtre aspirateur modele 1', 'Filtre aspirateur modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 50.69, 27.48, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S12', 'Filtre aspirateur modele 2', 'Filtre aspirateur modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 56.02, 34.51, 20, 20, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S21', 'Plaque chauffante modele 1', 'Plaque chauffante modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 72.7, 52.22, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S22', 'Plaque chauffante modele 2', 'Plaque chauffante modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 132.66, 90.45, 12, 12, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S31', 'Carafe filtrante modele 1', 'Carafe filtrante modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 62.17, 34.21, 20, 20, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S32', 'Carafe filtrante modele 2', 'Carafe filtrante modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 63.9, 41.3, 12, 12, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S41', 'Balance cuisine modele 1', 'Balance cuisine modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 133.18, 78.88, 25, 25, 'ACTIVE', 0, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S42', 'Balance cuisine modele 2', 'Balance cuisine modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 129.3, 90.77, 5, 5, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S51', 'Minuteur modele 1', 'Minuteur modele 1 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 134.93, 80.74, 25, 25, 'ACTIVE', 1, 0, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

INSERT INTO products (sku, name, description, category_id, supplier_id, brand_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-ELE-S52', 'Minuteur modele 2', 'Minuteur modele 2 - article de demonstration', c.id, s.id, b.id, u.id, t.id, 49.65, 29.36, 5, 5, 'ACTIVE', 1, 0, 'FIFO'
FROM categories c
JOIN suppliers s ON s.name = 'ElectroDis'
LEFT JOIN brands b ON b.name = 'ElectroDis'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Electromenager'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price),
  reorder_level = VALUES(reorder_level), is_active = VALUES(is_active), valuation_method = VALUES(valuation_method),
  brand_id = VALUES(brand_id), unit_id = VALUES(unit_id), tax_id = VALUES(tax_id);

-- ----------------------------------------------------------------------------
-- Variantes de demonstration
-- ----------------------------------------------------------------------------
-- Les vetements et chaussures utilisent taille/couleur (option
-- `clothing_variants_enabled`), les vins millesime/contenance (option
-- `bottle_variants_enabled`). Active l'option correspondante dans l'ecran
-- Parametres pour voir les champs et le module Variantes.
-- SKU construits comme le fait le generateur de variantes de l'application :
-- PREFIXE-ATTRIBUT1-ATTRIBUT2.

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-001-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-001-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-001-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-001-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-001-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-001-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-001-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-001-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-002-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-002-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-002-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-002-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-002-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-002-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-002-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-002-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-003-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-003-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-003-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-003-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-003-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-003-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-003-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-003-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-004-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-004-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-004-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-004-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-004-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-004-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-004-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-004-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-005-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-005-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-005-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-005-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-005-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-005-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-005-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-005-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-006-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-006-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-006-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-006-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-006-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-006-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-006-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-006-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-007-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-007-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-007-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-007-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-007-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-007-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-007-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-007-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-008-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-008-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-008-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-008-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-008-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-008-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-008-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-008-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-009-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-009'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-009-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-009'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-009-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-009'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-009-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-009'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-009-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-009'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-009-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-009'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-009-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-009'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-009-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-009'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-010-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-010'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-010-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-010'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-010-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-010'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-010-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-010'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-010-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-010'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-010-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-010'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-010-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-010'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-010-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-010'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-011-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-011'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-011-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-011'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-011-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-011'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-011-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-011'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-011-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-011'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-011-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-011'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-011-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-011'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-011-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-011'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-012-S-NOIR', 'S', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-012'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-012-S-BLANC', 'S', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-012'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-012-M-NOIR', 'M', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-012'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-012-M-BLANC', 'M', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-012'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-012-L-NOIR', 'L', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-012'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-012-L-BLANC', 'L', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-012'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-012-XL-NOIR', 'XL', 'Noir', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-012'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VET-012-XL-BLANC', 'XL', 'Blanc', NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-VET-012'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-001-39', '39', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-001-41', '41', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-001-43', '43', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-001-45', '45', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-002-39', '39', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-002-41', '41', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-002-43', '43', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-002-45', '45', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-003-39', '39', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-003-41', '41', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-003-43', '43', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-003-45', '45', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-004-39', '39', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-004-41', '41', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-004-43', '43', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-CHA-004-45', '45', NULL, NULL, NULL, 1
FROM products p WHERE p.sku = 'DEMO-CHA-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-001-2019-75', NULL, NULL, 2019, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-001-2019-150', NULL, NULL, 2019, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-001-2020-75', NULL, NULL, 2020, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-001-2020-150', NULL, NULL, 2020, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-001-2021-75', NULL, NULL, 2021, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-001-2021-150', NULL, NULL, 2021, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-001'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-002-2019-75', NULL, NULL, 2019, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-002-2019-150', NULL, NULL, 2019, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-002-2020-75', NULL, NULL, 2020, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-002-2020-150', NULL, NULL, 2020, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-002-2021-75', NULL, NULL, 2021, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-002-2021-150', NULL, NULL, 2021, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-002'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-003-2019-75', NULL, NULL, 2019, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-003-2019-150', NULL, NULL, 2019, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-003-2020-75', NULL, NULL, 2020, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-003-2020-150', NULL, NULL, 2020, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-003-2021-75', NULL, NULL, 2021, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-003-2021-150', NULL, NULL, 2021, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-003'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-004-2019-75', NULL, NULL, 2019, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-004-2019-150', NULL, NULL, 2019, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-004-2020-75', NULL, NULL, 2020, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-004-2020-150', NULL, NULL, 2020, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-004-2021-75', NULL, NULL, 2021, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-004-2021-150', NULL, NULL, 2021, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-004'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-005-2019-75', NULL, NULL, 2019, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-005-2019-150', NULL, NULL, 2019, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-005-2020-75', NULL, NULL, 2020, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-005-2020-150', NULL, NULL, 2020, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-005-2021-75', NULL, NULL, 2021, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-005-2021-150', NULL, NULL, 2021, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-005'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-006-2019-75', NULL, NULL, 2019, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-006-2019-150', NULL, NULL, 2019, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-006-2020-75', NULL, NULL, 2020, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-006-2020-150', NULL, NULL, 2020, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-006-2021-75', NULL, NULL, 2021, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-006-2021-150', NULL, NULL, 2021, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-006'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-007-2019-75', NULL, NULL, 2019, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-007-2019-150', NULL, NULL, 2019, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-007-2020-75', NULL, NULL, 2020, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-007-2020-150', NULL, NULL, 2020, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-007-2021-75', NULL, NULL, 2021, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-007-2021-150', NULL, NULL, 2021, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-007'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-008-2019-75', NULL, NULL, 2019, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-008-2019-150', NULL, NULL, 2019, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-008-2020-75', NULL, NULL, 2020, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-008-2020-150', NULL, NULL, 2020, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-008-2021-75', NULL, NULL, 2021, 75, 1
FROM products p WHERE p.sku = 'DEMO-VIN-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, size, color, vintage, volume_cl, is_active)
SELECT p.id, 'DEMO-VIN-008-2021-150', NULL, NULL, 2021, 150, 1
FROM products p WHERE p.sku = 'DEMO-VIN-008'
ON DUPLICATE KEY UPDATE size = VALUES(size), color = VALUES(color), vintage = VALUES(vintage), volume_cl = VALUES(volume_cl), is_active = VALUES(is_active);


-- ----------------------------------------------------------------------------
-- Stock initial
-- ----------------------------------------------------------------------------
-- Quantites variees, dont volontairement quelques articles sous leur seuil
-- d'alerte pour que le tableau de bord et l'ecran Alertes ne soient pas vides.
-- stock_levels.variant_id etant NULL pour un produit sans variante, la cle
-- unique (product_id, warehouse_id, variant_id) ne dedoublonne pas ces
-- lignes-la sous MySQL : on protege donc l'insertion par un NOT EXISTS plutot
-- que par ON DUPLICATE KEY UPDATE.

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 112, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 329, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 2, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-003'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 309, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-004'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 325, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-005'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 193, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-006'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 102, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-007'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 4, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-008'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 376, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-009'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 32, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-010'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 261, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-011'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 276, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-012'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 4, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-013'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 194, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-014'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 101, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-015'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 4, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 397, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 249, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-003'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 398, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-004'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 286, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-005'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 226, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-006'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 146, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-007'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 25, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-008'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 90, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 54, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 4, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-003'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 121, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-004'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 0, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-005'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 364, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-006'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 292, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-007'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 245, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 0, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 76, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-003'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 156, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-004'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 247, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-005'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 333, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-006'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 178, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-007'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 53, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-008'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 176, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-009'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 91, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-010'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 167, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-011'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 305, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-012'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 384, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 205, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 2, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-003'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 397, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-004'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 6, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-005'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 2, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-006'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 6, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-007'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 380, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-008'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 82, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 63, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 123, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-003'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 89, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-004'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 85, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-005'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 352, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-006'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 175, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-007'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 71, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-008'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 159, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S11'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 335, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S12'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 6, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S21'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 6, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S22'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 310, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S31'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 84, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S32'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 316, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 389, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S42'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 80, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S51'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 186, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-PAP-S52'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 2, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S11'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 88, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S12'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 243, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S21'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 169, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S22'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 223, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S31'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 4, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S32'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 232, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 158, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S42'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 278, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S51'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 52, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-INF-S52'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 202, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S11'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 295, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S12'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 65, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S21'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 143, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S22'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 226, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S31'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 347, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S32'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 351, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 129, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S42'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 35, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S51'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 6, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-BUR-S52'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 6, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S11'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 4, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S12'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 101, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S21'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 376, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S22'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 296, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S31'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 182, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S32'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 205, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 104, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S42'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 245, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S51'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 77, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ENT-S52'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 6, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S11'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 0, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S12'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 301, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S21'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 325, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S22'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 178, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S31'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 358, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S32'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 305, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 279, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S42'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 332, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S51'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 257, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-SEC-S52'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 292, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S11'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 357, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S12'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 373, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S21'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 293, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S22'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 354, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S31'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 325, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S32'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 338, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 66, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S42'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 2, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S51'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity)
SELECT p.id, w.id, 253, 0 FROM products p JOIN warehouses w ON w.is_default = 1
WHERE p.sku = 'DEMO-ELE-S52'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.variant_id IS NULL AND sl.location_id IS NULL);


-- Stock par variante. ATTENTION : depuis la migration 202602270012, la cle
-- unique de stock_levels inclut location_id, qui est nullable - MySQL
-- n'applique donc plus l'unicite sur ces lignes et ON DUPLICATE KEY UPDATE
-- creerait un doublon a chaque rechargement. Comme pour les produits sans
-- variante, on protege par NOT EXISTS.

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 50, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-001-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 68, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-001-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 36, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-001-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 41, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-001-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 3, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-001-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 13, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-001-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 89, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-001-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 104, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-001-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 116, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-002-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 109, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-002-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 55, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-002-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-002-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 23, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-002-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 22, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-002-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 61, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-002-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 0, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-002-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 30, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-003-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 40, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-003-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 21, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-003-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 15, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-003-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 43, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-003-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 15, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-003-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 106, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-003-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-003-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 93, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-004-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 89, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-004-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 62, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-004-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 97, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-004-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 51, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-004-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 29, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-004-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 93, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-004-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 84, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-004-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 77, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-005-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 74, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-005-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 88, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-005-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-005-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-005-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 83, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-005-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 34, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-005-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 109, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-005-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 18, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-006-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 77, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-006-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 93, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-006-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 59, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-006-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 93, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-006-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 120, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-006-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 18, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-006-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 75, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-006-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 71, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-007-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 114, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-007-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 120, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-007-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 58, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-007-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 68, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-007-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 20, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-007-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 84, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-007-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-007-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 16, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-008-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 119, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-008-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 60, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-008-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 38, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-008-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 24, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-008-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 8, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-008-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 99, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-008-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 114, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-008-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-009-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 103, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-009-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 107, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-009-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 37, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-009-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 54, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-009-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-009-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 117, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-009-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 96, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-009-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 3, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-010-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 87, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-010-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 28, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-010-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 55, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-010-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 108, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-010-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 69, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-010-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 60, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-010-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 28, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-010-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 65, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-011-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 107, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-011-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 64, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-011-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 3, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-011-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 47, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-011-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 18, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-011-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 28, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-011-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 49, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-011-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 116, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-012-S-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 0, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-012-S-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 110, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-012-M-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 115, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-012-M-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-012-L-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 74, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-012-L-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 49, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-012-XL-NOIR'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 74, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VET-012-XL-BLANC'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 33, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-001-39'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 69, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-001-41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 81, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-001-43'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 105, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-001-45'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 3, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-002-39'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 85, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-002-41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 38, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-002-43'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 88, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-002-45'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 32, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-003-39'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 70, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-003-41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 94, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-003-43'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 76, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-003-45'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 32, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-004-39'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 78, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-004-41'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-004-43'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 79, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-CHA-004-45'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 3, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-001-2019-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 57, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-001-2019-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 73, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-001-2020-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 95, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-001-2020-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 79, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-001-2021-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 29, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-001-2021-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 49, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-002-2019-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 76, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-002-2019-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 18, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-002-2020-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 61, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-002-2020-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 21, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-002-2021-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 103, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-002-2021-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 15, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-003-2019-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 119, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-003-2019-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 101, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-003-2020-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 72, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-003-2020-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 114, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-003-2021-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 116, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-003-2021-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-004-2019-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 55, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-004-2019-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 42, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-004-2020-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 95, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-004-2020-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 68, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-004-2021-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 12, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-004-2021-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 106, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-005-2019-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 0, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-005-2019-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 88, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-005-2020-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 85, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-005-2020-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 79, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-005-2021-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 116, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-005-2021-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 100, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-006-2019-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 58, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-006-2019-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 39, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-006-2020-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 25, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-006-2020-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 35, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-006-2021-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 61, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-006-2021-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 61, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-007-2019-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 78, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-007-2019-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 56, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-007-2020-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 42, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-007-2020-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 34, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-007-2021-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 116, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-007-2021-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 60, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-008-2019-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 79, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-008-2019-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 116, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-008-2020-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 33, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-008-2020-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 84, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-008-2021-75'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 44, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-VIN-008-2021-150'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);


-- Quelques tags poses sur le catalogue etendu.

INSERT INTO product_tags (product_id, tag_id)
SELECT p.id, t.id FROM products p JOIN tags t ON t.name = 'promo'
WHERE p.sku LIKE 'DEMO-VET-%'
  AND NOT EXISTS (SELECT 1 FROM product_tags pt WHERE pt.product_id = p.id AND pt.tag_id = t.id);

INSERT INTO product_tags (product_id, tag_id)
SELECT p.id, t.id FROM products p JOIN tags t ON t.name = 'saisonnier'
WHERE p.sku LIKE 'DEMO-CHA-%'
  AND NOT EXISTS (SELECT 1 FROM product_tags pt WHERE pt.product_id = p.id AND pt.tag_id = t.id);

INSERT INTO product_tags (product_id, tag_id)
SELECT p.id, t.id FROM products p JOIN tags t ON t.name = 'fragile'
WHERE p.sku LIKE 'DEMO-VIN-%'
  AND NOT EXISTS (SELECT 1 FROM product_tags pt WHERE pt.product_id = p.id AND pt.tag_id = t.id);

INSERT INTO product_tags (product_id, tag_id)
SELECT p.id, t.id FROM products p JOIN tags t ON t.name = 'gros-volume'
WHERE p.sku LIKE 'DEMO-PAP-%'
  AND NOT EXISTS (SELECT 1 FROM product_tags pt WHERE pt.product_id = p.id AND pt.tag_id = t.id);


-- ----------------------------------------------------------------------------
-- Repartition d'une partie du stock dans les emplacements
-- ----------------------------------------------------------------------------
-- Sans cela, tout le stock de demo reste "sans emplacement precis" et l'ecran
-- Stock d'une fiche produit n'affiche qu'une ligne par entrepot : la
-- fonctionnalite existe mais ne se voit nulle part. Ici, quelques articles sont
-- ranges dans des allees precises pour que le suivi par emplacement soit
-- visible des le chargement de la demo.
-- Idempotent : la ligne sans emplacement est FIXEE a une valeur (UPDATE, pas
-- une soustraction), et les lignes localisees sont protegees par NOT EXISTS.


UPDATE stock_levels sl
JOIN products p ON p.id = sl.product_id
JOIN warehouses w ON w.id = sl.warehouse_id AND w.is_default = 1
SET sl.quantity = 12
WHERE p.sku = 'DEMO-INF-001' AND sl.variant_id IS NULL AND sl.location_id IS NULL;

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 40, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'A1'
WHERE p.sku = 'DEMO-INF-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 25, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'A2'
WHERE p.sku = 'DEMO-INF-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 60, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'C1'
WHERE p.sku = 'DEMO-INF-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

UPDATE stock_levels sl
JOIN products p ON p.id = sl.product_id
JOIN warehouses w ON w.id = sl.warehouse_id AND w.is_default = 1
SET sl.quantity = 0
WHERE p.sku = 'DEMO-INF-002' AND sl.variant_id IS NULL AND sl.location_id IS NULL;

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 18, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'A1'
WHERE p.sku = 'DEMO-INF-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 90, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'C1'
WHERE p.sku = 'DEMO-INF-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

UPDATE stock_levels sl
JOIN products p ON p.id = sl.product_id
JOIN warehouses w ON w.id = sl.warehouse_id AND w.is_default = 1
SET sl.quantity = 5
WHERE p.sku = 'DEMO-PAP-001' AND sl.variant_id IS NULL AND sl.location_id IS NULL;

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 120, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'A2'
WHERE p.sku = 'DEMO-PAP-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 300, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'C2'
WHERE p.sku = 'DEMO-PAP-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

UPDATE stock_levels sl
JOIN products p ON p.id = sl.product_id
JOIN warehouses w ON w.id = sl.warehouse_id AND w.is_default = 1
SET sl.quantity = 0
WHERE p.sku = 'DEMO-PAP-002' AND sl.variant_id IS NULL AND sl.location_id IS NULL;

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 45, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'A3'
WHERE p.sku = 'DEMO-PAP-002'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

UPDATE stock_levels sl
JOIN products p ON p.id = sl.product_id
JOIN warehouses w ON w.id = sl.warehouse_id AND w.is_default = 1
SET sl.quantity = 3
WHERE p.sku = 'DEMO-SEC-001' AND sl.variant_id IS NULL AND sl.location_id IS NULL;

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 22, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'A1'
WHERE p.sku = 'DEMO-SEC-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 14, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'A3'
WHERE p.sku = 'DEMO-SEC-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);

UPDATE stock_levels sl
JOIN products p ON p.id = sl.product_id
JOIN warehouses w ON w.id = sl.warehouse_id AND w.is_default = 1
SET sl.quantity = 0
WHERE p.sku = 'DEMO-ELE-001' AND sl.variant_id IS NULL AND sl.location_id IS NULL;

INSERT INTO stock_levels (product_id, warehouse_id, location_id, quantity, reserved_quantity)
SELECT p.id, w.id, l.id, 30, 0
FROM products p
JOIN warehouses w ON w.is_default = 1
JOIN warehouse_locations l ON l.warehouse_id = w.id AND l.code = 'C2'
WHERE p.sku = 'DEMO-ELE-001'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.product_id = p.id AND sl.warehouse_id = w.id AND sl.location_id = l.id AND sl.variant_id IS NULL);
