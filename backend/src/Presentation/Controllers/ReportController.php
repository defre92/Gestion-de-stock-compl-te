<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\ReportService;
use App\Shared\Http\JsonResponse;
use App\Shared\Http\Request;

final class ReportController
{
    public function __construct(private readonly ReportService $service)
    {
    }

    /**
     * Page Statistiques (onglet Rapports) : CA par mois/annee, top clients,
     * article le plus vendu - voir ReportRepository::salesStats().
     */
    public function salesStats(Request $request): void
    {
        $yearParam = $request->query('year');
        $year = $yearParam !== null && $yearParam !== '' ? (int)$yearParam : null;

        JsonResponse::send(['data' => $this->service->salesStats($year)]);
    }

    /**
     * Export CSV "stats completes de l'annee" (bouton de la page
     * Statistiques) - resume + CA par mois + meilleurs clients + articles
     * les plus vendus, pour une seule annee.
     */
    public function salesStatsYearCsv(Request $request): void
    {
        $yearParam = $request->query('year');
        $year = $yearParam !== null && $yearParam !== '' ? (int)$yearParam : null;

        $this->sendCsv('statistiques-annee.csv', $this->service->salesStatsYearCsv($year));
    }

    /**
     * Export CSV "stats completes du mois" - meme principe, restreint a un
     * mois donne, avec une repartition jour par jour.
     */
    public function salesStatsMonthCsv(Request $request): void
    {
        $yearParam = $request->query('year');
        $monthParam = $request->query('month');
        $year = $yearParam !== null && $yearParam !== '' ? (int)$yearParam : null;
        $month = $monthParam !== null && $monthParam !== '' ? (int)$monthParam : null;

        $this->sendCsv('statistiques-mois.csv', $this->service->salesStatsMonthCsv($year, $month));
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