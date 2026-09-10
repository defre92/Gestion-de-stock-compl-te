<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Application\Services\Code128Encoder;
use App\Infrastructure\Persistence\ProductRepository;
use App\Shared\Http\JsonResponse;

final class BarcodeController
{
    /** Largeur d'un module, en points SVG. 2 pt donne un symbole lisible a l'ecran comme a l'impression. */
    private const MODULE = 2;

    /** Zone de silence obligatoire de part et d'autre du symbole : 10 modules minimum (norme). */
    private const QUIET_MODULES = 12;

    private const BAR_TOP = 30;
    private const BAR_HEIGHT = 80;
    private const HEIGHT = 170;

    public function __construct(
        private readonly ProductRepository $productRepository,
        private readonly Code128Encoder $encoder = new Code128Encoder()
    ) {
    }

    public function productLabelSvg(int $id): void
    {
        $product = $this->productRepository->findById($id);
        if (!$product) {
            JsonResponse::send(['message' => 'Produit introuvable'], 404);
            return;
        }

        // Le code barre du produit prime ; a defaut on encode le SKU, qui est
        // unique lui aussi. Une etiquette sans code n'aurait aucun usage.
        $code = trim((string)($product['barcode'] ?? ''));
        if ($code === '') {
            $code = trim((string)($product['sku'] ?? ''));
        }

        if ($code === '') {
            JsonResponse::send(['message' => 'Ce produit n\'a ni code barre ni SKU'], 422);
            return;
        }

        try {
            $widths = $this->encoder->widths($code);
        } catch (\InvalidArgumentException $exception) {
            JsonResponse::send(['message' => 'Etiquette impossible : ' . $exception->getMessage()], 422);
            return;
        }

        $quiet = self::QUIET_MODULES * self::MODULE;
        $symbolWidth = array_sum($widths) * self::MODULE;
        $width = $quiet * 2 + $symbolWidth;

        // Les largeurs alternent barre / espace en commencant par une barre :
        // on ne dessine que les elements de rang pair (les barres).
        $bars = '';
        $x = $quiet;
        foreach ($widths as $index => $modules) {
            $elementWidth = $modules * self::MODULE;
            if ($index % 2 === 0) {
                $bars .= '<rect x="' . $x . '" y="' . self::BAR_TOP . '" width="' . $elementWidth
                    . '" height="' . self::BAR_HEIGHT . '" fill="#000000" />';
            }
            $x += $elementWidth;
        }

        $name = htmlspecialchars((string)$product['name'], ENT_QUOTES, 'UTF-8');
        $sku = htmlspecialchars((string)($product['sku'] ?? ''), ENT_QUOTES, 'UTF-8');
        $codeSafe = htmlspecialchars($code, ENT_QUOTES, 'UTF-8');
        $price = number_format((float)($product['unit_price'] ?? 0), 2, ',', ' ');
        $center = (int)round($width / 2);

        header('Content-Type: image/svg+xml; charset=utf-8');
        header('Cache-Control: no-store');
        echo '<?xml version="1.0" encoding="UTF-8"?>';
        echo '<svg xmlns="http://www.w3.org/2000/svg" width="' . $width . '" height="' . self::HEIGHT
            . '" viewBox="0 0 ' . $width . ' ' . self::HEIGHT . '">';
        // Fond blanc plein : la zone de silence n'a de sens que si elle est
        // reellement blanche, y compris a l'impression.
        echo '<rect x="0" y="0" width="' . $width . '" height="' . self::HEIGHT . '" fill="#ffffff" />';
        echo '<text x="' . $center . '" y="20" text-anchor="middle" font-family="Arial, sans-serif" font-size="13" fill="#000000">'
            . $name . '</text>';
        echo $bars;
        // Texte en clair sous les barres : permet la saisie manuelle si le
        // lecteur ne passe pas (etiquette abimee, ecran trop sombre...).
        echo '<text x="' . $center . '" y="' . (self::BAR_TOP + self::BAR_HEIGHT + 18)
            . '" text-anchor="middle" font-family="monospace" font-size="15" letter-spacing="1" fill="#000000">'
            . $codeSafe . '</text>';
        echo '<text x="' . $center . '" y="' . (self::BAR_TOP + self::BAR_HEIGHT + 40)
            . '" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="#333333">'
            . $sku . ' - ' . $price . '</text>';
        echo '</svg>';
    }
}
