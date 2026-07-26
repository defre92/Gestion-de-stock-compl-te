<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\ProductSerialService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class ProductSerialController
{
    public function __construct(private readonly ProductSerialService $service)
    {
    }

    public function index(Request $request): void
    {
        $page = (int)$request->query('page', 1);
        $perPage = (int)$request->query('per_page', 20);
        $filters = [
            'q' => $request->query('q'),
            'product_id' => $request->query('product_id'),
            'warehouse_id' => $request->query('warehouse_id'),
            'status' => $request->query('status'),
        ];

        JsonResponse::send($this->service->paginate($page, $perPage, $filters));
    }

    public function show(int $id): void
    {
        JsonResponse::send(['data' => $this->service->findById($id)]);
    }

    /** Recherche exacte par SN: GET /product-serials/search?serial_number=XXXX */
    public function search(Request $request): void
    {
        $serialNumber = (string)$request->query('serial_number', '');
        JsonResponse::send(['data' => $this->service->search($serialNumber)]);
    }

    public function store(Request $request): void
    {
        $user = $request->attribute('auth_user');
        $ids = $this->service->create($request->input(), (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['ids' => $ids], 201);
    }

    public function markOut(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $notes = $request->input('notes');
        $this->service->markOut($id, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null, $notes !== null ? (string)$notes : null);

        JsonResponse::send(['message' => 'Numero de serie marque comme sorti']);
    }

    public function markInStock(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $warehouseId = (int)$request->input('warehouse_id', 0);
        $notes = $request->input('notes');
        $this->service->markInStock($id, $warehouseId, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null, $notes !== null ? (string)$notes : null);

        JsonResponse::send(['message' => 'Numero de serie remis en stock']);
    }

    public function destroy(Request $request, int $id): void
    {
        $user = $request->attribute('auth_user');
        $this->service->delete($id, (int)$user['id'], $_SERVER['REMOTE_ADDR'] ?? null);

        JsonResponse::send(['message' => 'Numero de serie supprime']);
    }
}
