<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Domain\Contracts\AuthTokenRepositoryInterface;
use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\RoleRepository;
use App\Infrastructure\Persistence\UserRepository;
use App\Shared\Http\HttpException;
use App\Shared\Security\PasswordService;

final class UserService
{
    private const MIN_PASSWORD_LENGTH = 10;

    public function __construct(
        private readonly UserRepository $repository,
        private readonly RoleRepository $roleRepository,
        private readonly PasswordService $passwordService,
        private readonly AuditRepository $auditRepository,
        private readonly AuthTokenRepositoryInterface $authTokenRepository
    ) {
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        return $this->repository->paginate($page, $perPage, $filters);
    }

    public function findById(int $id): array
    {
        $user = $this->repository->findById($id);
        if (!$user) {
            throw new HttpException('User not found', 404);
        }

        unset($user['password_hash']);
        return $user;
    }

    public function create(array $payload, int $actorId, ?string $ip): int
    {
        foreach (['full_name', 'email', 'password', 'role'] as $field) {
            if (empty($payload[$field])) {
                throw new HttpException("Field '{$field}' is required", 422);
            }
        }

        if (strlen((string)$payload['password']) < self::MIN_PASSWORD_LENGTH) {
            throw new HttpException('Le mot de passe doit faire au moins ' . self::MIN_PASSWORD_LENGTH . ' caracteres', 422);
        }

        $roleId = $this->roleRepository->idByCode((string)$payload['role']);
        if (!$roleId) {
            throw new HttpException('Unknown role', 422);
        }

        $id = $this->repository->create([
            'full_name' => $payload['full_name'],
            'email' => strtolower((string)$payload['email']),
            'password_hash' => $this->passwordService->hash((string)$payload['password']),
            'role_id' => $roleId,
            'is_active' => (int)($payload['is_active'] ?? 1),
        ]);

        $this->auditRepository->log($actorId, 'CREATE', 'user', $id, ['email' => $payload['email'], 'role' => strtoupper((string)$payload['role'])], $ip);

        return $id;
    }

    public function update(int $id, array $payload, int $actorId, ?string $ip): void
    {
        $user = $this->repository->findById($id);
        if (!$user) {
            throw new HttpException('User not found', 404);
        }

        $update = [];

        if (isset($payload['full_name'])) {
            $update['full_name'] = $payload['full_name'];
        }

        if (isset($payload['email'])) {
            $update['email'] = strtolower((string)$payload['email']);
        }

        if (isset($payload['is_active'])) {
            $update['is_active'] = (int)$payload['is_active'];
        }

        if (!empty($payload['role'])) {
            $roleId = $this->roleRepository->idByCode((string)$payload['role']);
            if (!$roleId) {
                throw new HttpException('Unknown role', 422);
            }
            $update['role_id'] = $roleId;
        }

        if (!empty($payload['password'])) {
            if (strlen((string)$payload['password']) < self::MIN_PASSWORD_LENGTH) {
                throw new HttpException('Le mot de passe doit faire au moins ' . self::MIN_PASSWORD_LENGTH . ' caracteres', 422);
            }
            $update['password_hash'] = $this->passwordService->hash((string)$payload['password']);
        }

        if ($update === []) {
            throw new HttpException('No data to update', 422);
        }

        $this->repository->update($id, $update);
        $this->auditRepository->log($actorId, 'UPDATE', 'user', $id, array_keys($update), $ip);
    }

    public function resetPassword(int $id, string $newPassword, int $actorId, ?string $ip): void
    {
        if (!$this->repository->findById($id)) {
            throw new HttpException('User not found', 404);
        }

        if (strlen($newPassword) < self::MIN_PASSWORD_LENGTH) {
            throw new HttpException('Le mot de passe doit faire au moins ' . self::MIN_PASSWORD_LENGTH . ' caracteres', 422);
        }

        $this->repository->update($id, [
            'password_hash' => $this->passwordService->hash($newPassword),
        ]);

        // Invalide toutes les sessions actives de l'utilisateur cible: un mot de
        // passe reinitialise (ex: compte compromis) ne doit pas laisser un token
        // deja emis continuer a fonctionner.
        $this->authTokenRepository->revokeAllForUser($id);

        $this->auditRepository->log($actorId, 'RESET_PASSWORD', 'user', $id, [], $ip);
    }

    public function changeOwnPassword(int $userId, string $currentPassword, string $newPassword, ?string $ip): void
    {
        $user = $this->repository->findById($userId);
        if (!$user) {
            throw new HttpException('User not found', 404);
        }

        if (!$this->passwordService->verify($currentPassword, (string)$user['password_hash'])) {
            throw new HttpException('Mot de passe actuel incorrect', 422);
        }

        if (strlen($newPassword) < self::MIN_PASSWORD_LENGTH) {
            throw new HttpException('Le mot de passe doit faire au moins ' . self::MIN_PASSWORD_LENGTH . ' caracteres', 422);
        }

        if ($this->passwordService->verify($newPassword, (string)$user['password_hash'])) {
            throw new HttpException('Le nouveau mot de passe doit etre different de l\'actuel', 422);
        }

        $this->repository->update($userId, [
            'password_hash' => $this->passwordService->hash($newPassword),
        ]);

        // Meme logique que resetPassword(): on force une reconnexion propre
        // partout, y compris sur la session courante (le frontend redirige
        // vers logout.php juste apres un succes, voir renderAccount() dans
        // app-clean.js).
        $this->authTokenRepository->revokeAllForUser($userId);

        $this->auditRepository->log($userId, 'CHANGE_PASSWORD', 'user', $userId, [], $ip);
    }

    public function delete(int $id, int $actorId, ?string $ip): void
    {
        if (!$this->repository->findById($id)) {
            throw new HttpException('User not found', 404);
        }

        $this->repository->delete($id);
        $this->auditRepository->log($actorId, 'DELETE', 'user', $id, [], $ip);
    }
}