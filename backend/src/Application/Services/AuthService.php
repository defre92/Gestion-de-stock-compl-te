<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Domain\Contracts\AuthTokenRepositoryInterface;
use App\Domain\Contracts\UserRepositoryInterface;
use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\LoginAttemptRepository;
use App\Shared\Http\HttpException;
use App\Shared\Security\PasswordService;
use App\Shared\Security\TokenService;

final class AuthService
{
    /** Nombre d'echecs autorises sur la fenetre avant blocage temporaire. */
    private const MAX_FAILED_ATTEMPTS = 5;
    /** Fenetre glissante (minutes) sur laquelle les echecs sont comptes. */
    private const WINDOW_MINUTES = 15;
    /** Duree de vie glissante d'un token: renouvelee a chaque requete authentifiee. */
    private const TOKEN_TTL_DAYS = 30;

    public function __construct(
        private readonly UserRepositoryInterface $userRepository,
        private readonly AuthTokenRepositoryInterface $tokenRepository,
        private readonly PasswordService $passwordService,
        private readonly TokenService $tokenService,
        private readonly AuditRepository $auditRepository,
        private readonly LoginAttemptRepository $loginAttemptRepository
    ) {
    }

    public function login(string $email, string $password, ?string $ipAddress): array
    {
        // Purge occasionnelle (pas a chaque requete) pour eviter que la table
        // ne grossisse indefiniment sur une instance restee active longtemps.
        if (random_int(1, 200) === 1) {
            $this->loginAttemptRepository->purgeOlderThan(7);
        }

        $recentFailures = $this->loginAttemptRepository->recentFailureCount($email, $ipAddress, self::WINDOW_MINUTES);
        if ($recentFailures >= self::MAX_FAILED_ATTEMPTS) {
            throw new HttpException('Trop de tentatives echouees. Reessaie dans quelques minutes.', 429);
        }

        $user = $this->userRepository->findByEmail($email);

        if (!$user || !$this->passwordService->verify($password, $user['password_hash'])) {
            $this->loginAttemptRepository->record($email, $ipAddress, false);
            throw new HttpException('Invalid credentials', 401);
        }

        if (!(bool)$user['is_active']) {
            $this->loginAttemptRepository->record($email, $ipAddress, false);
            throw new HttpException('Inactive account', 403);
        }

        $this->loginAttemptRepository->record($email, $ipAddress, true);

        $plainToken = $this->tokenService->generatePlainToken();
        $tokenHash = $this->tokenService->hash($plainToken);
        $this->tokenRepository->create((int)$user['id'], $tokenHash, $this->nextExpiry());

        $this->auditRepository->log((int)$user['id'], 'LOGIN', 'auth', (int)$user['id'], [], $ipAddress);

        return [
            'token' => $plainToken,
            'user' => [
                'id' => (int)$user['id'],
                'full_name' => $user['full_name'],
                'email' => $user['email'],
                'role' => $user['role_code'],
            ],
        ];
    }

    public function me(string $token): array
    {
        $user = $this->resolveUserByToken($token);

        return [
            'id' => (int)$user['id'],
            'full_name' => $user['full_name'],
            'email' => $user['email'],
            'role' => $user['role_code'],
        ];
    }

    public function logout(string $token, ?string $ipAddress): void
    {
        $user = $this->resolveUserByToken($token);
        $tokenHash = $this->tokenService->hash($token);
        $this->tokenRepository->revokeByHash($tokenHash);

        $this->auditRepository->log((int)$user['id'], 'LOGOUT', 'auth', (int)$user['id'], [], $ipAddress);
    }

    public function resolveUserByToken(string $token): array
    {
        $tokenHash = $this->tokenService->hash($token);
        $user = $this->userRepository->findByTokenHash($tokenHash);

        if (!$user || !(bool)$user['is_active']) {
            throw new HttpException('Unauthorized', 401);
        }

        if (isset($user['token_id'])) {
            $this->tokenRepository->touch((int)$user['token_id'], $this->nextExpiry());
        }

        return $user;
    }

    /** Calcule la prochaine date d'expiration glissante (NOW + TOKEN_TTL_DAYS). */
    private function nextExpiry(): string
    {
        return (new \DateTimeImmutable())->modify('+' . self::TOKEN_TTL_DAYS . ' days')->format('Y-m-d H:i:s');
    }
}