<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Infrastructure\Persistence\AuditRepository;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class AuditController
{
    public function __construct(private readonly AuditRepository $repository)
    {
    }

    public function index(Request $request): void
    {
        $page = (int)$request->query('page', 1);
        $perPage = (int)$request->query('per_page', 50);

        $filters = [
            'user_id' => $request->query('user_id'),
            'action' => $request->query('action'),
            'entity_type' => $request->query('entity_type'),
            'date_from' => $request->query('date_from'),
            'date_to' => $request->query('date_to'),
        ];

        JsonResponse::send($this->repository->paginate($page, $perPage, $filters));
    }
}
