<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\StockService;
use App\Infrastructure\Persistence\CostLayerRepository;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class StockController
{
    public function __construct(
        private readonly StockService $service,
        private readonly CostLayerRepository $costLayerRepository
    ) {
    }

    public function movements(Request $request): void
    {
        $page = (int)$request->query('page', 1);
        $perPage = (int)$request->query('per_page', 20);
        $filters = [
            'type' => $request->query('type'),
            'product_id' => $request->query('product_id'),
            'warehouse_id' => $request->query('warehouse_id'),
            'date_from' => $request->query('date_from'),
            'date_to' => $request->query('date_to'),
            'customer_id' => $request->query('customer_id'),
        ];
        JsonResponse::send($this->service->paginateMovements($page, $perPage, $filters));
    }

    public function createMovement(Request $request): void
    {
        $user = $request->attribute('auth_user');
        $id = $this->service->createMovement($request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);
        JsonResponse::send(['id' => $id], 201);
    }

    public function alerts(): void
    {
        JsonResponse::send(['data' => $this->service->lowStockAlerts()]);
    }

    /**
     * Lots FIFO encore en stock pour un produit (voir ValuationService).
     * Pertinent uniquement pour un produit en valorisation FIFO : un produit
     * en CUMP renverra une liste vide (aucun lot n'y est jamais consomme),
     * ce qui n'est pas une erreur - le front l'affiche seulement si utile.
     */
    public function costLayers(int $productId): void
    {
        JsonResponse::send(['data' => $this->costLayerRepository->listRemaining($productId)]);
    }
}
