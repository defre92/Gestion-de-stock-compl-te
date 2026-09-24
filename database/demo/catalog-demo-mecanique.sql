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
-- exemple complet cote client : 5 produits, 20 variantes (4 par produit,
-- comme une petite gamme entree/compacte/pro/pro+), en couvrant les deux
-- facons dont ces champs se remplissent en pratique (sans-fil decline par
-- tension de batterie, filaire decline par puissance).
--
-- Comme catalog-demo.sql, ce theme inclut aussi un scenario d'activite (et
-- non juste un catalogue statique) : 2 fournisseurs, 2 clients, une zone
-- d'entrepot dediee avec ses emplacements, une demande d'achat convertie en
-- commande receptionnee, une livraison client (BL) et les mouvements de
-- stock correspondants.
--
-- Idempotent (ON DUPLICATE KEY UPDATE / NOT EXISTS), rejouable sans risque.
-- ==============================================================================

SET NAMES utf8mb4;

-- Point de depart du scenario d'activite (commande, livraison...), comme
-- catalog-demo.sql : recalcule a chaque execution, la demo semble toujours
-- "recente" quel que soit le jour ou elle est chargee.
SET @demo_base = DATE_SUB(NOW(), INTERVAL 2 DAY);

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
('OutilPro', 'Nadia Benchekroun', '0467113322', 'nadia@outilpro.fr', 'Zone Artisanale du Pont, Toulouse'),
('ElectroBat Distribution', 'Karim Fassi', '0478223311', 'karim@electrobat.fr', 'Rue de la Batterie 5, Lille')
ON DUPLICATE KEY UPDATE contact_name = VALUES(contact_name), phone = VALUES(phone), email = VALUES(email), address = VALUES(address);

-- Marques volontairement fictives (jamais de marque deposee reelle dans des
-- donnees livrees a un client), comme le reste des fichiers de demo.
INSERT INTO brands (name, description) VALUES
('ForceTech', 'Outillage electroportatif sans fil'),
('MecaLine', 'Outillage electroportatif filaire')
ON DUPLICATE KEY UPDATE description = VALUES(description);

-- Clients de demo (comme catalog-demo.sql : "clients internes", cohabitent
-- sans conflit avec CLI-001/CLI-002 si les deux fichiers sont charges).
INSERT INTO customers (code, name, email, phone, address, status) VALUES
('CLI-OUT-001', 'Chantier Dupont Renovation', 'contact@dupont-renovation.fr', '0611223344', '14 rue des Artisans, Toulouse', 'ACTIVE'),
('CLI-OUT-002', 'Menuiserie Lefevre', 'atelier@menuiserie-lefevre.fr', '0622334455', '3 route de l Atelier, Colomiers', 'ACTIVE')
ON DUPLICATE KEY UPDATE name = VALUES(name), email = VALUES(email), phone = VALUES(phone), address = VALUES(address), status = VALUES(status);

-- Zone et emplacements dedies a l'outillage sur l'entrepot par defaut (codes
-- distincts de A/B/C utilises par catalog-demo.sql, aucune collision si les
-- deux fichiers sont charges ensemble).
INSERT INTO warehouse_zones (warehouse_id, code, name)
SELECT w.id, 'OUT', 'Zone Outillage' FROM warehouses w WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO warehouse_locations (warehouse_id, zone_id, code, description, capacity, is_active)
SELECT w.id, z.id, 'OUT1', 'Rayon outillage sans fil (perceuses, visseuses, ponceuses)', 150, 1
FROM warehouses w
JOIN warehouse_zones z ON z.warehouse_id = w.id AND z.code = 'OUT'
WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE description = VALUES(description), capacity = VALUES(capacity), is_active = VALUES(is_active);

