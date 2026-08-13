<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/bootstrap.php';

use App\Application\Services\AuthService;
use App\Application\Services\AttachmentService;
use App\Application\Services\CrudService;
use App\Application\Services\DashboardService;
use App\Application\Services\DeliveryService;
use App\Application\Services\FileStorageService;
use App\Application\Services\ImportService;
use App\Application\Services\InventoryService;
use App\Application\Services\PurchaseOrderService;
use App\Application\Services\PurchaseRequestService;
use App\Application\Services\ReportService;
use App\Application\Services\ProductSerialService;
use App\Application\Services\StockService;
use App\Application\Services\UserService;
use App\Infrastructure\Persistence\AppSettingRepository;
use App\Infrastructure\Persistence\AuditRepository;
use App\Infrastructure\Persistence\LoginAttemptRepository;
use App\Infrastructure\Persistence\AuthTokenRepository;
use App\Infrastructure\Persistence\BrandRepository;
use App\Infrastructure\Persistence\CategoryRepository;
use App\Infrastructure\Persistence\CustomerRepository;
use App\Infrastructure\Persistence\DashboardRepository;
use App\Infrastructure\Persistence\DeliveryRepository;
use App\Infrastructure\Persistence\DocumentAttachmentRepository;
use App\Infrastructure\Persistence\ImportJobRepository;
use App\Infrastructure\Persistence\InventoryRepository;
use App\Infrastructure\Persistence\ProductMediaRepository;
use App\Infrastructure\Persistence\ProductRepository;
use App\Infrastructure\Persistence\ProductVariantRepository;
use App\Infrastructure\Persistence\PurchaseOrderRepository;
use App\Infrastructure\Persistence\PurchaseRequestRepository;
use App\Infrastructure\Persistence\ReportRepository;
use App\Infrastructure\Persistence\RoleRepository;
use App\Infrastructure\Persistence\StockAlertRepository;
use App\Infrastructure\Persistence\ProductSerialRepository;
use App\Infrastructure\Persistence\StockMovementRepository;
use App\Infrastructure\Persistence\SupplierRepository;
use App\Infrastructure\Persistence\TagRepository;
use App\Infrastructure\Persistence\TaxRepository;
use App\Infrastructure\Persistence\UnitRepository;
use App\Infrastructure\Persistence\UserRepository;
use App\Infrastructure\Persistence\WarehouseLocationRepository;
use App\Infrastructure\Persistence\WarehouseRepository;
use App\Infrastructure\Persistence\WarehouseZoneRepository;
use App\Presentation\Controllers\AuthController;
use App\Presentation\Controllers\AttachmentController;
use App\Presentation\Controllers\AuditController;
use App\Presentation\Controllers\BarcodeController;
use App\Presentation\Controllers\CrudController;
use App\Presentation\Controllers\DashboardController;
use App\Presentation\Controllers\DeliveryController;
use App\Presentation\Controllers\ImportController;
use App\Presentation\Controllers\InventoryController;
use App\Presentation\Controllers\LookupController;
use App\Presentation\Controllers\ProductMediaController;
use App\Presentation\Controllers\PurchaseOrderController;
use App\Presentation\Controllers\PurchaseRequestController;
use App\Presentation\Controllers\ReportController;
use App\Presentation\Controllers\ProductSerialController;
use App\Presentation\Controllers\StockController;
use App\Presentation\Controllers\UserController;
use App\Presentation\Middleware\AuthMiddleware;
use App\Presentation\Middleware\RoleMiddleware;
use App\Shared\Http\HttpException;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;
use App\Shared\Http\Router;
use App\Shared\Security\PasswordService;
use App\Shared\Security\TokenService;

$appConfig = require dirname(__DIR__) . '/config/app.php';

