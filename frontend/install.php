<?php
declare(strict_types=1);

/**
 * Installateur web - aucun acces SSH necessaire.
 *
 * Utilisation:
 *  1. Uploader tout le projet via FTP sur l'hebergement du client.
 *  2. Creer via FTP un fichier config/install.key contenant une phrase secrete
 *     de ton choix (sert de "cle d'installation", evite qu'un tiers qui
 *     tomberait sur cette page avant toi puisse s'auto-installer un compte admin).
 *  3. Visiter https://domaine-du-client.tld/frontend/install.php
 *  4. Remplir le formulaire (BDD, infos client, logo, compte admin).
 *  5. Une fois termine : SUPPRIMER ce fichier (frontend/install.php) via FTP.
 */

$rootPath = dirname(__DIR__);
require_once $rootPath . '/config/env-loader.php';

$lockFile = $rootPath . '/config/.installed';
$keyFile = $rootPath . '/config/install.key';
$errors = [];
$success = null;

function e(?string $value): string
{
    return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}

/**
 * Meme logique que App\Shared\Security\PasswordService::preferredAlgorithm()
 * (non reutilisable ici, install.php n'utilise pas l'autoloader de l'app pour
 * rester un script autonome). Argon2id necessite l'extension sodium, souvent
 * absente sur les hebergements mutualises bas de gamme - premiere cible de
 * cet installateur (voir en-tete de ce fichier: "aucun acces SSH necessaire").
 * On bascule sur bcrypt si indisponible, sans quoi la creation du compte
 * admin plante avec une erreur fatale (constante non definie).
 */
function resolvePasswordAlgorithm(): string
{
    if (defined('PASSWORD_ARGON2ID') && in_array(PASSWORD_ARGON2ID, password_algos(), true)) {
        return PASSWORD_ARGON2ID;
    }

    return PASSWORD_BCRYPT;
}

