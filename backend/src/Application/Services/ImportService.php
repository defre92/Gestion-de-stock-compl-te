<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\ImportJobRepository;
use App\Shared\Database\Database;
use App\Shared\Http\HttpException;
use PDO;
use Throwable;

final class ImportService
{
    private const SUPPORTED_ENTITIES = ['products', 'suppliers', 'customers', 'initial-stocks'];

    public function __construct(
        private readonly ImportJobRepository $jobRepository,
        private readonly FileStorageService $storage,
        private readonly AuditRepository $auditRepository
    ) {
    }

    public function import(string $entity, array $file, int $actorId, ?string $ip): array
    {
        $entity = strtolower(trim($entity));
        if (!in_array($entity, self::SUPPORTED_ENTITIES, true)) {
            throw new HttpException('Unsupported import entity', 422);
        }

        $stored = $this->storage->storeUploadedFile($file, 'imports/' . $entity);

        $jobId = $this->jobRepository->create([
            'entity_type' => $entity,
            'file_name' => $stored['original_name'],
            'status' => 'RUNNING',
            'started_by' => $actorId,
            'total_rows' => 0,
            'success_rows' => 0,
            'failed_rows' => 0,
            'error_log' => null,
        ]);

        $pdo = Database::connection();
        $total = 0;
        $success = 0;
        $failed = 0;
        $errors = [];

        try {
            $rows = $this->readCsvRows($stored['absolute_path']);
            $total = count($rows);

            foreach ($rows as $index => $row) {
                $line = $index + 2;
                try {
                    $this->importRow($pdo, $entity, $row);
                    $success++;
                } catch (Throwable $exception) {
                    $failed++;
                    $errors[] = "line {$line}: " . $exception->getMessage();
                }
            }

            $status = $failed > 0 ? 'FAILED' : 'DONE';
            $this->jobRepository->update($jobId, [
                'status' => $status,
                'total_rows' => $total,
                'success_rows' => $success,
                'failed_rows' => $failed,
                'error_log' => $errors !== [] ? implode("\n", array_slice($errors, 0, 50)) : null,
            ]);

            $this->auditRepository->log($actorId, 'IMPORT', 'import_job', $jobId, [
                'entity' => $entity,
                'total' => $total,
                'success' => $success,
                'failed' => $failed,
            ], $ip);

            return [
                'job_id' => $jobId,
                'entity' => $entity,
                'total_rows' => $total,
                'success_rows' => $success,
                'failed_rows' => $failed,
                'errors' => array_slice($errors, 0, 20),
            ];
        } catch (Throwable $exception) {
            $this->jobRepository->update($jobId, [
                'status' => 'FAILED',
                'total_rows' => $total,
                'success_rows' => $success,
                'failed_rows' => max(1, $failed),
                'error_log' => $exception->getMessage(),
            ]);
            throw new HttpException('Import failed: ' . $exception->getMessage(), 422);
        }
    }

