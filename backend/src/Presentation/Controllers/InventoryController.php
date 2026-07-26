<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\InventoryService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class InventoryController
{
    public function __construct(private readonly InventoryService $service)
    {
    }

    public function index(Request $request): void
    {
        $page = (int)$request->query('page', 1);
        $perPage = (int)$request->query('per_page', 20);

        JsonResponse::send($this->service->paginateSessions($page, $perPage));
    }

    public function show(int $id): void
    {
        JsonResponse::send(['data' => $this->service->findSession($id)]);
    }

    public function store(Request $request): void
    {
        $user = $request->attribute('auth_user');
        $id = $this->service->createSession($request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['id' => $id], 201);
    }

    public function count(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $itemId = $this->service->addCount($id, $request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['id' => $itemId], 201);
    }

    public function finalize(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->finalize($id, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['message' => 'Inventory session finalized']);
    }
}