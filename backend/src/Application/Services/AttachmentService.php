<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\DocumentAttachmentRepository;
use App\Shared\Http\HttpException;

final class AttachmentService
{
    private const ALLOWED_EXTENSIONS = ['pdf', 'png', 'jpg', 'jpeg', 'csv', 'txt', 'doc', 'docx', 'xlsx'];

    public function __construct(
        private readonly DocumentAttachmentRepository $repository,
        private readonly FileStorageService $storage,
        private readonly AuditRepository $auditRepository
    ) {
    }

    public function listByEntity(string $entityType, int $entityId): array
    {
        if ($entityType === '' || $entityId <= 0) {
            throw new HttpException('entity_type and entity_id are required', 422);
        }

        return $this->repository->listByEntity($entityType, $entityId);
    }

    public function upload(array $payload, array $file, int $actorId, ?string $ip): int
    {
        $entityType = strtolower(trim((string)($payload['entity_type'] ?? '')));
        $entityId = (int)($payload['entity_id'] ?? 0);
        if ($entityType === '' || $entityId <= 0) {
            throw new HttpException('entity_type and entity_id are required', 422);
        }

        $original = (string)($file['name'] ?? '');
        $extension = strtolower(pathinfo($original, PATHINFO_EXTENSION));
        if ($extension === '' || !in_array($extension, self::ALLOWED_EXTENSIONS, true)) {
            throw new HttpException('Unsupported file type', 422);
        }

        $stored = $this->storage->storeUploadedFile($file, 'attachments/' . $entityType);

        $id = $this->repository->create([
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'file_name' => $stored['original_name'],
            'file_path' => $stored['absolute_path'],
            'mime_type' => $stored['mime_type'],
            'file_size' => $stored['size'],
            'uploaded_by' => $actorId,
        ]);

        $this->auditRepository->log($actorId, 'UPLOAD', 'document_attachment', $id, [
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'file_name' => $stored['original_name'],
        ], $ip);

        return $id;
    }

    public function findById(int $id): array
    {
        $row = $this->repository->findById($id);
        if (!$row) {
            throw new HttpException('Attachment not found', 404);
        }

        return $row;
    }
}
