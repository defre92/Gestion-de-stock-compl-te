<?php
declare(strict_types=1);

namespace App\Application\Services;

use App\Infrastructure\Persistence\ReportRepository;

final class ReportService
{
    private const MONTH_LABELS_FR = [
        1 => 'Janvier', 2 => 'Fevrier', 3 => 'Mars', 4 => 'Avril', 5 => 'Mai', 6 => 'Juin',
        7 => 'Juillet', 8 => 'Aout', 9 => 'Septembre', 10 => 'Octobre', 11 => 'Novembre', 12 => 'Decembre',
    ];

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

    public function productCsv(): string
    {
        return $this->toCsv($this->repository->productCatalog());
    }

    public function supplierCsv(): string
    {
        return $this->toCsv($this->repository->supplierList());
    }

    public function customerCsv(): string
    {
        return $this->toCsv($this->repository->customerList());
    }

    public function deliveryCsv(): string
    {
        return $this->toCsv($this->repository->deliveryJournal());
    }

    public function inventoryCsv(): string
    {
        return $this->toCsv($this->repository->inventorySessions());
    }

    /** @return array<int, int> */
    public function salesYears(): array
    {
        return $this->repository->salesYears();
    }

    /**
     * Page Statistiques de l'onglet Rapports. $year est valide/borne ici
     * (pas seulement caste cote controleur) : une annee farfelue envoyee a
     * la main dans l'URL doit renvoyer des stats vides, jamais une erreur
     * SQL ou une plage de dates absurde.
     *
     * @return array<string, mixed>
     */
    public function salesStats(?int $year): array
    {
        $availableYears = $this->repository->salesYears();
        $year = $this->normalizeYear($year, $availableYears);

        $stats = $this->repository->salesStats($year);
        // L'annee en cours doit rester choisissable dans le selecteur meme
        // sans aucune vente encore enregistree dessus (sinon impossible de
        // revenir dessus une fois qu'une annee plus ancienne est choisie).
        if (!in_array($year, $availableYears, true)) {
            array_unshift($availableYears, $year);
        }
        $stats['available_years'] = $availableYears;

        return $stats;
    }

    /**
     * Export CSV "stats completes de l'annee" (bouton de telechargement de
     * la page Statistiques) : un seul fichier reprenant le resume, le CA
     * mois par mois, les meilleurs clients et les articles les plus vendus.
     */
    public function salesStatsYearCsv(?int $year): string
    {
        $year = $this->normalizeYear($year, $this->repository->salesYears());
        $stats = $this->repository->salesStats($year);

        $sections = [];
        $sections[] = [
            'title' => "Statistiques annuelles {$year}",
            'headers' => ['Indicateur', 'Valeur'],
            'rows' => [
                ['Chiffre d\'affaires', $stats['summary']['revenue']],
                ['Nombre de livraisons', $stats['summary']['deliveries_count']],
                ['Panier moyen', $stats['summary']['average_basket']],
                ['Clients actifs', $stats['summary']['customers_count']],
            ],
        ];
        $sections[] = [
            'title' => 'Chiffre d\'affaires par mois',
            'headers' => ['Mois', 'Chiffre d\'affaires'],
            'rows' => array_map(
                fn (array $row): array => [self::MONTH_LABELS_FR[(int)$row['month']] ?? $row['month'], $row['revenue']],
                $stats['monthly_revenue']
            ),
        ];
        $sections[] = [
            'title' => 'Meilleurs clients',
            'headers' => ['Client', 'Chiffre d\'affaires', 'Livraisons'],
            'rows' => array_map(
                static fn (array $row): array => [$row['name'], $row['revenue'], $row['deliveries_count']],
                $stats['top_customers']
            ),
        ];
        $sections[] = [
            'title' => 'Articles les plus vendus',
            'headers' => ['SKU', 'Produit', 'Quantite vendue', 'Chiffre d\'affaires'],
            'rows' => array_map(
                static fn (array $row): array => [$row['sku'], $row['name'], $row['qty'], $row['revenue']],
                $stats['top_products']
            ),
        ];

        return $this->toMultiSectionCsv($sections);
    }

