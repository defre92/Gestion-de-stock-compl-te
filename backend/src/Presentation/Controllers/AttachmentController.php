<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\AttachmentService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class AttachmentController
{
    public function __construct(private readonly AttachmentService $service)
    {
    }

    public function index(Request $request): void
    {
        $entityType = (string)$request->query('entity_type', '');
        $entityId = (int)$request->query('entity_id', 0);

        JsonResponse::send([
            'data' => $this->service->listByEntity($entityType, $entityId),
        ]);
    }

    public function upload(Request $request): void
    {
        $user = $request->attribute('auth_user');
        $file = $request->file('file');
        if (!$file) {
            JsonResponse::send(['message' => 'file is required'], 422);
            return;
        }

        $id = $this->service->upload($request->input(), $file, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);
        JsonResponse::send(['id' => $id], 201);
    }

    public function download(int $id): void
    {
        $attachment = $this->service->findById($id);
        $path = (string)$attachment['file_path'];
        if ($path === '' || !is_file($path)) {
            JsonResponse::send(['message' => 'File not found on disk'], 404);
            return;
        }

        $mime = (string)($attachment['mime_type'] ?? 'application/octet-stream');
        $name = (string)($attachment['file_name'] ?? basename($path));
        // nosniff empeche le navigateur de re-interpreter le contenu si jamais
        // le Content-Type declare ne correspond pas exactement au contenu reel.
        // inline seulement pour les types nativement previsualisables (images,
        // PDF); le reste (doc/docx/xls/xlsx/csv) force le telechargement plutot
        // que de laisser le navigateur tenter un rendu inattendu.
        $disposition = (str_starts_with($mime, 'image/') || $mime === 'application/pdf') ? 'inline' : 'attachment';
        header('X-Content-Type-Options: nosniff');
        header('Content-Type: ' . $mime);
        header('Content-Length: ' . (string)filesize($path));
        header('Content-Disposition: ' . $disposition . '; filename="' . addslashes($name) . '"');
        readfile($path);
    }
}
