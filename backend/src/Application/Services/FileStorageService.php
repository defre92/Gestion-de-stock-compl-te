<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Shared\Http\HttpException;

final class FileStorageService
{
    /** Extensions autorisees et type MIME reel attendu (verifie via fileinfo, pas via le nom/Content-Type envoye par le client). */
    private const ALLOWED_TYPES = [
        'jpg' => ['image/jpeg'],
        'jpeg' => ['image/jpeg'],
        'png' => ['image/png'],
        'gif' => ['image/gif'],
        'webp' => ['image/webp'],
        'pdf' => ['application/pdf'],
        'csv' => ['text/csv', 'text/plain'],
        'doc' => ['application/msword'],
        'docx' => ['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/zip'],
        'xls' => ['application/vnd.ms-excel'],
        'xlsx' => ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/zip'],
    ];

    private const MAX_SIZE_BYTES = 15 * 1024 * 1024; // 15 Mo

    public function __construct(
        private readonly string $basePath
    ) {
    }

    public function storeUploadedFile(array $file, string $category): array
    {
        $error = (int)($file['error'] ?? UPLOAD_ERR_NO_FILE);
        if ($error !== UPLOAD_ERR_OK) {
            throw new HttpException('Le televersement du fichier a echoue', 422);
        }

        $tmpName = (string)($file['tmp_name'] ?? '');
        $originalName = (string)($file['name'] ?? 'upload.bin');
        $size = (int)($file['size'] ?? 0);

        if ($tmpName === '' || !is_file($tmpName) || !is_uploaded_file($tmpName)) {
            throw new HttpException('Fichier televerse manquant', 422);
        }

        if ($size <= 0 || $size > self::MAX_SIZE_BYTES) {
            throw new HttpException('Taille de fichier invalide (fichier vide ou trop volumineux)', 422);
        }

        $extension = strtolower(pathinfo($originalName, PATHINFO_EXTENSION));
        if (!isset(self::ALLOWED_TYPES[$extension])) {
            throw new HttpException('Type de fichier non autorise : .' . $extension, 422);
        }

        // Le type declare par le navigateur (Content-Type) n'est jamais fiable: on verifie
        // le contenu reel du fichier avec fileinfo pour empecher qu'un script (.php, .phtml...)
        // soit deguise en image/document.
        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $realMime = $finfo ? (finfo_file($finfo, $tmpName) ?: '') : '';
        if ($finfo) {
            finfo_close($finfo);
        }
        if ($realMime === '' || !in_array($realMime, self::ALLOWED_TYPES[$extension], true)) {
            throw new HttpException('Le contenu du fichier ne correspond pas a son extension', 422);
        }
        $mimeType = $realMime;

        $safeCategory = preg_replace('/[^a-zA-Z0-9_-]/', '-', $category) ?: 'misc';
        $relativeDir = $safeCategory . '/' . date('Y/m');
        $targetDir = rtrim($this->basePath, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relativeDir);

        if (!is_dir($targetDir) && !mkdir($targetDir, 0775, true) && !is_dir($targetDir)) {
            throw new HttpException('Impossible de creer le dossier de destination', 422);
        }

        $unique = bin2hex(random_bytes(8));
        $fileName = $unique . ($extension !== '' ? '.' . $extension : '');
        $targetPath = $targetDir . DIRECTORY_SEPARATOR . $fileName;

        if (!move_uploaded_file($tmpName, $targetPath)) {
            if (!rename($tmpName, $targetPath)) {
                throw new HttpException('Impossible d\'enregistrer le fichier sur le serveur', 422);
            }
        }

        return [
            'original_name' => $originalName,
            'stored_name' => $fileName,
            'mime_type' => $mimeType,
            'size' => $size,
            'relative_path' => $relativeDir . '/' . $fileName,
            'absolute_path' => $targetPath,
        ];
    }
}
