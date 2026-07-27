# Gestion Stock — par Servia

**Solution web complète de gestion de stock, achats et livraisons**, pensée
pour les PME et collectivités qui veulent piloter leurs produits, leurs
fournisseurs et leurs mouvements de stock sans usine à gaz.

> Application web (PHP 8.1+ / MySQL), architecture Clean Architecture,
> déployable en quelques minutes sur un hébergement mutualisé classique
> comme sur un VPS.

---

## En bref

- 📦 **Catalogue produits** complet : catégories, marques, unités, taxes,
  tags personnalisés, et suivi individuel par **numéro de série** pour le
  matériel (avec historique complet — quand et à quel client un exemplaire
  a été vendu).
- 🛒 **Achats pilotés** : une demande d'achat validée se transforme en
  commande fournisseur en un clic (entrepôt, produit, quantité pré-remplis
  automatiquement), avec conversion automatique du statut de la demande.
- 🚚 **Livraisons** : bons de livraison multi-lignes, sortie de stock
  automatique, association optionnelle d'un numéro de série par ligne,
  génération PDF/impression avec logo de votre entreprise.
- 🏬 **Multi-entrepôts** : organisation par zones et emplacements précis,
  mouvements tracés (entrées, sorties, transferts, ajustements, inventaires),
  alertes de rupture et de stock bas.
- 📊 **Tableau de bord** : indicateurs clés cliquables, journal d'audit,
  exports CSV, rapports.
- 🔐 **Sécurité prise au sérieux** : sessions en cookie httpOnly/Secure,
  protection anti brute-force applicative (fonctionne même sans accès
  serveur), rôles utilisateurs granulaires, revue de sécurité complète
  (voir plus bas).
- 🖥️ **Déploiement simple** : installateur web guidé (aucun accès SSH
  requis), chaque client dispose de son propre environnement indépendant.

## Stack technique

| Composant | Choix |
|---|---|
| Backend | PHP 8.1+, architecture en couches (Domain / Application / Infrastructure / Presentation) |
| Base de données | MySQL 8.x, migrations SQL versionnées |
| Frontend | HTML / CSS / JavaScript natif (aucun framework lourd, aucune dépendance de build) |
| Authentification | Sessions cookie httpOnly + Secure + SameSite=Strict |
| Déploiement | Hébergement mutualisé (Apache) ou VPS (Nginx), installateur web sans SSH |

## Pourquoi cette solution

- **Pas de ressaisie** : le parcours demande d'achat → commande → réception
  → livraison est pensé pour éviter les doubles saisies et les erreurs.
- **Traçabilité fine** : jusqu'au numéro de série d'un équipement individuel.
- **Autonomie du client final** : installation et administration 100% via
  navigateur, aucune compétence serveur requise.
- **Isolation totale** : une base de données par client, pas de
  multi-tenant partagé — aucun risque qu'un client accède aux données d'un
  autre.

---

## Sommaire

