# Gestion Stock - Servia

Application de gestion de stock professionnelle avec separation stricte Frontend/API, structure orientee Clean Architecture, migrations SQL versionnees et interface moderne en francais.

## Identite projet
- Nom produit: `Gestion Stock`
- Societe: `Servia`

## Architecture
- `frontend/`: interface utilisateur (HTML/CSS/JS), aucune logique metier backend.
- `backend/public/index.php`: point d'entree API (`/api/v1/...`).
- `backend/src/Domain`: entites et regles metier.
- `backend/src/Application`: cas d'usage.
- `backend/src/Infrastructure`: persistence, services techniques.
- `backend/src/Presentation`: controleurs HTTP, DTO, validation.
- `database/migrations/up|down`: scripts de migration.
- `database/seeders/pro`: jeux de donnees internes de developpement (usage
  interne uniquement, jamais deploye - voir section Seed interne plus bas).
- `database/demo/catalog-demo.sql`: donnees de demo catalogue, utilisees par
  `frontend/demo-data.php` (voir section dediee).
- `config/database.php`: configuration BDD prioritaire (fichier principal).

## Fonctionnalites principales

- Referentiels: produits, categories, unites, marques, taxes, tags.
- Variantes produit (optionnel): taille/couleur **ou** millesime/contenance
  par produit, stock et mouvements suivis par variante. Voir section dediee
  plus bas.
- Tiers: fournisseurs et clients.
- Stock: entrees, sorties, transferts, ajustements, inventaires.
- Achats: commandes, receptions partielles/totales, suivi des statuts.
- Pilotage: dashboard KPI, exports CSV, rapports.
- Administration: roles, utilisateurs, audit.
- Avance: import CSV multi-entites, pieces jointes, etiquettes/code-barres.

## Variantes produit - optionnel, 2 "saveurs" disponibles

Fonctionnalite optionnelle pour les catalogues avec variantes. Desactivee
par defaut, elle ne change rien pour une installation qui n'en a pas besoin.
**Deux options independantes**, chacune activable ou non selon l'activite
concernee :