    private function importRow(PDO $pdo, string $entity, array $row): void
    {
        if ($entity === 'suppliers') {
            $name = trim((string)($row['name'] ?? ''));
            if ($name === '') {
                throw new \RuntimeException('name is required');
            }

            $stmt = $pdo->prepare('
                INSERT INTO suppliers (name, contact_name, phone, email, address, created_at, updated_at)
                VALUES (:name, :contact_name, :phone, :email, :address, NOW(), NOW())
                ON DUPLICATE KEY UPDATE
                    contact_name = VALUES(contact_name),
                    phone = VALUES(phone),
                    email = VALUES(email),
                    address = VALUES(address),
                    updated_at = NOW()
            ');
            $stmt->execute([
                ':name' => $name,
                ':contact_name' => $row['contact_name'] ?? null,
                ':phone' => $row['phone'] ?? null,
                ':email' => $row['email'] ?? null,
                ':address' => $row['address'] ?? null,
            ]);
            return;
        }

        if ($entity === 'customers') {
            $name = trim((string)($row['name'] ?? ''));
            if ($name === '') {
                throw new \RuntimeException('name is required');
            }

            $code = trim((string)($row['code'] ?? ''));
            if ($code !== '') {
                $stmt = $pdo->prepare('
                    INSERT INTO customers (code, name, email, phone, address, status, created_at, updated_at)
                    VALUES (:code, :name, :email, :phone, :address, :status, NOW(), NOW())
                    ON DUPLICATE KEY UPDATE
                        name = VALUES(name),
                        email = VALUES(email),
                        phone = VALUES(phone),
                        address = VALUES(address),
                        status = VALUES(status),
                        updated_at = NOW()
                ');
                $stmt->execute([
                    ':code' => $code,
                    ':name' => $name,
                    ':email' => $row['email'] ?? null,
                    ':phone' => $row['phone'] ?? null,
                    ':address' => $row['address'] ?? null,
                    ':status' => strtoupper((string)($row['status'] ?? 'ACTIVE')),
                ]);
            } else {
                $stmt = $pdo->prepare('
                    INSERT INTO customers (name, email, phone, address, status, created_at, updated_at)
                    VALUES (:name, :email, :phone, :address, :status, NOW(), NOW())
                ');
                $stmt->execute([
                    ':name' => $name,
                    ':email' => $row['email'] ?? null,
                    ':phone' => $row['phone'] ?? null,
                    ':address' => $row['address'] ?? null,
                    ':status' => strtoupper((string)($row['status'] ?? 'ACTIVE')),
                ]);
            }
            return;
        }

        if ($entity === 'products') {
            $sku = trim((string)($row['sku'] ?? ''));
            $name = trim((string)($row['name'] ?? ''));
            $categoryName = trim((string)($row['category_name'] ?? ''));
            if ($sku === '' || $name === '' || $categoryName === '') {
                throw new \RuntimeException('sku, name, category_name are required');
            }

            $categoryId = $this->resolveCategoryId($pdo, $categoryName);
            $supplierId = null;
            $supplierName = trim((string)($row['supplier_name'] ?? ''));
            if ($supplierName !== '') {
                $supplierId = $this->resolveSupplierId($pdo, $supplierName);
            }

            $stmt = $pdo->prepare('
                INSERT INTO products
                (sku, barcode, name, description, category_id, supplier_id, unit_price, cost_price, reorder_level, status, created_at, updated_at)
                VALUES
                (:sku, :barcode, :name, :description, :category_id, :supplier_id, :unit_price, :cost_price, :reorder_level, :status, NOW(), NOW())
                ON DUPLICATE KEY UPDATE
                    barcode = VALUES(barcode),
                    name = VALUES(name),
                    description = VALUES(description),
                    category_id = VALUES(category_id),
                    supplier_id = VALUES(supplier_id),
                    unit_price = VALUES(unit_price),
                    cost_price = VALUES(cost_price),
                    reorder_level = VALUES(reorder_level),
                    status = VALUES(status),
                    updated_at = NOW()
            ');
            $stmt->execute([
                ':sku' => $sku,
                ':barcode' => $row['barcode'] ?? null,
                ':name' => $name,
                ':description' => $row['description'] ?? null,
                ':category_id' => $categoryId,
                ':supplier_id' => $supplierId,
                ':unit_price' => (float)($row['unit_price'] ?? 0),
                ':cost_price' => (float)($row['cost_price'] ?? 0),
                ':reorder_level' => (int)($row['reorder_level'] ?? 0),
                ':status' => strtoupper((string)($row['status'] ?? 'ACTIVE')),
            ]);
            return;
        }

        if ($entity === 'initial-stocks') {
            $sku = trim((string)($row['sku'] ?? ''));
            $warehouseCode = trim((string)($row['warehouse_code'] ?? ''));
            $quantity = (int)($row['quantity'] ?? 0);
            if ($sku === '' || $warehouseCode === '') {
                throw new \RuntimeException('sku and warehouse_code are required');
            }

            $productId = $this->resolveProductId($pdo, $sku);
            $warehouseId = $this->resolveWarehouseId($pdo, $warehouseCode);

            $stmt = $pdo->prepare('
                INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity, updated_at)
                VALUES (:product_id, :warehouse_id, :quantity, 0, NOW())
                ON DUPLICATE KEY UPDATE quantity = VALUES(quantity), updated_at = NOW()
            ');
            $stmt->execute([
                ':product_id' => $productId,
                ':warehouse_id' => $warehouseId,
                ':quantity' => $quantity,
            ]);
            return;
        }
    }

    /** @return array<int, array<string, mixed>> */
    private function readCsvRows(string $path): array
    {
        $handle = fopen($path, 'rb');
        if ($handle === false) {
            throw new \RuntimeException('Cannot open csv file');
        }

        try {
            $firstLine = fgets($handle);
            if ($firstLine === false) {
                return [];
            }
            $delimiter = substr_count($firstLine, ';') > substr_count($firstLine, ',') ? ';' : ',';
            rewind($handle);

            $headers = fgetcsv($handle, 0, $delimiter, '"', '\\');
            if (!is_array($headers) || $headers === []) {
                throw new \RuntimeException('Invalid CSV header');
            }

            $headers = array_map(static function ($value): string {
                $value = trim((string)$value);
                $value = preg_replace('/^\xEF\xBB\xBF/', '', $value) ?? $value;
                return strtolower(str_replace([' ', '-'], '_', $value));
            }, $headers);

            $rows = [];
            while (($cols = fgetcsv($handle, 0, $delimiter, '"', '\\')) !== false) {
                if ($cols === [null] || $cols === []) {
                    continue;
                }
                $assoc = [];
                foreach ($headers as $idx => $header) {
                    $assoc[$header] = isset($cols[$idx]) ? trim((string)$cols[$idx]) : null;
                }
                $rows[] = $assoc;
            }

            return $rows;
        } finally {
            fclose($handle);
        }
    }

    private function resolveCategoryId(PDO $pdo, string $name): int
    {
        $select = $pdo->prepare('SELECT id FROM categories WHERE name = :name LIMIT 1');
        $select->execute([':name' => $name]);
        $id = $select->fetchColumn();
        if ($id) {
            return (int)$id;
        }

        $insert = $pdo->prepare('INSERT INTO categories (name, description, created_at, updated_at) VALUES (:name, NULL, NOW(), NOW())');
        $insert->execute([':name' => $name]);
        return (int)$pdo->lastInsertId();
    }

    private function resolveSupplierId(PDO $pdo, string $name): int
    {
        $select = $pdo->prepare('SELECT id FROM suppliers WHERE name = :name LIMIT 1');
        $select->execute([':name' => $name]);
        $id = $select->fetchColumn();
        if ($id) {
            return (int)$id;
        }

        $insert = $pdo->prepare('INSERT INTO suppliers (name, created_at, updated_at) VALUES (:name, NOW(), NOW())');
        $insert->execute([':name' => $name]);
        return (int)$pdo->lastInsertId();
    }

    private function resolveProductId(PDO $pdo, string $sku): int
    {
        $stmt = $pdo->prepare('SELECT id FROM products WHERE sku = :sku LIMIT 1');
        $stmt->execute([':sku' => $sku]);
        $id = $stmt->fetchColumn();
        if (!$id) {
            throw new \RuntimeException("Unknown sku: {$sku}");
        }
        return (int)$id;
    }

    private function resolveWarehouseId(PDO $pdo, string $code): int
    {
        $stmt = $pdo->prepare('SELECT id FROM warehouses WHERE code = :code LIMIT 1');
        $stmt->execute([':code' => $code]);
        $id = $stmt->fetchColumn();
        if (!$id) {
            throw new \RuntimeException("Unknown warehouse_code: {$code}");
        }
        return (int)$id;
    }
}
