<?php
declare(strict_types=1);

namespace App\Shared\Export;

use RuntimeException;
use ZipArchive;

/**
 * Lecteur XLSX minimal, sans dependance externe (miroir de XlsxWriter).
 *
 * Contrairement a l'export, le fichier lu ici n'est pas forcement celui
 * qu'on a genere : c'est le plus souvent le meme classeur reouvert et
 * modifie dans un vrai Excel (ou LibreOffice), qui reecrit alors la
 * quasi-totalite du zip avec SES propres conventions - notamment une table
 * de chaines partagees (xl/sharedStrings.xml) plutot que des chaines
 * "inline" comme le fait XlsxWriter. Ce lecteur doit donc gerer les deux.
 *
 * Ne lit que la PREMIERE feuille du classeur (celle listee en premier dans
 * xl/workbook.xml) : suffisant pour un fichier de comptage a une seule
 * feuille, et on ne veut pas risquer de lire un mauvais onglet si
 * l'utilisateur en a ajoute d'autres pour ses propres notes.
 */
final class XlsxReader
{
    /**
     * @return array<int, array<string, string>> Une ligne par entree,
     *   cle sur l'en-tete normalise (comme readCsvRows en ImportService:
     *   minuscules, espaces/tirets -> underscore). La premiere ligne du
     *   fichier est toujours traitee comme l'en-tete.
     */
    public static function readRows(string $path): array
    {
        $zip = new ZipArchive();
        if ($zip->open($path) !== true) {
            throw new RuntimeException('Fichier xlsx illisible (ce n\'est peut-etre pas un vrai fichier Excel)');
        }

        try {
            $sheetPath = self::resolveFirstSheetPath($zip);
            $sheetXml = $zip->getFromName($sheetPath);
            if ($sheetXml === false) {
                throw new RuntimeException('Feuille de calcul introuvable dans le fichier xlsx');
            }

            $sharedStrings = self::readSharedStrings($zip);
            $grid = self::parseSheet($sheetXml, $sharedStrings);
        } finally {
            $zip->close();
        }

        if ($grid === []) {
            return [];
        }

        $maxCol = 0;
        foreach ($grid as $row) {
            $maxCol = max($maxCol, ...array_keys($row + [0 => 0]));
        }

        $headerRowIndex = array_key_first($grid);
        $headerRow = $grid[$headerRowIndex];
        $headers = [];
        for ($col = 0; $col <= $maxCol; $col++) {
            $raw = trim((string)($headerRow[$col] ?? ''));
            $raw = preg_replace('/^\xEF\xBB\xBF/', '', $raw) ?? $raw;
            $headers[$col] = $raw === '' ? "col_{$col}" : strtolower(str_replace([' ', '-'], '_', $raw));
        }

        $rows = [];
        foreach ($grid as $rowIndex => $row) {
            if ($rowIndex === $headerRowIndex) {
                continue;
            }
            $isEmpty = true;
            $assoc = [];
            for ($col = 0; $col <= $maxCol; $col++) {
                $value = $row[$col] ?? null;
                if ($value !== null && $value !== '') {
                    $isEmpty = false;
                }
                $assoc[$headers[$col]] = $value;
            }
            if ($isEmpty) {
                continue;
            }
            $rows[] = $assoc;
        }

        return $rows;
    }

    private static function resolveFirstSheetPath(ZipArchive $zip): string
    {
        $workbookXml = $zip->getFromName('xl/workbook.xml');
        if ($workbookXml === false) {
            throw new RuntimeException('xl/workbook.xml manquant : ce n\'est pas un fichier xlsx valide');
        }

        $relsXml = $zip->getFromName('xl/_rels/workbook.xml.rels');
        $targets = [];
        if ($relsXml !== false) {
            $relsDoc = self::loadXml($relsXml);
            foreach ($relsDoc->getElementsByTagName('Relationship') as $rel) {
                $id = $rel->getAttribute('Id');
                $target = $rel->getAttribute('Target');
                if ($id !== '' && $target !== '') {
                    $targets[$id] = $target;
                }
            }
        }

        $workbookDoc = self::loadXml($workbookXml);
        $firstSheet = $workbookDoc->getElementsByTagName('sheet')->item(0);
        if ($firstSheet === null) {
            throw new RuntimeException('Aucune feuille trouvee dans le classeur');
        }

        // r:id est dans le namespace des relations Office - getAttribute avec
        // le prefixe litteral fonctionne car DOMDocument le resout via le
        // xmlns:r declare sur l'element <workbook>.
        $rId = $firstSheet->getAttribute('r:id');
        $target = $targets[$rId] ?? 'worksheets/sheet1.xml';
        $target = ltrim($target, '/');
        if (!str_starts_with($target, 'xl/')) {
            $target = 'xl/' . $target;
        }

        return $target;
    }

