<?php
declare(strict_types=1);

namespace App\Domain\Contracts;

interface CrudRepositoryInterface
{
    public function paginate(int $page, int $perPage, array $filters = []): array;

    public function findById(int $id): ?array;

    public function create(array $payload): int;

    public function update(int $id, array $payload): bool;

    public function delete(int $id): bool;

    /**
     * Premiere ligne dont $column vaut $value, en ignorant eventuellement un
     * identifiant (celui de la ligne en cours de modification).
     *
     * Sert aux controles d'unicite applicatifs (voir CrudService).
     *
     * @return array<string, mixed>|null
     */
    public function findByColumn(string $column, string $value, ?int $excludeId = null): ?array;
}