<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\DashboardRepository;

final class DashboardService
{
    public function __construct(private readonly DashboardRepository $repository)
    {
    }

    public function stats(): array
    {
        return $this->repository->stats();
    }
}