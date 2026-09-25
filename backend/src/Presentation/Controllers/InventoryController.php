<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\InventoryService;
use App\Shared\Export\XlsxWriter;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class InventoryController
{
    public function __construct(private readonly InventoryService $service)
    {
    }

    public function index(Request $request): void
    {
        $page = (int)$request->query('page', 1);
        $perPage = (int)$request->query('per_page', 20);

        JsonResponse::send($this->service->paginateSessions($page, $perPage));
    }

    public function show(int $id): void
    {
        JsonResponse::send(['data' => $this->service->findSession($id)]);
    }

    public function remaining(int $id): void
    {
        JsonResponse::send(['data' => $this->service->remainingToCount($id)]);
    }

    public function store(Request $request): void
    {
        $user = $request->attribute('auth_user');
        $id = $this->service->createSession($request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['id' => $id], 201);
    }

    public function count(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $itemId = $this->service->addCount($id, $request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['id' => $itemId], 201);
    }

    public function deleteCount(Request $request, int $id, int $itemId): void
    {
        $user = $request->attribute('auth_user');
        $this->service->deleteCount($id, $itemId, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['message' => 'Comptage supprime']);
    }

    public function finalize(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->finalize($id, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['message' => 'Session d\'inventaire finalisee']);
    }

    public function exportXlsx(int $id): void
    {
        $session = $this->service->findSession($id);

        $headers = ['SKU', 'Produit', 'Attendu', 'Compte', 'Ecart', 'Emplacement', 'Compte par', 'Date'];
        $rows = [];
        foreach ($session['items'] as $item) {
            $rows[] = [
                (string)$item['sku'],
                (string)$item['product_name'],
                (int)$item['expected_qty'],
                (int)$item['counted_qty'],
                (int)$item['difference_qty'],
                (string)($item['location_code'] ?? ''),
                (string)($item['counted_by_name'] ?? ''),
                (string)$item['counted_at'],
            ];
        }

        $content = XlsxWriter::generate($headers, $rows);
        $filename = 'inventaire-' . preg_replace('/[^A-Za-z0-9_-]/', '', (string)$session['code']) . '.xlsx';

        header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Content-Length: ' . (string)strlen($content));
        header('X-Content-Type-Options: nosniff');
        echo $content;
    }

    /**
     * Feuille de comptage vierge (ou a completer) : SKU/produit/variante/
     * emplacement/quantite attendue pour reference, et une colonne "Quantite
     * comptee" vide - a remplir dans Excel puis reimporter via importCounts().
     * Les colonnes "ID ..." portent les identifiants techniques utilises a la
     * reimportation : l'utilisateur ne doit pas les modifier (rappel en fin
     * de nom de colonne), mais elles restent visibles plutot que masquees,
     * plus robuste qu'une colonne cachee qu'un simple copier-coller peut
     * reveler ou perdre.
     */
    public function exportCountSheetXlsx(int $id): void
    {
        $export = $this->service->exportCountSheet($id);
        $session = $export['session'];

        // Les 3 premieres colonnes sont des identifiants techniques utilises
        // a la reimportation (voir InventoryService::importCounts) : leur nom
        // ne doit pas changer sans mettre a jour readCsvRows/XlsxReader et
        // les cles lues cote import (id_produit/id_variante/id_emplacement -
        // un texte de mise en garde entre parentheses ici changerait la cle
        // normalisee et casserait le lien avec l'import).
        $headers = ['ID Produit', 'ID Variante', 'ID Emplacement', 'SKU', 'Produit', 'Variante', 'Emplacement', 'Quantite attendue', 'Quantite comptee'];
        $rows = [];
        foreach ($export['lines'] as $line) {
            $descriptors = array_filter([$line['variant_size'] ?? null, $line['variant_color'] ?? null]);
            $variantLabel = $line['variant_id'] !== null
                ? ($descriptors !== [] ? implode(' / ', $descriptors) : ($line['variant_sku'] ?? '-'))
                : '';

            $rows[] = [
                (int)$line['product_id'],
                $line['variant_id'] !== null ? (int)$line['variant_id'] : null,
                $line['location_id'] !== null ? (int)$line['location_id'] : null,
                (string)$line['sku'],
                (string)$line['product_name'],
                $variantLabel,
                (string)($line['location_code'] ?? ''),
                (int)$line['expected_qty'],
                null,
            ];
        }

        $content = XlsxWriter::generate($headers, $rows);
        $filename = 'comptage-' . preg_replace('/[^A-Za-z0-9_-]/', '', (string)$session['code']) . '.xlsx';

        header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Content-Length: ' . (string)strlen($content));
        header('X-Content-Type-Options: nosniff');
        echo $content;
    }

    public function importCounts(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $file = $request->file('file');
        if (!$file) {
            JsonResponse::send(['message' => 'Le fichier est requis'], 422);
            return;
        }

        $summary = $this->service->importCounts($id, $file, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);
        JsonResponse::send(['data' => $summary], 201);
    }
}