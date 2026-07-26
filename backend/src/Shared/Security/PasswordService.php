<?php
declare(strict_types=1);

namespace App\Shared\Security;

final class PasswordService
{
    public function hash(string $plain): string
    {
        return password_hash($plain, $this->preferredAlgorithm());
    }

    public function verify(string $plain, string $hashed): bool
    {
        return password_verify($plain, $hashed);
    }

    /**
     * Argon2id est preferable (resistant aux attaques GPU/ASIC) mais
     * necessite que PHP soit compile avec le support argon2 (extension
     * sodium) - souvent absent sur des hebergements mutualises bas de
     * gamme, la cible principale de ce projet (voir README "sans SSH").
     * On bascule automatiquement sur bcrypt si Argon2id n'est pas
     * disponible. password_verify() lit l'algorithme directement dans le
     * hash stocke, donc aucune migration n'est necessaire meme si
     * l'hebergement change plus tard (les deux formats cohabitent sans
     * probleme dans la meme colonne password_hash).
     */
    private function preferredAlgorithm(): string
    {
        if (defined('PASSWORD_ARGON2ID') && in_array(PASSWORD_ARGON2ID, password_algos(), true)) {
            return PASSWORD_ARGON2ID;
        }

        return PASSWORD_BCRYPT;
    }
}