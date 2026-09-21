<?php
declare(strict_types=1);

/**
 * Catalogue des themes de couleur de l'application.
 *
 * Choisi a l'installation, modifiable ensuite dans Parametres > Apparence
 * (frontend/assets/js/app-clean.js) sans reinstaller. Chaque theme fixe
 * trois choses : la couleur principale (boutons, liens, elements actifs),
 * une couleur secondaire (fond degrade du tableau de bord) et les 3 teintes
 * du degrade de la barre laterale - le tout gere par variables CSS dans
 * frontend/assets/css/clean.css (voir les blocs [data-theme="..."]).
 *
 * Ce fichier est la source de verite cote serveur : route-frontend.php et
 * install.php n'acceptent que les cles listees ici. Le front-end (app-clean.js,
 * THEME_CATALOG) affiche le meme catalogue sous forme de vignettes a
 * choisir - toute cle ajoutee/retiree ici doit l'etre aussi la-bas.
 */
return [
    'emeraude' => [
        'label' => 'Emeraude',
        'primary' => '#0f8f74',
        'secondary' => '#0f4f78',
        'sidebar' => ['#0d2532', '#0d443d', '#0e3b5a'],
    ],
    'ocean' => [
        'label' => 'Ocean',
        'primary' => '#2563eb',
        'secondary' => '#0ea5e9',
        'sidebar' => ['#0b1e3a', '#0d2f52', '#0b3a63'],
    ],
    'violet' => [
        'label' => 'Violet',
        'primary' => '#7c3aed',
        'secondary' => '#a855f7',
        'sidebar' => ['#1e1033', '#2d1854', '#3a1f6e'],
    ],
    'ardoise' => [
        'label' => 'Ardoise',
        'primary' => '#475569',
        'secondary' => '#64748b',
        'sidebar' => ['#0f172a', '#1e293b', '#334155'],
    ],
    'rubis' => [
        'label' => 'Rubis',
        'primary' => '#dc2626',
        'secondary' => '#b91c1c',
        'sidebar' => ['#2a0e0e', '#4a1414', '#5c1a1a'],
    ],
    'ambre' => [
        'label' => 'Ambre',
        'primary' => '#d97706',
        'secondary' => '#b45309',
        'sidebar' => ['#2a1a06', '#452b0a', '#5c380d'],
    ],
    'framboise' => [
        'label' => 'Framboise',
        'primary' => '#db2777',
        'secondary' => '#be185d',
        'sidebar' => ['#2a0e1c', '#4a1430', '#5c1a3c'],
    ],
    'indigo' => [
        'label' => 'Indigo (nuit)',
        'primary' => '#4f46e5',
        'secondary' => '#4338ca',
        'sidebar' => ['#0e1029', '#191c47', '#22265c'],
    ],
];
