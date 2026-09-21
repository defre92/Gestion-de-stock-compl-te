<?php
declare(strict_types=1);

// Calcule automatiquement la base URL du front, meme si le projet change de dossier.
$scriptName = str_replace('\\', '/', $_SERVER['SCRIPT_NAME'] ?? '/gestion-stock/frontend/index.php');
$frontendMarker = '/frontend';
$markerPos = strpos($scriptName, $frontendMarker);

if ($markerPos !== false) {
    $basePath = substr($scriptName, 0, $markerPos + strlen($frontendMarker));
} else {
    $basePath = rtrim(str_replace('\\', '/', dirname($scriptName)), '/');
    if ($basePath === '') {
        $basePath = '/frontend';
    }
}

$projectBase = str_ends_with($basePath, '/frontend')
    ? substr($basePath, 0, -strlen('/frontend'))
    : rtrim($basePath, '/');

$projectBase = rtrim($projectBase, '/');

// L'API publique est exposee uniquement via /backend/public/api/v1.
$apiBasePath = ($projectBase !== '' ? $projectBase : '') . '/backend/public/api/v1';

if (!defined('FRONTEND_BASE_URL')) {
    define('FRONTEND_BASE_URL', $basePath);
}
if (!defined('API_BASE_URL')) {
    define('API_BASE_URL', $apiBasePath);
}

/**
 * URL d'un fichier statique, suffixee par sa date de modification.
 *
 * Sans ce suffixe, le navigateur garde en cache l'ancien app-clean.js apres
 * une mise a jour : l'application deployee est la nouvelle, mais l'ecran
 * continue d'afficher l'ancien comportement, sans aucun message - et il faut
 * penser a vider le cache pour s'en sortir. Le suffixe change des que le
 * fichier change, le navigateur recharge alors de lui-meme.
 *
 * A noter : les modules importes DEPUIS un fichier JS (ex: http-client.js,
 * importe par app-clean.js) ne passent pas par ici, leur URL etant ecrite
 * dans le code JavaScript. Ces fichiers changent rarement ; en cas de doute
 * apres une mise a jour, un rechargement force (Ctrl+F5) les met a jour.
 */
function assetUrl(string $relativePath): string
{
    $absolute = __DIR__ . '/' . ltrim($relativePath, '/');
    $version = is_file($absolute) ? (string)filemtime($absolute) : '0';

    return FRONTEND_BASE_URL . '/' . ltrim($relativePath, '/') . '?v=' . $version;
}

// Content-Security-Policy stricte: un nonce different a chaque requete autorise
// uniquement les <script> qui le portent explicitement (voir index.php/login.php/
// logout.php). Pas de 'unsafe-inline' sur les scripts.
$cspNonce = bin2hex(random_bytes(16));

if (!headers_sent()) {
    header(
        "Content-Security-Policy: default-src 'self'; "
        . "script-src 'self' 'nonce-{$cspNonce}' https://cdn.jsdelivr.net; "
        . "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net; "
        . "font-src 'self' https://fonts.gstatic.com https://cdn.jsdelivr.net; "
        // blob: est indispensable a l'apercu d'etiquette : le SVG est
        // recupere par fetch avec le jeton d'authentification, puis affiche
        // via URL.createObjectURL(). Sans blob: dans img-src, le navigateur
        // refusait silencieusement l'image - l'onglet Etiquette affichait une
        // image cassee, sans aucune erreur visible cote application.
        . "img-src 'self' data: blob:; "
        . "connect-src 'self'; "
        . "frame-ancestors 'none'; "
        . "base-uri 'self'; "
        . "form-action 'self'; "
        . "object-src 'none'"
    );
    header('X-Content-Type-Options: nosniff');
    header('Referrer-Policy: strict-origin-when-cross-origin');
}

// Le frontend n'inclut pas bootstrap.php (cote backend uniquement): on charge
// donc ici aussi le .env pour que le branding (config/tenant.php) soit a jour.
require_once dirname(__DIR__) . '/config/env-loader.php';

// Identite du client final (nom, logo, theme de couleur) - personnalisable
// par install.php.
$tenantConfigFile = dirname(__DIR__) . '/config/tenant.php';
$tenant = is_file($tenantConfigFile) ? require $tenantConfigFile : [];
$tenant += [
    'company_name' => 'Gestion Stock',
    'logo_file' => null,
    'theme' => 'emeraude',
    'support_email' => '',
    'footer_text' => '',
];
// Le logo par defaut sert aussi de filet de securite : si TENANT_LOGO_FILE
// designe un fichier absent du serveur (renommage, upload rate), on retombe
// dessus au lieu d'afficher une image cassee sur l'ecran de connexion.
$brandDir = __DIR__ . '/assets/img/brand/';
$tenantLogoFile = $tenant['logo_file'];
if ($tenantLogoFile !== null && !is_file($brandDir . $tenantLogoFile)) {
    $tenantLogoFile = null;
}

$tenantLogoUrl = $tenantLogoFile
    ? FRONTEND_BASE_URL . '/assets/img/brand/' . rawurlencode($tenantLogoFile)
    : FRONTEND_BASE_URL . '/assets/img/brand/lm-code-monogram.svg';

// config/themes.php est la seule source de verite pour les cles de theme
// valides : toute valeur hors catalogue (ancienne valeur, ligne corrompue en
// base) retombe silencieusement sur le theme par defaut plutot que de poser
// un data-theme invalide sur <html> (qui laisserait l'application dans le
// theme "emeraude" de :root sans qu'on comprenne pourquoi).
$themeCatalog = require dirname(__DIR__) . '/config/themes.php';
if (!array_key_exists($tenant['theme'], $themeCatalog)) {
    $tenant['theme'] = 'emeraude';
}

// Le theme choisi a l'installation (config/tenant.php, via TENANT_THEME)
// peut ensuite etre change depuis l'ecran Parametres de l'application, sans
// reinstaller : ce reglage est stocke comme n'importe quel autre dans
// app_settings et prime ici sur le fichier de configuration s'il existe. La
// base peut etre momentanement indisponible (maintenance, pic de charge) :
// dans ce cas on garde le theme du fichier plutot que de casser l'affichage
// de la page de connexion ou du tableau de bord.
try {
    require_once dirname(__DIR__) . '/backend/src/Shared/Support/Autoloader.php';
    \App\Shared\Support\Autoloader::register(dirname(__DIR__) . '/backend');
    $settingsPdo = \App\Shared\Database\Database::connection();
    $settingsStmt = $settingsPdo->prepare('SELECT setting_value FROM app_settings WHERE setting_key = :key LIMIT 1');
    $settingsStmt->execute([':key' => 'tenant_theme']);
    $dbTheme = $settingsStmt->fetchColumn();
    if (is_string($dbTheme) && array_key_exists($dbTheme, $themeCatalog)) {
        $tenant['theme'] = $dbTheme;
    }
} catch (\Throwable $ignored) {
    // Base indisponible ou table absente (installation non terminee) : on
    // garde le theme de config/tenant.php.
}
