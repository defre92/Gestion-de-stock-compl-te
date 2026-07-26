<?php
declare(strict_types=1);

namespace App\Presentation\Middleware;

use App\Application\Services\AuthService;
use App\Shared\Http\HttpException;
use App\Shared\Http\Request;
use App\Shared\Security\AuthCookie;

final class AuthMiddleware
{
    public function __construct(private readonly AuthService $authService)
    {
    }

    public function __invoke(Request $request, array $params, callable $next): void
    {
        $token = $request->cookie(AuthCookie::NAME);
        if (!$token) {
            throw new HttpException('Missing session cookie', 401);
        }

        $user = $this->authService->resolveUserByToken($token);
        $request->setAttribute('auth_user', $user);
        $request->setAttribute('auth_token', $token);

        $next($request, $params);
    }
}