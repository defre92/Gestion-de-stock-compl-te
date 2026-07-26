<?php
declare(strict_types=1);

use App\Shared\Support\Autoloader;

require_once __DIR__ . '/src/Shared/Support/Autoloader.php';

// Charge automatiquement les classes du backend.
Autoloader::register(__DIR__);

// Charge le fichier .env (s'il existe) - logique partagee avec le frontend.
require_once dirname(__DIR__) . '/config/env-loader.php';

$appConfig = require __DIR__ . '/config/app.php';
date_default_timezone_set($appConfig['timezone']);

// Gestion globale des exceptions pour CLI et HTTP.
set_exception_handler(static function (Throwable $exception) use ($appConfig): void {
    if (PHP_SAPI === 'cli') {
        fwrite(STDERR, '[ERROR] ' . $exception->getMessage() . PHP_EOL);
        if ($appConfig['debug']) {
            fwrite(STDERR, $exception->getFile() . ':' . $exception->getLine() . PHP_EOL);
        }
        exit(1);
    }

    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');

    $payload = ['message' => 'Internal server error'];

    if ($appConfig['debug']) {
        $payload['exception'] = [
            'message' => $exception->getMessage(),
            'file' => $exception->getFile(),
            'line' => $exception->getLine(),
        ];
    }

    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
});