INSERT INTO warehouse_locations (warehouse_id, zone_id, code, description, capacity, is_active)
SELECT w.id, z.id, 'OUT2', 'Rayon outillage filaire (meuleuses, scies)', 150, 1
FROM warehouses w
JOIN warehouse_zones z ON z.warehouse_id = w.id AND z.code = 'OUT'
WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE description = VALUES(description), capacity = VALUES(capacity), is_active = VALUES(is_active);

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
-- Variantes (20) - 4 par produit, comme une petite gamme entree/compacte/
-- pro/pro+ (le meme principe que les tailles d'un vetement ou les millesimes
-- d'un vin dans le catalogue de demo standard, applique ici a la puissance ou
-- a la tension de batterie).
-- ----------------------------------------------------------------------------

-- Perceuse-visseuse : declinee par tension de batterie (vitesse et forme
-- varient avec, la puissance en Watts n'a pas de sens sur du sans-fil).
INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-001-108V', 'ForceTech', 'Ultra-compacte', '0-1200 tr/min', '10.8 V', 'Pistolet', 59.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-001'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-001-12V', 'ForceTech', 'Compacte', '0-1500 tr/min', '12 V', 'Pistolet', 74.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-001'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-001-18V', 'ForceTech', 'Pro', '0-1800 tr/min', '18 V', 'Pistolet', 99.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-001'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-001-20V', 'ForceTech', 'Pro+', '0-2000 tr/min', '20 V', 'Pistolet', 119.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-001'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- Meuleuse d'angle : declinee par puissance filaire (tension secteur fixe a
-- 230 V pour toutes, la puissance et le diametre de disque varient).
INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-002-750W', '750 W', 'MecaLine', 'Standard', '11000 tr/min', '230 V', 'Disque 115mm', 59.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-002'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-002-1200W', '1200 W', 'MecaLine', 'Standard+', '10000 tr/min', '230 V', 'Disque 125mm', 74.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-002'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-002-2000W', '2000 W', 'MecaLine', 'Pro', '9000 tr/min', '230 V', 'Disque 230mm', 89.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-002'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-002-2400W', '2400 W', 'MecaLine', 'Pro+', '8500 tr/min', '230 V', 'Disque 230mm antivibration', 109.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-002'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- Visseuse a chocs : declinee par tension de batterie, comme la perceuse
-- (couple de serrage indique via le champ vitesse, faute de champ dedie).
INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-003-108V', 'ForceTech', 'Ultra-compacte', '120 Nm', '10.8 V', 'Pistolet', 69.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-003'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-003-12V', 'ForceTech', 'Compacte', '180 Nm', '12 V', 'Pistolet', 89.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-003'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-003-18V', 'ForceTech', 'Pro', '250 Nm', '18 V', 'Pistolet', 119.00, 1
FROM products p WHERE p.sku = 'DEMO-OUT-003'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-003-20V', 'ForceTech', 'Pro+', '300 Nm', '20 V', 'Pistolet', 139.00, 1
FROM products p WHERE p.sku = 'DEMO-OUT-003'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- Scie sauteuse : declinee par puissance filaire (comme la meuleuse).
INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-004-350W', '350 W', 'MecaLine', 'Entree de gamme', '500-2800 crs/min', '230 V', 'Lame droite', 49.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-004'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-004-550W', '550 W', 'MecaLine', 'Standard', '500-3000 crs/min', '230 V', 'Lame droite', 69.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-004'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-004-720W', '720 W', 'MecaLine', 'Pro', '500-3200 crs/min', '230 V', 'Lame pendulaire', 84.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-004'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, puissance, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-004-900W', '900 W', 'MecaLine', 'Pro+', '500-3400 crs/min', '230 V', 'Lame pendulaire renforcee', 99.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-004'
ON DUPLICATE KEY UPDATE puissance = VALUES(puissance), marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