    /**
     * Export CSV "stats completes du mois" : resume, CA jour par jour,
     * meilleurs clients et articles les plus vendus, restreints au mois
     * demande.
     */
    public function salesStatsMonthCsv(?int $year, ?int $month): string
    {
        $year = $this->normalizeYear($year, $this->repository->salesYears());
        $month = $this->normalizeMonth($month);
        $stats = $this->repository->salesStatsMonth($year, $month);
        $monthLabel = self::MONTH_LABELS_FR[$month] ?? (string)$month;

        $sections = [];
        $sections[] = [
            'title' => "Statistiques du mois - {$monthLabel} {$year}",
            'headers' => ['Indicateur', 'Valeur'],
            'rows' => [
                ['Chiffre d\'affaires', $stats['summary']['revenue']],
                ['Nombre de livraisons', $stats['summary']['deliveries_count']],
                ['Panier moyen', $stats['summary']['average_basket']],
                ['Clients actifs', $stats['summary']['customers_count']],
            ],
        ];
        $sections[] = [
            'title' => 'Chiffre d\'affaires par jour',
            'headers' => ['Jour', 'Chiffre d\'affaires'],
            'rows' => array_map(
                static fn (array $row): array => [$row['day'], $row['revenue']],
                $stats['daily_revenue']
            ),
        ];
        $sections[] = [
            'title' => 'Meilleurs clients',
            'headers' => ['Client', 'Chiffre d\'affaires', 'Livraisons'],
            'rows' => array_map(
                static fn (array $row): array => [$row['name'], $row['revenue'], $row['deliveries_count']],
                $stats['top_customers']
            ),
        ];
        $sections[] = [
            'title' => 'Articles les plus vendus',
            'headers' => ['SKU', 'Produit', 'Quantite vendue', 'Chiffre d\'affaires'],
            'rows' => array_map(
                static fn (array $row): array => [$row['sku'], $row['name'], $row['qty'], $row['revenue']],
                $stats['top_products']
            ),
        ];

        return $this->toMultiSectionCsv($sections);
    }

    /**
     * Une annee farfelue ou absente retombe sur la plus recente ayant des
     * ventes (ou l'annee en cours a defaut) - jamais une erreur SQL.
     *
     * @param array<int, int> $availableYears
     */
    private function normalizeYear(?int $year, array $availableYears): int
    {
        if ($year === null || $year < 2000 || $year > 2100) {
            return $availableYears[0] ?? (int)date('Y');
        }

        return $year;
    }

    /** Un mois hors 1-12 retombe sur le mois en cours. */
    private function normalizeMonth(?int $month): int
    {
        if ($month === null || $month < 1 || $month > 12) {
            return (int)date('n');
        }

        return $month;
    }

    /**
     * Rapport complet : un ZIP contenant l'ensemble des exports CSV. Genere
     * dans un fichier temporaire (ZipArchive ne sait pas ecrire directement
     * en memoire) puis lu et supprime avant de renvoyer son contenu binaire.
     */
    public function fullReportZip(): string
    {
        $files = [
            'stock.csv' => $this->stockCsv(),
            'mouvements.csv' => $this->movementCsv(),
            'achats.csv' => $this->purchaseCsv(),
            'produits.csv' => $this->productCsv(),
            'fournisseurs.csv' => $this->supplierCsv(),
            'clients.csv' => $this->customerCsv(),
            'livraisons.csv' => $this->deliveryCsv(),
            'inventaires.csv' => $this->inventoryCsv(),
        ];

        $tmpPath = tempnam(sys_get_temp_dir(), 'report-');
        if ($tmpPath === false) {
            throw new \RuntimeException('Impossible de generer le rapport complet');
        }

        $zip = new \ZipArchive();
        if ($zip->open($tmpPath, \ZipArchive::OVERWRITE) !== true) {
            @unlink($tmpPath);
            throw new \RuntimeException('Impossible de generer le rapport complet');
        }

        foreach ($files as $name => $content) {
            $zip->addFromString($name, $content);
        }
        $zip->close();

        $content = file_get_contents($tmpPath) ?: '';
        @unlink($tmpPath);

        return $content;
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

    /**
     * Construit un CSV a plusieurs sections (titre + entetes + lignes,
     * separees par une ligne vide) - utilise pour les exports "stats
     * completes" de la page Statistiques, qui melangent plusieurs tableaux
     * dans un seul fichier a la difference des autres exports (un tableau
     * homogene chacun, geres par toCsv()).
     *
     * @param array<int, array{title: string, headers: array<int, string>, rows: array<int, array<int, mixed>>}> $sections
     */
    private function toMultiSectionCsv(array $sections): string
    {
        $stream = fopen('php://temp', 'w+');
        // BOM UTF-8 : sans lui, Excel sous Windows lit le fichier en ANSI et
        // massacre les accents.
        fwrite($stream, "\xEF\xBB\xBF");

        foreach ($sections as $index => $section) {
            if ($index > 0) {
                fputcsv($stream, [], ';');
            }
            fputcsv($stream, [$section['title']], ';');
            fputcsv($stream, array_map([$this, 'neutralizeFormula'], $section['headers']), ';');
            foreach ($section['rows'] as $row) {
                fputcsv($stream, array_map([$this, 'neutralizeFormula'], $row), ';');
            }
        }

        rewind($stream);
        $content = stream_get_contents($stream) ?: '';
        fclose($stream);

        return $content;
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