<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\PurchaseOrderService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class PurchaseOrderController
{
    public function __construct(private readonly PurchaseOrderService $service)
    {
    }

    public function index(Request $request): void
    {
        $page = (int)$request->query('page', 1);
        $perPage = (int)$request->query('per_page', 20);

        JsonResponse::send($this->service->paginate($page, $perPage));
    }

    public function show(int $id): void
    {
        JsonResponse::send(['data' => $this->service->findById($id)]);
    }

    public function store(Request $request): void
    {
        $user = $request->attribute('auth_user');
        $id = $this->service->create($request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['id' => $id], 201);
    }

    public function updateStatus(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->updateStatus($id, $request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['message' => 'Purchase order status updated']);
    }

    public function receive(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->receive($id, $request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['message' => 'Purchase order receipt saved']);
    }
}
