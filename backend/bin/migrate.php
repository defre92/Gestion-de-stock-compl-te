<?php
declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "This script must be executed in CLI mode.\n");
    exit(1);
}

$rootPath = dirname(__DIR__, 2);
require_once $rootPath . '/config/env-loader.php';

$command = $argv[1] ?? 'up';
$upPath = $rootPath . '/database/migrations/up';
$downPath = $rootPath . '/database/migrations/down';

$config = require dirname(__DIR__) . '/config/database.php';
$pdo = connectDatabase($config);
ensureMigrationTable($pdo);

try {
    switch ($command) {
        case 'up':
            migrateUp($pdo, $upPath);
            break;
        case 'down':
            rollbackLastBatch($pdo, $downPath);
            break;
        case 'status':
            showStatus($pdo, $upPath);
            break;
        case 'fresh':
            while (rollbackLastBatch($pdo, $downPath, silentIfEmpty: true)) {
            }
            migrateUp($pdo, $upPath);
            break;
        default:
            fwrite(STDOUT, "Usage: php backend/bin/migrate.php [up|down|status|fresh]\n");
            exit(1);
    }
} catch (Throwable $exception) {
    fwrite(STDERR, '[ERROR] ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}

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

function migrateUp(PDO $pdo, string $upPath): void
{
    $files = listSqlFiles($upPath);
    if ($files === []) {
        fwrite(STDOUT, "No migration files found in {$upPath}.\n");
        return;
    }

    $applied = appliedMigrations($pdo);
    $pending = array_values(array_filter($files, static fn (string $file): bool => !isset($applied[basename($file)])));

    if ($pending === []) {
        fwrite(STDOUT, "No pending migrations.\n");
        return;
    }

    $batch = (int)$pdo->query('SELECT COALESCE(MAX(batch),0) + 1 FROM schema_migrations')->fetchColumn();

    foreach ($pending as $file) {
        $name = basename($file);
        applySqlFile($pdo, $file);

        $stmt = $pdo->prepare('INSERT INTO schema_migrations (filename, batch) VALUES (:filename, :batch)');
        $stmt->execute([':filename' => $name, ':batch' => $batch]);

        fwrite(STDOUT, "[MIGRATED] {$name}\n");
    }

    fwrite(STDOUT, "Applied " . count($pending) . " migration(s) in batch {$batch}.\n");
}

function rollbackLastBatch(PDO $pdo, string $downPath, bool $silentIfEmpty = false): bool
{
    $batch = (int)$pdo->query('SELECT COALESCE(MAX(batch),0) FROM schema_migrations')->fetchColumn();
    if ($batch === 0) {
        if (!$silentIfEmpty) {
            fwrite(STDOUT, "No migration batch to rollback.\n");
        }

        return false;
    }

    $stmt = $pdo->prepare('SELECT id, filename FROM schema_migrations WHERE batch = :batch ORDER BY id DESC');
    $stmt->execute([':batch' => $batch]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($rows as $row) {
        $downFile = $downPath . '/' . $row['filename'];
        if (!is_file($downFile)) {
            throw new RuntimeException("Missing rollback file: {$downFile}");
        }

        applySqlFile($pdo, $downFile);

        $del = $pdo->prepare('DELETE FROM schema_migrations WHERE id = :id');
        $del->execute([':id' => (int)$row['id']]);

        fwrite(STDOUT, "[ROLLED BACK] {$row['filename']}\n");
    }

    fwrite(STDOUT, "Rolled back batch {$batch}.\n");
    return true;
}

function showStatus(PDO $pdo, string $upPath): void
{
    $files = listSqlFiles($upPath);
    $applied = appliedMigrations($pdo);

    fwrite(STDOUT, "Migration status:\n");

    foreach ($files as $file) {
        $name = basename($file);
        $status = isset($applied[$name]) ? 'APPLIED' : 'PENDING';
        fwrite(STDOUT, sprintf("- [%s] %s\n", $status, $name));
    }
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
        throw new RuntimeException("Unable to read file: {$file}");
    }
    $pdo->exec($sql);
}