- `clothing_variants_enabled` = `1` : taille + couleur — couvre le
  pret-a-porter **et** la chaussure (la pointure va simplement dans le
  champ "Taille / Pointure", pas besoin d'une option separee).
- `bottle_variants_enabled` = `1` : millesime + contenance en cl (vins,
  spiritueux, boissons).

Les deux cles se creent dans l'ecran Parametres. Des qu'au moins une des
deux est activee, l'entree "Variantes" apparait dans le menu lateral sous
**Referentiels**, juste apres Produits - avec un seul et meme module (pas
deux ecrans separes) : chaque variante ne remplit que les champs qui la
concernent (taille/couleur OU millesime/contenance), les autres restent
vides. Le module reste masque si aucune des deux n'est activee.

Le formulaire suit la meme regle : le champ "Ce produit a des variantes"
n'apparait sur la fiche produit que si au moins une option est active, et
son libelle s'adapte a l'option reellement activee (taille/couleur,
millesime/contenance, ou les deux). Les champs de la variante elle-meme
(taille, couleur / millesime, contenance) n'apparaissent que dans le module
Variantes, jamais dans le formulaire produit : un produit porte **plusieurs**
variantes, il ne peut donc pas les saisir sur sa propre fiche.

**Parcours de saisie** : creer le produit avec "Ce produit a des variantes =
Oui" -> le message de confirmation propose directement un bouton "Ajouter les
variantes" qui ouvre le module deja filtre sur ce produit -> creer les
variantes -> enregistrer les mouvements de stock, le selecteur de variante
apparaissant automatiquement dans le formulaire de mouvement. Tant qu'un
produit a variantes n'a aucune variante, aucun mouvement ne peut etre
enregistre dessus (controle cote backend).

**Generation en lot** : le module Variantes propose un panneau "Generer des
variantes en lot". On choisit le produit, on saisit les listes de valeurs
separees par des virgules (tailles et couleurs, et/ou millesimes et
contenances) et le generateur cree toutes les combinaisons. Un vetement en
5 tailles x 4 couleurs = 20 variantes en une operation au lieu de 20 saisies.

- Le prefixe des SKU se pre-remplit avec le SKU du produit et reste
  modifiable ; chaque SKU est construit comme `PREFIXE-TAILLE-COULEUR`
  (accents supprimes, majuscules), par exemple `TSHIRT-001-M-ROUGE`.
- Le bouton **Previsualiser** affiche la liste complete avant toute
  ecriture, avec pour chaque ligne son etat ("a creer" ou "existe deja -
  ignoree"). La generation ne porte que sur ce qui a ete affiche.
- Relancer un lot elargi ne cree aucun doublon : les SKU deja presents sur
  le produit sont ignores.
- Le produit est automatiquement marque `has_variants = 1` si ce n'etait pas
  deja le cas, sans quoi le selecteur de variante n'apparaitrait pas dans les
  mouvements de stock.
- Plafond de 200 combinaisons par lot, pour eviter une saisie accidentelle
  qui lancerait des milliers de creations.

Techniquement, le generateur est **entierement cote frontend** : il enchaine
les memes `POST /product-variants` que le formulaire unitaire, une requete par
combinaison. Aucune route ni migration supplementaire. La contrepartie est
qu'un lot peut aboutir partiellement (coupure reseau, SKU en conflit) : le
rapport de fin liste alors precisement les echecs, et il suffit de relancer le
lot, les variantes deja creees etant ignorees.

**Pourquoi une seule table plutot que deux** : le stock, les mouvements,
les alertes, les livraisons, les achats et les inventaires ne raisonnent
tous qu'en `variant_id` - ils sont deja entierement agnostiques du type
d'attribut. Reutiliser `product_variants` pour les deux "saveurs" evite de
dupliquer toute cette mecanique (et donc tous les bugs potentiels) pour
chaque nouveau type de variante qu'on voudrait ajouter plus tard (ex:
pointure pour la chaussure, format pour l'electromenager...).

**Par produit** : chaque produit choisit individuellement s'il utilise des
variantes (case "Ce produit a des variantes" sur sa fiche,
`products.has_variants`). Un catalogue mixte (certains produits avec
variantes, d'autres sans, voire un melange vetement/bouteille) est le cas
normal.

**Modele de donnees** : table `product_variants` (SKU propre, code-barre,
taille, couleur, millesime, contenance en cl, prix optionnel qui surcharge
celui du produit, `attributes_json` en reserve pour d'autres attributs
futurs sans nouvelle migration). `stock_levels`, `stock_movements` et
`stock_alerts` ont tous une colonne `variant_id` nullable : le stock,
l'historique des mouvements et les alertes de stock bas sont donc suivis
par variante quand elle est renseignee.

**Ce qui est deja variant-aware** : creation/edition de variantes (module
dedie), mouvements de stock (IN/OUT/ADJUSTMENT/TRANSFER, y compris depuis
la fiche produit), alertes de stock bas par variante, livraisons (creation
+ annulation, selecteur de variante dans le formulaire), demandes et
commandes d'achat (creation + reception, selecteur de variante dans le
formulaire), sessions d'inventaire (comptage + finalisation cote backend -
le calcul d'ecart distingue bien deux variantes du meme produit comptees
dans la meme session).

**Pas encore variant-aware (limitation connue)** : le formulaire frontend
de saisie d'un comptage d'inventaire n'expose pas encore de selecteur de
variante (le backend l'accepte via `variant_id` dans le payload JSON, mais
l'ecran ne le propose pas encore). A completer si le besoin se confirme.

## Prerequis
- WAMP (Apache + MySQL) actif.
- PHP 8.1+ recommande.
- MySQL 8.x (ou compatible).
- Extension PDO MySQL active.

## Installation (hebergement mutualise, FTP uniquement, sans SSH)

Chaque installation a son propre hebergement independant (pas de multi-tenant partage).
Tout se fait par navigateur, aucun acces SSH n'est necessaire.

### 1. Uploader le projet
Envoyer tout le contenu du zip a la racine du document root cible (via FTP,
gestionnaire de fichiers cPanel, etc.). Le fichier `.htaccess` a la racine bloque
deja l'acces direct a `config/`, `database/`, `backend/src/`, `backend/bin/`,
`backend/.env` etc. - seuls `frontend/` et `backend/public/` restent accessibles
depuis le web.

### 2. Creer la cle d'installation
Toujours via FTP, creer le fichier `config/install.key` contenant une phrase
secrete de ton choix (une seule ligne, ex: `abc-install-2026-xyz`). Cette cle
empeche qu'un tiers tombant sur la page d'installation avant toi puisse creer
un compte admin a ta place.

### 3. Lancer l'installation
Visiter `https://ton-domaine.tld/frontend/install.php`. Le formulaire
demande:
- les acces MySQL (host/port/base/utilisateur/mot de passe) - teste la connexion
- les infos de l'organisation: nom, couleur, email de support, logo (upload direct)
- l'URL publique du site (pour le CORS et les liens generes)
- le nom/email/mot de passe de l'administrateur (choisi directement, 10
  caracteres minimum)

Il ecrit `backend/.env`, joue les migrations, cree les roles + l'entrepot par
defaut + le compte admin + des reglages par defaut dans `app_settings`
(devise EUR, langue fr, fuseau Europe/Paris, stock min. 10, format de
numerotation `{PREFIX}-{YEAR}-{SEQ}`, valorisation par defaut CUMP, variantes
vetement/chaussure et bouteille desactivees par defaut - modifiables ensuite depuis l'ecran
Parametres, jamais ecrases si l'installateur est relance sur une base
existante), et enregistre le logo dans `frontend/assets/img/brand/`.

### 4. Apres l'installation - IMPORTANT
**Supprimer `frontend/install.php` via FTP immediatement apres usage.**

Trois protections se cumulent desormais, mais aucune ne remplace la
suppression du fichier :

1. **Verrou dur** : des que `config/.installed` existe, `install.php` refuse
   categoriquement de s'executer et renvoie une page 403. Il n'y a plus
   d'option "reconfigurer quand meme". Pour reinstaller volontairement il
   faut supprimer `config/.installed` via FTP - ce qui suppose un acces
   serveur, donc d'etre l'exploitant de l'instance.
2. **Cle d'installation** : `config/install.key` est supprime automatiquement
   apres chaque installation reussie, et sans lui la page n'affiche que les
   instructions de creation de la cle.
3. **Anti-brute-force** : chaque tentative de cle incorrecte est ralentie de
   500 ms.

### A verifier apres l'installation
- Que l'utilisateur systeme du serveur web (souvent `www-data`) a bien les
  droits d'ecriture sur `config/`, `backend/` (pour `.env`),
  `backend/public/uploads/` et `frontend/assets/img/brand/` - sinon
  l'installateur echoue avec une erreur explicite.
- Tester que `https://domaine/backend/.env`, `https://domaine/config/database.php`
  et `https://domaine/README.md` renvoient bien une erreur 403 (pas le contenu).
- Tester qu'une requete en `http://` (sans s) redirige bien en 301 vers `https://`
  (force par le `.htaccess` racine, ou par `nginx-gestion-stock.conf.example`
  sous Nginx). Necessite un certificat SSL valide sur le domaine cible
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
  (nginx + php-fpm reels) avant deploiement.

  **Important: ce fichier ne "s'active" pas juste en le laissant dans le
  projet** (contrairement au `.htaccess` Apache, qui est lu automatiquement).
  Nginx lit sa configuration depuis `/etc/nginx/`, pas depuis le dossier du
  site. Procedure sur le VPS:
  ```bash
  # 1. Prerequis (si pas deja installes)
  apt install nginx php-fpm php-mysql php-curl php-mbstring php-xml \
      mariadb-server certbot python3-certbot-nginx

  # 2. Copier la conf dans le dossier nginx (pas dans le projet)
  cp nginx-gestion-stock.conf.example /etc/nginx/sites-available/gestion-stock.conf
  # editer: server_name, root (chemin reel de deploiement), socket php-fpm

  # 3. Activer le site
  ln -s /etc/nginx/sites-available/gestion-stock.conf /etc/nginx/sites-enabled/
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx

  # 4. Domaine + SSL: DNS (enregistrement A vers l'IP du VPS) puis
  certbot --nginx -d ton-domaine.tld
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


## Donnees de demo (frontend/demo-data.php, sans SSH)

### Migrations sans SSH (frontend/migrate.php)
Meme principe que `demo-data.php` : accessible depuis le navigateur, reserve
aux comptes ADMIN, pas de terminal necessaire. Reprend exactement la logique
de `backend/bin/migrate.php` (meme table `schema_migrations`, meme dossiers
`database/migrations/up|down`) - les deux sont interchangeables et se
partagent le meme etat, tu peux utiliser l'un ou l'autre selon ce qui est
disponible sur l'hebergement du moment.

Affiche l'etat de chaque migration (appliquee/en attente), un bouton pour
appliquer les migrations en attente, et un bouton d'annulation du dernier
lot (protege par confirmation textuelle "ANNULER", a n'utiliser qu'en cas
d'erreur juste apres une migration - peut supprimer des colonnes/tables et
leurs donnees).


Une fois l'installation terminee et le compte admin cree (voir
section precedente), on peut charger soi-meme des donnees d'exemple
pour explorer l'application, ou tout reinitialiser - le tout depuis le
navigateur, sans acces SSH ni FTP.

**Acces**: `https://ton-domaine.tld/frontend/demo-data.php`, en etant
deja connecte avec un compte du role `ADMIN`. La page vérifie le cookie de
session `gs_token` exactement comme le fait l'API (meme logique que
`AuthMiddleware`/`RoleMiddleware`) - un compte non-admin ou non connecte est
redirige/rejete (403).

### Action 1 - Charger les donnees de demo
Insere des categories, fournisseurs, produits et niveaux de stock d'exemple
depuis `database/demo/catalog-demo.sql`. Requetes idempotentes
(`ON DUPLICATE KEY UPDATE` / `NOT EXISTS`): le bouton peut etre cliqué
plusieurs fois sans creer de doublons.

**Volume charge** (verifie sur une base MariaDB 10.11 reelle, migrations
jouees puis fichier execute trois fois de suite) :

| Element | Quantite |
| --- | --- |
| Produits | 144 (dont 24 a variantes, 6 desactives, 34 en FIFO) |
| Variantes | 160 (taille/couleur, pointure, millesime/contenance) |
| Lignes de stock | 280 (produits et variantes) |
| Categories / fournisseurs / marques | 9 / 7 / 7 |
| Unites / taxes / tags | 3 / 3 / 7 |
| Scenario complet | demande d'achat, commande, livraison, inventaire, mouvements, alertes |