// CORS simple: on autorise uniquement les origines configurees.
$origin = $_SERVER['HTTP_ORIGIN'] ?? '*';
$allowedOrigins = $appConfig['cors_allowed_origins'];
if ($origin !== '*' && in_array($origin, $allowedOrigins, true)) {
    header('Access-Control-Allow-Origin: ' . $origin);
} elseif ($allowedOrigins !== []) {
    header('Access-Control-Allow-Origin: ' . $allowedOrigins[0]);
}
header('Vary: Origin');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
// Necessaire pour que le navigateur envoie/accepte le cookie de session
// httpOnly (voir AuthCookie) sur les requetes fetch avec credentials: 'include'.
header('Access-Control-Allow-Credentials: true');

// Defense en profondeur: l'API ne sert que du JSON, aucun script/style/frame
// n'a de raison de charger ni d'encadrer une reponse de ce endpoint.
header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");
header('X-Content-Type-Options: nosniff');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$request = Request::fromGlobals();

// Construction des dependances metier et techniques.
$auditRepository = new AuditRepository();
$tokenService = new TokenService();
$passwordService = new PasswordService();
$userRepository = new UserRepository();
$authTokenRepository = new AuthTokenRepository();
$roleRepository = new RoleRepository();
$storageService = new FileStorageService(dirname(__DIR__) . '/public/uploads');

$loginAttemptRepository = new LoginAttemptRepository();
$authService = new AuthService($userRepository, $authTokenRepository, $passwordService, $tokenService, $auditRepository, $loginAttemptRepository);
$authController = new AuthController($authService);

$categoryController = new CrudController(new CrudService(new CategoryRepository(), $auditRepository, 'category', ['name']));
$supplierController = new CrudController(new CrudService(new SupplierRepository(), $auditRepository, 'supplier', ['name', 'status']));
$productController = new CrudController(new CrudService(new ProductRepository(), $auditRepository, 'product', ['sku', 'name', 'category_id', 'status']));
$productVariantController = new CrudController(new CrudService(new ProductVariantRepository(), $auditRepository, 'product_variant', ['product_id', 'sku']));
$userController = new UserController(new UserService($userRepository, $roleRepository, $passwordService, $auditRepository, $authTokenRepository));
$auditController = new AuditController($auditRepository);

$brandController = new CrudController(new CrudService(new BrandRepository(), $auditRepository, 'brand', ['name']));
$unitController = new CrudController(new CrudService(new UnitRepository(), $auditRepository, 'unit', ['code', 'name']));
$taxController = new CrudController(new CrudService(new TaxRepository(), $auditRepository, 'tax', ['code', 'name', 'rate']));
$tagController = new CrudController(new CrudService(new TagRepository(), $auditRepository, 'tag', ['name']));
$customerController = new CrudController(new CrudService(new CustomerRepository(), $auditRepository, 'customer', ['name', 'status']));
$warehouseController = new CrudController(new CrudService(new WarehouseRepository(), $auditRepository, 'warehouse', ['code', 'name', 'status']));
$warehouseZoneController = new CrudController(new CrudService(new WarehouseZoneRepository(), $auditRepository, 'warehouse_zone', ['warehouse_id', 'code', 'name']));
$warehouseLocationController = new CrudController(new CrudService(new WarehouseLocationRepository(), $auditRepository, 'warehouse_location', ['warehouse_id', 'code']));
$appSettingController = new CrudController(new CrudService(new AppSettingRepository(), $auditRepository, 'app_setting', ['setting_key', 'setting_value']));
$productMediaController = new CrudController(new CrudService(new ProductMediaRepository(), $auditRepository, 'product_media', ['product_id', 'media_type', 'file_name', 'file_path']));
$stockAlertController = new CrudController(new CrudService(new StockAlertRepository(), $auditRepository, 'stock_alert', ['alert_type', 'message']));
$importJobController = new CrudController(new CrudService(new ImportJobRepository(), $auditRepository, 'import_job', ['entity_type', 'status', 'started_by']));

