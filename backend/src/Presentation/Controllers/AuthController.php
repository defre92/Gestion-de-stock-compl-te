<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\AuthService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;
use App\Shared\Security\AuthCookie;

final class AuthController
{
    public function __construct(private readonly AuthService $authService)
    {
    }

    public function login(Request $request): void
    {
        $result = $this->authService->login(
            (string)$request->input('email', ''),
            (string)$request->input('password', ''),
            $_SERVER['REMOTE_ADDR'] ?? null
        );

        // Le token ne transite plus jamais dans le corps JSON: il est pose
        // directement en cookie httpOnly, inaccessible au JS (voir AuthCookie).
        AuthCookie::issue((string)$result['token']);

        JsonResponse::send(['data' => ['user' => $result['user']]], 200);
    }

    public function me(Request $request): void
    {
        $token = (string)$request->attribute('auth_token');
        $user = $this->authService->me($token);

        JsonResponse::send(['data' => $user]);
    }

    public function logout(Request $request): void
    {
        $token = (string)$request->attribute('auth_token');
        $this->authService->logout($token, $_SERVER['REMOTE_ADDR'] ?? null);

        AuthCookie::forget();

        JsonResponse::send(['message' => 'Logged out']);
    }
}