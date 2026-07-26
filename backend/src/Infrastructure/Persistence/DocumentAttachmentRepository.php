<?php
declare(strict_types=1);

namespace App\Infrastructure\Persistence;

use App\Shared\Database\Database;
use PDO;

final class DocumentAttachmentRepository
{
    private PDO $pdo;

    public function __construct()
    {
        $this->pdo = Database::connection();
    }

    /** @return array<int, array<string, mixed>> */
    public function listByEntity(string $entityType, int $entityId): array
    {
        $stmt = $this->pdo->prepare('
            SELECT id, entity_type, entity_id, file_name, mime_type, file_size, created_at
            FROM document_attachments
            WHERE entity_type = :entity_type AND entity_id = :entity_id
            ORDER BY id DESC
        ');
        $stmt->execute([
            ':entity_type' => $entityType,
            ':entity_id' => $entityId,
        ]);

        return $stmt->fetchAll();
    }

    public function findById(int $id): ?array
    {
        $stmt = $this->pdo->prepare('SELECT * FROM document_attachments WHERE id = :id LIMIT 1');
        $stmt->execute([':id' => $id]);
        $row = $stmt->fetch();
        return $row ?: null;
    }

    public function create(array $payload): int
    {
        $stmt = $this->pdo->prepare('
            INSERT INTO document_attachments
            (entity_type, entity_id, file_name, file_path, mime_type, file_size, uploaded_by, created_at)
            VALUES
            (:entity_type, :entity_id, :file_name, :file_path, :mime_type, :file_size, :uploaded_by, NOW())
        ');
        $stmt->execute([
            ':entity_type' => $payload['entity_type'],
            ':entity_id' => $payload['entity_id'],
            ':file_name' => $payload['file_name'],
            ':file_path' => $payload['file_path'],
            ':mime_type' => $payload['mime_type'] ?? null,
            ':file_size' => $payload['file_size'] ?? null,
            ':uploaded_by' => $payload['uploaded_by'] ?? null,
        ]);

        return (int)$this->pdo->lastInsertId();
    }
}