$dashboardController = new DashboardController(new DashboardService(new DashboardRepository()));
$stockService = new StockService(new ProductRepository(), new WarehouseRepository(), new StockMovementRepository(), new StockAlertRepository(), $auditRepository);
$productSerialController = new ProductSerialController(new ProductSerialService(new ProductSerialRepository(), $auditRepository));
$stockController = new StockController($stockService);
$deliveryController = new DeliveryController(new DeliveryService(new DeliveryRepository(), $stockService, $auditRepository, new ProductSerialRepository(), new ProductRepository()));
$purchaseOrderController = new PurchaseOrderController(new PurchaseOrderService(new PurchaseOrderRepository(), $stockService, $auditRepository, new PurchaseRequestRepository(), new ProductRepository()));
$purchaseRequestController = new PurchaseRequestController(new PurchaseRequestService(new PurchaseRequestRepository(), $auditRepository, new ProductRepository()));
$inventoryController = new InventoryController(new InventoryService(new InventoryRepository(), new ProductRepository(), $auditRepository, $stockService));
$reportController = new ReportController(new ReportService(new ReportRepository()));
$attachmentController = new AttachmentController(new AttachmentService(new DocumentAttachmentRepository(), $storageService, $auditRepository));
$importController = new ImportController(new ImportService(new ImportJobRepository(), $storageService, $auditRepository));
$productMediaUploadController = new ProductMediaController(new ProductMediaRepository(), new ProductRepository(), $storageService, $auditRepository);
$barcodeController = new BarcodeController(new ProductRepository());

$lookupController = new LookupController(
    $roleRepository,
    new WarehouseRepository(),
    new WarehouseZoneRepository(),
    new WarehouseLocationRepository(),
    new CategoryRepository(),
    new SupplierRepository(),
    new ProductRepository(),
    new UnitRepository(),
    new TaxRepository(),
    new BrandRepository(),
    new CustomerRepository(),
    new TagRepository()
);

$authMiddleware = new AuthMiddleware($authService);
$adminRolesMiddleware = new RoleMiddleware(['SUPER_ADMIN', 'ADMIN']);
$stockRolesMiddleware = new RoleMiddleware(['SUPER_ADMIN', 'ADMIN', 'STOREKEEPER', 'MANAGER']);
$buyRolesMiddleware = new RoleMiddleware(['SUPER_ADMIN', 'ADMIN', 'BUYER', 'MANAGER']);

// Point central de declaration des routes API v1.
$router = new Router();

$router->add('GET', '/api/v1/health', static fn () => JsonResponse::send(['status' => 'ok', 'service' => 'gestion-stock-api-v2']));

$router->add('POST', '/api/v1/auth/login', static fn (Request $req) => $authController->login($req));
$router->add('GET', '/api/v1/auth/me', static fn (Request $req) => $authController->me($req), [$authMiddleware]);
$router->add('POST', '/api/v1/auth/logout', static fn (Request $req) => $authController->logout($req), [$authMiddleware]);

$router->add('GET', '/api/v1/dashboard/stats', static fn () => $dashboardController->stats(), [$authMiddleware]);
$router->add('GET', '/api/v1/lookups/options', static fn () => $lookupController->options(), [$authMiddleware]);

