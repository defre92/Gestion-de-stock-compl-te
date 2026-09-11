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
            throw new HttpException('Type d\'import non pris en charge', 422);
        }

        // L'import lit du CSV, et RIEN d'autre. Le stockage de fichiers, lui,
        // accepte aussi .xlsx et .xls (il sert aussi aux pieces jointes) : sans
        // ce controle, un classeur Excel depose ici etait accepte puis lu comme
        // du texte - donnant un import "reussi" rempli de lignes absurdes, ou
        // une erreur incomprehensible. Le message dit quoi faire.
        $extension = strtolower(pathinfo((string)($file['name'] ?? ''), PATHINFO_EXTENSION));
        if ($extension !== 'csv') {
            throw new HttpException(
                'Ce fichier n\'est pas un CSV. Dans Excel : Fichier > Enregistrer sous > '
                . 'CSV UTF-8 (delimite par des virgules), puis importe le fichier .csv obtenu.',
                422
            );
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
                    $errors[] = "ligne {$line} : " . $exception->getMessage();
                }
            }

            // Un import de 500 lignes dont 1 est rejetee reste un import
            // reussi : il ne doit pas s'afficher "FAILED" dans l'historique.
            // Seul un import ou AUCUNE ligne n'est passee est un echec.
            $status = ($failed > 0 && $success === 0) ? 'FAILED' : 'DONE';
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
            throw new HttpException('Echec de l\'import : ' . $exception->getMessage(), 422);
        }
    }

    private function importRow(PDO $pdo, string $entity, array $row): void
    {
        if ($entity === 'suppliers') {
            $name = trim((string)($row['name'] ?? ''));
            if ($name === '') {
                throw new \RuntimeException('La colonne "name" est obligatoire');
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
                ':contact_name' => $this->nullIfBlank($row['contact_name'] ?? null),
                ':phone' => $this->nullIfBlank($row['phone'] ?? null),
                ':email' => $this->nullIfBlank($row['email'] ?? null),
                ':address' => $this->nullIfBlank($row['address'] ?? null),
            ]);
            return;
        }

        if ($entity === 'customers') {
            $name = trim((string)($row['name'] ?? ''));
            if ($name === '') {
                throw new \RuntimeException('La colonne "name" est obligatoire');
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
                    ':email' => $this->nullIfBlank($row['email'] ?? null),
                    ':phone' => $this->nullIfBlank($row['phone'] ?? null),
                    ':address' => $this->nullIfBlank($row['address'] ?? null),
                    ':status' => $this->parseStatus($row['status'] ?? null),
                ]);
            } else {
                $stmt = $pdo->prepare('
                    INSERT INTO customers (name, email, phone, address, status, created_at, updated_at)
                    VALUES (:name, :email, :phone, :address, :status, NOW(), NOW())
                ');
                $stmt->execute([
                    ':name' => $name,
                    ':email' => $this->nullIfBlank($row['email'] ?? null),
                    ':phone' => $this->nullIfBlank($row['phone'] ?? null),
                    ':address' => $this->nullIfBlank($row['address'] ?? null),
                    ':status' => $this->parseStatus($row['status'] ?? null),
                ]);
            }
            return;
        }

        if ($entity === 'products') {
            $sku = trim((string)($row['sku'] ?? ''));
            $name = trim((string)($row['name'] ?? ''));
            $categoryName = trim((string)($row['category_name'] ?? ''));
            if ($sku === '' || $name === '' || $categoryName === '') {
                throw new \RuntimeException('Les colonnes "sku", "name" et "category_name" sont obligatoires');
            }

            $categoryId = $this->resolveCategoryId($pdo, $categoryName);
            $supplierId = null;
            $supplierName = trim((string)($row['supplier_name'] ?? ''));
            if ($supplierName !== '') {
                $supplierId = $this->resolveSupplierId($pdo, $supplierName);
            }

            // Meme regle que la creation depuis l'ecran Produits : un produit
            // importe sans TVA reprend la taxe par defaut de sa categorie
            // (categories.default_tax_id). Le fichier CSV ne porte pas de
            // colonne TVA, c'est donc le seul moyen pour un import en masse
            // d'arriver avec des taux corrects.
            $taxStmt = $pdo->prepare('SELECT default_tax_id FROM categories WHERE id = :id LIMIT 1');
            $taxStmt->execute([':id' => $categoryId]);
            $defaultTaxId = $taxStmt->fetchColumn();
            $taxId = ($defaultTaxId !== false && $defaultTaxId !== null && (int)$defaultTaxId > 0)
                ? (int)$defaultTaxId
                : null;

            $stmt = $pdo->prepare('
                INSERT INTO products
                (sku, barcode, name, description, category_id, supplier_id, tax_id, unit_price, cost_price, reorder_level, status, created_at, updated_at)
                VALUES
                (:sku, :barcode, :name, :description, :category_id, :supplier_id, :tax_id, :unit_price, :cost_price, :reorder_level, :status, NOW(), NOW())
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
                ':barcode' => $this->nullIfBlank($row['barcode'] ?? null),
                ':name' => $name,
                ':description' => $this->nullIfBlank($row['description'] ?? null),
                ':category_id' => $categoryId,
                ':supplier_id' => $supplierId,
                ':tax_id' => $taxId,
                ':unit_price' => $this->parseDecimal($row['unit_price'] ?? 0),
                ':cost_price' => $this->parseDecimal($row['cost_price'] ?? 0),
                ':reorder_level' => $this->parseInteger($row['reorder_level'] ?? 0),
                ':status' => $this->parseStatus($row['status'] ?? null),
            ]);
            return;
        }

        if ($entity === 'initial-stocks') {
            $sku = trim((string)($row['sku'] ?? ''));
            $warehouseCode = trim((string)($row['warehouse_code'] ?? ''));
            $quantity = $this->parseInteger($row['quantity'] ?? 0);
            if ($sku === '' || $warehouseCode === '') {
                throw new \RuntimeException('Les colonnes "sku" et "warehouse_code" sont obligatoires');
            }

            $productId = $this->resolveProductId($pdo, $sku);
            $warehouseId = $this->resolveWarehouseId($pdo, $warehouseCode);

            // ATTENTION : pas de ON DUPLICATE KEY UPDATE ici. La cle unique
            // uq_stock_level porte sur (product_id, warehouse_id, variant_id),
            // et MySQL n'applique PAS l'unicite quand une colonne de la cle
            // vaut NULL - ce qui est le cas d'un stock sans variante. Avec
            // ON DUPLICATE KEY, reimporter le meme fichier n'ecrasait donc pas
            // la ligne existante : il en ajoutait une nouvelle, et le stock
            // total (calcule par SUM(quantity)) gonflait a chaque import.
            // On cible donc explicitement la ligne "sans variante".
            // location_id IS NULL : depuis le suivi par emplacement, un produit
            // peut avoir plusieurs lignes dans le meme entrepot. Un import de
            // stock initial vise la ligne "sans emplacement precis", pas une
            // ligne rangee au hasard.
            $existing = $pdo->prepare('
                SELECT id FROM stock_levels
                WHERE product_id = :product_id AND warehouse_id = :warehouse_id
                  AND variant_id IS NULL AND location_id IS NULL
                LIMIT 1
            ');
            $existing->execute([':product_id' => $productId, ':warehouse_id' => $warehouseId]);
            $stockId = $existing->fetchColumn();

            if ($stockId) {
                $stmt = $pdo->prepare('UPDATE stock_levels SET quantity = :quantity, updated_at = NOW() WHERE id = :id');
                $stmt->execute([':quantity' => $quantity, ':id' => (int)$stockId]);
                return;
            }

            $stmt = $pdo->prepare('
                INSERT INTO stock_levels (product_id, warehouse_id, quantity, reserved_quantity, updated_at)
                VALUES (:product_id, :warehouse_id, :quantity, 0, NOW())
            ');
            $stmt->execute([
                ':product_id' => $productId,
                ':warehouse_id' => $warehouseId,
                ':quantity' => $quantity,
            ]);
            return;
        }
    }

    /**
     * Colonne facultative laissee vide -> NULL, et non chaine vide.
     *
     * Un modele CSV contient toutes les colonnes, y compris celles qu'on ne
     * remplit pas : la cellule vide arrivait alors en base sous forme de ''.
     * Inoffensif pour un telephone, beaucoup moins pour une colonne ENUM.
     */
    private function nullIfBlank(mixed $value): ?string
    {
        $raw = trim((string)($value ?? ''));
        return $raw === '' ? null : $raw;
    }

    /**
     * Statut ACTIVE / INACTIVE, avec un message utilisable en cas de faute.
     *
     * Avant : une colonne "status" presente mais VIDE envoyait '' dans une
     * colonne ENUM, et MySQL repondait "Data truncated for column 'status'" -
     * message incomprehensible pour l'utilisateur, alors que sa ligne etait
     * parfaitement legitime. Vide = ACTIVE, comme le formulaire de saisie.
     */
    private function parseStatus(mixed $value): string
    {
        $status = strtoupper(trim((string)($value ?? '')));
        if ($status === '') {
            return 'ACTIVE';
        }

        if (!in_array($status, ['ACTIVE', 'INACTIVE'], true)) {
            throw new \RuntimeException(
                'La colonne "status" doit valoir ACTIVE ou INACTIVE (ou rester vide), valeur recue : ' . $status
            );
        }

        return $status;
    }

    /**
     * Convertit un nombre saisi dans un CSV, quelle que soit sa convention.
     *
     * Excel en francais exporte "19,90" et "1 234,56" ; en anglais
     * "1,234.56". Un simple (float) sur "19,90" rend 19.0 : le prix perd
     * ses centimes en silence, sans aucune erreur. C'est le genre de bug qui
     * ne se voit qu'a la facturation.
     *
     * Regle : on retire les espaces (y compris insecables), puis si les deux
     * separateurs sont presents, le DERNIER rencontre est le separateur
     * decimal et l'autre un separateur de milliers.
     */
    private function parseDecimal(mixed $value): float
    {
        $raw = trim((string)$value);
        if ($raw === '') {
            return 0.0;
        }

        $raw = str_replace([' ', "\xC2\xA0", "\xE2\x80\xAF"], '', $raw);

        $lastComma = strrpos($raw, ',');
        $lastDot = strrpos($raw, '.');

        if ($lastComma !== false && $lastDot !== false) {
            if ($lastComma > $lastDot) {
                $raw = str_replace('.', '', $raw);
                $raw = str_replace(',', '.', $raw);
            } else {
                $raw = str_replace(',', '', $raw);
            }
        } elseif ($lastComma !== false) {
            $raw = str_replace(',', '.', $raw);
        }

        return (float)$raw;
    }

    /** Meme normalisation pour les quantites entieres ("1 000" -> 1000). */
    private function parseInteger(mixed $value): int
    {
        return (int)round($this->parseDecimal($value));
    }

    /** @return array<int, array<string, mixed>> */
    private function readCsvRows(string $path): array
    {
        $handle = fopen($path, 'rb');
        if ($handle === false) {
            throw new \RuntimeException('Impossible d\'ouvrir le fichier CSV');
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
                throw new \RuntimeException('En-tete CSV invalide ou illisible');
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
            throw new \RuntimeException("SKU introuvable : {$sku}");
        }
        return (int)$id;
    }

    private function resolveWarehouseId(PDO $pdo, string $code): int
    {
        $stmt = $pdo->prepare('SELECT id FROM warehouses WHERE code = :code LIMIT 1');
        $stmt->execute([':code' => $code]);
        $id = $stmt->fetchColumn();
        if (!$id) {
            throw new \RuntimeException("Code entrepot introuvable : {$code}");
        }
        return (int)$id;
    }
}
