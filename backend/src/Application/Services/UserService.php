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
            throw new HttpException('Utilisateur introuvable', 404);
        }

        unset($user['password_hash']);
        return $user;
    }

    public function create(array $payload, int $actorId, ?string $ip): int
    {
        foreach (['full_name', 'email', 'password', 'role'] as $field) {
            if (empty($payload[$field])) {
                throw new HttpException("Le champ '{$field}' est obligatoire", 422);
            }
        }

        if (strlen((string)$payload['password']) < self::MIN_PASSWORD_LENGTH) {
            throw new HttpException('Le mot de passe doit faire au moins ' . self::MIN_PASSWORD_LENGTH . ' caracteres', 422);
        }

        $this->rejectSuperAdminAssignment((string)$payload['role']);

        $roleId = $this->roleRepository->idByCode((string)$payload['role']);
        if (!$roleId) {
            throw new HttpException('Profil inconnu', 422);
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

    public function update(int $id, array $payload, int $actorId, string $actorRole, ?string $ip): void
    {
        $user = $this->repository->findById($id);
        if (!$user) {
            throw new HttpException('Utilisateur introuvable', 404);
        }

        $this->rejectCrossSuperAdminAction($user, $actorRole);

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
            $this->rejectSuperAdminAssignment((string)$payload['role']);

            $roleId = $this->roleRepository->idByCode((string)$payload['role']);
            if (!$roleId) {
                throw new HttpException('Profil inconnu', 422);
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
            throw new HttpException('Aucune donnee a mettre a jour', 422);
        }

        $this->repository->update($id, $update);
        $this->auditRepository->log($actorId, 'UPDATE', 'user', $id, array_keys($update), $ip);
    }

    /**
     * SUPER_ADMIN ne s'attribue jamais depuis cet ecran (ni sa liste
     * deroulante, voir RoleRepository::allAssignable(), ni un appel API
     * direct) : c'est le role du tout premier compte de l'installation
     * (voir install.php), et il ne doit exister qu'une fois. Le contourner
     * ici empecherait un Administrateur de s'auto-promouvoir en modifiant
     * la requete a la main.
     */
    private function rejectSuperAdminAssignment(string $role): void
    {
        if (strtoupper($role) === 'SUPER_ADMIN') {
            throw new HttpException('Le profil Super administrateur ne peut pas etre attribue depuis cet ecran', 422);
        }
    }

    /**
     * Un compte Super administrateur ne peut etre modifie, retrograde,
     * desactive, reinitialise (mot de passe) ou supprime que par un autre
     * Super administrateur. Sans ce controle, un simple Administrateur
     * pourrait, via l'ecran Utilisateurs (qui lui est accessible au meme
     * titre qu'a un Super administrateur, voir $adminRolesMiddleware dans
     * index.php), retrograder le compte Super administrateur en
     * Administrateur ou Employe, le desactiver, reinitialiser son mot de
     * passe ou le supprimer purement et simplement - ce qui viderait de son
     * sens la distinction entre les deux profils.
     */
    private function rejectCrossSuperAdminAction(array $targetUser, string $actorRole): void
    {
        $targetIsSuperAdmin = strtoupper((string)($targetUser['role_code'] ?? '')) === 'SUPER_ADMIN';
        $actorIsSuperAdmin = strtoupper($actorRole) === 'SUPER_ADMIN';

        if ($targetIsSuperAdmin && !$actorIsSuperAdmin) {
            throw new HttpException('Seul un Super administrateur peut modifier ce compte', 403);
        }
    }

    public function resetPassword(int $id, string $newPassword, int $actorId, string $actorRole, ?string $ip): void
    {
        $user = $this->repository->findById($id);
        if (!$user) {
            throw new HttpException('Utilisateur introuvable', 404);
        }

        $this->rejectCrossSuperAdminAction($user, $actorRole);

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
            throw new HttpException('Utilisateur introuvable', 404);
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

    public function delete(int $id, int $actorId, string $actorRole, ?string $ip): void
    {
        $user = $this->repository->findById($id);
        if (!$user) {
            throw new HttpException('Utilisateur introuvable', 404);
        }

        $this->rejectCrossSuperAdminAction($user, $actorRole);

        $this->repository->delete($id);
        $this->auditRepository->log($actorId, 'DELETE', 'user', $id, [], $ip);
    }
}