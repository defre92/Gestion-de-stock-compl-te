<?php
declare(strict_types=1);

/**
 * Charge backend/.env dans l'environnement du process courant, sans ecraser
 * des variables deja definies au niveau du serveur (Apache/PHP-FPM/systemd).
 * Utilise par le backend (bootstrap.php) ET par le frontend (route-frontend.php)
 * puisque le branding (config/tenant.php) doit etre lisible des deux cotes.
 */
if (!function_exists('loadDotEnv')) {
    function loadDotEnv(string $envFile): void
    {
        if (!is_file($envFile)) {
            return;
        }

        $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
                continue;
            }
            [$key, $value] = explode('=', $line, 2);
            $key = trim($key);
            $value = trim($value);
            if (strlen($value) >= 2 && (
                ($value[0] === '"' && str_ends_with($value, '"')) ||
                ($value[0] === "'" && str_ends_with($value, "'"))
            )) {
                $value = substr($value, 1, -1);
            }
            if ($key !== '' && getenv($key) === false) {
                putenv($key . '=' . $value);
            }
        }
    }
}

loadDotEnv(dirname(__DIR__) . '/backend/.env');
