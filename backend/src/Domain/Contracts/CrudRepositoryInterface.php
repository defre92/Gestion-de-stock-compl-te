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
}