    /** @return array<int, string> Index -> chaine (table de chaines partagees, absente pour un fichier "inline strings"). */
    private static function readSharedStrings(ZipArchive $zip): array
    {
        $xml = $zip->getFromName('xl/sharedStrings.xml');
        if ($xml === false) {
            return [];
        }

        $doc = self::loadXml($xml);
        $strings = [];
        foreach ($doc->getElementsByTagName('si') as $index => $si) {
            // Un <si> peut contenir plusieurs <r> (runs, texte avec mise en
            // forme mixte) au lieu d'un simple <t> direct : on concatene tout
            // le texte, la mise en forme ne nous interesse pas ici.
            $text = '';
            foreach ($si->getElementsByTagName('t') as $t) {
                $text .= $t->textContent;
            }
            $strings[$index] = $text;
        }

        return $strings;
    }

    /**
     * @param array<int, string> $sharedStrings
     * @return array<int, array<int, string>> grille[ligne][colonne] = valeur texte brute
     */
    private static function parseSheet(string $sheetXml, array $sharedStrings): array
    {
        $doc = self::loadXml($sheetXml);
        $grid = [];

        foreach ($doc->getElementsByTagName('row') as $rowEl) {
            $rowRef = $rowEl->getAttribute('r');
            $rowIndex = $rowRef !== '' ? ((int)$rowRef - 1) : count($grid);

            foreach ($rowEl->getElementsByTagName('c') as $cellEl) {
                $cellRef = $cellEl->getAttribute('r');
                $colIndex = $cellRef !== '' ? self::columnIndexFromRef($cellRef) : 0;
                $type = $cellEl->getAttribute('t');

                $value = self::extractCellValue($cellEl, $type, $sharedStrings);
                if ($value !== null) {
                    $grid[$rowIndex][$colIndex] = $value;
                }
            }
        }

        ksort($grid);
        foreach ($grid as &$row) {
            ksort($row);
        }
        unset($row);

        return $grid;
    }

    private static function extractCellValue(\DOMElement $cellEl, string $type, array $sharedStrings): ?string
    {
        if ($type === 'inlineStr') {
            $isNode = $cellEl->getElementsByTagName('is')->item(0);
            if ($isNode === null) {
                return null;
            }
            $text = '';
            foreach ($isNode->getElementsByTagName('t') as $t) {
                $text .= $t->textContent;
            }
            return $text;
        }

        $vNode = $cellEl->getElementsByTagName('v')->item(0);
        if ($vNode === null) {
            return null;
        }
        $raw = $vNode->textContent;

        if ($type === 's') {
            $index = (int)$raw;
            return $sharedStrings[$index] ?? '';
        }

        if ($type === 'b') {
            return $raw === '1' ? '1' : '0';
        }

        // Type par defaut (pas de t="...") = numerique, ou "str" = resultat
        // de formule deja calcule : dans les deux cas la valeur brute suffit.
        return $raw;
    }

    /** "C7" -> 2 (colonne C = index 2, base 0). Ignore les chiffres (partie ligne) de la reference. */
    private static function columnIndexFromRef(string $ref): int
    {
        $letters = '';
        for ($i = 0; $i < strlen($ref); $i++) {
            $char = $ref[$i];
            if ($char >= 'A' && $char <= 'Z') {
                $letters .= $char;
            } else {
                break;
            }
        }
        if ($letters === '') {
            return 0;
        }

        $index = 0;
        for ($i = 0; $i < strlen($letters); $i++) {
            $index = $index * 26 + (ord($letters[$i]) - ord('A') + 1);
        }

        return $index - 1;
    }

    private static function loadXml(string $xml): \DOMDocument
    {
        $doc = new \DOMDocument();
        $previous = libxml_use_internal_errors(true);
        // Pas d'acces reseau pendant le parsing : un xlsx est un fichier
        // utilisateur, on ne fait pas confiance a son XML au point de
        // resoudre une entite externe qu'il declarerait (XXE).
        $loaded = $doc->loadXML($xml, LIBXML_NONET);
        libxml_use_internal_errors($previous);
        if (!$loaded) {
            throw new RuntimeException('XML illisible dans le fichier xlsx');
        }

        return $doc;
    }
}
