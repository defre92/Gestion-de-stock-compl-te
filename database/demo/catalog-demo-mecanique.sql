-- ==============================================================================
-- DEMO "OUTILLAGE ELECTROPORTATIF" (materiel / mecanique) - THEME ALTERNATIF
-- ==============================================================================
-- Utilise par frontend/demo-data.php, bouton "Charger la demo outillage".
--
-- Independant du catalogue de demo standard (database/demo/catalog-demo.sql) :
-- cree son propre entrepot par defaut si besoin, ainsi que l'unite "PIECE" et
-- la taxe "TVA_20" (memes garde-fous idempotents que ce fichier). Tu peux
-- donc charger CE fichier seul - par exemple pour un client dont l'activite
-- est justement l'outillage, sans vetements/boissons/fournitures de bureau
-- qui ne lui parleraient pas - ou les deux ensemble, les deux catalogues
-- cohabitent sans conflit (categories, fournisseurs et SKU distincts).
--
-- Theme : montre la 4e "saveur" de variantes (Puissance / Marque / Type /
-- Vitesse / Tension / Forme, option technical_variants_enabled a activer dans
-- Parametres) sur cinq articles d'outillage electroportatif types, pour un
-- exemple complet cote client : 5 produits, 10 variantes, en couvrant les
-- deux facons dont ces champs se remplissent en pratique (sans-fil decline
-- par tension de batterie, filaire decline par puissance).
--
-- Idempotent (ON DUPLICATE KEY UPDATE / NOT EXISTS), rejouable sans risque.
-- ==============================================================================

SET NAMES utf8mb4;

-- Entrepot par defaut : cree seulement si aucun entrepot par defaut n'existe
-- deja chez toi (n'ecrase jamais un entrepot existant, meme logique que
-- catalog-demo.sql). Necessaire pour que ce fichier soit chargeable seul.
INSERT INTO warehouses (name, location, is_default)
SELECT 'Entrepot Principal', 'Bruxelles', 1
WHERE NOT EXISTS (SELECT 1 FROM warehouses WHERE is_default = 1);

-- Unite et taux de TVA de base : memes codes que catalog-demo.sql, sans
-- collision possible (ON DUPLICATE KEY UPDATE) si les deux fichiers sont
-- charges l'un apres l'autre.
INSERT INTO units (code, name, symbol, base_unit, conversion_factor, is_active) VALUES
('PIECE', 'Piece', 'pc', 'PIECE', 1, 1)
ON DUPLICATE KEY UPDATE name = VALUES(name), symbol = VALUES(symbol), conversion_factor = VALUES(conversion_factor), is_active = VALUES(is_active);

INSERT INTO taxes (code, name, rate, is_default) VALUES
('TVA_20', 'TVA 20%', 20.000, 1)
ON DUPLICATE KEY UPDATE name = VALUES(name), rate = VALUES(rate);

-- ----------------------------------------------------------------------------
-- Categorie, fournisseur, marques
-- ----------------------------------------------------------------------------
INSERT INTO categories (name, description) VALUES
('Outillage', 'Outillage electroportatif : perceuses, meuleuses, visseuses')
ON DUPLICATE KEY UPDATE description = VALUES(description);

INSERT INTO suppliers (name, contact_name, phone, email, address) VALUES
('OutilPro', 'Nadia Benchekroun', '0467113322', 'nadia@outilpro.fr', 'Zone Artisanale du Pont, Toulouse')
ON DUPLICATE KEY UPDATE contact_name = VALUES(contact_name), phone = VALUES(phone), email = VALUES(email), address = VALUES(address);

-- Marques volontairement fictives (jamais de marque deposee reelle dans des
-- donnees livrees a un client), comme le reste des fichiers de demo.
INSERT INTO brands (name, description) VALUES
('ForceTech', 'Outillage electroportatif sans fil'),
('MecaLine', 'Outillage electroportatif filaire')
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- ----------------------------------------------------------------------------
-- Produits (5) - quatrieme saveur de variantes (Puissance / Marque / Type /
-- Vitesse / Tension / Forme), en texte LIBRE (l'unite fait partie de la
-- valeur saisie). Deux facons typiques dont ces 6 champs se remplissent :
-- sans-fil decline par tension de batterie, filaire decline par puissance -
-- rarement les 6 a la fois sur un meme article.
-- Active `technical_variants_enabled` dans l'ecran Parametres pour voir les
-- champs et ces variantes dans le module Variantes.
-- ----------------------------------------------------------------------------

INSERT INTO products (sku, name, description, category_id, supplier_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-OUT-001', 'Perceuse-visseuse sans fil', 'Perceuse-visseuse sans fil - article de demonstration', c.id, s.id, u.id, t.id, 89.90, 54.00, 8, 8, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OutilPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Outillage'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price), reorder_level = VALUES(reorder_level), has_variants = VALUES(has_variants);

INSERT INTO products (sku, name, description, category_id, supplier_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-OUT-002', 'Meuleuse d angle filaire', 'Meuleuse d angle filaire - article de demonstration', c.id, s.id, u.id, t.id, 64.50, 39.00, 6, 6, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OutilPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Outillage'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price), reorder_level = VALUES(reorder_level), has_variants = VALUES(has_variants);

