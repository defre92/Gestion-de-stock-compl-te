<?php
declare(strict_types=1);

/**
 * Outils de demonstration - accessible depuis le navigateur, aucun acces SSH
 * necessaire (meme logique que frontend/install.php).
 *
 * Reserve aux comptes ADMIN deja connectes (verifie via le cookie de session
 * gs_token, comme le fait App\Presentation\Middleware\AuthMiddleware/RoleMiddleware
 * cote API). Cette page n'utilise pas l'autoloader de l'app pour rester
 * autonome, mais reproduit exactement la meme verification.
 *
 * Deux actions :
 *  1) Charger les donnees de demo catalogue (database/demo/catalog-demo.sql)
 *     -> categories, fournisseurs, produits, stock, referentiels de base.
 *     Aucun utilisateur ni role n'est touche. Peut etre relance sans risque
 *     (requetes idempotentes).
 *  2) Reinitialiser les donnees -> vide tout le catalogue/stock/mouvements/
 *     achats/livraisons/inventaires du client, mais conserve les comptes
 *     utilisateurs, les roles, les parametres d'application et le journal
 *     d'audit. Necessite de taper "SUPPRIMER" pour confirmer, en plus de la
 *     confirmation JS.
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

/**
 * Reproduit App\Application\Services\AuthService::resolveUserByToken() +
 * RoleMiddleware(['ADMIN']), sans dependre de l'autoloader de l'app.
 */
