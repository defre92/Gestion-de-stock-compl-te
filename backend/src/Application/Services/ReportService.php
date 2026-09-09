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

    /**
     * Neutralise l'injection de formule dans les tableurs.
     *
     * Excel et LibreOffice interpretent comme une formule toute cellule
     * commencant par = + - @ (ou une tabulation / un retour chariot). Un nom
     * de produit saisi comme `=HYPERLINK("http://...")` ou
     * `=cmd|'/c calc'!A1` s'executerait donc a l'ouverture du fichier chez le
     * destinataire de l'export. On prefixe ces valeurs d'une apostrophe, que
     * le tableur consomme a l'affichage : la valeur reste lisible, mais n'est
     * plus une formule.
     */
    private function neutralizeFormula(mixed $value): mixed
    {
        if (!is_string($value) || $value === '') {
            return $value;
        }

        // Un nombre negatif ("-12", "-3.5") commence par '-' sans etre une
        // formule : le prefixer le transformerait en texte dans le tableur et
        // casserait les totaux d'un export de mouvements de stock.
        if (is_numeric($value)) {
            return $value;
        }

        return in_array($value[0], ['=', '+', '-', '@', "\t", "\r"], true) ? "'" . $value : $value;
    }

    /** @param array<int, array<string, mixed>> $rows */
    private function toCsv(array $rows): string
    {
        if ($rows === []) {
            return "Aucune donnee\n";
        }

        $stream = fopen('php://temp', 'w+');
        // BOM UTF-8 : sans lui, Excel sous Windows lit le fichier en ANSI et
        // massacre les accents des noms de produits et de fournisseurs.
        fwrite($stream, "\xEF\xBB\xBF");
        fputcsv($stream, array_map([$this, 'neutralizeFormula'], array_keys($rows[0])), ';');

        foreach ($rows as $row) {
            fputcsv($stream, array_map([$this, 'neutralizeFormula'], $row), ';');
        }

        rewind($stream);
        $content = stream_get_contents($stream) ?: '';
        fclose($stream);

        return $content;
    }
}