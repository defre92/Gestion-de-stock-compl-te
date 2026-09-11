<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Domain\Contracts\CrudRepositoryInterface;
use App\Infrastructure\Persistence\AuditRepository;
use App\Shared\Http\HttpException;

final class CrudService
{
    public function __construct(
        private readonly CrudRepositoryInterface $repository,
        private readonly AuditRepository $auditRepository,
        private readonly string $entityType,
        private readonly array $requiredFields = [],
        /**
         * Colonnes qui doivent rester uniques, avec le libelle a afficher :
         * ['barcode' => 'code barre']. Controle APPLICATIF, sans contrainte
         * en base : une base existante peut deja contenir des doublons, et une
         * contrainte SQL empecherait alors toute modification de ces lignes -
         * y compris un simple changement de prix.
         *
         * @var array<string, string>
         */
        private readonly array $uniqueFields = []
    ) {
    }

    public function paginate(int $page, int $perPage, array $filters = []): array
    {
        return $this->repository->paginate($page, $perPage, $filters);
    }

    public function findById(int $id): array
    {
        $item = $this->repository->findById($id);
        if (!$item) {
            throw new HttpException(ucfirst($this->entityType) . ' not found', 404);
        }

        return $item;
    }

    public function create(array $payload, ?int $actorId, ?string $ip): int
    {
        $this->assertRequiredFields($payload);
        $this->assertUniqueFields($payload, null);
        $id = $this->repository->create($payload);

        if ($id <= 0) {
            throw new HttpException('Donnees invalides', 422);
        }

        $this->auditRepository->log($actorId, 'CREATE', $this->entityType, $id, $payload, $ip);
        return $id;
    }

    public function update(int $id, array $payload, ?int $actorId, ?string $ip): void
    {
        $current = $this->findById($id);
        $this->assertUniqueFields($payload, $current);
        if (!$this->repository->update($id, $payload)) {
            throw new HttpException('Aucune donnee mise a jour', 422);
        }

        $this->auditRepository->log($actorId, 'UPDATE', $this->entityType, $id, $payload, $ip);
    }

    public function delete(int $id, ?int $actorId, ?string $ip): void
    {
        $this->findById($id);
        $this->repository->delete($id);

        $this->auditRepository->log($actorId, 'DELETE', $this->entityType, $id, [], $ip);
    }

    /**
     * Refuse une valeur deja portee par une AUTRE ligne.
     *
     * Deux produits avec le meme code barre rendent le scan ambigu : la
     * douchette remonte deux articles et n'ouvre aucune fiche. Le controle
     * porte donc sur la saisie, au moment ou l'ambiguite serait creee.
     *
     * Volontairement tolerant sur l'existant : en modification, la valeur
     * n'est verifiee que si elle CHANGE. Une base qui contient deja des
     * doublons (aucune contrainte n'existait jusqu'ici) reste donc modifiable
     * - on peut corriger le prix d'un article en doublon sans etre oblige de
     * resoudre le doublon d'abord. Seule une saisie qui creerait ou
     * deplacerait l'ambiguite est bloquee.
     *
     * @param array<string, mixed> $payload
     * @param array<string, mixed>|null $current ligne actuelle (modification)
     */
    private function assertUniqueFields(array $payload, ?array $current): void
    {
        foreach ($this->uniqueFields as $field => $label) {
            if (!array_key_exists($field, $payload)) {
                continue;
            }

            $value = trim((string)($payload[$field] ?? ''));
            if ($value === '') {
                // Un champ facultatif laisse vide n'entre pas en conflit :
                // plusieurs produits sans code barre est un cas normal.
                continue;
            }

            if ($current !== null && trim((string)($current[$field] ?? '')) === $value) {
                continue;
            }

            $conflict = $this->repository->findByColumn($field, $value, $current['id'] ?? null);
            if ($conflict === null) {
                continue;
            }

            $who = trim((string)($conflict['sku'] ?? $conflict['code'] ?? ''));
            $name = trim((string)($conflict['name'] ?? ''));
            $designation = $who !== '' && $name !== ''
                ? "{$name} ({$who})"
                : ($name !== '' ? $name : ($who !== '' ? $who : 'id ' . (string)($conflict['id'] ?? '?')));

            throw new HttpException(
                "Ce {$label} est deja utilise par : {$designation}. Deux articles avec le meme {$label} rendraient le scan ambigu.",
                409
            );
        }
    }

    private function assertRequiredFields(array $payload): void
    {
        foreach ($this->requiredFields as $field) {
            if (!array_key_exists($field, $payload) || $payload[$field] === '') {
                throw new HttpException("Le champ '{$field}' est obligatoire", 422);
            }
        }
    }
}