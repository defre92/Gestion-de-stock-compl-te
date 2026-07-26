<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\DeliveryService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class DeliveryController
{
    public function __construct(private readonly DeliveryService $service)
    {
    }

    public function index(Request $request): void
    {
        $page = (int)$request->query('page', 1);
        $perPage = (int)$request->query('per_page', 20);
        $filters = [
            'customer_id' => $request->query('customer_id'),
            'status' => $request->query('status'),
        ];

        JsonResponse::send($this->service->paginate($page, $perPage, $filters));
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

    public function cancel(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->cancel($id, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['message' => 'Delivery cancelled']);
    }
}
