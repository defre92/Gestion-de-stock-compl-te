<?php
declare(strict_types=1);

return [
    'name' => getenv('APP_NAME') ?: 'LM-Code Gestion Stock',
    'env' => getenv('APP_ENV') ?: 'local',
    'debug' => filter_var(getenv('APP_DEBUG') ?: '0', FILTER_VALIDATE_BOOL),
    'timezone' => getenv('APP_TIMEZONE') ?: 'Europe/Paris',
    'frontend_url' => getenv('FRONTEND_URL') ?: 'http://localhost/gestion-stock/frontend',
    'cors_allowed_origins' => array_values(array_filter(array_map(
        static fn (string $origin): string => trim($origin),
        explode(',', getenv('CORS_ALLOWED_ORIGINS') ?: 'http://localhost,http://127.0.0.1,http://localhost:80')
    ))),
];
