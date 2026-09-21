<?php
declare(strict_types=1);

namespace App\Shared\Database;

use PDO;

final class Database
{
    private static ?PDO $pdo = null;

    public static function connection(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        $config = require dirname(__DIR__, 3) . '/config/database.php';
        $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=%s', $config['host'], $config['port'], $config['name'], $config['charset']);

        self::$pdo = new PDO($dsn, $config['username'], $config['password'], [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);

        // Aligne le fuseau horaire de la session MySQL sur celui de PHP
        // (Europe/Paris, deja regle dans bootstrap.php). Sans cela, les
        // CURRENT_TIMESTAMP par defaut des tables (created_at, etc.) suivent
        // le fuseau du SERVEUR MySQL - generalement UTC sur un hebergement
        // mutualise - d'ou un decalage de 1h (hiver) ou 2h (ete) sur toutes
        // les dates affichees. Un fuseau nomme ('Europe/Paris') necessiterait
        // les tables de fuseaux horaires MySQL (mysql_tzinfo_to_sql), rarement
        // installees sur un hebergement mutualise sans acces SSH - on utilise
        // donc un decalage numerique, recalcule a chaque connexion pour rester
        // correct a la bascule heure d'ete/hiver.
        $offset = (new \DateTime('now', new \DateTimeZone('Europe/Paris')))->format('P');
        self::$pdo->exec("SET time_zone = '{$offset}'");

        return self::$pdo;
    }
}