-- Ponceuse excentrique : declinee par tension de batterie (meme logique que
-- la perceuse et la visseuse, troisieme exemple de la meme "famille" pour
-- montrer la coherence du theme sans-fil).
INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-005-108V', 'ForceTech', 'Ultra-compacte', '4000-8500 osc/min', '10.8 V', 'Ronde 125mm', 64.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-005'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-005-12V', 'ForceTech', 'Compacte', '4000-9500 osc/min', '12 V', 'Ronde 125mm', 84.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-005'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-005-18V', 'ForceTech', 'Pro', '4000-10500 osc/min', '18 V', 'Ronde 150mm', 104.90, 1
FROM products p WHERE p.sku = 'DEMO-OUT-005'
ON DUPLICATE KEY UPDATE marque = VALUES(marque), type = VALUES(type), vitesse = VALUES(vitesse), tension = VALUES(tension), forme = VALUES(forme), unit_price = VALUES(unit_price), is_active = VALUES(is_active);

INSERT INTO product_variants (product_id, sku, marque, type, vitesse, tension, forme, unit_price, is_active)
SELECT p.id, 'DEMO-OUT-005-20V', 'ForceTech', 'Pro+', '4000-11000 osc/min variable', '20 V', 'Ronde 150mm', 124.90, 1
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
SELECT v.product_id, v.id, w.id, 18, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-001-108V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 14, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-001-12V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 7, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-001-18V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 3, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-001-20V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 5, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-002-750W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 9, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-002-1200W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 2, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-002-2000W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 1, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-002-2400W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 15, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-003-108V'
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
SELECT v.product_id, v.id, w.id, 2, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-003-20V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 12, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-004-350W'
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
SELECT v.product_id, v.id, w.id, 1, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-004-900W'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 10, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-005-108V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 8, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-005-12V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 3, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-005-18V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

INSERT INTO stock_levels (product_id, variant_id, warehouse_id, quantity, reserved_quantity)
SELECT v.product_id, v.id, w.id, 1, 0 FROM product_variants v JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-005-20V'
  AND NOT EXISTS (SELECT 1 FROM stock_levels sl WHERE sl.variant_id = v.id AND sl.warehouse_id = w.id AND sl.location_id IS NULL);

-- Les cinq produits concernes doivent etre marques "a des variantes" (deja le
-- cas des la creation ci-dessus, cette ligne le garantit aussi en cas de
-- relance sur une base ou ils existaient deja autrement).
UPDATE products SET has_variants = 1 WHERE sku IN ('DEMO-OUT-001', 'DEMO-OUT-002', 'DEMO-OUT-003', 'DEMO-OUT-004', 'DEMO-OUT-005');

-- ==============================================================================
-- ACTIVITE DE DEMO : une demande d'achat -> commande fournisseur receptionnee
-- -> livraison client (BL) -> mouvements de stock, pour que ce theme montre
-- lui aussi un usage reel et pas seulement un catalogue statique (meme
-- principe que catalog-demo.sql). Numeros de piece "-OUT-" distincts de
-- "-DEMO-" utilises par catalog-demo.sql : aucun conflit si les deux
-- fichiers sont charges ensemble. Toutes les dates sont relatives a
-- @demo_base (defini plus haut), donc toujours "recentes".
-- ==============================================================================

-- Demande d'achat : reappro de la perceuse-visseuse 18V, convertie en commande.
INSERT INTO purchase_requests (request_number, requester_id, warehouse_id, status, requested_at, needed_at, notes, created_at, updated_at)
SELECT 'PR-OUT-0001', __CURRENT_ADMIN_ID__, w.id, 'CONVERTED',
       DATE_ADD(@demo_base, INTERVAL 500 SECOND),
       DATE_ADD(DATE_ADD(@demo_base, INTERVAL 500 SECOND), INTERVAL 14 DAY),
       'Reappro perceuse-visseuse 18V', DATE_ADD(@demo_base, INTERVAL 500 SECOND), DATE_ADD(@demo_base, INTERVAL 560 SECOND)
FROM warehouses w WHERE w.is_default = 1
ON DUPLICATE KEY UPDATE status = VALUES(status), updated_at = VALUES(updated_at);

