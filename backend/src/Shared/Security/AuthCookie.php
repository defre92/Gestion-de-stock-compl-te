<?php
declare(strict_types=1);

namespace App\Shared\Security;

/**
 * Le token de session vit desormais uniquement dans un cookie httpOnly, jamais
 * accessible en JS (protection contre le vol de session via XSS). SameSite=Strict
 * sert de defense principale contre le CSRF: le frontend et l'API sont servis
 * depuis le meme domaine (voir nginx-gestion-stock.conf.example), donc le
 * navigateur n'envoie ce cookie que pour des requetes emises depuis ce site.
 */
final class AuthCookie
{
    public const NAME = 'gs_token';

    /** Duree de vie du cookie cote navigateur (doit rester coherente avec AuthService::TOKEN_TTL_DAYS). */
    private const TTL_DAYS = 30;

    public static function issue(string $token): void
    {
        self::set($token, time() + (self::TTL_DAYS * 86400));
    }

    public static function forget(): void
    {
        self::set('', time() - 3600);
    }

    private static function set(string $value, int $expires): void
    {
        if (headers_sent()) {
            return;
        }

        // En local (APP_ENV=local, cf. .env.example) le serveur tourne souvent
        // en simple HTTP: le flag Secure y est desactive pour ne pas bloquer les
        // tests, il reste actif par defaut (production) des que APP_ENV change.
        $secure = (getenv('APP_ENV') ?: 'production') !== 'local';

        setcookie(self::NAME, $value, [
            'expires' => $expires,
            'path' => '/',
            'domain' => '',
            'secure' => $secure,
            'httponly' => true,
            'samesite' => 'Strict',
        ]);
    }
}
