<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\ReportRepository;

final class ReportService
{
    public function __construct(private readonly ReportRepository $repository)
    {
    }

    public function stockCsv(): string
    {
        return $this->toCsv($this->repository->stockSnapshot());
    }

    public function movementCsv(): string
    {
        return $this->toCsv($this->repository->movementJournal());
    }

    public function purchaseCsv(): string
    {
        return $this->toCsv($this->repository->purchaseSummary());
    }

    /** @param array<int, array<string, mixed>> $rows */
    private function toCsv(array $rows): string
    {
        if ($rows === []) {
            return "empty\n";
        }

        $stream = fopen('php://temp', 'w+');
        fputcsv($stream, array_keys($rows[0]), ';');

        foreach ($rows as $row) {
            fputcsv($stream, $row, ';');
        }

        rewind($stream);
        $content = stream_get_contents($stream) ?: '';
        fclose($stream);

        return $content;
    }
}