INSERT INTO purchase_request_items (purchase_request_id, product_id, variant_id, quantity_requested)
SELECT pr.id, p.id, v.id, 5
FROM purchase_requests pr, products p, product_variants v
WHERE pr.request_number = 'PR-OUT-0001' AND p.sku = 'DEMO-OUT-001' AND v.sku = 'DEMO-OUT-001-18V'
  AND NOT EXISTS (SELECT 1 FROM purchase_request_items i WHERE i.purchase_request_id = pr.id AND i.variant_id = v.id);

-- Commande fournisseur issue de la demande ci-dessus, deja receptionnee chez OutilPro.
INSERT INTO purchase_orders (order_number, supplier_id, warehouse_id, purchase_request_id, status, ordered_by, ordered_at, expected_at, received_at, notes, created_at, updated_at)
SELECT 'PO-OUT-0001', s.id, w.id, pr.id, 'RECEIVED', __CURRENT_ADMIN_ID__,
       DATE_ADD(@demo_base, INTERVAL 560 SECOND),
       DATE_ADD(DATE_ADD(@demo_base, INTERVAL 560 SECOND), INTERVAL 10 DAY),
       DATE_ADD(@demo_base, INTERVAL 610 SECOND),
       '', DATE_ADD(@demo_base, INTERVAL 560 SECOND), DATE_ADD(@demo_base, INTERVAL 610 SECOND)
FROM suppliers s
JOIN warehouses w ON w.is_default = 1
JOIN purchase_requests pr ON pr.request_number = 'PR-OUT-0001'
WHERE s.name = 'OutilPro'
ON DUPLICATE KEY UPDATE status = VALUES(status), received_at = VALUES(received_at);

INSERT INTO purchase_order_items (purchase_order_id, product_id, variant_id, quantity_ordered, quantity_received, unit_cost, line_total)
SELECT po.id, p.id, v.id, 5, 5, 60.00, 300.00
FROM purchase_orders po, products p, product_variants v
WHERE po.order_number = 'PO-OUT-0001' AND p.sku = 'DEMO-OUT-001' AND v.sku = 'DEMO-OUT-001-18V'
  AND NOT EXISTS (SELECT 1 FROM purchase_order_items i WHERE i.purchase_order_id = po.id AND i.variant_id = v.id);

-- Livraison client (BL) : meuleuse 2000W et scie sauteuse 550W, pour CLI-OUT-001.
INSERT INTO deliveries (delivery_number, customer_id, warehouse_id, status, delivered_by, delivered_at, notes, created_at, updated_at)
SELECT 'BL-OUT-0001', c.id, w.id, 'VALIDATED', __CURRENT_ADMIN_ID__,
       DATE_ADD(@demo_base, INTERVAL 700 SECOND), '',
       DATE_ADD(@demo_base, INTERVAL 700 SECOND), DATE_ADD(@demo_base, INTERVAL 700 SECOND)
FROM customers c
JOIN warehouses w ON w.is_default = 1
WHERE c.code = 'CLI-OUT-001'
ON DUPLICATE KEY UPDATE status = VALUES(status);

INSERT INTO delivery_lines (delivery_id, product_id, variant_id, quantity, unit_price, line_total)
SELECT d.id, p.id, v.id, 2, v.unit_price, 2 * v.unit_price
FROM deliveries d, products p, product_variants v
WHERE d.delivery_number = 'BL-OUT-0001' AND p.sku = 'DEMO-OUT-002' AND v.sku = 'DEMO-OUT-002-2000W'
  AND NOT EXISTS (SELECT 1 FROM delivery_lines l WHERE l.delivery_id = d.id AND l.variant_id = v.id);

INSERT INTO delivery_lines (delivery_id, product_id, variant_id, quantity, unit_price, line_total)
SELECT d.id, p.id, v.id, 1, v.unit_price, 1 * v.unit_price
FROM deliveries d, products p, product_variants v
WHERE d.delivery_number = 'BL-OUT-0001' AND p.sku = 'DEMO-OUT-004' AND v.sku = 'DEMO-OUT-004-550W'
  AND NOT EXISTS (SELECT 1 FROM delivery_lines l WHERE l.delivery_id = d.id AND l.variant_id = v.id);

