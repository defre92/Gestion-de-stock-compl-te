<?php
declare(strict_types=1);

// Identite visuelle et infos du client final.
// Ce fichier est (re)genere automatiquement par frontend/install.php.
// Ne pas versionner la version personnalisee dans un depot public partage.
return [
    'company_name' => getenv('TENANT_NAME') ?: 'Gestion Stock',
    'logo_file' => getenv('TENANT_LOGO_FILE') ?: null, // ex: 'custom-logo.png', relatif a frontend/assets/img/brand/
    'theme' => getenv('TENANT_THEME') ?: 'emeraude', // voir config/themes.php pour les cles valides
    'support_email' => getenv('TENANT_SUPPORT_EMAIL') ?: '',
    'footer_text' => getenv('TENANT_FOOTER_TEXT') ?: '',
];
