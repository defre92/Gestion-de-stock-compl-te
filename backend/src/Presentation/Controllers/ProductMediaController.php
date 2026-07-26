<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\FileStorageService;
use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\ProductMediaRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class ProductMediaController
{
    public function __construct(
        private readonly ProductMediaRepository $mediaRepository,
        private readonly ProductRepository $productRepository,
        private readonly FileStorageService $storage,
        private readonly AuditRepository $auditRepository
    ) {
    }

    public function upload(Request $request, int $productId): void
    {
        $product = $this->productRepository->findById($productId);
        if (!$product) {
            JsonResponse::send(['message' => 'Product not found'], 404);
            return;
        }

        $file = $request->file('file');
        if (!$file) {
            JsonResponse::send(['message' => 'file is required'], 422);
            return;
        }

        $user = $request->attribute('auth_user');
        $mediaType = strtoupper((string)($request->input('media_type') ?? 'IMAGE'));
        if (!in_array($mediaType, ['IMAGE', 'DOCUMENT'], true)) {
            $mediaType = 'DOCUMENT';
        }

        $stored = $this->storage->storeUploadedFile($file, 'product-media/' . $productId);
        $id = $this->mediaRepository->create([
            'product_id' => $productId,
            'media_type' => $mediaType,
            'file_name' => $stored['original_name'],
            'file_path' => $stored['absolute_path'],
            'mime_type' => $stored['mime_type'],
            'uploaded_by' => (int)$user['id'],
        ]);

        $this->auditRepository->log((int)$user['id'], 'UPLOAD', 'product_media', $id, [
            'product_id' => $productId,
            'file_name' => $stored['original_name'],
        ], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['id' => $id], 201);
    }

    public function download(int $id): void
    {
        $media = $this->mediaRepository->findById($id);
        if (!$media) {
            JsonResponse::send(['message' => 'Media not found'], 404);
            return;
        }

        $path = (string)($media['file_path'] ?? '');
        if ($path === '' || !is_file($path)) {
            JsonResponse::send(['message' => 'File not found on disk'], 404);
            return;
        }

        $mime = (string)($media['mime_type'] ?? 'application/octet-stream');
        $name = (string)($media['file_name'] ?? basename($path));
        $disposition = (str_starts_with($mime, 'image/') || $mime === 'application/pdf') ? 'inline' : 'attachment';
        header('X-Content-Type-Options: nosniff');
        header('Content-Type: ' . $mime);
        header('Content-Length: ' . (string)filesize($path));
        header('Content-Disposition: ' . $disposition . '; filename="' . addslashes($name) . '"');
        readfile($path);
    }
}