INSERT INTO products (sku, name, description, category_id, supplier_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-OUT-003', 'Visseuse a chocs sans fil', 'Visseuse a chocs sans fil - article de demonstration', c.id, s.id, u.id, t.id, 109.00, 66.00, 6, 6, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OutilPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Outillage'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price), reorder_level = VALUES(reorder_level), has_variants = VALUES(has_variants);

INSERT INTO products (sku, name, description, category_id, supplier_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-OUT-004', 'Scie sauteuse filaire', 'Scie sauteuse filaire - article de demonstration', c.id, s.id, u.id, t.id, 74.90, 45.00, 5, 5, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OutilPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Outillage'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price), reorder_level = VALUES(reorder_level), has_variants = VALUES(has_variants);

INSERT INTO products (sku, name, description, category_id, supplier_id, unit_id, tax_id, unit_price, cost_price, reorder_level, min_stock, status, is_active, has_variants, valuation_method)
SELECT 'DEMO-OUT-005', 'Ponceuse excentrique sans fil', 'Ponceuse excentrique sans fil - article de demonstration', c.id, s.id, u.id, t.id, 94.50, 57.00, 5, 5, 'ACTIVE', 1, 1, 'CUMP'
FROM categories c
JOIN suppliers s ON s.name = 'OutilPro'
LEFT JOIN units u ON u.code = 'PIECE'
LEFT JOIN taxes t ON t.code = 'TVA_20'
WHERE c.name = 'Outillage'
ON DUPLICATE KEY UPDATE name = VALUES(name), unit_price = VALUES(unit_price), cost_price = VALUES(cost_price), reorder_level = VALUES(reorder_level), has_variants = VALUES(has_variants);

-- ----------------------------------------------------------------------------
-- Variantes (10) - 2 par produit
-- ----------------------------------------------------------------------------

-- Perceuse-visseuse : declinee par tension de batterie (vitesse et forme
-- varient avec, la puissance en Watts n'a pas de sens sur du sans-fil).
INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-001-12V', 'ForceTech', 'Compacte', '0-1500 tr/min', '12 V', 'Pistolet', 74.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-001'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-001-18V', 'ForceTech', 'Pro', '0-1800 tr/min', '18 V', 'Pistolet', 99.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-001'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- Meuleuse d'angle : declinee par puissance filaire (tension secteur fixe a
-- 230 V pour les deux, la puissance et le diametre de disque varient).
INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-002-750W', '750 W', 'MecaLine', 'Standard', '11000 tr/min', '230 V', 'Disque 115mm', 59.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-002'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-002-2000W', '2000 W', 'MecaLine', 'Pro', '9000 tr/min', '230 V', 'Disque 230mm', 89.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-002'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- Visseuse a chocs : declinee par tension de batterie, comme la perceuse
-- (couple de serrage indique via le champ vitesse, faute de champ dedie).
INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-003-12V', 'ForceTech', 'Compacte', '180 Nm', '12 V', 'Pistolet', 89.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-003'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-003-18V', 'ForceTech', 'Pro', '250 Nm', '18 V', 'Pistolet', 119.00, 1
FROM products p WHERE p.sku = 'DEMO-OUT-003'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- Scie sauteuse : declinee par puissance filaire (comme la meuleuse).
INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-004-550W', '550 W', 'MecaLine', 'Standard', '500-3000 crs/min', '230 V', 'Lame droite', 69.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-004'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-004-720W', '720 W', 'MecaLine', 'Pro', '500-3200 crs/min', '230 V', 'Lame pendulaire', 84.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-004'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- Ponceuse excentrique : declinee par tension de batterie (meme logique que
-- la perceuse et la visseuse, troisieme exemple de la meme "famille" pour
-- montrer la coherence du theme sans-fil).
INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-005-12V', 'ForceTech', 'Compacte', '4000-9500 osc/min', '12 V', 'Ronde 125mm', 84.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-005'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-005-18V', 'ForceTech', 'Pro', '4000-10500 osc/min', '18 V', 'Ronde 150mm', 104.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-005'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- ----------------------------------------------------------------------------
-- Stock initial (sur l'entrepot par defaut existant, le tien ou celui cree
-- ci-dessus). NOT EXISTS et non ON DUPLICATE KEY UPDATE : location_id est
-- NULL ici, et MySQL n'applique pas l'unicite de (product_id, warehouse_id,
-- variant_id, location_id) quand une colonne de la cle est NULL - avec
-- ON DUPLICATE KEY, relancer le script creerait une deuxieme ligne de stock.
-- ----------------------------------------------------------------------------

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 14, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-001-12V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 7, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-001-18V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-002-750W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 2, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-002-2000W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 11, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-003-12V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 6, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-003-18V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 9, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-004-550W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 4, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-004-720W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 8, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-005-12V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 3, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-005-18V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

-- Les cinq produits concernes doivent etre marques "a des variantes" (deja le
-- cas des la creation ci-dessus, cette ligne le garantit aussi en cas de
-- relance sur une base ou ils existaient deja autrement).
UPDATE products SET has_variants = 1 WHERE sku IN ('DEMO-OUT-001', 'DEMO-OUT-002', 'DEMO-OUT-003', 'DEMO-OUT-004', 'DEMO-OUT-005');