function ensureMigrationTable(PDO $pdo): void
{
    $pdo->exec('
        CREATE TABLE IF NOT EXISTS schema_migrations (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            filename VARCHAR(255) NOT NULL UNIQUE,
            batch INT NOT NULL,
            applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB
    ');
}

/** @return array<int, string> */
function listSqlFiles(string $path): array
{
    if (!is_dir($path)) {
        return [];
    }
    $files = glob($path . '/*.sql') ?: [];
    sort($files, SORT_NATURAL);
    return $files;
}

/** @return array<string, bool> */
function appliedMigrations(PDO $pdo): array
{
    $rows = $pdo->query('SELECT filename FROM schema_migrations')->fetchAll(PDO::FETCH_COLUMN);
    $map = [];
    foreach ($rows as $filename) {
        $map[(string)$filename] = true;
    }
    return $map;
}

function applySqlFile(PDO $pdo, string $file): void
{
    $sql = file_get_contents($file);
    if ($sql === false) {
        throw new RuntimeException("Impossible de lire le fichier de migration: {$file}");
    }
    $pdo->exec($sql);
}

function runMigrations(PDO $pdo, string $upPath): int
{
    ensureMigrationTable($pdo);
    $files = listSqlFiles($upPath);
    $applied = appliedMigrations($pdo);
    $pending = array_values(array_filter($files, static fn (string $f): bool => !isset($applied[basename($f)])));

    if ($pending === []) {
        return 0;
    }

    $batch = (int)$pdo->query('SELECT COALESCE(MAX(batch),0) + 1 FROM schema_migrations')->fetchColumn();
    foreach ($pending as $file) {
        applySqlFile($pdo, $file);
        $stmt = $pdo->prepare('INSERT INTO schema_migrations (filename, batch) VALUES (:filename, :batch)');
        $stmt->execute([':filename' => basename($file), ':batch' => $batch]);
    }
    return count($pending);
}

/**
 * Verifie et copie un logo uploade. Retourne le nom de fichier stocke, ou null
 * si aucun fichier n'a ete fourni. Leve une exception si le fichier est invalide.
 */
function handleLogoUpload(array $file, string $destDir): ?string
{
    $error = (int)($file['error'] ?? UPLOAD_ERR_NO_FILE);
    if ($error === UPLOAD_ERR_NO_FILE) {
        return null;
    }
    if ($error !== UPLOAD_ERR_OK) {
        throw new RuntimeException('Erreur lors de l\'upload du logo (code ' . $error . ').');
    }

    $tmpName = (string)($file['tmp_name'] ?? '');
    $originalName = (string)($file['name'] ?? '');
    $size = (int)($file['size'] ?? 0);

    if ($tmpName === '' || !is_uploaded_file($tmpName)) {
        throw new RuntimeException('Fichier logo invalide.');
    }
    if ($size <= 0 || $size > 3 * 1024 * 1024) {
        throw new RuntimeException('Le logo doit faire moins de 3 Mo.');
    }

    $extension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
    $allowedRaster = ['png' => 'image/png', 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'webp' => 'image/webp', 'gif' => 'image/gif'];

    if ($extension === 'svg') {
        $content = file_get_contents($tmpName) ?: '';
        $isValidSvg = str_contains($content, '<svg');
        // Blocage large: balises de script, gestionnaires d'evenements (onload=,
        // onerror=, etc.), et references externes (javascript:, xlink:href vers
        // une ressource distante) qui pourraient executer du JS si ce SVG etait
        // un jour ouvert directement plutot qu'affiche via une balise <img>
        // (qui, elle, neutralise deja l'execution de script dans les SVG).
        $isDangerous = preg_match('/<script\b/i', $content)
            || preg_match('/\bon[a-z]+\s*=/i', $content)
            || preg_match('/javascript\s*:/i', $content)
            || preg_match('/<foreignObject\b/i', $content);
        if (!$isValidSvg || $isDangerous) {
            throw new RuntimeException('Fichier SVG invalide ou potentiellement dangereux.');
        }
    } elseif (isset($allowedRaster[$extension])) {
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $realMime = $finfo ? (finfo_file($finfo, $tmpName) ?: '') : '';
        if ($finfo) {
            finfo_close($finfo);
        }
        if ($realMime !== $allowedRaster[$extension]) {
            throw new RuntimeException('Le contenu du fichier ne correspond pas a son extension.');
        }
    } else {
        throw new RuntimeException('Format de logo non supporte (png, jpg, jpeg, webp, gif, svg uniquement).');
    }

    if (!is_dir($destDir)) {
        mkdir($destDir, 0775, true);
    }
    $storedName = 'custom-logo.' . $extension;
    if (!move_uploaded_file($tmpName, $destDir . '/' . $storedName)) {
        throw new RuntimeException('Impossible d\'enregistrer le logo sur le serveur.');
    }

    return $storedName;
}

// --- Etat de l'installation ---
$alreadyInstalled = is_file($lockFile);
$keyFileExists = is_file($keyFile);

if (!$keyFileExists) {
    // Rien a faire sans la cle: on affiche juste les instructions.
    ?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Installation - cle requise</title>
<style>body{font-family:system-ui,sans-serif;max-width:640px;margin:60px auto;line-height:1.6;color:#1e293b}
code{background:#f1f5f9;padding:2px 6px;border-radius:4px}pre{background:#0f172a;color:#e2e8f0;padding:16px;border-radius:8px;overflow:auto}</style>
</head>
<body>
<h1>Cle d'installation requise</h1>
<p>Pour lancer l'installation, cree via FTP (ou le gestionnaire de fichiers de ton hebergement) le fichier suivant, contenant une phrase secrete de ton choix :</p>
<pre><?= e($rootPath) ?>/config/install.key</pre>
<p>Exemple de contenu du fichier (une seule ligne) :</p>
<pre>abc-installation-2026-xyz</pre>
<p>Recharge ensuite cette page une fois le fichier cree. Cette cle t'evite qu'une personne tombant sur cette page avant toi puisse lancer l'installation a ta place.</p>
</body>
</html>
    <?php
    exit;
}

$installKeyValue = trim((string)file_get_contents($keyFile));

if ($alreadyInstalled && ($_POST['confirm_reinstall'] ?? '') !== 'oui') {
    ?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Deja installe</title>
<style>body{font-family:system-ui,sans-serif;max-width:640px;margin:60px auto;line-height:1.6;color:#1e293b}
.warn{background:#fef3c7;border:1px solid #f59e0b;padding:16px;border-radius:8px}</style>
</head>
<body>
<h1>Cette instance est deja installee</h1>
<div class="warn">
<p>Le fichier <code>config/.installed</code> existe deja. Relancer l'installation ne supprime pas les donnees existantes mais va recreer/mettre a jour le compte admin et le branding.</p>
<form method="post">
<input type="hidden" name="confirm_reinstall" value="oui">
<p>Cle d'installation:<br><input type="password" name="install_key" required style="width:100%;padding:8px"></p>
<button type="submit" style="padding:10px 20px">Reconfigurer quand meme</button>
</form>
</div>
<p>Si ce n'est pas volontaire, ignore cette page et supprime <code>frontend/install.php</code> via FTP.</p>
</body>
</html>
    <?php
    exit;
}

// --- Traitement du formulaire ---
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $providedKey = (string)($_POST['install_key'] ?? '');
    if ($providedKey === '' || !hash_equals($installKeyValue, $providedKey)) {
        usleep(500000); // ralentit le brute-force sur la cle
        $errors[] = "Cle d'installation incorrecte.";
    }

    $dbHost = trim((string)($_POST['db_host'] ?? ''));
    $dbPort = (int)($_POST['db_port'] ?? 3306);
    $dbName = trim((string)($_POST['db_name'] ?? ''));
    $dbUser = trim((string)($_POST['db_user'] ?? ''));
    $dbPass = (string)($_POST['db_pass'] ?? '');

    $tenantName = trim((string)($_POST['tenant_name'] ?? ''));
    $tenantSupportEmail = trim((string)($_POST['tenant_support_email'] ?? ''));
    $tenantPrimaryColor = trim((string)($_POST['tenant_primary_color'] ?? '#2563eb'));
    $tenantFooterText = trim((string)($_POST['tenant_footer_text'] ?? ''));

    $siteUrl = rtrim(trim((string)($_POST['site_url'] ?? '')), '/');

    $adminName = trim((string)($_POST['admin_name'] ?? ''));
    $adminEmail = trim((string)($_POST['admin_email'] ?? ''));
    $adminPassword = (string)($_POST['admin_password'] ?? '');
    $adminPasswordConfirm = (string)($_POST['admin_password_confirm'] ?? '');

    foreach ([
        'Hote MySQL' => $dbHost, 'Nom de la base' => $dbName, 'Utilisateur MySQL' => $dbUser,
        'Nom de la societe' => $tenantName, 'URL du site' => $siteUrl,
        'Nom de l\'administrateur' => $adminName, 'Email de l\'administrateur' => $adminEmail,
    ] as $label => $value) {
        if ($value === '') {
            $errors[] = "Le champ \"{$label}\" est obligatoire.";
        }
    }
    if (!filter_var($adminEmail, FILTER_VALIDATE_EMAIL)) {
        $errors[] = 'Email administrateur invalide.';
    }
    if (strlen($adminPassword) < 10) {
        $errors[] = 'Le mot de passe admin doit faire au moins 10 caracteres.';
    }
    if ($adminPassword !== $adminPasswordConfirm) {
        $errors[] = 'La confirmation du mot de passe ne correspond pas.';
    }
    if (!preg_match('/^https?:\/\//', $siteUrl)) {
        $errors[] = 'L\'URL du site doit commencer par http:// ou https://.';
    }

    $pdo = null;
    if ($errors === []) {
        try {
            $rootDsn = sprintf('mysql:host=%s;port=%d;charset=utf8mb4', $dbHost, $dbPort);
            $rootPdo = new PDO($rootDsn, $dbUser, $dbPass, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_TIMEOUT => 5,
            ]);
            $rootPdo->exec("CREATE DATABASE IF NOT EXISTS `{$dbName}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");

            $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $dbHost, $dbPort, $dbName);
            $pdo = new PDO($dsn, $dbUser, $dbPass, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]);
        } catch (Throwable $e) {
            $errors[] = 'Connexion MySQL impossible : ' . $e->getMessage();
        }
    }

    // Le logo n'est ecrit sur disque qu'une fois la BDD validee, pour eviter
    // qu'une tentative echouee (ex: mauvais hote MySQL) laisse un fichier
    // orphelin non reference dans .env apres une resoumission du formulaire
    // (les champs fichier ne sont jamais resoumis automatiquement).
    $logoFileName = null;
    if ($errors === []) {
        try {
            if (isset($_FILES['tenant_logo'])) {
                $logoFileName = handleLogoUpload($_FILES['tenant_logo'], $rootPath . '/frontend/assets/img/brand');
            }
        } catch (Throwable $e) {
            $errors[] = $e->getMessage();
        }
    }

    if ($errors === [] && $pdo instanceof PDO) {
        try {
            $migratedCount = runMigrations($pdo, $rootPath . '/database/migrations/up');

            $pdo->exec("
                INSERT INTO roles (code, label) VALUES
                ('ADMIN', 'Administrateur'),
                ('MANAGER', 'Responsable stock'),
                ('STOREKEEPER', 'Magasinier'),
                ('EMPLOYEE', 'Employe')
                ON DUPLICATE KEY UPDATE label = VALUES(label)
            ");

            $stmt = $pdo->prepare("
                INSERT INTO warehouses (name, location, is_default)
                VALUES ('Entrepot Principal', :location, 1)
                ON DUPLICATE KEY UPDATE location = VALUES(location)
            ");
            $stmt->execute([':location' => $tenantName]);

            $passwordHash = password_hash($adminPassword, resolvePasswordAlgorithm());
            $stmt = $pdo->prepare("
                INSERT INTO users (full_name, email, password_hash, role_id, is_active)
                SELECT :full_name, :email, :password_hash, r.id, 1
                FROM roles r WHERE r.code = 'ADMIN'
                ON DUPLICATE KEY UPDATE full_name = VALUES(full_name), password_hash = VALUES(password_hash), is_active = 1
            ");
            $stmt->execute([
                ':full_name' => $adminName,
                ':email' => $adminEmail,
                ':password_hash' => $passwordHash,
            ]);

            // Reglages generaux par defaut : sans ca, l'ecran "Parametres"
            // reste vide apres l'installation et le client doit les saisir
            // a la main un par un. idempotent (ON DUPLICATE KEY UPDATE), donc
            // sans risque si l'installateur est relance sur une base existante
            // (n'ecrase pas une valeur que le client aurait deja personnalisee
            // depuis l'ecran Parametres, sauf a vouloir la remettre au defaut).
            $pdo->exec("
                INSERT INTO app_settings (setting_key, setting_value) VALUES
                ('default_currency', 'EUR'),
                ('default_language', 'fr'),
                ('default_timezone', 'Europe/Paris'),
                ('default_min_stock', '10'),
                ('document_number_format', '{PREFIX}-{YEAR}-{SEQ}')
                ON DUPLICATE KEY UPDATE setting_key = setting_key
            ");

            // --- Ecriture du .env ---
            $envContent = "APP_NAME={$tenantName}\n"
                . "APP_ENV=production\n"
                . "APP_DEBUG=0\n"
                . "APP_TIMEZONE=Europe/Paris\n"
                . "FRONTEND_URL={$siteUrl}/frontend\n"
                . "CORS_ALLOWED_ORIGINS={$siteUrl}\n\n"
                . "DB_HOST={$dbHost}\n"
                . "DB_PORT={$dbPort}\n"
                . "DB_NAME={$dbName}\n"
                . "DB_USER={$dbUser}\n"
                . "DB_PASS={$dbPass}\n"
                . "DB_CHARSET=utf8mb4\n\n"
                . "TENANT_NAME={$tenantName}\n"
                . "TENANT_LOGO_FILE={$logoFileName}\n"
                . "TENANT_PRIMARY_COLOR={$tenantPrimaryColor}\n"
                . "TENANT_SUPPORT_EMAIL={$tenantSupportEmail}\n"
                . "TENANT_FOOTER_TEXT={$tenantFooterText}\n";

            file_put_contents($rootPath . '/backend/.env', $envContent);
            @chmod($rootPath . '/backend/.env', 0640);

            file_put_contents($lockFile, 'Installe le ' . date('Y-m-d H:i:s') . " pour {$tenantName}\n");
            @unlink($keyFile);

            $success = [
                'site_url' => $siteUrl,
                'admin_email' => $adminEmail,
                'migrated' => $migratedCount,
            ];
        } catch (Throwable $e) {
            $errors[] = 'Erreur pendant l\'installation : ' . $e->getMessage();
        }
    }
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Installation - Gestion Stock</title>
<style>
  body{font-family:system-ui,-apple-system,sans-serif;background:#f8fafc;color:#1e293b;margin:0;padding:40px 16px}
  .wrap{max-width:640px;margin:0 auto}
  h1{font-size:1.5rem}
  fieldset{border:1px solid #e2e8f0;border-radius:10px;padding:20px;margin-bottom:20px;background:#fff}
  legend{font-weight:600;padding:0 8px;color:#334155}
  label{display:block;margin-bottom:14px;font-size:.92rem}
  label span{display:block;margin-bottom:4px;color:#475569}
  input[type=text],input[type=email],input[type=password],input[type=number],input[type=url],input[type=color],input[type=file]{
    width:100%;padding:9px 10px;border:1px solid #cbd5e1;border-radius:6px;font-size:.95rem;box-sizing:border-box}
  .row2{display:grid;grid-template-columns:1fr 1fr;gap:12px}
  button{background:#2563eb;color:#fff;border:none;padding:12px 24px;border-radius:8px;font-size:1rem;cursor:pointer}
  button:hover{background:#1d4ed8}
  .errors{background:#fef2f2;border:1px solid #fca5a5;color:#991b1b;padding:14px 18px;border-radius:8px;margin-bottom:20px}
  .success{background:#f0fdf4;border:1px solid #86efac;color:#166534;padding:18px 22px;border-radius:10px}
  .success code{background:#dcfce7;padding:2px 6px;border-radius:4px}
  .hint{color:#64748b;font-size:.82rem;margin-top:-8px;margin-bottom:14px}
  .warn-box{background:#fffbeb;border:1px solid #fcd34d;color:#92400e;padding:14px 18px;border-radius:8px;margin-top:20px}
</style>
</head>
<body>
<div class="wrap">
<h1>Installation - Gestion Stock</h1>

<?php if ($success !== null): ?>
  <div class="success">
    <h2>Installation terminee</h2>
    <p><?= $success['migrated'] ?> migration(s) appliquee(s).</p>
    <p>Connexion : <a href="<?= e($success['site_url']) ?>/frontend/login.php"><?= e($success['site_url']) ?>/frontend/login.php</a></p>
    <p>Compte admin : <code><?= e($success['admin_email']) ?></code> avec le mot de passe que tu viens de choisir.</p>
    <p>Reglages par defaut appliques (modifiables ensuite dans Parametres) : devise EUR, langue fr, fuseau Europe/Paris, stock min. 10, numerotation documents <code>{PREFIX}-{YEAR}-{SEQ}</code>.</p>
  </div>
  <div class="warn-box">
    <strong>Derniere etape importante :</strong> supprime maintenant le fichier
    <code>frontend/install.php</code> via FTP (ou ton gestionnaire de fichiers).
    Tant qu'il reste en ligne, n'importe qui connaissant la cle d'installation
    pourrait relancer ou modifier la configuration.
  </div>
<?php else: ?>

  <?php if ($errors !== []): ?>
    <div class="errors">
      <strong>Impossible de continuer :</strong>
      <ul><?php foreach ($errors as $err): ?><li><?= e($err) ?></li><?php endforeach; ?></ul>
    </div>
  <?php endif; ?>

  <form method="post" enctype="multipart/form-data">
    <fieldset>
      <legend>Cle d'installation</legend>
      <label><span>Cle (definie dans config/install.key)</span>
        <input type="password" name="install_key" required></label>
    </fieldset>

    <fieldset>
      <legend>Base de donnees MySQL</legend>
      <div class="row2">
        <label><span>Hote</span><input type="text" name="db_host" value="<?= e($_POST['db_host'] ?? '127.0.0.1') ?>" required></label>
        <label><span>Port</span><input type="number" name="db_port" value="<?= e($_POST['db_port'] ?? '3306') ?>" required></label>
      </div>
      <label><span>Nom de la base</span><input type="text" name="db_name" value="<?= e($_POST['db_name'] ?? 'gestion_stock') ?>" required></label>
      <label><span>Utilisateur</span><input type="text" name="db_user" value="<?= e($_POST['db_user'] ?? '') ?>" required></label>
      <label><span>Mot de passe</span><input type="password" name="db_pass" value=""></label>
      <p class="hint">Ces identifiants te sont fournis par l'hebergeur (panneau d'administration / cPanel).</p>
    </fieldset>

    <fieldset>
      <legend>Informations du client final</legend>
      <label><span>Nom de la societe / application</span><input type="text" name="tenant_name" value="<?= e($_POST['tenant_name'] ?? '') ?>" required></label>
      <label><span>Email de support (optionnel)</span><input type="email" name="tenant_support_email" value="<?= e($_POST['tenant_support_email'] ?? '') ?>"></label>
      <label><span>Couleur principale</span><input type="color" name="tenant_primary_color" value="<?= e($_POST['tenant_primary_color'] ?? '#2563eb') ?>"></label>
      <label><span>Texte de pied de page (optionnel)</span><input type="text" name="tenant_footer_text" value="<?= e($_POST['tenant_footer_text'] ?? '') ?>"></label>
      <label><span>Logo (png, jpg, webp, gif ou svg, optionnel)</span><input type="file" name="tenant_logo" accept=".png,.jpg,.jpeg,.webp,.gif,.svg"></label>
    </fieldset>

    <fieldset>
      <legend>Environnement</legend>
      <label><span>URL publique du site</span>
        <input type="url" name="site_url" placeholder="https://stock.client.fr" value="<?= e($_POST['site_url'] ?? '') ?>" required></label>
    </fieldset>

    <fieldset>
      <legend>Compte administrateur</legend>
      <label><span>Nom complet</span><input type="text" name="admin_name" value="<?= e($_POST['admin_name'] ?? '') ?>" required></label>
      <label><span>Email</span><input type="email" name="admin_email" value="<?= e($_POST['admin_email'] ?? '') ?>" required></label>
      <div class="row2">
        <label><span>Mot de passe (10 caracteres min.)</span><input type="password" name="admin_password" required minlength="10"></label>
        <label><span>Confirmation</span><input type="password" name="admin_password_confirm" required minlength="10"></label>
      </div>
    </fieldset>

    <button type="submit">Installer</button>
  </form>
<?php endif; ?>
</div>
</body>
</html>
