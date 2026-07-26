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
            'data' => [
                'roles' => $this->roleRepository->all(),
                'warehouses' => $this->warehouseRepository->paginate(1, 200)['data'],
                'warehouse_zones' => $this->warehouseZoneRepository->paginate(1, 500)['data'],
                'warehouse_locations' => $this->warehouseLocationRepository->paginate(1, 1000)['data'],
                'categories' => $this->categoryRepository->paginate(1, 300)['data'],
                'suppliers' => $this->supplierRepository->paginate(1, 300)['data'],
                'products' => $this->productRepository->paginate(1, 500)['data'],
                'units' => $this->unitRepository->paginate(1, 200)['data'],
                'taxes' => $this->taxRepository->paginate(1, 200)['data'],
                'brands' => $this->brandRepository->paginate(1, 200)['data'],
                'customers' => $this->customerRepository->paginate(1, 200)['data'],
                'tags' => $this->tagRepository->paginate(1, 200)['data'],
            ],
        ]);
    }
}