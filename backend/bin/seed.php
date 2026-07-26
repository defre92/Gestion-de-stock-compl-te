<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "This script must be executed in CLI mode.\n");
    exit(1);
}

$rootPath = dirname(__DIR__, 2);
require_once $rootPath . '/config/env-loader.php';

if ((getenv('APP_ENV') ?: 'local') === 'production' && !in_array('--force', $argv, true)) {
    fwrite(STDERR, "ATTENTION: ce seed contient des donnees de DEMONSTRATION et un compte\n");
    fwrite(STDERR, "admin avec un mot de passe connu publiquement (voir historique du depot).\n");
    fwrite(STDERR, "Ne l'utilise PAS pour une installation client reelle: utilise plutot\n");
    fwrite(STDERR, "frontend/install.php, qui cree un admin propre avec un mot de passe unique.\n");
    fwrite(STDERR, "Relance avec --force si tu es certain de vouloir charger ces donnees de demo.\n");
    exit(1);
}

$seedPath = $rootPath . '/database/seeders/pro';
$config = require dirname(__DIR__) . '/config/database.php';
$pdo = connectDatabase($config);

if (!is_dir($seedPath)) {
    fwrite(STDERR, "Seed directory not found: {$seedPath}\n");
    exit(1);
}

$files = glob($seedPath . '/*.sql') ?: [];
sort($files, SORT_NATURAL);

if ($files === []) {
    fwrite(STDOUT, "No seed files found.\n");
    exit(0);
}

foreach ($files as $file) {
    $sql = file_get_contents($file);
    if ($sql === false) {
        fwrite(STDERR, "Unable to read {$file}\n");
        exit(1);
    }

    $pdo->beginTransaction();

    try {
        $pdo->exec($sql);
        $pdo->commit();
        fwrite(STDOUT, '[SEEDED] ' . basename($file) . PHP_EOL);
    } catch (Throwable $exception) {
        $pdo->rollBack();
        fwrite(STDERR, '[ERROR] ' . basename($file) . ' => ' . $exception->getMessage() . PHP_EOL);
        exit(1);
    }
}

fwrite(STDOUT, "Seed completed.\n");

/** @param array<string, mixed> $config */
function connectDatabase(array $config): PDO
{
    $rootDsn = sprintf('mysql:host=%s;port=%d;charset=%s', $config['host'], $config['port'], $config['charset']);
    $rootPdo = new PDO($rootDsn, (string)$config['username'], (string)$config['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);

    $dbName = (string)$config['name'];
    $rootPdo->exec("CREATE DATABASE IF NOT EXISTS `{$dbName}` CHARACTER SET {$config['charset']} COLLATE utf8mb4_unicode_ci");

    $dbDsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=%s', $config['host'], $config['port'], $dbName, $config['charset']);
    return new PDO($dbDsn, (string)$config['username'], (string)$config['password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]);
}