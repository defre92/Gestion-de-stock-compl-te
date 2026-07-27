<?php
declare(strict_types=1);

namespace App\Shared\Http;

use JsonException;

final class JsonResponse
{
    public static function send(array $payload, int $status = 200): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        // Une reponse API (surtout une liste comme GET /products) ne doit
        // jamais etre mise en cache par le navigateur ou un proxy
        // intermediaire: sinon un rafraichissement juste apres une creation/
        // modification peut resservir une version perimee.
        header('Cache-Control: no-store, no-cache, must-revalidate');
        header('Pragma: no-cache');

        try {
            echo json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        } catch (JsonException) {
            echo '{"message":"JSON encoding error"}';
        }
    }

    public static function empty(int $status = 204): void
    {
        http_response_code($status);
    }
}