<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\UserService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class UserController
{
    public function __construct(private readonly UserService $service)
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

    public function update(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->update($id, $request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);
        JsonResponse::send(['message' => 'Updated']);
    }

    public function resetPassword(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->resetPassword(
            $id,
            (string)$request->input('password', ''),
            (int)$user['id'],
            $_SERVER['REMOTE_ADDR'] ?? null
        );
        JsonResponse::send(['message' => 'Password reset']);
    }

    public function changeOwnPassword(Request $request): void
    {
        $user = $request->attribute('auth_user');
        $this->service->changeOwnPassword(
            (int)$user['id'],
            (string)$request->input('current_password', ''),
            (string)$request->input('new_password', ''),
            $_SERVER['REMOTE_ADDR'] ?? null
        );
        JsonResponse::send(['message' => 'Password changed']);
    }

    public function destroy(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->delete($id, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);
        JsonResponse::empty();
    }
}