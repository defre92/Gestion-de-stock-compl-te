<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\ProductSerialRepository;
use App\Shared\Http\HttpException;

final class ProductSerialService
{
    public function __construct(
        private readonly ProductSerialRepository $repository,
        private readonly AuditRepository $auditRepository
    ) {
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        return $this->repository->paginate($page, $perPage, $filters);
    }

    public function findById(int $id): array
    {
        $serial = $this->repository->findById($id);
        if (!$serial) {
            throw new HttpException('Numero de serie introuvable', 404);
        }

        return $serial;
    }

    /**
     * Recherche un article par son SN exact - c'est le besoin principal:
     * "pouvoir rechercher un article par SN" retrouve directement le produit,
     * son statut, sa localisation actuelle, et l'historique des livraisons
     * (quand et a quel client il a ete vendu, le cas echeant).
     */
    public function search(string $serialNumber): array
    {
        $serialNumber = trim($serialNumber);
        if ($serialNumber === '') {
            throw new HttpException('Numero de serie requis', 422);
        }

        $result = $this->repository->findBySerialNumber($serialNumber);
        if (!$result) {
            throw new HttpException('Aucun article trouve pour ce numero de serie', 404);
        }

        $result['delivery_history'] = $this->repository->findDeliveryHistory((int)$result['id']);

        return $result;
    }

    public function create(array $payload, int $actorId, ?string $ip): array
    {
        $productId = (int)($payload['product_id'] ?? 0);
        $warehouseId = isset($payload['warehouse_id']) && $payload['warehouse_id'] !== ''
            ? (int)$payload['warehouse_id']
            : null;

        // Accepte soit un seul SN (serial_number), soit une liste (serial_numbers,
        // un par ligne cote frontend) pour enregistrer un lot recu d'un coup.
        $serials = [];
        if (!empty($payload['serial_numbers']) && is_array($payload['serial_numbers'])) {
            $serials = $payload['serial_numbers'];
        } elseif (!empty($payload['serial_number'])) {
            $serials = [$payload['serial_number']];
        }

        $serials = array_values(array_unique(array_filter(array_map(
            static fn ($s): string => trim((string)$s),
            $serials
        ), static fn (string $s): bool => $s !== '')));

        if ($productId <= 0) {
            throw new HttpException('Produit requis', 422);
        }
        if ($serials === []) {
            throw new HttpException('Au moins un numero de serie est requis', 422);
        }

        foreach ($serials as $serial) {
            if (strlen($serial) > 120) {
                throw new HttpException("Numero de serie trop long: {$serial}", 422);
            }
            if ($this->repository->findBySerialNumber($serial) !== null) {
                throw new HttpException("Ce numero de serie existe deja: {$serial}", 422);
            }
        }

        $ids = $this->repository->createMany($productId, $warehouseId, $serials, $actorId);

        $this->auditRepository->log($actorId, 'CREATE', 'product_serial', null, [
            'product_id' => $productId,
            'count' => count($ids),
        ], $ip);

        return $ids;
    }

    public function markOut(int $id, int $actorId, ?string $ip, ?string $notes): void
    {
        $serial = $this->repository->findById($id);
        if (!$serial) {
            throw new HttpException('Numero de serie introuvable', 404);
        }
        if ($serial['status'] === 'OUT') {
            throw new HttpException('Ce numero de serie est deja sorti', 422);
        }

        $this->repository->updateStatus($id, 'OUT', null, $notes);
        $this->auditRepository->log($actorId, 'MARK_OUT', 'product_serial', $id, [], $ip);
    }

    public function markInStock(int $id, int $warehouseId, int $actorId, ?string $ip, ?string $notes): void
    {
        $serial = $this->repository->findById($id);
        if (!$serial) {
            throw new HttpException('Numero de serie introuvable', 404);
        }
        if ($serial['status'] === 'IN_STOCK') {
            throw new HttpException('Ce numero de serie est deja en stock', 422);
        }

        $this->repository->updateStatus($id, 'IN_STOCK', $warehouseId, $notes);
        $this->auditRepository->log($actorId, 'MARK_IN_STOCK', 'product_serial', $id, [], $ip);
    }

    public function delete(int $id, int $actorId, ?string $ip): void
    {
        $serial = $this->repository->findById($id);
        if (!$serial) {
            throw new HttpException('Numero de serie introuvable', 404);
        }

        $this->repository->delete($id);
        $this->auditRepository->log($actorId, 'DELETE', 'product_serial', $id, [], $ip);
    }
}