De quoi remplir 6 pages de catalogue a 25 lignes par page, avec des articles
volontairement sous leur seuil pour alimenter le tableau de bord et l'ecran
Alertes. Pour voir les variantes, active `clothing_variants_enabled` et/ou
`bottle_variants_enabled` dans l'ecran Parametres.

**Ne touche jamais**: `users`, `roles`, `personal_access_tokens`. Aucun
compte, aucun mot de passe n'est cree ou modifie par cette action -
contrairement au seed interne (voir plus bas), ce fichier ne contient
aucune donnee sensible et peut etre deploye sans risque.

### Action 2 - Reinitialiser les donnees
Vide integralement le catalogue et l'activite metier: produits, categories,
marques, unites, taxes, tags, fournisseurs, clients, entrepots (+ zones/
emplacements), stock, mouvements de stock, alertes, commandes et demandes
d'achat, livraisons, inventaires, numeros de serie, pieces jointes,
compteurs de sequence documentaire, imports CSV.

**Conserve volontairement**: `users`, `roles`, `personal_access_tokens`
(personne n'est deconnecte ni supprime), `app_settings` (reglages devise/
langue/fuseau), et `audits` (le journal d'audit garde la trace de qui a
fait quoi, y compris de ce reset lui-meme - action journalisee sous
`DATA_RESET`).

Protection: action irreversible, doublement confirmee (popup JS +
obligation de taper `SUPPRIMER` dans un champ texte). Techniquement,
utilise des `DELETE FROM` dans une transaction (pas des `TRUNCATE`, qui
provoquent un commit implicite en MySQL et demandent le privilege `DROP`,
pas toujours accorde en mutualise) - un reset auto-increment best-effort
est tente ensuite via `ALTER TABLE` mais echoue silencieusement si
l'hebergement ne l'autorise pas, sans consequence sur le reset lui-meme.

### A savoir
`frontend/demo-data.php` peut rester en ligne en permanence (contrairement
a `install.php`, qui doit etre supprime apres usage) : il est protege par
l'authentification admin de l'application elle-meme, pas par une cle
statique. Si tu preferes qu'aucun utilisateur n'y ait acces, il suffit
de ne pas inclure `frontend/demo-data.php` ni `database/demo/` dans le
deploiement - l'application fonctionne normalement sans.

