<?php
declare(strict_types=1);

namespace App\Presentation\Controllers;

use App\Infrastructure\Persistence\ProductRepository;
use App\Shared\Http\JsonResponse;

final class BarcodeController
{
    public function __construct(private readonly ProductRepository $productRepository)
    {
    }

    public function productLabelSvg(int $id): void
    {
        $product = $this->productRepository->findById($id);
        if (!$product) {
            JsonResponse::send(['message' => 'Product not found'], 404);
            return;
        }

        $code = trim((string)($product['barcode'] ?? ''));
        if ($code === '') {
            $code = trim((string)($product['sku'] ?? ''));
        }

        if ($code === '') {
            JsonResponse::send(['message' => 'No barcode or sku on product'], 422);
            return;
        }

        $bars = '';
        $x = 20;
        $pattern = $this->codePattern($code);
        foreach (str_split($pattern) as $bit) {
            $width = $bit === '1' ? 3 : 1;
            if ($bit === '1') {
                $bars .= '<rect x="' . $x . '" y="20" width="' . $width . '" height="90" fill="#111111" />';
            }
            $x += $width + 1;
        }

        $name = htmlspecialchars((string)$product['name'], ENT_QUOTES, 'UTF-8');
        $codeSafe = htmlspecialchars($code, ENT_QUOTES, 'UTF-8');
        $price = number_format((float)($product['unit_price'] ?? 0), 2, '.', ' ');

        header('Content-Type: image/svg+xml; charset=utf-8');
        echo '<?xml version="1.0" encoding="UTF-8"?>';
        echo '<svg xmlns="http://www.w3.org/2000/svg" width="520" height="180" viewBox="0 0 520 180">';
        echo '<rect x="0" y="0" width="520" height="180" fill="#ffffff" stroke="#d6d6d6" />';
        echo '<text x="20" y="16" font-family="Arial, sans-serif" font-size="12" fill="#444444">' . $name . '</text>';
        echo $bars;
        echo '<text x="20" y="130" font-family="monospace" font-size="14" fill="#111111">' . $codeSafe . '</text>';
        echo '<text x="20" y="155" font-family="Arial, sans-serif" font-size="14" fill="#111111">Prix: ' . $price . '</text>';
        echo '</svg>';
    }

    private function codePattern(string $code): string
    {
        $pattern = '';
        foreach (str_split($code) as $char) {
            $ascii = ord($char);
            $bits = str_pad(decbin($ascii), 8, '0', STR_PAD_LEFT);
            $pattern .= $bits . '0';
        }

        return $pattern;
    }
}
