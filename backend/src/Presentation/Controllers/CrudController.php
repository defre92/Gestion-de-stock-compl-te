<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\CrudService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class CrudController
{
    public function __construct(private readonly CrudService $service)
    {
    }

    public function index(Request $request): void
    {
        $page = (int)$request->query('page', 1);
        $perPage = (int)$request->query('per_page', 20);
        $filters = $request->queryParams();
        unset($filters['page'], $filters['per_page']);

        $result = $this->service->paginate($page, $perPage, $filters);
        JsonResponse::send($result);
    }

    public function show(int $id): void
    {
        JsonResponse::send(['data' => $this->service->findById($id)]);
    }

    public function store(Request $request): void
    {
        $user = $request->attribute('auth_user');
        $id = $this->service->create(
            $request->input(),
            isset($user['id']) ? (int)$user['id'] : null,
            $_SERVER['REMOTE_ADDR'] ?? null
        );

        JsonResponse::send(['id' => $id], 201);
    }

    public function update(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->update(
            $id,
            $request->input(),
            isset($user['id']) ? (int)$user['id'] : null,
            $_SERVER['REMOTE_ADDR'] ?? null
        );

        JsonResponse::send(['message' => 'Updated']);
    }

    public function destroy(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->delete(
            $id,
            isset($user['id']) ? (int)$user['id'] : null,
            $_SERVER['REMOTE_ADDR'] ?? null
        );

        JsonResponse::empty();
    }
}
