-- Nouveau role SUPER_ADMIN : reserve au tout premier compte de
-- l'installation. A partir de cette version, ADMIN garde tous les droits
-- sauf deux ecrans sensibles (Donnees de demo, Migrations - voir
-- frontend/demo-data.php et frontend/migrate.php), desormais reserves au
-- Super administrateur.
--
-- Idempotent : peut etre rejouee sans risque (ON DUPLICATE KEY, WHERE qui ne
-- selectionne plus rien une fois le premier admin promu).
--
-- Sur une installation existante, tous les comptes sont aujourd'hui ADMIN :
-- sans intervention, aucun ne deviendrait SUPER_ADMIN et personne n'aurait
-- plus acces aux deux ecrans ci-dessus. On promeut donc ici le compte ADMIN
-- le plus ancien (le premier cree, par id croissant) - c'est la meme regle
-- que celle appliquee par install.php pour une installation neuve.
--
-- Note : demo-data.php et migrate.php font DEJA cette promotion tout seuls
-- au premier acces (voir ensureSuperAdminExists() dans ces deux fichiers),
-- pour ne pas dependre de cette migration pour pouvoir etre executee - cette
-- migration reste utile pour que le role existe des la mise a jour de la
-- base, sans attendre qu'un admin ouvre l'un de ces deux ecrans.

INSERT INTO roles (code, label) VALUES
    ('SUPER_ADMIN', 'Super administrateur')
ON DUPLICATE KEY UPDATE label = VALUES(label);

UPDATE users
SET role_id = (SELECT id FROM roles WHERE code = 'SUPER_ADMIN' LIMIT 1)
WHERE id = (
    SELECT first_admin_id FROM (
        SELECT u.id AS first_admin_id
        FROM users u
        INNER JOIN roles r ON r.id = u.role_id
        WHERE r.code = 'ADMIN'
        ORDER BY u.id ASC
        LIMIT 1
    ) AS first_admin
)
AND NOT EXISTS (
    SELECT 1 FROM users u2
    INNER JOIN roles r2 ON r2.id = u2.role_id
    WHERE r2.code = 'SUPER_ADMIN'
);
