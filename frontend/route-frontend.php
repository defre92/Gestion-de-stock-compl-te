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
        . "img-src 'self' data:; "
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

// Identite du client final (nom, logo, couleur) - personnalisable par install.php.
$tenantConfigFile = dirname(__DIR__) . '/config/tenant.php';
$tenant = is_file($tenantConfigFile) ? require $tenantConfigFile : [];
$tenant += [
    'company_name' => 'Gestion Stock',
    'logo_file' => null,
    'primary_color' => '#2563eb',
    'support_email' => '',
    'footer_text' => '',
];
$tenantLogoUrl = $tenant['logo_file']
    ? FRONTEND_BASE_URL . '/assets/img/brand/' . rawurlencode($tenant['logo_file'])
    : FRONTEND_BASE_URL . '/assets/img/brand/lm-code-monogram.svg';