-- Mouvements de stock correspondant a ce scenario (reception PO, puis
-- expedition des 2 lignes de la livraison). balance_after tient compte du
-- stock initial cree plus haut (7 pour la 18V, 2 pour la meuleuse 2000W, 9
-- pour la scie 550W).
INSERT INTO stock_movements (product_id, variant_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
SELECT p.id, v.id, w.id, 'IN', 5, 12, 'PURCHASE_ORDER', po.id, CONCAT('PO receipt ', po.order_number), 'PO_RECEIPT', __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 610 SECOND)
FROM products p JOIN product_variants v ON v.product_id = p.id JOIN warehouses w ON w.is_default = 1 JOIN purchase_orders po ON po.order_number = 'PO-OUT-0001'
WHERE v.sku = 'DEMO-OUT-001-18V'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

INSERT INTO stock_movements (product_id, variant_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
SELECT p.id, v.id, w.id, 'OUT', 2, 0, 'DELIVERY', d.id, CONCAT('BL ', d.delivery_number), 'DELIVERY', __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 700 SECOND)
FROM products p JOIN product_variants v ON v.product_id = p.id JOIN warehouses w ON w.is_default = 1 JOIN deliveries d ON d.delivery_number = 'BL-OUT-0001'
WHERE v.sku = 'DEMO-OUT-002-2000W'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

INSERT INTO stock_movements (product_id, variant_id, warehouse_id, type, quantity, balance_after, reference_type, reference_id, notes, reason_code, moved_by, created_at)
SELECT p.id, v.id, w.id, 'OUT', 1, 8, 'DELIVERY', d.id, CONCAT('BL ', d.delivery_number), 'DELIVERY', __CURRENT_ADMIN_ID__, DATE_ADD(@demo_base, INTERVAL 700 SECOND)
FROM products p JOIN product_variants v ON v.product_id = p.id JOIN warehouses w ON w.is_default = 1 JOIN deliveries d ON d.delivery_number = 'BL-OUT-0001'
WHERE v.sku = 'DEMO-OUT-004-550W'
ON DUPLICATE KEY UPDATE balance_after = VALUES(balance_after);

-- Alerte de rupture sur la meuleuse 2000W, entierement expediee par la livraison ci-dessus.
INSERT INTO stock_alerts (alert_type, severity, product_id, variant_id, warehouse_id, message, status, created_at)
SELECT 'OUT_OF_STOCK', 'CRITICAL', p.id, v.id, w.id, 'Rupture de stock pour Meuleuse d angle filaire (DEMO-OUT-002-2000W)', 'OPEN', DATE_ADD(@demo_base, INTERVAL 700 SECOND)
FROM products p JOIN product_variants v ON v.product_id = p.id JOIN warehouses w ON w.is_default = 1
WHERE v.sku = 'DEMO-OUT-002-2000W'
  AND NOT EXISTS (SELECT 1 FROM stock_alerts a WHERE a.message = 'Rupture de stock pour Meuleuse d angle filaire (DEMO-OUT-002-2000W)' AND a.created_at = DATE_ADD(@demo_base, INTERVAL 700 SECOND));

-- Quantites finales en stock, coherentes avec l'historique de mouvements
-- ci-dessus (7 -> 12 pour la perceuse 18V apres reception ; 2 -> 0 pour la
-- meuleuse 2000W et 9 -> 8 pour la scie 550W apres livraison).
UPDATE stock_levels sl
JOIN product_variants v ON v.id = sl.variant_id
SET sl.quantity = 12
WHERE v.sku = 'DEMO-OUT-001-18V';

UPDATE stock_levels sl
JOIN product_variants v ON v.id = sl.variant_id
SET sl.quantity = 0
WHERE v.sku = 'DEMO-OUT-002-2000W';

UPDATE stock_levels sl
JOIN product_variants v ON v.id = sl.variant_id
SET sl.quantity = 8
WHERE v.sku = 'DEMO-OUT-004-550W';
