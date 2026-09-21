<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\ReportService;

final class ReportController
{
    public function __construct(private readonly ReportService $service)
    {
    }

    public function stockCsv(): void
    {
        $this->sendCsv('stock-report.csv', $this->service->stockCsv());
    }

    public function movementCsv(): void
    {
        $this->sendCsv('movement-report.csv', $this->service->movementCsv());
    }

    public function purchaseCsv(): void
    {
        $this->sendCsv('purchase-report.csv', $this->service->purchaseCsv());
    }

    public function productCsv(): void
    {
        $this->sendCsv('product-report.csv', $this->service->productCsv());
    }

    public function supplierCsv(): void
    {
        $this->sendCsv('supplier-report.csv', $this->service->supplierCsv());
    }

    public function customerCsv(): void
    {
        $this->sendCsv('customer-report.csv', $this->service->customerCsv());
    }

    public function deliveryCsv(): void
    {
        $this->sendCsv('delivery-report.csv', $this->service->deliveryCsv());
    }

    public function inventoryCsv(): void
    {
        $this->sendCsv('inventory-report.csv', $this->service->inventoryCsv());
    }

    public function fullZip(): void
    {
        $content = $this->service->fullReportZip();
        header('Content-Type: application/zip');
        header('Content-Disposition: attachment; filename="rapport-complet.zip"');
        header('Content-Length: ' . strlen($content));
        echo $content;
    }

    private function sendCsv(string $filename, string $content): void
    {
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        echo $content;
    }
}