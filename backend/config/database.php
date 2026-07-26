<?php
declare(strict_types=1);

// Fallback intelligent: on lit d'abord la config racine si elle existe.
$rootConfig = dirname(__DIR__, 2) . '/config/database.php';
if (is_file($rootConfig)) {
    $loaded = require $rootConfig;
    if (is_array($loaded)) {
        return $loaded;
    }
}

// Valeurs par defaut si aucune config externe n'est fournie.
return [
    'host' => getenv('DB_HOST') ?: '127.0.0.1',
    'port' => (int)(getenv('DB_PORT') ?: 3306),
    'name' => getenv('DB_NAME') ?: 'gestion_stock',
    'username' => getenv('DB_USER') ?: 'root',
    'password' => getenv('DB_PASS') ?: '',
    'charset' => getenv('DB_CHARSET') ?: 'utf8mb4',
];
