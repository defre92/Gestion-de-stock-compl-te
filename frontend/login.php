<?php
declare(strict_types=1);
require_once __DIR__ . '/route-frontend.php';
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Connexion | <?= htmlspecialchars($tenant['company_name'], ENT_QUOTES, 'UTF-8') ?></title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="<?= FRONTEND_BASE_URL ?>/assets/css/clean.css">
    <link rel="icon" type="image/svg+xml" href="<?= FRONTEND_BASE_URL ?>/assets/img/brand/lm-code-monogram.svg">
    <style>:root { --brand-primary: <?= htmlspecialchars($tenant['primary_color'], ENT_QUOTES, 'UTF-8') ?>; }</style>
</head>
<body class="login-body">
    <main class="login-shell">
        <section class="login-card">
            <img class="login-logo" src="<?= htmlspecialchars($tenantLogoUrl, ENT_QUOTES, 'UTF-8') ?>" alt="<?= htmlspecialchars($tenant['company_name'], ENT_QUOTES, 'UTF-8') ?>">
            <p class="eyebrow"><?= htmlspecialchars($tenant['company_name'], ENT_QUOTES, 'UTF-8') ?></p>
            <h1>Connexion securisee</h1>
            <p class="muted">Accede au dashboard centralise et a toutes les operations stock.</p>

            <form id="loginForm" class="form-grid">
                <label>
                    <span>Email</span>
                    <input type="email" name="email" placeholder="vous@exemple.com" required>
                </label>
                <label>
                    <span>Mot de passe</span>
                    <input type="password" name="password" placeholder="********" required>
                </label>
                <button type="submit" class="btn btn-primary">Se connecter</button>
                <p id="loginError" class="error-text" aria-live="polite"></p>
            </form>
        </section>
        <footer class="login-footer">
            <?php if ($tenant['support_email'] !== ''): ?>
                <a href="mailto:<?= htmlspecialchars($tenant['support_email'], ENT_QUOTES, 'UTF-8') ?>">Assistance</a>
            <?php endif; ?>
            <?php if ($tenant['footer_text'] !== ''): ?>
                <span><?= htmlspecialchars($tenant['footer_text'], ENT_QUOTES, 'UTF-8') ?></span>
            <?php endif; ?>
        </footer>
    </main>

    <script nonce="<?= $cspNonce ?>">
        window.APP_CONFIG = {
            apiBaseUrl: <?= json_encode(API_BASE_URL, JSON_UNESCAPED_SLASHES) ?>,
            frontendBaseUrl: <?= json_encode(FRONTEND_BASE_URL, JSON_UNESCAPED_SLASHES) ?>
        };
    </script>
    <script type="module" src="<?= FRONTEND_BASE_URL ?>/assets/js/login.js"></script>
</body>
</html>
