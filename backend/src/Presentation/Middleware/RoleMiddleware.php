<?php
declare(strict_types=1);

namespace App\Presentation\Middleware;

use App\Shared\Http\HttpException;
use App\Shared\Http\Request;

final class RoleMiddleware
{
    /** @param array<int, string> $allowedRoles */
    public function __construct(private readonly array $allowedRoles)
    {
    }

    public function __invoke(Request $request, array $params, callable $next): void
    {
        $user = $request->attribute('auth_user');
        $role = strtoupper((string)($user['role_code'] ?? ''));

        if (!in_array($role, $this->allowedRoles, true)) {
            throw new HttpException('Forbidden', 403);
        }

        $next($request, $params);
    }
}