### Reset automatique nocturne d'une instance de demo separee (optionnel)
Si tu maintiens une instance de demo publique separee des installations
normales (par exemple pour presenter l'application), elle peut se
reinitialiser seule chaque nuit sans qu'un admin ait a cliquer sur les
boutons de `demo-data.php`.

`backend/bin/reset-demo-cron.php` fait exactement ce que font les 2
boutons de `demo-data.php`, dans l'ordre (vide puis recharge), en ligne de
commande - aucune session/cookie necessaire, donc utilisable depuis une
tache planifiee.

A configurer dans cPanel > Cron Jobs (ou equivalent chez l'hebergeur) sur
l'hebergement de cette instance de demo, par exemple tous les jours a 4h :
```
php /chemin/absolu/vers/le/projet/backend/bin/reset-demo-cron.php
```

**Ne jamais pointer ce cron vers une base de production** - il efface
tout sans aucune confirmation (normal pour un cron, mais destructeur). Il
reutilise `config/demo-reset-tables.php` (liste des tables videes, partagee
avec `demo-data.php` pour eviter que les deux listes divergent) et
`database/demo/catalog-demo.sql`.


## Installation locale WAMP (pour dev/demo uniquement, BDD jamais creee)
1. Copier le projet dans `c:\wamp64\www\gestion-stock`.
2. Demarrer WAMP et verifier que `Apache` + `MySQL` sont en vert.
3. Creer la base vide (phpMyAdmin ou SQL):

```sql
CREATE DATABASE IF NOT EXISTS gestion_stock
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

4. Configurer les acces MySQL. `config/database.php` ne contient **aucune
valeur en dur** : il lit les variables d'environnement chargees depuis
`backend/.env` (via `config/env-loader.php`). C'est donc `backend/.env`
qu'il faut renseigner, en partant de `backend/.env.example` :

```dotenv
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=gestion_stock
DB_USER=root
DB_PASS=
DB_CHARSET=utf8mb4
```

Pour memoire, la structure retournee par `config/database.php` (a ne
modifier qu'en connaissance de cause - noter la cle `name`, et non
`dbname`) :

```php
return [
    'host'     => getenv('DB_HOST') ?: '127.0.0.1',
    'port'     => (int)(getenv('DB_PORT') ?: 3306),
    'name'     => getenv('DB_NAME') ?: 'gestion_stock',
    'username' => getenv('DB_USER') ?: 'root',
    'password' => getenv('DB_PASS') ?: '',
    'charset'  => getenv('DB_CHARSET') ?: 'utf8mb4',
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

Ces deux fichiers lisent l'environnement, ils ne se modifient pas
directement. Variables a renseigner dans `backend/.env`:
- `DB_USER` = login MySQL
- `DB_PASS` = mot de passe MySQL
- `DB_NAME` = nom de la base
- `DB_HOST` et `DB_PORT` selon votre serveur

### 2e passe de durcissement (post-livraison client)

En plus de ce qui precede:

- **Cookie httpOnly** remplace le jeton `Bearer` en `localStorage` (voir
  ci-dessus) - `AuthCookie`, `AuthMiddleware`, `http-client.js`.
- **Expiration glissante des sessions** (7 jours d'inactivite max) au lieu
  de jetons illimites - `AuthService::TOKEN_TTL_DAYS`, a garder aligne avec
  `AuthCookie::TTL_DAYS` (duree de vie du cookie cote navigateur).
- **Content-Security-Policy** avec nonce par requete (aucun `unsafe-inline`
  sur les scripts) + `X-Content-Type-Options` et `Referrer-Policy` -
  `route-frontend.php`, `backend/public/index.php`,
  `nginx-gestion-stock.conf.example`. La protection contre le clickjacking
  est assuree par la directive CSP `frame-ancestors 'none'` (et non par un
  en-tete `X-Frame-Options`, qu'elle remplace sur tous les navigateurs
  actuels).
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
  quoi, filtrable par utilisateur/action. Le bouton "Reinitialiser" ne fait
  que vider les filtres (reaffiche tout). Un bouton separe **"Vider le
  journal"** supprime definitivement tout l'historique
  (`DELETE /api/v1/audits`, admin uniquement) - double confirmation requise
  (saisie du mot "SUPPRIMER"). Cette suppression est elle-meme journalisee
  (`AUDIT_LOG_CLEARED`), qui devient donc la premiere entree du nouveau
  journal.
- **Seed interne LM-Code** (`database/seeders/`, mot de passe admin partage
  entre environnements de demo LM-Code): a **exclure systematiquement des
  livraisons clients** - reserve a l'usage interne, voir avertissement en
  tete de `database/seeders/pro/202602270001_seed_core_data.sql`. A ne pas
  confondre avec `database/demo/` + `frontend/demo-data.php`, concus au
  contraire pour etre livres au client (voir section dediee).
- **Suite de tests automatises** sur les briques d'authentification/securite
  (voir section Tests plus bas).
- **Compatibilite hebergement mutualise**: `PasswordService` et
  `frontend/install.php` basculent automatiquement sur bcrypt si Argon2id
  n'est pas disponible (extension `sodium` souvent absente sur du mutualise
  bas de gamme) - sans ce fallback, la creation du premier compte admin
  plantait avec une erreur fatale sur ce type d'hebergement.

## Etat d'un produit et valorisation

### Un seul champ d'activation
Le schema initial portait une colonne `products.status` (ACTIVE/INACTIVE) et
la migration `202602270002` a ajoute `is_active` juste apres, sans retirer la
premiere : deux champs pour la meme idee, dont un (`status`) qui n'etait lu
par aucune requete du projet.

Le formulaire produit n'expose desormais que **`is_active`**, et ce champ a un
effet reel :

- un produit inactif reste visible et modifiable dans l'ecran Produits, et
  tout son historique (mouvements, livraisons, achats) est conserve ;
- il disparait des listes deroulantes de saisie (mouvements de stock,
  livraisons, demandes et commandes d'achat) : on ne peut plus lui passer de
  nouvelle operation ;
- il est exclu des alertes de stock bas du tableau de bord.

C'est exactement le comportement deja applique aux variantes. La colonne
`status` reste en base et l'import CSV continue de la remplir : rien n'est
casse pour l'existant, elle n'est simplement plus proposee a la saisie.

Cote technique, `ProductRepository::selectableForLookup()` remplace l'appel
`paginate(1, 500)` du `LookupController`. Au passage cela corrige une
troncature silencieuse : `paginate()` plafonne a 100 lignes (garde-fou
anti-abus sur `?per_page`), donc au-dela de 100 produits les listes
deroulantes n'en proposaient que 100. Les produits y sont maintenant tries
par nom plutot que par date de creation decroissante.

### Methode de valorisation par defaut
Le reglage `default_valuation_method` (ecran Parametres, valeurs `CUMP` ou
`FIFO`, `CUMP` par defaut) pre-selectionne la methode de valorisation a la
**creation** d'un produit. Elle reste modifiable produit par produit : un
catalogue majoritairement CUMP avec quelques references en FIFO reste
possible, sans avoir a corriger le champ a chaque saisie.

En edition, la valeur enregistree du produit prime toujours sur le reglage
global - changer le reglage ne modifie retroactivement aucun produit
existant.

### 6e passe - audit approfondi (concurrence, import, exports)

Passe de relecture ligne a ligne des zones qui n'avaient pas encore ete
auditees. Chaque correctif ci-dessous a ete verifie contre une base MariaDB
10.11 reelle, API demarree et endpoints appeles.

- **Course sur le stock (correctness).** `StockService::createMovement()`
  lisait le stock puis le reecrivait sans verrou. Deux sorties simultanees sur
  le meme article lisaient toutes les deux l'ancienne quantite : reproduit ici
  avec un stock de 5 et deux sorties de 3, **les deux etaient acceptees** et le
  stock ne descendait que de 3 - 6 unites sorties, 3 decomptees. Ajout de
  `SELECT ... FOR UPDATE` (`ProductRepository::stockLevel($..., forUpdate: true)`)
  sur la ligne source et sur la ligne de destination d'un transfert. Apres
  correctif, la seconde sortie est correctement refusee.
- **Import de stock initial qui gonflait le stock.** L'import
  `initial-stocks` utilisait `ON DUPLICATE KEY UPDATE` sur `stock_levels`,
  dont la cle unique contient `variant_id`. MySQL n'appliquant pas l'unicite
  quand une colonne de la cle est NULL, **reimporter le meme fichier
  n'ecrasait pas la ligne : il en ajoutait une**. Trois imports de 50, 75 puis
  90 donnaient un stock de 215 au lieu de 90 (`stock_total` etant un
  `SUM(quantity)`). Remplace par un SELECT cible puis UPDATE ou INSERT.
- **Finalisation d'inventaire sans transaction.** Chaque ajustement etait
  commite individuellement : un echec au 5e produit d'une session de 10
  laissait 4 ajustements appliques et la session toujours ouverte. La
  finalisation est desormais tout ou rien.
- **Listes deroulantes tronquees a 100 entrees.** `paginate()` plafonne a 100
  lignes (garde-fou anti-abus sur `?per_page`), mais `LookupController` s'en
  servait pour charger des referentiels entiers. Ajout de
  `PdoCrudRepository::allForLookup()`, utilise pour les entrepots, zones,
  emplacements, categories, fournisseurs, clients, unites, taxes, marques et
  tags - avec tri alphabetique (`$lookupOrderColumn`) plutot que par date de
  creation. Verifie avec 157 fournisseurs : les 157 remontent.
- **Injection de formule dans les exports CSV.** Un nom de produit saisi comme
  `=cmd|'/c calc'!A1` ou `=HYPERLINK(...)` s'executait a l'ouverture du
  fichier dans Excel chez le destinataire. Les valeurs commencant par
  `= + - @`, tabulation ou retour chariot sont prefixees d'une apostrophe -
  sauf les nombres, pour qu'un ecart negatif reste un nombre exploitable.
  Ajout au passage du **BOM UTF-8**, sans lequel Excel sous Windows lit le
  fichier en ANSI et massacre les accents.
- **Comptage d'inventaire par variante.** La limitation connue est levee : le
  formulaire propose un selecteur de variante quand le produit en utilise, le
  tableau des comptages affiche une colonne Variante, et l'ecart est calcule
  par variante. Verifie de bout en bout : deux variantes du meme produit
  comptees dans une meme session, ajustements appliques separement.
- **En-tetes de telechargement.** Les caracteres de controle sont retires du
  nom de fichier avant de le placer dans `Content-Disposition` (pieces jointes
  et medias produit), le nom venant de l'utilisateur qui a televerse.
- **Derniers messages techniques en anglais** traduits : messages de
  `FileStorageService`, erreurs d'import, et les notes stockees en base par
  les mouvements automatiques (`Auto generated destination move`,
  `PO receipt`, `Inventory adjustment generated from session`).
- **Statut des jobs d'import.** Un import de 500 lignes dont une seule est
  rejetee s'affichait `FAILED`. Seul un import ou aucune ligne n'est passee
  est desormais un echec.

## Stock suivi par emplacement

Migration `202602270012_stock_by_location`. Le stock n'est plus suivi a la
maille entrepot mais a la maille **emplacement** : on ne sait plus seulement
"40 unites a Bruxelles", mais "24 en A1 et 16 en A2".

### Modele

`stock_levels` gagne une colonne `location_id` **nullable**, et sa cle unique
devient `(product_id, warehouse_id, variant_id, location_id)`. Une ligne a
`location_id NULL` represente du stock present dans l'entrepot sans rangement
precis : c'est l'etat de toutes les lignes existantes apres la migration (rien
n'est perdu ni deplace) et le cas normal d'un entrepot ou aucun emplacement
n'est defini.

`ON DELETE RESTRICT` sur l'emplacement : supprimer un emplacement qui contient
encore du stock echoue proprement (409 avec message metier) plutot que de faire
disparaitre des quantites.

### Regles de mouvement

| Operation | Avec emplacement | Sans emplacement |
| --- | --- | --- |
| Entree | ajoute a cet emplacement | ajoute a la ligne "non precise" |
| Sortie | ne pioche que dans cet emplacement, echoue s'il n'y en a pas assez **meme si l'entrepot en a ailleurs** | consomme sur tout l'entrepot, en commencant par le stock non range puis emplacement par emplacement |
| Ajustement | remplace la quantite de cet emplacement | accepte seulement si le produit tient sur une seule ligne, sinon refuse en demandant de preciser |
| Transfert | sortie de l'emplacement source, entree dans l'emplacement destination | sortie repartie, entree en "non precise" |

Un emplacement qui n'appartient pas a l'entrepot du mouvement est refuse : sans
ce controle, la ligne de stock existerait mais designerait un endroit ou
l'article n'est pas.

`balance_after` d'un mouvement devient le **total de l'entrepot** apres
l'operation : avec plusieurs emplacements, la quantite d'une seule ligne ne
veut plus dire grand-chose dans un historique.

### Ce qui continue de fonctionner sans rien preciser

Livraisons, receptions de commande, numeros de serie et import de stock initial
ne connaissent pas d'emplacement : ils travaillent sur l'entrepot entier, la
sortie etant repartie automatiquement. Leur comportement est inchange.

### Inventaire

Le comptage accepte un emplacement, propose parmi ceux de l'entrepot de la
session. Avec emplacement, l'ecart ne porte que sur cette allee et l'ajustement
genere la vise precisement ; sans emplacement, on compte le produit dans tout
l'entrepot comme avant. La cle de deduplication des comptages inclut
l'emplacement : deux allees du meme produit sont deux comptages distincts.

### Corrections liees

- **Quatre migrations "down" etaient des copies de leur "up"** (007, 008, 009,
  011) : elles ajoutaient des colonnes au lieu de les retirer. Le bouton
  "Annuler le dernier lot" de `frontend/migrate.php` les aurait jouees telles
  quelles - au mieux une erreur "colonne deja existante", au pire une base dans
  un etat imprevu. Reecrites correctement.
- **Donnees de demo** : les 160 insertions de stock par variante utilisaient
  `ON DUPLICATE KEY UPDATE`, qui ne dedoublonne plus depuis que la cle unique
  contient `location_id` (nullable). Passees en `NOT EXISTS`. Verifie par trois
  chargements consecutifs : 280 lignes de stock, zero doublon.

### Correctif : les emplacements manquaient sur l'ecran Mouvements

Les champs "Emplacement source" et "Emplacement destination" n'avaient jamais
ete ajoutes au formulaire de l'ecran **Mouvements** - seulement a celui de la
fiche produit. Le code qui les alimente etait bien present, mais pointait vers
des elements inexistants : silencieux, et invisible aux verifications
syntaxiques.

Cause : lors de l'ajout initial, le script de modification effectuait trois
remplacements et le troisieme a echoue sur une assertion. Le script s'est
interrompu **sans rien ecrire**, y compris les deux remplacements deja
calcules. Seule la partie rejouee ensuite a ete conservee.

Sont retablis sur l'ecran Mouvements : les deux selecteurs d'emplacement, leur
envoi dans la requete, et les colonnes de l'historique. Un controle de symetrie
verifie desormais que chaque element apparait bien **deux fois** dans le
fichier - une fois par formulaire.

### Vue rapide : ou se trouve un produit

Le suivi par emplacement existait mais restait invisible : il fallait ouvrir la
fiche d'un produit, puis son onglet Stock, pour savoir dans quelle allee aller
le chercher - et la zone n'y figurait meme pas.

- **Colonne "Emplacements" dans la liste des produits** : `A1 (40), A2 (25),
  C1 (60)` en un coup d'oeil, sans ouvrir la fiche. Les lignes a quantite nulle
  et le stock non range sont ecartes du resume : on ne liste que les endroits
  ou il y a reellement quelque chose. Le resume respecte le filtre par entrepot
  - filtrer sur l'entrepot secondaire n'affiche que ses emplacements.
- **Resume en tete de l'onglet Stock** d'une fiche produit : un bloc par
  entrepot, avec le total et le detail des emplacements. La question courante -
  "ou vais-je le chercher" - trouve sa reponse avant le tableau.
- **Colonne Zone** dans le tableau de stock, et l'emplacement affiche avec sa
  description (`A1 - Allee A niveau 1`) plutot que son seul code.

Cote technique, le resume est calcule par un `GROUP_CONCAT` dans la requete
existante : aucune requete supplementaire par produit. La colonne `location_id`
venant de la migration 202602270012, sa presence est verifiee avant usage - sur
une base qui n'aurait pas encore joue la migration, la colonne s'affiche vide
au lieu de casser toute la liste des produits.

### Zones et emplacements dans les donnees de demo

La demo ne definissait qu'une zone et un emplacement (B1), et dans l'entrepot
**secondaire** - alors que la totalite du stock de demo est dans l'entrepot
**principal**. En choisissant l'entrepot principal dans un mouvement, la liste
des emplacements etait donc vide : la fonctionnalite paraissait cassee alors
qu'il n'y avait simplement rien a proposer.

- L'entrepot principal recoit deux zones (`A - Picking`, `C - Reserve`) et cinq
  emplacements (A1, A2, A3, C1, C2).
- Six articles ont leur stock **reparti dans ces emplacements**, pour que le
  suivi par emplacement soit visible des le chargement de la demo au lieu de
  n'afficher que des lignes "non precise". La repartition est idempotente : la
  ligne sans emplacement est fixee par un `UPDATE` (et non diminuee), les
  lignes localisees sont protegees par `NOT EXISTS`.
- Le message d'une liste d'emplacements vide indique desormais ou aller en
  creer ("Logistique > Emplacements") plutot que de laisser croire a un
  dysfonctionnement.

**Rappel de conception** : un produit n'est pas *affecte* a un emplacement. On
n'attribue pas une allee a un article dans sa fiche - c'est le **stock** qui se
trouve a un emplacement, et il y arrive par un mouvement. La fiche produit,
onglet Stock, affiche ensuite une ligne par emplacement.

### Numeros de serie localises

Migration `202602270013_product_serials_location`. Un numero de serie designe
UN article physique : ne connaitre que son entrepot alors que le stock est
localise n'avait pas de sens, d'autant que c'est justement l'exemplaire qu'on
va chercher a la main.

- `product_serials.location_id`, nullable, `ON DELETE RESTRICT` comme pour
  `stock_levels`.
- L'enregistrement propose l'emplacement parmi ceux de l'entrepot choisi, et le
  mouvement d'entree genere vise **ce meme emplacement** : ranger un exemplaire
  en A1 incremente A1, pas le stock non localise de l'entrepot.
- Marquer sorti decremente l'emplacement ou l'exemplaire se trouvait ;
  "Remettre en stock" demande entrepot **et** emplacement de retour (ils
  peuvent differer de l'origine, un article revient rarement dans son allee).
- **Une livraison sur numero de serie sort du stock de l'emplacement reel de
  cet exemplaire**, au lieu de laisser la repartition automatique piocher
  ailleurs. Verifie : un entrepot avec 50 unites non rangees et 1 exemplaire en
  A2, livraison de cet exemplaire - A2 passe a 0, les 50 ne bougent pas.
- Emplacement affiche dans la liste, dans la fiche de recherche par numero de
  serie, et pris en compte a la suppression avec ajustement de stock.

A l'annulation d'une livraison, l'exemplaire revient dans l'entrepot **sans**
emplacement : on ne sait pas ou il sera range, et le mouvement d'entree
alimente lui aussi la ligne non localisee - les deux restent coherents. C'est a
l'operateur de le ranger ensuite.

### Entrepots, emplacements et stock initial

**Filtre par entrepot sur la liste des produits.** Un produit n'appartient pas
a un entrepot : c'est son STOCK qui y est reparti. L'information existait
(fiche produit, onglet Stock) mais nulle part ailleurs, et la colonne "Stock"
de la liste affichait un total tous entrepots confondus sans le dire. Le filtre
restreint la liste aux produits presents dans l'entrepot choisi, la colonne
n'y compte plus que ce stock-la, et son libelle le precise ("Stock (Entrepot
Principal)" ou "Stock (tous entrepots)"). `warehouse_id` n'etant pas une
colonne de `products`, il est traite a part dans `ProductRepository::paginate()`
et non par `buildWhere()`.

**Stock initial a la creation d'un produit.** Deux champs optionnels
(entrepot + quantite) affiches uniquement a la CREATION - modifier un stock se
fait par un mouvement trace, jamais en editant une fiche. Ils generent un vrai
mouvement d'entree `INITIAL_STOCK`, audite comme les autres, au lieu d'ecrire
directement dans `stock_levels`. Un produit a variantes refuse le stock initial
avec un message explicite : sa quantite appartient a chaque variante.

**Emplacements branches sur les mouvements.** Zones et emplacements existaient
comme referentiels, et le backend acceptait deja `source_location_id` /
`destination_location_id` sur un mouvement - mais **aucun formulaire ne les
envoyait**. Ils ne servaient qu'a une case du comptage d'inventaire. Desormais :

- emplacement source et destination dans le formulaire de mouvement et dans
  celui de la fiche produit, **filtres sur l'entrepot concerne** (pour un
  transfert, la destination suit l'entrepot de destination) ;
- colonnes "Empl. source" et "Empl. dest." dans l'historique des mouvements ;
- **dernier emplacement connu** par entrepot sur la fiche produit, deduit du
  dernier mouvement qui en mentionne un.

**Limite assumee** : `stock_levels` ne porte pas d'emplacement, le stock reste
suivi par entrepot. Le dernier emplacement est donc une indication - "ou cet
article a ete range la derniere fois" - et non un inventaire par allee. Un vrai
suivi par emplacement demanderait une migration de `stock_levels` et toucherait
mouvements, inventaires, livraisons et achats ; a n'entreprendre que si
quelqu'un cherche reellement du materiel etagere par etagere.

### Listes deroulantes filtrables, et libelles "PO"

- **Champ de filtrage sur les listes de plus de 12 entrees.** Une balise
  `<select>` native ne permet de taper que deux ou trois caracteres : le
  navigateur cherche depuis le DEBUT du libelle et remet son tampon a zero
  apres une seconde. Avec 144 produits, retrouver "Clavier mecanique" en
  tapant "clav" etait impossible - limite du composant natif, pas un defaut de
  configuration. Le filtrage porte sur n'importe quelle partie du libelle (donc
  aussi le SKU), ignore accents et casse, et selectionne automatiquement le
  resultat quand il est unique.
  Applique par un `MutationObserver` sur le document plutot que par un appel
  apres chaque rendu : les ecrans sont reconstruits par `innerHTML` a une
  vingtaine d'endroits, et un futur ecran en beneficiera sans qu'on ait a y
  penser. Le `<select>` reste un `<select>`, les formulaires lisent toujours
  `.value`.
- **"PO" remplace par "Commandes"** dans le tableau de bord et les tableaux
  d'achats : l'abreviation anglaise (purchase order) n'a aucun sens pour un
  utilisateur francais.

### Numeros de serie : reconciliation avec le stock quantitatif

Le modele voulait que les deux registres restent d'accord, et l'ecran
**Mouvements** le faisait deja correctement : une entree de 10 avec 10 numeros
de serie cree le mouvement (+10) *et* enregistre les 10 series. Les livraisons
aussi. Mais l'onglet **Numeros de serie** etait entierement aveugle au stock :
enregistrer, marquer sorti, remettre en stock, supprimer - aucune de ces
actions ne touchait aux quantites. Or c'est l'ecran vers lequel on va
naturellement, puisqu'il porte le nom de la fonctionnalite.

Consequence concrete : on enregistrait 10 series sur un produit a 0 en stock,
puis la premiere livraison echouait sur "Stock insuffisant" - la
fonctionnalite paraissait cassee alors qu'elle faisait ce qu'on lui demandait.

- **Enregistrement** : un choix explicite plutot qu'une regle implicite, parce
  que les deux usages sont legitimes. *"Ces articles arrivent"* (par defaut)
  cree un mouvement d'entree `SERIAL_IN` de N ; *"Ces articles sont deja
  comptes dans le stock"* n'en cree aucun. Sans ce choix, l'un des deux cas
  doublait la quantite.
- **Marquer sorti** cree un mouvement `SERIAL_OUT` de 1 depuis l'entrepot du
  numero de serie ; **remettre en stock** cree un `SERIAL_RETURN` de 1 dans
  l'entrepot choisi.
- **L'ecran Mouvements envoie `creates_stock_entry: false`** lors de la saisie
  de series accompagnant une entree : le mouvement vient d'etre cree par
  l'appel precedent, sans ce drapeau la quantite serait comptee deux fois.
  Idem depuis la fiche produit.
- **Tout ou rien** : creation des series et mouvement sont dans une meme
  transaction (`createMany()` est devenue transaction-aware). Si le mouvement
  echoue, le statut du numero de serie n'est pas modifie.
- Si la quantite ne permet pas la sortie, le message explique la cause reelle
  - divergence entre les deux registres - au lieu d'un "Stock insuffisant"
  incomprehensible a cet endroit.
- **Suppression d'un numero de serie** : la question est posee a
  l'utilisateur, dans ses termes, au moment ou il decide. Supprimer couvre
  deux situations que rien dans les donnees ne distingue - une erreur de
  saisie (le numero est faux, l'article est bien la : la quantite ne bouge
  pas) ou un article qui n'est plus la (casse, perdu, jamais recu : la
  quantite baisse de 1). L'ancien comportement supposait toujours le premier
  cas en silence, ce qui laissait la quantite trop haute sans que personne ne
  le sache - une regle que seul un lecteur du code pouvait connaitre. Chaque
  choix affiche sa consequence concrete (`askChoice()`). Un numero deja sorti
  n'etant plus compte dans la quantite, sa suppression ne pose aucune question
  et ne peut pas decrementer deux fois.

### Numeros de serie : entrepot fiabilise

Un numero de serie designe un objet physique unique. Or l'entrepot saisi a
l'enregistrement n'etait controle nulle part.

- **Livraison depuis le mauvais entrepot : refusee.** On pouvait livrer depuis
  l'entrepot B un article enregistre dans l'entrepot A, sans aucun message :
  la quantite etait decrementee au mauvais endroit et la localisation du
  numero de serie devenait fausse. `DeliveryService` verifie desormais la
  concordance. Un numero de serie **sans** entrepot renseigne (colonne
  nullable, donnees anterieures) reste accepte : l'existant n'est pas bloque.
- **L'entrepot devient obligatoire** a l'enregistrement d'un numero de serie,
  avec un rappel explicite : l'article ne pourra etre livre que depuis cet
  entrepot.
- **Fin de la saisie d'un identifiant a la main.** La remise en stock d'un
  article sorti demandait l'entrepot via `window.prompt('Id de l'entrepot ?')`
  : il fallait connaitre l'identifiant numerique et le taper, sans le moindre
  controle - taper 3 au lieu de 1 remettait l'article au mauvais endroit en
  silence. Remplace par une liste deroulante des entrepots (`askWarehouse()`).

**A savoir** : enregistrer un numero de serie ne modifie pas la quantite en
stock. Les numeros de serie et les quantites sont deux registres independants
- c'est le fonctionnement voulu, mais cela signifie qu'un ecart entre les deux
est possible et n'est signale nulle part.

### Recherche produit instantanee

- **Recherche au fil de la frappe** sur l'ecran Produits : plus besoin de
  valider par Entree. Un delai de 300 ms evite une requete par touche.
  Depuis un autre ecran, la touche Entree reste necessaire pour basculer sur
  Produits - basculer des la premiere lettre serait deroutant si on est en
  train de remplir un formulaire. La touche Echap vide la recherche.
- **Les rendus sont serialises.** Deux requetes lancees a 300 ms d'intervalle
  peuvent revenir dans le desordre : la reponse lente pour "vel" repeindrait
  l'ecran apres la reponse rapide pour "velo", affichant des resultats qui ne
  correspondent plus a la saisie. Une saisie arrivee pendant un chargement est
  memorisee et traitee juste apres, donc l'affichage se termine toujours sur
  la derniere valeur tapee.
- **La recherche se vide en quittant Produits.** Elle ne filtre que cet ecran :
  le mot restait ecrit dans la barre pendant qu'on consultait Fournisseurs ou
  Mouvements, ou il ne s'appliquait pas, et on revenait sur Produits avec une
  liste toujours filtree sans comprendre pourquoi. Le filtre par tag est remis
  a zero en meme temps.

### 8e passe - tests de bout en bout import / exports / pieces jointes

Campagne de tests contre l'API reelle (MariaDB 10.11, serveur PHP demarre,
fichiers reellement televerses et telecharges). Deux bugs trouves.

**Virgule decimale francaise perdue a l'import.** Excel en francais exporte
`19,90` ; `(float)"19,90"` vaut `19.0`. Un prix importe perdait donc ses
centimes **en silence**, sans aucune erreur - visible seulement a la
facturation. `ImportService::parseDecimal()` gere desormais les quatre
conventions (`19,90`, `19.90`, `1 234,56`, `1,234.56`, espaces insecables
inclus) et `parseInteger()` fait de meme pour les quantites et les seuils.
13 cas de test.

**Fichier rejete = "Erreur serveur" 500.** Les erreurs de validation d'upload
(mauvaise extension, contenu ne correspondant pas, fichier vide) etaient des
`RuntimeException` qui tombaient dans le `catch (Throwable)` generique :
l'utilisateur recevait un 500 sans explication. `FileStorageService` leve
desormais des `HttpException` **422** avec le motif exact. `HttpException`
etendant `RuntimeException`, le changement reste compatible avec tout code qui
attraperait encore ce type.

**Export XLSX : `t="str"` remplace par `t="inlineStr"`.** En OOXML, `t="str"`
designe le resultat *cache d'une formule* ; la facon standard d'ecrire une
chaine sans table partagee est `inlineStr` avec `<is><t>`. Le fichier
s'ouvrait, mais autant ne pas risquer le message "Excel a trouve un probleme
avec le contenu de ce fichier" devant un client. Verifie en rouvrant le
fichier genere avec openpyxl : 3 lignes, 8 colonnes, entiers typés comme
entiers.

**Ce qui a ete verifie et fonctionne** : import des 4 entites (produits,
fournisseurs, clients, stocks initiaux) ; separateurs `,` et `;` detectes
automatiquement ; BOM UTF-8 en entete retire ; accents et guillemets
echappes preserves jusqu'en base (`Cle a molette, 12" chromee`) ; categories
et fournisseurs inconnus crees a la volee ; lignes invalides rejetees une par
une avec leur numero de ligne, sans bloquer les autres ; les trois exports CSV
avec BOM et accents relus sans erreur ; export XLSX ouvert par une vraie
bibliotheque tableur.

**Pieces jointes** : PNG legitime accepte, `.php` refuse, PHP renomme en
`.png` refuse par la verification du contenu reel (fileinfo). Un fichier
"polyglotte" (vrai en-tete PNG suivi de code PHP) est **accepte** - c'est
attendu, aucune detection de contenu ne peut faire mieux - mais il n'est pas
exploitable : il est stocke sous un nom aleatoire avec l'extension `.png`,
dans un dossier ou `.htaccess` coupe le moteur PHP, interdit `ExecCGI` et
sert les scripts en `text/plain`. Le telechargement renvoie
`X-Content-Type-Options: nosniff`.

### Modes d'inventaire : Global et Tournant

Le champ `counting_mode` d'une session existait mais n'etait lu par aucune
logique : Global ou Tournant, le comportement etait identique. C'etait un
controle qui laissait croire a un effet qu'il n'avait pas - le meme travers
que l'ancien couple `status` / `is_active` sur les produits.

- **Global** : la session compte tout l'entrepot. Un panneau **"Reste a
  compter"** liste les articles ayant du stock dans cet entrepot et pas encore
  comptes, avec un compteur `X / Y article(s) compte(s)` et un bouton
  "Compter" qui pre-selectionne l'article (et sa variante) dans le formulaire
  de saisie.
- **Tournant** : la session ne porte que sur une selection d'articles, le
  panneau ne s'affiche pas. C'est le backend qui le decide, via le drapeau
  `applicable` de `GET /api/v1/inventories/{id}/remaining`.

**Point de conception important** : le panneau est en LECTURE SEULE, aucun
comptage n'est pre-cree a 0. Pre-charger des comptages a zero aurait ete
dangereux - la finalisation applique un ajustement des que l'ecart n'est pas
nul, donc un article pre-charge puis oublie aurait vu **son stock remis a
zero**. Un inventaire global abandonne a mi-parcours aurait vide l'entrepot.
Ici, un article non compte reste simplement non ajuste, son stock est
inchange. Verifie : session globale sur un entrepot de 3 articles, 2 comptes
puis finalisation - le 3e conserve exactement sa quantite.

Les lignes a quantite nulle sont ecartees de la liste : elles n'ont rien a
faire dans une liste d'articles a aller compter physiquement.

### 7e passe - garde-fou sur l'entrepot d'un inventaire

Une session d'inventaire ne porte que sur **un** entrepot : la quantite
attendue d'un produit est celle de cet entrepot-la. Compter un produit stocke
ailleurs affichait donc "Attendu 0", un ecart egal a toute la quantite saisie,
et la finalisation **creait** ce stock dans l'entrepot de la session sans
toucher a l'autre - une erreur silencieuse et couteuse, dont rien dans l'ecran
ne prevenait.

Le calcul etait correct, c'est l'interface qui laissait tomber dans le piege.
Desormais :

- le titre du formulaire et un rappel en tete nomment explicitement l'entrepot
  de la session ;
- a la selection d'un produit, si celui-ci n'a aucun stock dans l'entrepot de
  la session **mais en a ailleurs**, un avertissement rouge nomme les
  entrepots concernes et leurs quantites, et explique ce que fera la
  finalisation.

Un produit reellement neuf (aucun stock nulle part) ne declenche rien : c'est
un cas normal d'inventaire d'entree.

### 5e passe - jeu de demonstration etendu

- **`database/demo/catalog-demo.sql` etoffe** : le catalogue passe de 2 a 144
  produits, avec 160 variantes, un melange CUMP/FIFO, des articles desactives,
  des marques, unites, taxes et tags. Objectif : pouvoir eprouver la
  pagination, le module Variantes et les alertes de stock sans saisir quoi que
  ce soit a la main.
- **`product_variants` manquait dans `RESET_TABLES`** (`frontend/demo-data.php`).
  Le reset desactive les contraintes (`SET FOREIGN_KEY_CHECKS = 0`), donc le
  `ON DELETE CASCADE` de `product_variants` vers `products` ne se declenchait
  pas : les variantes **survivaient au reset** en pointant vers des produits
  supprimes, puis se rattachaient silencieusement aux nouveaux produits une
  fois les `AUTO_INCREMENT` remis a 1. Corrige.
- **Deux inserts de stock non idempotents** dans le fichier de demo : ils
  utilisaient `ON DUPLICATE KEY UPDATE` sur `stock_levels`, dont la cle unique
  contient `variant_id`. MySQL n'applique pas l'unicite quand une colonne de la
  cle vaut NULL, donc chaque rechargement de la demo ajoutait une ligne de
  stock en double pour ces deux produits. Passes en `NOT EXISTS`.

### 4e passe - pagination et erreurs d'integrite

- **Pagination des ecrans CRUD.** Le frontend n'envoyait ni `page` ni
  `per_page` : l'API appliquait son defaut (`per_page = 20`) et **chaque ecran
  de gestion n'affichait que les 20 enregistrements les plus recents**, sans
  bouton page suivante ni compteur - le reste du catalogue etait simplement
  inaccessible en navigation (seule la recherche globale permettait de le
  retrouver). Ajout d'une barre sous chaque tableau : nombre total de
  resultats, plage affichee, page courante sur nombre de pages, boutons
  Precedent/Suivant et choix 25/50/100 lignes par page. La page revient a 1
  quand la recherche, le filtre par tag ou la taille de page change, et apres
  une creation (la nouvelle ligne apparait en tete de liste). Si la page
  courante n'existe plus apres des suppressions, l'ecran se replie sur la
  derniere page disponible au lieu d'afficher une liste vide.
- **Listes deroulantes tronquees a 100 entrees.** `LookupController`
  demandait 200 a 1000 lignes selon les referentiels, mais
  `PdoCrudRepository::paginate()` plafonne a 100 (garde-fou anti-abus sur
  `?per_page`). Corrige pour les produits via
  `ProductRepository::selectableForLookup()` (voir section precedente).
- **Erreurs d'integrite de la base traduites en messages metier.** Les
  violations de contrainte tombaient dans le `catch (Throwable)` generique et
  l'utilisateur recevait un `500 Erreur serveur` sans explication. Un
  `catch (PDOException)` dedie renvoie desormais un **409** avec un message
  clair : suppression d'un element encore reference (MySQL 1451, cas typique
  d'un produit deja present dans des mouvements de stock), reference vers une
  ligne inexistante (1452), et surtout **doublon sur un index unique** (1062,
  cas d'un SKU deja pris - qui affichait lui aussi "Erreur serveur").
- **4 derniers messages en anglais** traduits : ils etaient construits par
  interpolation en guillemets doubles (`"Field '{$field}' is required"`,
  `"Unknown PO item: {$itemId}"`...) et avaient echappe a la passe
  precedente, qui ne visait que les chaines en guillemets simples.

### 3e passe - francisation et durcissement complementaire

- **Interface entierement en francais.** Les ~75 messages d'erreur et de
  confirmation de l'API etaient encore en anglais ("Product not found",
  "Insufficient stock", "Forbidden"...) : ils sont traduits a la source, dans
  les `HttpException` et les reponses JSON. Le dictionnaire de repli de
  `http-client.js` reste en place comme filet de securite.
- **Statuts techniques traduits a l'affichage.** La fonction
  `localizeValue()` de `app-clean.js` existait mais son dictionnaire etait
  incomplet : `DRAFT`, `IN`, `OUT`, `ADJUSTMENT`, `TRANSFER`, `LOW_STOCK`,
  `ADMIN`... s'affichaient bruts dans les tableaux. Dictionnaire complete,
  libelles des listes deroulantes traduits, et badge utilisateur qui affichait
  "ADMIN" au lieu de "Administrateur". **Les valeurs stockees en base et
  envoyees a l'API sont inchangees**, seul l'affichage est traduit.
  Une liste `RAW_VALUE_KEYS` protege les colonnes de donnees libres (SKU,
  code, nom...) pour qu'une unite dont le code est `IN` (pouce) ne s'affiche
  pas "Entree".
- **Installateur verrouille apres installation** (voir section Installation).
- **Session ramenee de 30 a 7 jours** d'inactivite.
- **Logo par defaut** : `frontend/assets/img/brand/lm-code-monogram.svg` est
  desormais present dans le depot. Il etait reference comme favicon par
  `index.php` et `login.php` et comme logo de repli par `route-frontend.php`
  sans exister, ce qui cassait le favicon sur toutes les pages. En prime,
  `route-frontend.php` verifie l'existence du logo du client avant de
  l'utiliser et retombe sur ce monogramme s'il a disparu, au lieu d'afficher
  une image cassee sur l'ecran de connexion.
- **Dossier `stats/`** (statistiques webalizer de l'hebergeur) : son
  `.htaccess` etait corrompu (il contenait litteralement
  `Files HASH(0x...)`, un bug d'interpolation du script qui l'a genere) et ne
  protegeait donc rien, alors que ces pages exposent les URLs visitees, les
  IP et les referents. `.htaccess` reecrit, et le dossier est a exclure des
  livraisons.

## Migrations et seed interne LM-Code (dev interne uniquement - PAS pour un client)
**A ne pas confondre avec `frontend/demo-data.php` (section dediee plus haut),
qui est le bon outil pour donner de la demo a un client.** Ce qui suit est
reserve au dev interne LM-Code sur un environnement jetable.

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
`frontend/install.php` pour l'installation client, voir plus haut, et
`frontend/demo-data.php` pour lui donner des donnees de demo une fois
installe). `seed.php` refuse de s'executer si `APP_ENV=production` sauf a
forcer avec `--force`.

**Important**: le dossier `database/seeders/` (a ne pas confondre avec
`database/demo/`, qui lui est concu pour etre livre) est un outil interne. Il
ne doit **jamais** faire partie d'une livraison a un client final - a
exclure systematiquement de tout export/zip destine a un tiers.

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

## Git
Pour lier ce projet a ton propre depot Servia:

```bash
git init
git remote add origin <url-du-depot-servia>
git add .
git commit -m "Initialisation Gestion Stock - Servia"
git push -u origin main
```
