<?php
declare(strict_types=1);

/**
 * Lance les migrations de base de donnees depuis le navigateur - meme
 * logique que backend/bin/migrate.php (CLI), mais accessible sans SSH.
 * Reserve aux comptes ADMIN deja connectes (meme verification que
 * frontend/demo-data.php : cookie de session gs_token + role ADMIN).
 *
 * A garder en ligne en permanence (contrairement a install.php) : protege
 * par l'authentification admin de l'application, utile a chaque nouvelle
 * migration livree.
 */

$rootPath = dirname(__DIR__);
require_once $rootPath . '/config/env-loader.php';
require_once __DIR__ . '/route-frontend.php';

function e(?string $value): string
{
    return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}

function connectDb(): PDO
{
    global $rootPath;
    $config = require $rootPath . '/config/database.php';
    $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=%s', $config['host'], $config['port'], $config['name'], $config['charset']);
    return new PDO($dsn, (string)$config['username'], (string)$config['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}

/** Reproduit App\Application\Services\AuthService + RoleMiddleware(['ADMIN']). */
function requireAdmin(PDO $pdo): array
{
    $token = $_COOKIE['gs_token'] ?? null;
    if (!$token) {
        header('Location: ' . FRONTEND_BASE_URL . '/login.php');
        exit;
    }

    $tokenHash = hash('sha256', (string)$token);
    $stmt = $pdo->prepare("
        SELECT u.id, u.full_name, r.code AS role_code
        FROM personal_access_tokens t
        INNER JOIN users u ON u.id = t.user_id
        INNER JOIN roles r ON r.id = u.role_id
        WHERE t.token_hash = :token_hash AND (t.expires_at IS NULL OR t.expires_at > NOW())
        LIMIT 1
    ");
    $stmt->execute([':token_hash' => $tokenHash]);
    $user = $stmt->fetch();

    if (!$user) {
        header('Location: ' . FRONTEND_BASE_URL . '/login.php');
        exit;
    }
    if (strtoupper((string)$user['role_code']) !== 'ADMIN') {
        http_response_code(403);
        echo 'Reserve aux administrateurs.';
        exit;
    }

    return $user;
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
        throw new RuntimeException("Impossible de lire : {$file}");
    }
    $pdo->exec($sql);
}

/** @return array<int, string> messages de log */
function migrateUp(PDO $pdo, string $upPath): array
{
    $log = [];
    $files = listSqlFiles($upPath);
    if ($files === []) {
        return ["Aucun fichier de migration dans {$upPath}."];
    }

    $applied = appliedMigrations($pdo);
    $pending = array_values(array_filter($files, static fn (string $file): bool => !isset($applied[basename($file)])));

    if ($pending === []) {
        return ['Aucune migration en attente.'];
    }

    $batch = (int)$pdo->query('SELECT COALESCE(MAX(batch),0) + 1 FROM schema_migrations')->fetchColumn();

    foreach ($pending as $file) {
        $name = basename($file);
        applySqlFile($pdo, $file);

        $stmt = $pdo->prepare('INSERT INTO schema_migrations (filename, batch) VALUES (:filename, :batch)');
        $stmt->execute([':filename' => $name, ':batch' => $batch]);

        $log[] = "[OK] {$name}";
    }

    $log[] = 'Applique ' . count($pending) . " migration(s) dans le batch {$batch}.";
    return $log;
}

/** @return array<int, string> */
function rollbackLastBatch(PDO $pdo, string $downPath): array
{
    $log = [];
    $batch = (int)$pdo->query('SELECT COALESCE(MAX(batch),0) FROM schema_migrations')->fetchColumn();
    if ($batch === 0) {
        return ['Aucun batch a annuler.'];
    }

    $stmt = $pdo->prepare('SELECT id, filename FROM schema_migrations WHERE batch = :batch ORDER BY id DESC');
    $stmt->execute([':batch' => $batch]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($rows as $row) {
        $downFile = $downPath . '/' . $row['filename'];
        if (!is_file($downFile)) {
            throw new RuntimeException("Fichier de rollback manquant : {$downFile}");
        }

        applySqlFile($pdo, $downFile);

        $del = $pdo->prepare('DELETE FROM schema_migrations WHERE id = :id');
        $del->execute([':id' => (int)$row['id']]);

        $log[] = "[ANNULE] {$row['filename']}";
    }

    $log[] = "Batch {$batch} annule.";
    return $log;
}

/** @return array<int, array{name:string, status:string}> */
function migrationStatus(PDO $pdo, string $upPath): array
{
    $files = listSqlFiles($upPath);
    $applied = appliedMigrations($pdo);

    return array_map(static function (string $file) use ($applied): array {
        $name = basename($file);
        return ['name' => $name, 'status' => isset($applied[$name]) ? 'APPLIQUEE' : 'EN ATTENTE'];
    }, $files);
}

$pdo = connectDb();
$admin = requireAdmin($pdo);
ensureMigrationTable($pdo);

$upPath = $rootPath . '/database/migrations/up';
$downPath = $rootPath . '/database/migrations/down';

$log = null;
$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    try {
        if ($action === 'up') {
            $log = migrateUp($pdo, $upPath);
        } elseif ($action === 'down') {
            if (($_POST['confirm_text'] ?? '') !== 'ANNULER') {
                $error = 'Confirmation invalide : tape exactement "ANNULER" pour valider.';
            } else {
                $log = rollbackLastBatch($pdo, $downPath);
            }
        }
    } catch (Throwable $ex) {
        $error = '[ERREUR] ' . $ex->getMessage();
    }
}

$status = migrationStatus($pdo, $upPath);
$pendingCount = count(array_filter($status, static fn (array $row): bool => $row['status'] === 'EN ATTENTE'));
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Migrations - <?= e($tenant['company_name']) ?></title>
<style>
  body{font-family:system-ui,-apple-system,sans-serif;background:#f8fafc;color:#1e293b;margin:0;padding:40px 16px}
  .wrap{max-width:680px;margin:0 auto}
  h1{font-size:1.5rem}
  fieldset{border:1px solid #e2e8f0;border-radius:10px;padding:20px;margin-bottom:20px;background:#fff}
  legend{font-weight:600;padding:0 8px;color:#334155}
  p.hint{color:#64748b;font-size:.9rem;margin-top:4px}
  button{background:#2563eb;color:#fff;border:none;padding:12px 24px;border-radius:8px;font-size:1rem;cursor:pointer}
  button:hover{background:#1d4ed8}
  button.danger{background:#dc2626}
  button.danger:hover{background:#b91c1c}
  button:disabled{background:#94a3b8;cursor:not-allowed}
  .success{background:#f0fdf4;border:1px solid #86efac;color:#166534;padding:14px 18px;border-radius:8px;margin-bottom:20px;white-space:pre-line;font-family:monospace;font-size:.85rem}
  .errors{background:#fef2f2;border:1px solid #fca5a5;color:#991b1b;padding:14px 18px;border-radius:8px;margin-bottom:20px}
  .warn-box{background:#fffbeb;border:1px solid #fcd34d;color:#92400e;padding:14px 18px;border-radius:8px;margin-top:14px;font-size:.9rem}
  table{width:100%;border-collapse:collapse;font-size:.9rem}
  th,td{text-align:left;padding:8px 6px;border-bottom:1px solid #eef2f6}
  .badge{display:inline-block;padding:2px 8px;border-radius:999px;font-size:.75rem;font-weight:600}
  .badge-ok{background:#dcfce7;color:#166534}
  .badge-pending{background:#fef9c3;color:#854d0e}
  input[type=text]{width:100%;padding:9px 10px;border:1px solid #cbd5e1;border-radius:6px;font-size:.95rem;box-sizing:border-box;margin-top:8px}
  a.back{display:inline-block;margin-bottom:20px;color:#2563eb;text-decoration:none;font-size:.9rem}
</style>
</head>
<body>
<div class="wrap">
  <a class="back" href="<?= e(FRONTEND_BASE_URL) ?>/index.php">&larr; Retour au tableau de bord</a>
  <h1>Migrations de base de donnees</h1>

  <?php if ($log): ?><div class="success"><?= e(implode("\n", $log)) ?></div><?php endif; ?>
  <?php if ($error): ?><div class="errors"><?= e($error) ?></div><?php endif; ?>

  <fieldset>
    <legend>Appliquer les migrations</legend>
    <p><?= $pendingCount > 0 ? "{$pendingCount} migration(s) en attente." : 'Tout est a jour.' ?></p>
    <form method="post">
      <input type="hidden" name="action" value="up">
      <button type="submit" <?= $pendingCount === 0 ? 'disabled' : '' ?>>Appliquer les migrations en attente</button>
    </form>
  </fieldset>

  <fieldset>
    <legend>Etat des migrations</legend>
    <table>
      <thead><tr><th>Fichier</th><th>Statut</th></tr></thead>
      <tbody>
        <?php foreach ($status as $row): ?>
        <tr>
          <td><?= e($row['name']) ?></td>
          <td><span class="badge <?= $row['status'] === 'APPLIQUEE' ? 'badge-ok' : 'badge-pending' ?>"><?= e($row['status']) ?></span></td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </fieldset>

  <fieldset>
    <legend>Annuler le dernier lot de migrations</legend>
    <p>Annule uniquement le dernier batch applique (pas tout l'historique).</p>
    <div class="warn-box">A utiliser seulement en cas d'erreur juste apres une migration. Peut supprimer des colonnes/tables et les donnees qu'elles contiennent.</div>
    <form method="post" onsubmit="return confirm('Annuler le dernier lot de migrations ? Cette action peut supprimer des donnees.');">
      <input type="hidden" name="action" value="down">
      <label>
        Tape <strong>ANNULER</strong> pour confirmer :
        <input type="text" name="confirm_text" autocomplete="off">
      </label>
      <br><br>
      <button type="submit" class="danger">Annuler le dernier lot</button>
    </form>
  </fieldset>
</div>
</body>
</html>
