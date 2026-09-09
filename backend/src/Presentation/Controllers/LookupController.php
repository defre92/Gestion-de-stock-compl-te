<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Infrastructure\Persistence\BrandRepository;
use App\Infrastructure\Persistence\CategoryRepository;
use App\Infrastructure\Persistence\CustomerRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Infrastructure\Persistence\RoleRepository;
use App\Infrastructure\Persistence\SupplierRepository;
use App\Infrastructure\Persistence\TagRepository;
use App\Infrastructure\Persistence\TaxRepository;
use App\Infrastructure\Persistence\UnitRepository;
use App\Infrastructure\Persistence\WarehouseLocationRepository;
use App\Infrastructure\Persistence\WarehouseRepository;
use App\Infrastructure\Persistence\WarehouseZoneRepository;
use App\Shared\Http\JsonResponse;

final class LookupController
{
    public function __construct(
        private readonly RoleRepository $roleRepository,
        private readonly WarehouseRepository $warehouseRepository,
        private readonly WarehouseZoneRepository $warehouseZoneRepository,
        private readonly WarehouseLocationRepository $warehouseLocationRepository,
        private readonly CategoryRepository $categoryRepository,
        private readonly SupplierRepository $supplierRepository,
        private readonly ProductRepository $productRepository,
        private readonly UnitRepository $unitRepository,
        private readonly TaxRepository $taxRepository,
        private readonly BrandRepository $brandRepository,
        private readonly CustomerRepository $customerRepository,
        private readonly TagRepository $tagRepository
    ) {
    }

    public function options(): void
    {
        JsonResponse::send([
            // allForLookup() et selectableForLookup() servent des referentiels
            // complets pour les listes deroulantes : ils ne subissent pas le
            // plafond de 100 lignes de paginate(), qui protege le parametre
            // HTTP ?per_page et tronquait ces listes sans le dire.
            'data' => [
                'roles' => $this->roleRepository->all(),
                'warehouses' => $this->warehouseRepository->allForLookup(),
                'warehouse_zones' => $this->warehouseZoneRepository->allForLookup(),
                'warehouse_locations' => $this->warehouseLocationRepository->allForLookup(),
                'categories' => $this->categoryRepository->allForLookup(),
                'suppliers' => $this->supplierRepository->allForLookup(),
                'products' => $this->productRepository->selectableForLookup(500),
                'units' => $this->unitRepository->allForLookup(),
                'taxes' => $this->taxRepository->allForLookup(),
                'brands' => $this->brandRepository->allForLookup(),
                'customers' => $this->customerRepository->allForLookup(),
                'tags' => $this->tagRepository->allForLookup(),
            ],
        ]);
    }
}