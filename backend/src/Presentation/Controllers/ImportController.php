<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\ImportService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class ImportController
{
    public function __construct(private readonly ImportService $service)
    {
    }

    public function upload(Request $request, string $entity): void
    {
        $user = $request->attribute('auth_user');
        $file = $request->file('file');
        if (!$file) {
            JsonResponse::send(['message' => 'file is required'], 422);
            return;
        }

        $summary = $this->service->import($entity, $file, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);
        JsonResponse::send(['data' => $summary], 201);
    }
}
