<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Domain\Contracts\AuthTokenRepositoryInterface;
use App\Shared\Database\Database;
use PDO;

final class AuthTokenRepository implements AuthTokenRepositoryInterface
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    public function create(int $userId, string $tokenHash, ?string $expiresAt = null): int
    {
        $stmt = $this->pdo->prepare('
            INSERT INTO personal_access_tokens (user_id, token_hash, expires_at, created_at)
            VALUES (:user_id, :token_hash, :expires_at, NOW())
        ');
        $stmt->execute([
            ':user_id' => $userId,
            ':token_hash' => $tokenHash,
            ':expires_at' => $expiresAt,
        ]);

        return (int)$this->pdo->lastInsertId();
    }

    public function findToken(string $tokenHash): ?array
    {
        $stmt = $this->pdo->prepare('SELECT * FROM personal_access_tokens WHERE token_hash = :token_hash LIMIT 1');
        $stmt->execute([':token_hash' => $tokenHash]);
        $result = $stmt->fetch();

        return $result ?: null;
    }

    public function touch(int $tokenId, ?string $expiresAt = null): void
    {
        if ($expiresAt !== null) {
            $stmt = $this->pdo->prepare('UPDATE personal_access_tokens SET last_used_at = NOW(), expires_at = :expires_at WHERE id = :id');
            $stmt->execute([':id' => $tokenId, ':expires_at' => $expiresAt]);
            return;
        }

        $stmt = $this->pdo->prepare('UPDATE personal_access_tokens SET last_used_at = NOW() WHERE id = :id');
        $stmt->execute([':id' => $tokenId]);
    }

    public function revokeByHash(string $tokenHash): void
    {
        $stmt = $this->pdo->prepare('DELETE FROM personal_access_tokens WHERE token_hash = :token_hash');
        $stmt->execute([':token_hash' => $tokenHash]);
    }

    public function revokeAllForUser(int $userId): void
    {
        $stmt = $this->pdo->prepare('DELETE FROM personal_access_tokens WHERE user_id = :user_id');
        $stmt->execute([':user_id' => $userId]);
    }
}