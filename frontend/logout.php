<?php
declare(strict_types=1);
require_once __DIR__ . '/route-frontend.php';
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <title>Deconnexion...</title>
    <script nonce="<?= $cspNonce ?>">
        // Le token vit dans un cookie httpOnly: on ne peut pas le supprimer en
        // JS, il faut appeler l'API pour qu'elle le revoque cote serveur et
        // efface le cookie (Set-Cookie expire). On redirige ensuite dans tous
        // les cas (session deja expiree, API injoignable, etc.).
        try { localStorage.removeItem('gs_user'); } catch (_) {}
        try { sessionStorage.removeItem('gs_user'); } catch (_) {}

        const apiBaseUrl = <?= json_encode(API_BASE_URL, JSON_UNESCAPED_SLASHES) ?>;
        const loginUrl = <?= json_encode(FRONTEND_BASE_URL . '/login.php', JSON_UNESCAPED_SLASHES) ?>;

        fetch(`${apiBaseUrl}/auth/logout`, { method: 'POST', credentials: 'include' })
            .catch(() => {})
            .finally(() => {
                window.location.replace(loginUrl);
            });
    </script>
</head>
<body></body>
</html>
