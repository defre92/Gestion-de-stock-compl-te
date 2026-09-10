<?php
declare(strict_types=1);

namespace App\Application\Services;

/**
 * Encodeur Code 128 (norme ISO/IEC 15417).
 *
 * Pourquoi cette classe existe : l'etiquette produit dessinait auparavant des
 * barres a partir des bits ASCII bruts du code. Le resultat RESSEMBLAIT a un
 * code barre mais n'en etait pas un - ni caractere de depart, ni cle de
 * controle, ni zone de silence, ni largeurs normalisees. AUCUNE douchette ne
 * pouvait le lire. Une etiquette illisible par un lecteur n'a aucun interet.
 *
 * Le Code 128 est le symbole le plus adapte a un stock : il accepte les
 * lettres comme les chiffres (donc un SKU du type "MAT-PLAN-001"), il est
 * dense, et tous les lecteurs du commerce le decodent sans configuration.
 *
 * Deux jeux sont utilises :
 *  - jeu C pour un code entierement numerique de longueur paire (deux chiffres
 *    par symbole : moitie moins large, utile pour un EAN a 13 chiffres) ;
 *  - jeu B sinon, qui couvre l'ASCII imprimable (espace a ~).
 */
final class Code128Encoder
{
    /**
     * Les 107 motifs de la norme. Chaque motif donne les largeurs, en modules,
     * des 6 elements du symbole, en alternant barre / espace en commencant par
     * une barre. Le dernier (valeur 106, STOP) en compte 7.
     *
     * @var string[]
     */
    private const PATTERNS = [
        '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213',
        '221312', '231212', '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132',
        '221231', '213212', '223112', '312131', '311222', '321122', '321221', '312212', '322112', '322211',
        '212123', '212321', '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313',
        '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', '313121', '211331',
        '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111',
        '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214',
        '112412', '122114', '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111',
        '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', '421211', '212141',
        '214121', '412121', '111143', '111341', '131141', '114113', '114311', '411113', '411311', '113141',
        '114131', '311141', '411131', '211412', '211214', '211232', '2331112',
    ];

    private const START_B = 104;
    private const START_C = 105;
    private const STOP = 106;

    /**
     * Suite de largeurs (barre, espace, barre, ...) du symbole complet, zones
     * de silence exclues.
     *
     * @return int[]
     * @throws \InvalidArgumentException si le code contient un caractere non
     *         encodable en jeu B (hors ASCII imprimable).
     */
    public function widths(string $code): array
    {
        $values = $this->values($code);

        // Cle de controle : (valeur de depart + somme des valeurs ponderees par
        // leur position) modulo 103. Sans elle, le lecteur rejette le symbole.
        $checksum = $values[0];
        foreach (array_slice($values, 1) as $index => $value) {
            $checksum += $value * ($index + 1);
        }
        $values[] = $checksum % 103;
        $values[] = self::STOP;

        $widths = [];
        foreach ($values as $value) {
            foreach (str_split(self::PATTERNS[$value]) as $width) {
                $widths[] = (int)$width;
            }
        }

        return $widths;
    }

    /**
     * Valeurs des symboles, caractere de depart inclus, cle et STOP exclus.
     *
     * @return int[]
     */
    private function values(string $code): array
    {
        if ($code === '') {
            throw new \InvalidArgumentException('Code vide : rien a encoder.');
        }

        // Jeu C : deux chiffres par symbole. Interessant des 4 chiffres, et
        // seulement en longueur paire (sinon il faudrait basculer de jeu en
        // cours de route, complexite inutile ici).
        if (preg_match('/^\d+$/', $code) === 1 && strlen($code) % 2 === 0 && strlen($code) >= 4) {
            $values = [self::START_C];
            foreach (str_split($code, 2) as $pair) {
                $values[] = (int)$pair;
            }

            return $values;
        }

        $values = [self::START_B];
        foreach (str_split($code) as $char) {
            $ascii = ord($char);
            if ($ascii < 32 || $ascii > 126) {
                throw new \InvalidArgumentException(
                    'Caractere non encodable en Code 128 : ' . $char . ' (seul l\'ASCII imprimable est accepte).'
                );
            }
            $values[] = $ascii - 32;
        }

        return $values;
    }
}
