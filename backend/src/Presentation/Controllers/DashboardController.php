<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\DashboardService;
use App\Shared\Http\JsonResponse;

final class DashboardController
{
    public function __construct(private readonly DashboardService $service)
    {
    }

    public function stats(): void
    {
        JsonResponse::send(['data' => $this->service->stats()]);
    }
}