- [Architecture](#architecture)
- [Fonctionnalités principales](#fonctionnalites-principales)
- [Prérequis](#prerequis)
- [Installation chez un client](#installation-chez-un-client-hebergement-mutualise-ftp-uniquement-sans-ssh)
- [Installation locale (dev)](#installation-locale-wamp-pour-devdemo-uniquement-bdd-jamais-creee)
- [Audit de sécurité effectué](#audit-de-securite-effectue)
- [Tests automatisés](#tests-automatises)

---

## Architecture
- `frontend/`: interface utilisateur (HTML/CSS/JS), aucune logique metier backend.
- `backend/public/index.php`: point d'entree API (`/api/v1/...`).
- `backend/src/Domain`: entites et regles metier.
- `backend/src/Application`: cas d'usage.
- `backend/src/Infrastructure`: persistence, services techniques.
- `backend/src/Presentation`: controleurs HTTP, DTO, validation.
- `database/migrations/up|down`: scripts de migration.
- `database/seeders/pro`: jeux de donnees initiaux.
- `config/database.php`: configuration BDD prioritaire (fichier principal).

## Fonctionnalites principales

- Referentiels: produits (avec tags et numeros de serie), categories, unites, marques, taxes.
- Tiers: fournisseurs et clients.
- Stock: entrees, sorties, transferts, ajustements, inventaires, zones et emplacements.
- Achats: demandes d'achat convertibles en commandes, receptions partielles/totales, suivi des statuts.
- Livraisons: bons de livraison avec numeros de serie, impression/PDF, annulation avec re-credit de stock.
- Pilotage: dashboard KPI cliquable, exports CSV, rapports.
- Administration: roles, utilisateurs, audit.
- Avance: import CSV multi-entites, pieces jointes, etiquettes/code-barres.

## Prerequis
- WAMP (Apache + MySQL) actif.
- PHP 8.1+ recommande.
- MySQL 8.x (ou compatible).
- Extension PDO MySQL active.

## Installation chez un client (hebergement mutualise, FTP uniquement, sans SSH)

Chaque client a son propre hebergement independant (pas de multi-tenant partage).
Tout se fait par navigateur, aucun acces SSH n'est necessaire.

### 1. Uploader le projet
Envoyer tout le contenu du zip a la racine du document root du client (via FTP,
gestionnaire de fichiers cPanel, etc.). Le fichier `.htaccess` a la racine bloque
deja l'acces direct a `config/`, `database/`, `backend/src/`, `backend/bin/`,
`backend/.env` etc. - seuls `frontend/` et `backend/public/` restent accessibles
depuis le web.

### 2. Creer la cle d'installation
Toujours via FTP, creer le fichier `config/install.key` contenant une phrase
secrete de ton choix (une seule ligne, ex: `abc-client-2026-xyz`). Cette cle
empeche qu'un tiers tombant sur la page d'installation avant toi puisse creer
un compte admin a ta place.

### 3. Lancer l'installation
Visiter `https://domaine-du-client.tld/frontend/install.php`. Le formulaire
demande:
- les acces MySQL (host/port/base/utilisateur/mot de passe) - teste la connexion
- les infos du client final: nom, couleur, email de support, logo (upload direct)
- l'URL publique du site (pour le CORS et les liens generes)
- le nom/email/mot de passe de l'administrateur (choisi directement, 10
  caracteres minimum)

Il ecrit `backend/.env`, joue les migrations, cree les roles + l'entrepot par
defaut + le compte admin, et enregistre le logo dans `frontend/assets/img/brand/`.

### 4. Apres l'installation - IMPORTANT
**Supprimer `frontend/install.php` via FTP immediatement apres usage.** Tant
qu'il reste en ligne, quiconque connait (ou devine) la cle d'installation peut
le relancer. Une reconfiguration nécessite de toute facon de recreer
`config/install.key` (il est supprime automatiquement apres chaque installation
reussie), ce qui offre une double protection meme si l'oubli de suppression
du fichier arrive.

### A verifier apres l'installation
- Que l'utilisateur systeme du serveur web (souvent `www-data`) a bien les
  droits d'ecriture sur `config/`, `backend/` (pour `.env`),
  `backend/public/uploads/` et `frontend/assets/img/brand/` - sinon
  l'installateur echoue avec une erreur explicite.
- Tester que `https://domaine/backend/.env`, `https://domaine/config/database.php`
  et `https://domaine/README.md` renvoient bien une erreur 403 (pas le contenu).
- Tester qu'une requete en `http://` (sans s) redirige bien en 301 vers `https://`
  (force par le `.htaccess` racine, ou par `nginx-gestion-stock.conf.example`
  sous Nginx). Necessite un certificat SSL valide sur le domaine du client
  (Let's Encrypt, ou fourni par l'hebergeur).
- Sur Apache: `backend/public/uploads/.htaccess` doit etre pris en compte,
  le vhost doit avoir `AllowOverride All` (quasi toujours le cas en mutualise
  cPanel).
- **Sur Nginx (VPS que tu administres):** les fichiers `.htaccess` ne sont pas
  lus du tout - `backend/.env`, `config/`, `database/` etc. ne sont PAS
  proteges par defaut. `nginx-gestion-stock.conf.example` (a la racine du
  projet, fourni comme reference/modele) contient la conf complete
  (blocage des dossiers sensibles, execution PHP interdite dans
  `backend/public/uploads/`, routage API, HTTPS force + HSTS), testee en local
  (nginx + php-fpm reels) avant livraison.

  **Important: ce fichier ne "s'active" pas juste en le laissant dans le
  projet** (contrairement au `.htaccess` Apache, qui est lu automatiquement).
  Nginx lit sa configuration depuis `/etc/nginx/`, pas depuis le dossier du
  site. Procedure sur le VPS:
  ```bash
  # 1. Prerequis (si pas deja installes)
  apt install nginx php-fpm php-mysql php-curl php-mbstring php-xml \
      mariadb-server certbot python3-certbot-nginx

  # 2. Copier la conf dans le dossier nginx (pas dans le projet)
  cp nginx-gestion-stock.conf.example /etc/nginx/sites-available/gestion-stock-client.conf
  # editer: server_name, root (chemin reel de deploiement), socket php-fpm

  # 3. Activer le site
  ln -s /etc/nginx/sites-available/gestion-stock-client.conf /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx

  # 4. Domaine + SSL: DNS (enregistrement A vers l'IP du VPS) puis
  certbot --nginx -d domaine-du-client.tld
  ```
  `certbot` s'occupe de generer le certificat et d'ajuster les chemins
  `ssl_certificate`/`ssl_certificate_key` dans la conf automatiquement.

### Protection contre le brute-force (deja en place)
Le login applique un rate-limiting cote application (table `login_attempts`,
migration `202602270004`): **5 echecs** sur une fenetre glissante de **15
minutes** (par email ET par IP) declenchent un blocage temporaire (HTTP 429).
Aucune configuration supplementaire n'est necessaire, et **ca fonctionne sur
n'importe quel hebergement, y compris mutualise** (pur PHP/MySQL, aucun acces
serveur requis).

Le bloc `limit_req_zone` de `nginx-gestion-stock.conf.example` est une couche
**supplementaire optionnelle**, uniquement utilisable si tu administres toi
meme le nginx (VPS/serveur dedie) - inapplicable sur un hebergement mutualise
classique ou tu n'as pas la main sur la conf serveur. Ce n'est pas un
probleme: la protection ci-dessus (deja active par defaut) suffit pour ce cas
de figure.


## Installation locale WAMP (pour dev/demo uniquement, BDD jamais creee)
1. Copier le projet dans `c:\wamp64\www\gestion-stock`.
2. Demarrer WAMP et verifier que `Apache` + `MySQL` sont en vert.
3. Creer la base vide (phpMyAdmin ou SQL):

```sql
CREATE DATABASE IF NOT EXISTS gestion_stock
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

4. Configurer les acces MySQL dans `config/database.php`.

Exemple:

```php
return [
    'host' => '127.0.0.1',
    'port' => 3306,
    'dbname' => 'gestion_stock',
    'username' => 'root',
    'password' => '',
    'charset' => 'utf8mb4',
];
```

## Audit de securite effectue

En vue d'une revente a des clients finaux, une revue complete a ete faite (pas
un simple echantillonnage) sur les points suivants:

**Injection SQL** - les 28 repositories du dossier
`backend/src/Infrastructure/Persistence/` ont ete relus un par un. Toutes les
requetes passent par des requetes preparees avec parametres lies. Les rares
endroits ou un nom de colonne est insere dynamiquement dans le SQL (tri,
filtres) sont systematiquement verifies contre une liste blanche codee en dur
(`$filterable`/`$fillable`) avant interpolation - jamais une valeur venant
directement de la requete HTTP. Aucune injection trouvee.

**XSS (injection dans le DOM)** - les 3 fichiers JS du frontend
(`app-clean.js`, `http-client.js`, `login.js`) ont ete relus integralement.
Toutes les donnees utilisateur affichees passent par une fonction `sanitize()`
qui echappe `&<>"'`, y compris les champs les plus a risque (description
produit, notes, noms). Aucun `eval()`, `document.write()` ni construction
dangereuse trouvee.

**Telechargement de fichiers** (`AttachmentController`, `ProductMediaController`):
ajout du header `X-Content-Type-Options: nosniff` (empeche un navigateur de
re-interpreter un fichier different de son type declare) et passage en
`Content-Disposition: attachment` pour tout ce qui n'est pas une image/PDF
(au lieu de `inline` pour tout, y compris les documents Office/CSV).

**Upload de logo SVG** (installateur web): la validation ne bloquait que la
balise `<script>` - elargie pour bloquer aussi les gestionnaires d'evenements
(`onload=`, `onerror=`...), les URLs `javascript:` et les balises
`<foreignObject>`, qui peuvent aussi executer du JS dans un SVG ouvert
directement (le risque reste faible en pratique puisque le logo n'est
affiche que via une balise `<img>`, qui neutralise l'execution de script dans
les SVG - mais autant fermer la porte).

**Authentification**: mise a jour (voir aussi la 2e passe plus bas) - jeton de
session en cookie `httpOnly` + `Secure` + `SameSite=Strict`, plus jamais
accessible en JS (un XSS ne peut plus le voler). `SameSite=Strict` sert de
protection CSRF principale, viable car frontend et API sont servis depuis le
meme domaine (voir `nginx-gestion-stock.conf.example`).

**Isolation des donnees**: une base de donnees = un client (voir plus haut,
pas de multi-tenant partage) - aucun risque qu'un client A accede aux donnees
d'un client B.

- Fichier principal: `config/database.php`
- Fallback backend: `backend/config/database.php`

Champs a renseigner:
- `username` = login MySQL
- `password` = mot de passe MySQL
- `dbname` = nom de la base
- `host` et `port` selon votre serveur

### 2e passe de durcissement (post-livraison client)

En plus de ce qui precede:

- **Cookie httpOnly** remplace le jeton `Bearer` en `localStorage` (voir
  ci-dessus) - `AuthCookie`, `AuthMiddleware`, `http-client.js`.
- **Expiration glissante des sessions** (30 jours d'inactivite max) au lieu
  de jetons illimites - `AuthService::TOKEN_TTL_DAYS`.
- **Content-Security-Policy** avec nonce par requete (aucun `unsafe-inline`
  sur les scripts) + `X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy` - `route-frontend.php`, `backend/public/index.php`,
  `nginx-gestion-stock.conf.example`.
- **Rate limiting nginx** dedie sur `/auth/login` (5 req/min/IP), en plus du
  blocage applicatif deja documente ci-dessus.
- **`APP_DEBUG`** desactive par defaut si absent du `.env` (fail-safe), au
  lieu d'etre active par defaut.
- **`.htaccess` racine** durci: bloque generiquement tout fichier cache
  (`.gitignore`, etc.), pas seulement une liste d'extensions.
- **Reinitialisation de mot de passe par un admin** (fiche utilisateur) et
  **changement de mot de passe personnel** (self-service, "Mon compte"):
  toutes deux invalident les sessions actives de l'utilisateur concerne
  apres coup.
- **Journal d'audit** consultable dans l'UI (admin uniquement): qui a fait
  quoi, filtrable par utilisateur/action.
- **Seed de demo** (`database/seeders/`, mot de passe admin partage entre
  environnements de demo LM-Code): a **exclure systematiquement des
  livraisons clients** - reserve a l'usage interne, voir avertissement en
  tete de `database/seeders/pro/202602270001_seed_core_data.sql`.
- **Suite de tests automatises** sur les briques d'authentification/securite
  (voir section Tests plus bas).
- **Compatibilite hebergement mutualise**: `PasswordService` et
  `frontend/install.php` basculent automatiquement sur bcrypt si Argon2id
  n'est pas disponible (extension `sodium` souvent absente sur du mutualise
  bas de gamme) - sans ce fallback, la creation du premier compte admin
  plantait avec une erreur fatale sur ce type d'hebergement.

## Migrations et seed (dev/demo uniquement)
Depuis la racine du projet:

```bash
php backend/bin/migrate.php up
php backend/bin/seed.php
```

Le seed charge des donnees de DEMONSTRATION (produits, fournisseurs factices)
et un compte admin dont le mot de passe est fixe et partage entre tous les
environnements de demo LM-Code (voir avertissement en tete de
`database/seeders/pro/202602270001_seed_core_data.sql`): **a n'utiliser que
pour du dev/demo local, jamais pour un client reel** (utiliser
`frontend/install.php` pour ca, voir plus haut). `seed.php` refuse de
s'executer si `APP_ENV=production` sauf a forcer avec `--force`.

**Important**: le dossier `database/seeders/` est un outil interne. Il ne
doit **jamais** faire partie d'une livraison a un client final - a exclure
systematiquement de tout export/zip destine a un tiers.

Commandes utiles:

```bash
php backend/bin/migrate.php status
php backend/bin/migrate.php down
php backend/bin/migrate.php fresh
```

## Tests automatises
Suite de tests maison (pas de Composer/PHPUnit, coherent avec le reste du
projet), concentree sur les briques d'authentification/securite. Ne
necessite **aucune base de donnees** (la connexion PDO n'est ouverte que
dans les repositories, jamais au chargement):

```bash
php backend/tests/run.php
```

Couvre: hachage/verification des mots de passe (Argon2id, salage),
generation/hachage des jetons de session, controle d'acces par role
(`RoleMiddleware`), extraction du jeton Bearer et des cookies (`Request`).

## Lancer et tester manuellement (dev local)
- Login: `http://localhost/gestion-stock/frontend/login.php`
- App: `http://localhost/gestion-stock/frontend/index.php`
- API health: `http://localhost/gestion-stock/backend/public/api/v1/health`

---

## Projet initial de LM-Code 
Site LM-Code: https://lm-code.be
Tutoriel complet LM-Code: https://lm-code.be/tutoriel-app-gestion-stock-php-mysql/
GitHub LM-Code: https://github.com/LM-Code-Be/
Contact: https://lm-code.be/contact/
Code source projet: https://github.com/LM-Code-Be/gestion-stock

## Projet amélioré et finalisé par servia
web: https://servia.fr
Code source projet: https://github.com/defre92/Gestion-de-stock-compl-te)


---
