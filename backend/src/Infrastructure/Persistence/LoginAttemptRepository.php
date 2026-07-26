<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

final class LoginAttemptRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function record(string $email, ?string $ipAddress, bool $success): void
    {
        $stmt = $this->pdo->prepare('
            INSERT INTO login_attempts (email, ip_address, success, attempted_at)
            VALUES (:email, :ip_address, :success, NOW())
        ');
        $stmt->execute([
            ':email' => strtolower($email),
            ':ip_address' => $ipAddress,
            ':success' => $success ? 1 : 0,
        ]);
    }

    /**
     * Nombre d'echecs recents pour cet email OU cette IP, sur la fenetre donnee.
     * On bloque si l'un des deux depasse le seuil, pour limiter a la fois le
     * bourrage sur un compte precis et le bourrage distribue depuis une IP.
     */
    public function recentFailureCount(string $email, ?string $ipAddress, int $windowMinutes): int
    {
        $stmt = $this->pdo->prepare('
            SELECT COUNT(*) FROM login_attempts
            WHERE success = 0
              AND attempted_at >= (NOW() - INTERVAL :minutes MINUTE)
              AND (email = :email OR (:ip_address IS NOT NULL AND ip_address = :ip_address2))
        ');
        $stmt->execute([
            ':minutes' => $windowMinutes,
            ':email' => strtolower($email),
            ':ip_address' => $ipAddress,
            ':ip_address2' => $ipAddress,
        ]);

        return (int)$stmt->fetchColumn();
    }

    /** A appeler periodiquement (ou simplement de temps en temps depuis login()) pour ne pas faire grossir la table indefiniment. */
    public function purgeOlderThan(int $days): void
    {
        $stmt = $this->pdo->prepare('DELETE FROM login_attempts WHERE attempted_at < (NOW() - INTERVAL :days DAY)');
        $stmt->execute([':days' => $days]);
    }
}
