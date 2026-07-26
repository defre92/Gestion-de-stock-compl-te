<?php
declare(strict_types=1);

namespace App\Shared\Security;

final class TokenService
{
    public function generatePlainToken(): string
    {
        return bin2hex(random_bytes(32));
    }

    public function hash(string $token): string
    {
        return hash('sha256', $token);
    }
}