function requireAdmin(PDO $pdo): array
{
    $token = $_COOKIE['gs_token'] ?? null;
    if (!$token) {
        header('Location: ' . FRONTEND_BASE_URL . '/login.php');
        exit;
    }

    $tokenHash = hash('sha256', (string)$token);
    $stmt = $pdo->prepare("
        SELECT u.id, u.full_name, u.email, u.is_active, r.code AS role_code
        FROM personal_access_tokens t
        INNER JOIN users u ON u.id = t.user_id
        INNER JOIN roles r ON r.id = u.role_id
        WHERE t.token_hash = :token_hash
          AND (t.expires_at IS NULL OR t.expires_at > NOW())
        LIMIT 1
    ");
    $stmt->execute([':token_hash' => $tokenHash]);
    $user = $stmt->fetch();

    if (!$user || !(bool)$user['is_active']) {
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

function logAudit(PDO $pdo, int $userId, string $action, ?string $ip): void
{
    $stmt = $pdo->prepare('
        INSERT INTO audits (user_id, action, entity_type, entity_id, payload_json, ip_address)
        VALUES (:user_id, :action, :entity_type, NULL, NULL, :ip_address)
    ');
    $stmt->execute([
        ':user_id' => $userId,
        ':action' => $action,
        ':entity_type' => 'demo_data',
        ':ip_address' => $ip,
    ]);
}

// Tables videes par le reset. Volontairement absentes de cette liste (donc
// conservees) : users, roles, personal_access_tokens, login_attempts,
// app_settings, audits.
const RESET_TABLES = [
    'delivery_lines', 'deliveries',
    'purchase_order_items', 'purchase_orders',
    'purchase_request_items', 'purchase_requests',
    'inventory_session_items', 'inventory_sessions',
    'inventory_adjustments',
    'stock_alerts', 'stock_movements', 'stock_levels',
    'product_serials', 'product_media', 'product_price_history', 'product_tags',
    'document_attachments', 'document_sequences', 'import_jobs',
    'products',
    'warehouse_locations', 'warehouse_zones', 'warehouses',
    'supplier_contacts', 'suppliers',
    'customers',
    'tags', 'brands', 'units', 'taxes', 'categories',
];

$pdo = connectDb();
$admin = requireAdmin($pdo);

$message = null;
$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    $ip = $_SERVER['REMOTE_ADDR'] ?? null;

    if ($action === 'load_demo') {
        $sqlFile = $rootPath . '/database/demo/catalog-demo.sql';
        try {
            $sql = file_get_contents($sqlFile);
            if ($sql === false) {
                throw new RuntimeException("Fichier introuvable : {$sqlFile}");
            }
            $pdo->beginTransaction();
            $pdo->exec($sql);
            $pdo->commit();
            logAudit($pdo, (int)$admin['id'], 'DEMO_DATA_LOADED', $ip);
            $message = "Donnees de demo chargees : categories, fournisseurs, produits, stock et referentiels. Aucun compte utilisateur n'a ete touche.";
        } catch (Throwable $ex) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            $error = "Echec du chargement des donnees de demo : " . $ex->getMessage();
        }
    } elseif ($action === 'reset_data') {
        if (($_POST['confirm_text'] ?? '') !== 'SUPPRIMER') {
            $error = 'Confirmation invalide : tape exactement "SUPPRIMER" pour valider la reinitialisation.';
        } else {
            try {
                // DELETE plutot que TRUNCATE : TRUNCATE fait un commit
                // implicite en MySQL (rendrait la transaction inutile en cas
                // d'echec partiel) et demande le privilege DROP, pas toujours
                // accorde sur de l'hebergement mutualise. DELETE ne demande
                // que DELETE et reste dans la transaction.
                $pdo->beginTransaction();
                $pdo->exec('SET FOREIGN_KEY_CHECKS = 0');
                foreach (RESET_TABLES as $table) {
                    $pdo->exec('DELETE FROM `' . $table . '`');
                }
                $pdo->exec('SET FOREIGN_KEY_CHECKS = 1');
                $pdo->commit();

                // Best-effort : remet les compteurs auto-increment a zero.
                // ALTER TABLE fait aussi un commit implicite et demande le
                // privilege ALTER : on l'isole donc de la transaction
                // principale et on ignore silencieusement si indisponible,
                // ca ne remet pas en cause le reset des donnees lui-meme.
                foreach (RESET_TABLES as $table) {
                    try {
                        $pdo->exec('ALTER TABLE `' . $table . '` AUTO_INCREMENT = 1');
                    } catch (Throwable $ignored) {
                        // Privilege ALTER absent ou hebergement restrictif : sans consequence.
                    }
                }

                logAudit($pdo, (int)$admin['id'], 'DATA_RESET', $ip);
                $message = 'Catalogue, stock, mouvements, achats, livraisons et inventaires ont ete vides. Tes comptes utilisateurs, roles et parametres ont ete conserves.';
            } catch (Throwable $ex) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                $error = 'Echec de la reinitialisation : ' . $ex->getMessage();
            }
        }
    }
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Donnees de demo - <?= e($tenant['company_name']) ?></title>
<style>
  body{font-family:system-ui,-apple-system,sans-serif;background:#f8fafc;color:#1e293b;margin:0;padding:40px 16px}
  .wrap{max-width:640px;margin:0 auto}
  h1{font-size:1.5rem}
  fieldset{border:1px solid #e2e8f0;border-radius:10px;padding:20px;margin-bottom:20px;background:#fff}
  legend{font-weight:600;padding:0 8px;color:#334155}
  p.hint{color:#64748b;font-size:.9rem;margin-top:4px}
  button{background:#2563eb;color:#fff;border:none;padding:12px 24px;border-radius:8px;font-size:1rem;cursor:pointer}
  button:hover{background:#1d4ed8}
  button.danger{background:#dc2626}
  button.danger:hover{background:#b91c1c}
  .success{background:#f0fdf4;border:1px solid #86efac;color:#166534;padding:14px 18px;border-radius:8px;margin-bottom:20px}
  .errors{background:#fef2f2;border:1px solid #fca5a5;color:#991b1b;padding:14px 18px;border-radius:8px;margin-bottom:20px}
  .warn-box{background:#fffbeb;border:1px solid #fcd34d;color:#92400e;padding:14px 18px;border-radius:8px;margin-top:14px;font-size:.9rem}
  input[type=text]{width:100%;padding:9px 10px;border:1px solid #cbd5e1;border-radius:6px;font-size:.95rem;box-sizing:border-box;margin-top:8px}
  a.back{display:inline-block;margin-bottom:20px;color:#2563eb;text-decoration:none;font-size:.9rem}
</style>
</head>
<body>
<div class="wrap">
  <a class="back" href="<?= e(FRONTEND_BASE_URL) ?>/index.php">&larr; Retour au tableau de bord</a>
  <h1>Donnees de demo</h1>

  <?php if ($message): ?><div class="success"><?= e($message) ?></div><?php endif; ?>
  <?php if ($error): ?><div class="errors"><?= e($error) ?></div><?php endif; ?>

  <fieldset>
    <legend>Charger les donnees de demo</legend>
    <p>Ajoute des categories, fournisseurs, produits et niveaux de stock d'exemple, pour explorer l'application avec des donnees deja remplies.</p>
    <p class="hint">Sans risque : n'ajoute rien qui ecrase tes donnees existantes, ne touche aucun compte utilisateur.</p>
    <form method="post">
      <input type="hidden" name="action" value="load_demo">
      <button type="submit">Charger les donnees de demo</button>
    </form>
  </fieldset>

  <fieldset>
    <legend>Reinitialiser les donnees</legend>
    <p>Vide entierement le catalogue (produits, categories, fournisseurs...), le stock, les mouvements, les achats, les livraisons et les inventaires.</p>
    <p class="hint">Tes comptes utilisateurs, roles et parametres d'application sont conserves : personne n'est deconnecte ni supprime.</p>
    <div class="warn-box">Action irreversible. Toutes les donnees metier seront definitivement effacees.</div>
    <form method="post" id="resetForm" onsubmit="return confirmReset(event)">
      <input type="hidden" name="action" value="reset_data">
      <label>
        Tape <strong>SUPPRIMER</strong> pour confirmer :
        <input type="text" name="confirm_text" id="confirmText" autocomplete="off">
      </label>
      <br><br>
      <button type="submit" class="danger">Reinitialiser les donnees</button>
    </form>
  </fieldset>
</div>
<script nonce="<?= e($cspNonce) ?>">
function confirmReset(evt) {
  var value = document.getElementById('confirmText').value;
  if (value !== 'SUPPRIMER') {
    alert('Tape exactement "SUPPRIMER" dans le champ pour confirmer.');
    evt.preventDefault();
    return false;
  }
  return confirm('Cette action va effacer definitivement tout le catalogue, le stock, les mouvements, les achats, les livraisons et les inventaires. Continuer ?');
}
</script>
</body>
</html>
