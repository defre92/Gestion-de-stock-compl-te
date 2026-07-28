<?php
declare(strict_types=1);

namespace App\Shared\Export;

use ZipArchive;

/**
 * Genere un vrai fichier .xlsx (pas un CSV renomme) sans aucune dependance
 * externe: le format XLSX est juste un zip contenant des fichiers XML, et
 * ZipArchive fait partie de PHP standard. On utilise des chaines "inline"
 * (type="str") plutot qu'une table de chaines partagees, ce qui suffit pour
 * des exports simples et evite une piece XML supplementaire.
 */
final class XlsxWriter
{
    /**
     * @param array<int, string> $headers
     * @param array<int, array<int, string|int|float|null>> $rows
     */
    public static function generate(array $headers, array $rows): string
    {
        $tmpFile = tempnam(sys_get_temp_dir(), 'xlsx');
        if ($tmpFile === false) {
            throw new \RuntimeException('Impossible de creer le fichier temporaire pour l\'export');
        }

        $zip = new ZipArchive();
        $zip->open($tmpFile, ZipArchive::OVERWRITE);

        $zip->addEmptyDir('_rels');
        $zip->addEmptyDir('xl');
        $zip->addEmptyDir('xl/_rels');
        $zip->addEmptyDir('xl/worksheets');

        $zip->addFromString('[Content_Types].xml', self::contentTypesXml());
        $zip->addFromString('_rels/.rels', self::rootRelsXml());
        $zip->addFromString('xl/workbook.xml', self::workbookXml());
        $zip->addFromString('xl/_rels/workbook.xml.rels', self::workbookRelsXml());
        $zip->addFromString('xl/styles.xml', self::stylesXml());
        $zip->addFromString('xl/worksheets/sheet1.xml', self::sheetXml($headers, $rows));

        $zip->close();

        $content = file_get_contents($tmpFile);
        unlink($tmpFile);

        if ($content === false) {
            throw new \RuntimeException('Impossible de lire le fichier xlsx genere');
        }

        return $content;
    }

    private static function contentTypesXml(): string
    {
        return <<<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
XML;
    }

    private static function rootRelsXml(): string
    {
        return <<<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
XML;
    }

    private static function workbookXml(): string
    {
        return <<<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
    <sheets>
        <sheet name="Export" sheetId="1" r:id="rId1"/>
    </sheets>
</workbook>
XML;
    }

    private static function workbookRelsXml(): string
    {
        return <<<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
XML;
    }

    private static function stylesXml(): string
    {
        // 2 formats de cellule: 0 = normal, 1 = gras (utilise pour l'entete).
        return <<<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="2">
        <font><sz val="11"/><name val="Calibri"/></font>
        <font><b/><sz val="11"/><name val="Calibri"/></font>
    </fonts>
    <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0"/></cellStyleXfs>
    <cellXfs count="2">
        <xf numFmtId="0" fontId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" xfId="0" applyFont="1"/>
    </cellXfs>
    <cellStyles count="1">
        <cellStyle name="Normal" xfId="0" builtinId="0"/>
    </cellStyles>
</styleSheet>
XML;
    }

    private static function columnLetter(int $index): string
    {
        $letter = '';
        $index++;
        while ($index > 0) {
            $mod = ($index - 1) % 26;
            $letter = chr(65 + $mod) . $letter;
            $index = intdiv($index - 1, 26);
        }
        return $letter;
    }

    private static function escapeXml(string $value): string
    {
        return htmlspecialchars($value, ENT_XML1 | ENT_QUOTES, 'UTF-8');
    }

    /**
     * @param array<int, string> $headers
     * @param array<int, array<int, string|int|float|null>> $rows
     */
    private static function sheetXml(array $headers, array $rows): string
    {
        $xmlRows = [];

        $headerCells = [];
        foreach ($headers as $colIndex => $header) {
            $ref = self::columnLetter($colIndex) . '1';
            $headerCells[] = '<c r="' . $ref . '" t="str" s="1"><v>' . self::escapeXml((string)$header) . '</v></c>';
        }
        $xmlRows[] = '<row r="1">' . implode('', $headerCells) . '</row>';

        foreach ($rows as $rowIndex => $row) {
            $excelRow = $rowIndex + 2; // ligne 1 = entete
            $cells = [];
            foreach ($row as $colIndex => $value) {
                $ref = self::columnLetter($colIndex) . $excelRow;
                if ($value === null || $value === '') {
                    continue;
                }
                if (is_int($value) || is_float($value)) {
                    $cells[] = '<c r="' . $ref . '"><v>' . $value . '</v></c>';
                } else {
                    $cells[] = '<c r="' . $ref . '" t="str"><v>' . self::escapeXml((string)$value) . '</v></c>';
                }
            }
            $xmlRows[] = '<row r="' . $excelRow . '">' . implode('', $cells) . '</row>';
        }

        $sheetData = implode('', $xmlRows);

        return <<<XML
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <sheetData>{$sheetData}</sheetData>
</worksheet>
XML;
    }
}
