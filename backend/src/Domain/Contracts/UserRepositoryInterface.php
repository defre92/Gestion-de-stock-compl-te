<?php
declare(strict_types=1);

namespace App\Domain\Contracts;

interface UserRepositoryInterface extends CrudRepositoryInterface
{
    public function findByEmail(string $email): ?array;

    public function findByTokenHash(string $tokenHash): ?array;
}