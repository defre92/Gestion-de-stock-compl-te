<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Domain\Contracts\CrudRepositoryInterface;
use App\Infrastructure\Persistence\AuditRepository;
use App\Shared\Http\HttpException;

final class CrudService
{
    public function __construct(
        private readonly CrudRepositoryInterface $repository,
        private readonly AuditRepository $auditRepository,
        private readonly string $entityType,
        private readonly array $requiredFields = []
    ) {
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        return $this->repository->paginate($page, $perPage, $filters);
    }

    public function findById(int $id): array
    {
        $item = $this->repository->findById($id);
        if (!$item) {
            throw new HttpException(ucfirst($this->entityType) . ' not found', 404);
        }

        return $item;
    }

    public function create(array $payload, ?int $actorId, ?string $ip): int
    {
        $this->assertRequiredFields($payload);
        $id = $this->repository->create($payload);

        if ($id <= 0) {
            throw new HttpException('Invalid payload', 422);
        }

        $this->auditRepository->log($actorId, 'CREATE', $this->entityType, $id, $payload, $ip);
        return $id;
    }

    public function update(int $id, array $payload, ?int $actorId, ?string $ip): void
    {
        $this->findById($id);
        if (!$this->repository->update($id, $payload)) {
            throw new HttpException('No data updated', 422);
        }

        $this->auditRepository->log($actorId, 'UPDATE', $this->entityType, $id, $payload, $ip);
    }

    public function delete(int $id, ?int $actorId, ?string $ip): void
    {
        $this->findById($id);
        $this->repository->delete($id);

        $this->auditRepository->log($actorId, 'DELETE', $this->entityType, $id, [], $ip);
    }

    private function assertRequiredFields(array $payload): void
    {
        foreach ($this->requiredFields as $field) {
            if (!array_key_exists($field, $payload) || $payload[$field] === '') {
                throw new HttpException("Field '{$field}' is required", 422);
            }
        }
    }
}