$router->add('GET', '/api/v1/categories', static fn (Request $req) => $categoryController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/categories/{id}', static fn (Request $req, array $p) => $categoryController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/categories', static fn (Request $req) => $categoryController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/categories/{id}', static fn (Request $req, array $p) => $categoryController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/categories/{id}', static fn (Request $req, array $p) => $categoryController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/suppliers', static fn (Request $req) => $supplierController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/suppliers/{id}', static fn (Request $req, array $p) => $supplierController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/suppliers', static fn (Request $req) => $supplierController->store($req), [$authMiddleware, $buyRolesMiddleware]);
$router->add('PUT', '/api/v1/suppliers/{id}', static fn (Request $req, array $p) => $supplierController->update($req, (int)$p['id']), [$authMiddleware, $buyRolesMiddleware]);
$router->add('DELETE', '/api/v1/suppliers/{id}', static fn (Request $req, array $p) => $supplierController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/products', static fn (Request $req) => $productController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/products/{id}', static fn (Request $req, array $p) => $productController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/products', static fn (Request $req) => $productController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/products/{id}', static fn (Request $req, array $p) => $productController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/products/{id}', static fn (Request $req, array $p) => $productController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/product-variants', static fn (Request $req) => $productVariantController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/product-variants/{id}', static fn (Request $req, array $p) => $productVariantController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/product-variants', static fn (Request $req) => $productVariantController->store($req), [$authMiddleware, $stockRolesMiddleware]);
$router->add('PUT', '/api/v1/product-variants/{id}', static fn (Request $req, array $p) => $productVariantController->update($req, (int)$p['id']), [$authMiddleware, $stockRolesMiddleware]);
$router->add('DELETE', '/api/v1/product-variants/{id}', static fn (Request $req, array $p) => $productVariantController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('GET', '/api/v1/product-media', static fn (Request $req) => $productMediaController->index($req), [$authMiddleware]);
$router->add('POST', '/api/v1/product-media', static fn (Request $req) => $productMediaController->store($req), [$authMiddleware]);
$router->add('POST', '/api/v1/products/{id}/media/upload', static fn (Request $req, array $p) => $productMediaUploadController->upload($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('GET', '/api/v1/product-media/{id}/download', static fn (Request $req, array $p) => $productMediaUploadController->download((int)$p['id']), [$authMiddleware]);
$router->add('GET', '/api/v1/products/{id}/label.svg', static fn (Request $req, array $p) => $barcodeController->productLabelSvg((int)$p['id']), [$authMiddleware]);

$router->add('GET', '/api/v1/brands', static fn (Request $req) => $brandController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/brands/{id}', static fn (Request $req, array $p) => $brandController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/brands', static fn (Request $req) => $brandController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/brands/{id}', static fn (Request $req, array $p) => $brandController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/brands/{id}', static fn (Request $req, array $p) => $brandController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/units', static fn (Request $req) => $unitController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/units/{id}', static fn (Request $req, array $p) => $unitController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/units', static fn (Request $req) => $unitController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/units/{id}', static fn (Request $req, array $p) => $unitController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/units/{id}', static fn (Request $req, array $p) => $unitController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/taxes', static fn (Request $req) => $taxController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/taxes/{id}', static fn (Request $req, array $p) => $taxController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/taxes', static fn (Request $req) => $taxController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/taxes/{id}', static fn (Request $req, array $p) => $taxController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/taxes/{id}', static fn (Request $req, array $p) => $taxController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/tags', static fn (Request $req) => $tagController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/tags/{id}', static fn (Request $req, array $p) => $tagController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/tags', static fn (Request $req) => $tagController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/tags/{id}', static fn (Request $req, array $p) => $tagController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/tags/{id}', static fn (Request $req, array $p) => $tagController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/customers', static fn (Request $req) => $customerController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/customers/{id}', static fn (Request $req, array $p) => $customerController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/customers', static fn (Request $req) => $customerController->store($req), [$authMiddleware, $buyRolesMiddleware]);
$router->add('PUT', '/api/v1/customers/{id}', static fn (Request $req, array $p) => $customerController->update($req, (int)$p['id']), [$authMiddleware, $buyRolesMiddleware]);
$router->add('DELETE', '/api/v1/customers/{id}', static fn (Request $req, array $p) => $customerController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/warehouses', static fn (Request $req) => $warehouseController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/warehouses/{id}', static fn (Request $req, array $p) => $warehouseController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/warehouses', static fn (Request $req) => $warehouseController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/warehouses/{id}', static fn (Request $req, array $p) => $warehouseController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/warehouses/{id}', static fn (Request $req, array $p) => $warehouseController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/warehouse-zones', static fn (Request $req) => $warehouseZoneController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/warehouse-zones/{id}', static fn (Request $req, array $p) => $warehouseZoneController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/warehouse-zones', static fn (Request $req) => $warehouseZoneController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/warehouse-zones/{id}', static fn (Request $req, array $p) => $warehouseZoneController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/warehouse-zones/{id}', static fn (Request $req, array $p) => $warehouseZoneController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/warehouse-locations', static fn (Request $req) => $warehouseLocationController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/warehouse-locations/{id}', static fn (Request $req, array $p) => $warehouseLocationController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/warehouse-locations', static fn (Request $req) => $warehouseLocationController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/warehouse-locations/{id}', static fn (Request $req, array $p) => $warehouseLocationController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/warehouse-locations/{id}', static fn (Request $req, array $p) => $warehouseLocationController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/settings', static fn (Request $req) => $appSettingController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/settings/{id}', static fn (Request $req, array $p) => $appSettingController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/settings', static fn (Request $req) => $appSettingController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/settings/{id}', static fn (Request $req, array $p) => $appSettingController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/settings/{id}', static fn (Request $req, array $p) => $appSettingController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/users', static fn (Request $req) => $userController->index($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('GET', '/api/v1/users/{id}', static fn (Request $req, array $p) => $userController->show((int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('POST', '/api/v1/users', static fn (Request $req) => $userController->store($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('PUT', '/api/v1/users/{id}', static fn (Request $req, array $p) => $userController->update($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('POST', '/api/v1/users/{id}/reset-password', static fn (Request $req, array $p) => $userController->resetPassword($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('GET', '/api/v1/audits', static fn (Request $req) => $auditController->index($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('DELETE', '/api/v1/audits', static fn (Request $req) => $auditController->clear($req), [$authMiddleware, $adminRolesMiddleware]);
$router->add('POST', '/api/v1/me/password', static fn (Request $req) => $userController->changeOwnPassword($req), [$authMiddleware]);
$router->add('DELETE', '/api/v1/users/{id}', static fn (Request $req, array $p) => $userController->destroy($req, (int)$p['id']), [$authMiddleware, $adminRolesMiddleware]);

$router->add('GET', '/api/v1/stock/movements', static fn (Request $req) => $stockController->movements($req), [$authMiddleware]);
$router->add('POST', '/api/v1/stock/movements', static fn (Request $req) => $stockController->createMovement($req), [$authMiddleware, $stockRolesMiddleware]);

$router->add('GET', '/api/v1/product-serials/search', static fn (Request $req) => $productSerialController->search($req), [$authMiddleware]);
$router->add('GET', '/api/v1/product-serials', static fn (Request $req) => $productSerialController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/product-serials/{id}', static fn (Request $req, array $p) => $productSerialController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/product-serials', static fn (Request $req) => $productSerialController->store($req), [$authMiddleware, $stockRolesMiddleware]);
$router->add('POST', '/api/v1/product-serials/{id}/mark-out', static fn (Request $req, array $p) => $productSerialController->markOut($req, (int)$p['id']), [$authMiddleware, $stockRolesMiddleware]);
$router->add('POST', '/api/v1/product-serials/{id}/mark-in-stock', static fn (Request $req, array $p) => $productSerialController->markInStock($req, (int)$p['id']), [$authMiddleware, $stockRolesMiddleware]);
$router->add('DELETE', '/api/v1/product-serials/{id}', static fn (Request $req, array $p) => $productSerialController->destroy($req, (int)$p['id']), [$authMiddleware, $stockRolesMiddleware]);
$router->add('GET', '/api/v1/stock/alerts', static fn () => $stockController->alerts(), [$authMiddleware]);

$router->add('GET', '/api/v1/deliveries', static fn (Request $req) => $deliveryController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/deliveries/{id}', static fn (Request $req, array $p) => $deliveryController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/deliveries', static fn (Request $req) => $deliveryController->store($req), [$authMiddleware, $stockRolesMiddleware]);
$router->add('POST', '/api/v1/deliveries/{id}/cancel', static fn (Request $req, array $p) => $deliveryController->cancel($req, (int)$p['id']), [$authMiddleware, $stockRolesMiddleware]);
$router->add('GET', '/api/v1/alerts', static fn (Request $req) => $stockAlertController->index($req), [$authMiddleware]);
$router->add('PUT', '/api/v1/alerts/{id}', static fn (Request $req, array $p) => $stockAlertController->update($req, (int)$p['id']), [$authMiddleware, $stockRolesMiddleware]);
$router->add('GET', '/api/v1/attachments', static fn (Request $req) => $attachmentController->index($req), [$authMiddleware]);
$router->add('POST', '/api/v1/attachments/upload', static fn (Request $req) => $attachmentController->upload($req), [$authMiddleware]);
$router->add('GET', '/api/v1/attachments/{id}/download', static fn (Request $req, array $p) => $attachmentController->download((int)$p['id']), [$authMiddleware]);

$router->add('GET', '/api/v1/purchase-requests', static fn (Request $req) => $purchaseRequestController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/purchase-requests/{id}', static fn (Request $req, array $p) => $purchaseRequestController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/purchase-requests', static fn (Request $req) => $purchaseRequestController->store($req), [$authMiddleware, $buyRolesMiddleware]);
$router->add('POST', '/api/v1/purchase-requests/{id}/status', static fn (Request $req, array $p) => $purchaseRequestController->updateStatus($req, (int)$p['id']), [$authMiddleware, $buyRolesMiddleware]);

$router->add('GET', '/api/v1/purchase-orders', static fn (Request $req) => $purchaseOrderController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/purchase-orders/{id}', static fn (Request $req, array $p) => $purchaseOrderController->show((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/purchase-orders', static fn (Request $req) => $purchaseOrderController->store($req), [$authMiddleware, $buyRolesMiddleware]);
$router->add('POST', '/api/v1/purchase-orders/{id}/status', static fn (Request $req, array $p) => $purchaseOrderController->updateStatus($req, (int)$p['id']), [$authMiddleware, $buyRolesMiddleware]);
$router->add('POST', '/api/v1/purchase-orders/{id}/receive', static fn (Request $req, array $p) => $purchaseOrderController->receive($req, (int)$p['id']), [$authMiddleware, $buyRolesMiddleware]);

$router->add('GET', '/api/v1/inventories', static fn (Request $req) => $inventoryController->index($req), [$authMiddleware]);
$router->add('GET', '/api/v1/inventories/{id}', static fn (Request $req, array $p) => $inventoryController->show((int)$p['id']), [$authMiddleware]);
$router->add('GET', '/api/v1/inventories/{id}/export.xlsx', static fn (Request $req, array $p) => $inventoryController->exportXlsx((int)$p['id']), [$authMiddleware]);
$router->add('POST', '/api/v1/inventories', static fn (Request $req) => $inventoryController->store($req), [$authMiddleware, $stockRolesMiddleware]);
$router->add('POST', '/api/v1/inventories/{id}/counts', static fn (Request $req, array $p) => $inventoryController->count($req, (int)$p['id']), [$authMiddleware, $stockRolesMiddleware]);
$router->add('POST', '/api/v1/inventories/{id}/finalize', static fn (Request $req, array $p) => $inventoryController->finalize($req, (int)$p['id']), [$authMiddleware, $stockRolesMiddleware]);

$router->add('GET', '/api/v1/reports/stock.csv', static fn () => $reportController->stockCsv(), [$authMiddleware]);
$router->add('GET', '/api/v1/reports/movements.csv', static fn () => $reportController->movementCsv(), [$authMiddleware]);
$router->add('GET', '/api/v1/reports/purchases.csv', static fn () => $reportController->purchaseCsv(), [$authMiddleware]);
$router->add('POST', '/api/v1/imports/{entity}', static fn (Request $req, array $p) => $importController->upload($req, (string)$p['entity']), [$authMiddleware, $adminRolesMiddleware]);
$router->add('GET', '/api/v1/import-jobs', static fn (Request $req) => $importJobController->index($req), [$authMiddleware, $adminRolesMiddleware]);

// Retour d'erreur propre pour le front (debug detaille seulement en mode debug).
try {
    $router->dispatch($request);
} catch (HttpException $exception) {
    JsonResponse::send(['message' => $exception->getMessage()], $exception->status());
} catch (Throwable $exception) {
    JsonResponse::send(['message' => 'Erreur serveur', 'error' => $appConfig['debug'] ? $exception->getMessage() : null], 500);
}
