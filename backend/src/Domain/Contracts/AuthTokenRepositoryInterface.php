<?php
declare(strict_types=1);

namespace App\Domain\Contracts;

interface AuthTokenRepositoryInterface
{
    public function create(int $userId, string $tokenHash, ?string $expiresAt = null): int;

    public function findToken(string $tokenHash): ?array;

    public function touch(int $tokenId, ?string $expiresAt = null): void;

    public function revokeByHash(string $tokenHash): void;

    public function revokeAllForUser(int $userId): void;
}