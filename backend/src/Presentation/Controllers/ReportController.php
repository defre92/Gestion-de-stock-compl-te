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

    private function sendCsv(string $filename, string $content): void
    {
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        echo $content;
    }
}