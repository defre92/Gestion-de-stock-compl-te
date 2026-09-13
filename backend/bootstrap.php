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

/**
 * Filet de securite pour les erreurs que le gestionnaire d'exceptions ne voit
 * PAS : erreur de syntaxe, fichier manquant, signature de methode
 * incompatible avec la classe parente... Ces erreurs-la surviennent au
 * CHARGEMENT du code, donc avant tout code applicatif, et PHP se contentait
 * de renvoyer une reponse VIDE avec un code 500. Cote navigateur :
 * "Erreur interne du serveur" sur toutes les routes a la fois, et rien pour
 * comprendre - meme avec APP_DEBUG=1.
 *
 * Desormais : le detail part dans backend/storage/logs/php-error.log (a
 * envoyer au support), et la reponse JSON dit ou regarder. Le detail complet
 * n'est renvoye au navigateur que si APP_DEBUG=1.
 */
register_shutdown_function(static function () use ($appConfig): void {
    $error = error_get_last();
    if ($error === null || !in_array($error['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR], true)) {
        return;
    }

    $line = sprintf(
        "[%s] %s dans %s:%d%s",
        date('Y-m-d H:i:s'),
        $error['message'],
        $error['file'],
        $error['line'],
        PHP_EOL
    );

    // Le fichier n'est cree qu'a la premiere erreur fatale : tant que tout
    // fonctionne, il n'existe pas. Si le dossier n'est pas accessible en
    // ecriture (hebergement mutualise verrouille), on bascule sur le journal
    // d'erreurs PHP de l'hebergeur : le detail ne doit pas etre perdu au
    // moment precis ou on en a besoin.
    $logDir = __DIR__ . '/storage/logs';
    $written = false;
    if (is_dir($logDir) || @mkdir($logDir, 0775, true)) {
        $written = @file_put_contents($logDir . '/php-error.log', $line, FILE_APPEND) !== false;
    }

    if (!$written) {
        error_log('[gestion-stock] ' . trim($line));
    }

    if (PHP_SAPI === 'cli') {
        fwrite(STDERR, '[FATAL] ' . $error['message'] . PHP_EOL);
        return;
    }

    if (headers_sent()) {
        return;
    }

    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');

    $payload = [
        'message' => 'Erreur fatale du serveur. Detail enregistre dans backend/storage/logs/php-error.log.',
    ];

    if ($appConfig['debug']) {
        $payload['fatal'] = [
            'message' => $error['message'],
            'file' => $error['file'],
            'line' => $error['line'],
        ];
    }

    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
});
