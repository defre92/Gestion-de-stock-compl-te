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

## Variantes produit - optionnel, 3 "saveurs" disponibles

Fonctionnalite optionnelle pour les catalogues avec variantes. Desactivee
par defaut, elle ne change rien pour une installation qui n'en a pas besoin.
**Trois options independantes**, chacune activable ou non selon l'activite
concernee :

- `clothing_variants_enabled` = `1` : taille + couleur — couvre le
  pret-a-porter **et** la chaussure (la pointure va simplement dans le
  champ "Taille / Pointure", pas besoin d'une option separee).
- `bottle_variants_enabled` = `1` : millesime + contenance en cl (vins,
  spiritueux, boissons).
- `dimension_variants_enabled` = `1` : largeur + hauteur + profondeur +
  poids (materiel, mobilier, decoupe sur mesure, tissu au metre).
  **Ces quatre champs sont libres** : l'unite fait partie de la valeur
  saisie, on peut donc ecrire "120 cm", "2 m", "3/4 pouce", "12,5 kg" ou
  meme "sur mesure" sans etre bloque par une unite imposee.

Ces dimensions de variante ne remplacent pas les champs numeriques
Largeur/Hauteur/Profondeur/Poids de la **fiche produit** : les deux
coexistent selon les articles. La fiche produit porte les cotes d'un article
qui n'a qu'une seule taille ; la variante porte les cotes de chaque
declinaison d'un article qui en a plusieurs, chacune avec son propre stock.

Les cles se creent dans l'ecran Parametres. Des qu'au moins une des trois
est activee, l'entree "Variantes" apparait dans le menu lateral sous
**Referentiels**, juste apres Produits - avec un seul et meme module (pas
trois ecrans separes) : chaque variante ne remplit que les champs qui la
concernent (taille/couleur, millesime/contenance OU dimensions), les autres
restent vides. Le module reste masque si aucune des trois n'est activee.

Le formulaire suit la meme regle : le champ "Ce produit a des variantes"
n'apparait sur la fiche produit que si au moins une option est active, et
son libelle s'adapte aux options reellement activees (taille/couleur,
millesime/contenance, dimensions, ou plusieurs a la fois). Les champs de la
variante elle-meme (taille, couleur / millesime, contenance / largeur,
hauteur, profondeur, poids) n'apparaissent que dans le module
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
separees par des virgules (tailles et couleurs, millesimes et contenances,
et/ou largeurs, hauteurs, profondeurs et poids) et le generateur cree toutes
les combinaisons. Un vetement en 5 tailles x 4 couleurs = 20 variantes en une
operation au lieu de 20 saisies ; un plan de travail en 4 largeurs x 3
profondeurs = 12 references de la meme facon.

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
d'attribut. Reutiliser `product_variants` pour les trois "saveurs" evite de
dupliquer toute cette mecanique (et donc tous les bugs potentiels) pour
chaque nouveau type de variante qu'on voudrait ajouter plus tard (ex:
pointure pour la chaussure, format pour l'electromenager...).

**Par produit** : chaque produit choisit individuellement s'il utilise des
variantes (case "Ce produit a des variantes" sur sa fiche,
`products.has_variants`). Un catalogue mixte (certains produits avec
variantes, d'autres sans, voire un melange vetement/bouteille/materiel) est
le cas normal.

**Modele de donnees** : table `product_variants` (SKU propre, code-barre,
taille, couleur, millesime, contenance en cl, largeur, hauteur, profondeur et
poids en texte libre, prix optionnel qui surcharge celui du produit, `attributes_json` en reserve pour d'autres attributs
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
| Produits | 144 (dont 26 a variantes, 6 desactives, 34 en FIFO) |
| Variantes | 165 (taille/couleur, pointure, millesime/contenance, dimensions) |
| Lignes de stock | 294 (produits et variantes) |
| Categories / fournisseurs / marques | 9 / 7 / 7 |
| Unites / taxes / tags | 3 / 3 / 7 |
| Scenario complet | demande d'achat, commande, livraison, inventaire, mouvements, alertes |

De quoi remplir 6 pages de catalogue a 25 lignes par page, avec des articles
volontairement sous leur seuil pour alimenter le tableau de bord et l'ecran
Alertes. Pour voir les variantes, active `clothing_variants_enabled`,
`bottle_variants_enabled` et/ou `dimension_variants_enabled` dans l'ecran
Parametres.

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

## Inventaires : corriger ou supprimer un comptage saisi par erreur

Jusqu'ici, un comptage saisi ne pouvait ni etre modifie ni supprime : la
seule facon de corriger une quantite mal saisie etait de resaisir tout le
formulaire (produit, variante, emplacement) en esperant se souvenir des bons
choix, et une ligne saisie sur le mauvais produit restait definitivement
dans la liste sans moyen de l'annuler.

Deux ajouts dans le tableau "Comptages saisis" d'une session encore ouverte :
- **Corriger** : pre-remplit le formulaire "Ajouter un comptage" avec le
  meme produit, la meme variante et le meme emplacement que la ligne
  cliquee - il ne reste plus qu'a corriger la quantite et valider.
- **Supprimer** : retire completement une ligne saisie par erreur (mauvais
  produit choisi). Uniquement possible tant que la session n'est pas
  finalisee.

Pourquoi ce n'est PAS une edition en place de la ligne existante ("Corriger"
cree un nouveau comptage plutot que de modifier l'ancien) : voir la question
de legalite/normalite ci-dessous, elle repond aussi a ce choix technique.

Consequence directe : un meme produit peut desormais avoir plusieurs lignes
dans le tableau (le comptage d'origine, puis sa correction). Comme c'est
deja le cas depuis le debut (la finalisation ne retient que le dernier
comptage saisi par produit/variante/emplacement), une colonne **"Statut"**
indique desormais explicitement, pour chaque ligne, si elle sera "Appliquee
a la finalisation" ou "Remplacee par un comptage plus recent" (affichee en
grise) - avant cet ajout, rien ne le disait, on pouvait facilement confondre
les deux lignes.

**Verifie** : un comptage errone (7) suivi d'une correction (8) - la
premiere ligne passe bien "Remplacee", la seconde "Appliquee" ; le bouton
Corriger pre-remplit bien le formulaire (produit et quantite) ; le bouton
Supprimer retire bien la ligne (verifie sur une base reelle, avec en plus
la verification que la suppression est refusee une fois la session
finalisee, et qu'un identifiant de comptage d'une autre session est
rejete).

## Ecran Produits : filtres Categorie, Fournisseur et Emplacement

L'ecran Produits proposait deja un filtre par entrepot et par tag, mais pas
par categorie, fournisseur ou emplacement - alors que ce sont des criteres
tout aussi naturels pour retrouver un article dans un catalogue qui en
compte beaucoup.

Trois filtres ajoutes a cote des deux existants :
- **Categorie** et **Fournisseur** : listes deroulantes classiques.
- **Emplacement** : desactive tant qu'aucun entrepot n'est choisi (un
  emplacement appartient a un seul entrepot, comme partout ailleurs dans
  l'application), puis propose les emplacements de l'entrepot selectionne
  une fois celui-ci choisi.

Les filtres se combinent entre eux (ex: categorie + fournisseur + entrepot
en meme temps), comme le faisaient deja entrepot et tag. Le bouton
"Effacer filtres" les reinitialise tous.

Cote serveur, category_id et supplier_id etaient deja acceptes par l'API
(simplement jamais exposes a l'ecran) ; le filtre par emplacement, lui,
n'existait pas du tout et a ete ajoute au meme titre que celui par
entrepot.

**Verifie** (navigateur reel, avec un produit place a l'emplacement A1 de
l'entrepot Principal) : le filtre categorie restreint bien la liste aux
produits de la categorie choisie ; le filtre fournisseur idem ; le filtre
emplacement reste desactive avec le message "Choisis d'abord un entrepot"
tant qu'aucun entrepot n'est selectionne, s'active une fois un entrepot
choisi, et ne montre bien que le produit range a cet emplacement une fois
selectionne (avec la colonne Stock qui bascule sur "Stock (entrepot
Principal)", comme le fait deja le filtre entrepot seul).

## Ajout produit : suppression de 5 champs qui ne servaient a rien

Suite a la remarque precedente sur les variantes, la question a ete posee
pour "Poids kg", "Largeur cm", "Hauteur cm", "Profondeur cm" et
"Conditionnement" du formulaire produit : a quoi servent-ils ?

Verification faite : ces 5 champs etaient bien enregistres en base, mais
n'etaient affiches NULLE PART - ni sur la fiche produit (onglet Infos), ni
dans la liste des produits, ni en export/import CSV, ni sur l'etiquette.
Meme defaut que les anciens "stock mini/maxi/securite" deja corriges
(migration 202602270015) : des champs qui donnent l'illusion de servir a
quelque chose, sans aucun effet reel.

Pour le poids et les 3 dimensions, l'equivalent utile existe deja et reste
disponible : quand l'option "materiel" est activee dans Parametres, le
module **Variantes** propose des champs libres largeur/hauteur/profondeur/
poids (memes champs texte libres que "taille" ou "cl" pour les autres
options de variantes) - exactement le meme principe que celui deja en
place pour ces deux dernieres.

Les 5 champs ont ete retires du formulaire "Ajout/Edition produit". Les
colonnes restent en base (aucune donnee saisie n'est perdue) : modifier un
produit qui a deja ces valeurs ne les efface pas, elles restent
simplement invisibles depuis ce formulaire (comme avant, elles ne l'etaient
de toute facon nulle part).

**Verifie** : le formulaire "Ajout produit" ne propose plus ces 5 champs ;
modifier un produit qui possede deja des valeurs de poids/dimensions/
conditionnement en base envoie bien une requete de mise a jour SANS ces
champs (verifie sur la requete reellement envoyee), donc sans les
ecraser.

## Ajout produit : les champs de variante (cl, taille...) introuvables

Quand une option de variantes est activee dans Parametres (vetement:
taille/couleur, ou bouteille: millesime/contenance), le formulaire "Ajout
produit" propose un champ "Ce produit a des variantes" - mais choisir "Oui"
ne faisait apparaitre aucun champ pour saisir les valeurs elles-memes (la
contenance en cl, la taille...), et rien n'indiquait ou aller les
renseigner.

C'est normal qu'elles ne soient pas dans ce formulaire : un produit a
variantes en a generalement plusieurs a la fois (ex: 3 tailles x 4
couleurs), ce qui ne peut pas tenir dans un champ unique de sa fiche. Ces
valeurs se saisissent dans le module dedie **Variantes** (menu de gauche),
qui existait deja et permet de les ajouter une par une ou en lot (toutes
les combinaisons possibles generees d'un coup a partir des listes de
tailles/couleurs ou de millesimes/contenances saisies). Mais rien sur
l'ecran "Ajout produit" ne le disait : le champ se contentait d'un
"Oui - gerer les variantes dans le module dedie", sans dire lequel ni ou
le trouver.

Un texte d'aide a ete ajoute sous ce champ, qui renvoie explicitement vers
le menu "Variantes" et rappelle qu'on peut y ajouter les combinaisons en
lot.

**Verifie** (navigateur reel) : avec l'option "contenance en cl" activee
dans Parametres, le formulaire "Ajout produit" affiche desormais sous le
champ "Ce produit a des variantes (millesime/contenance)" le texte "Les
valeurs precises (millesime/contenance) ne se saisissent pas ici : une
fois \"Oui\" choisi et le produit enregistre, utilise le menu **Variantes**
pour les ajouter une par une ou en lot..." ; meme verification avec les
deux options (vetement + bouteille) activees en meme temps, le libelle
s'adapte bien aux deux ("taille/couleur ou millesime/contenance").

## Fiche produit : fusion des onglets Media/Pieces jointes, apercu en grand, acces direct a la fiche

Trois ameliorations liees a la fiche produit, remontees ensemble :

**1. Onglets "Media" et "Pieces jointes" fusionnes en un seul onglet "Documents"**

Les deux onglets faisaient la meme chose (televerser un fichier lie au
produit) avec deux formulaires separes, deux listes separees, et une
distinction "Media / Piece jointe" que rien n'obligeait a faire cote
utilisateur. Un seul onglet **Documents** les remplace desormais : un seul
formulaire de televersement, une seule liste. Le type (image ou document)
est detecte automatiquement a partir du fichier envoye, l'utilisateur n'a
plus a le choisir.

Comme l'application n'a pas encore de donnees de production (uniquement
des donnees de demonstration a ce stade), aucune migration de donnees n'a
ete necessaire pour cette fusion.

**2. Apercu "Voir en grand" sans telechargement force**

Les images et les PDF lies a un produit ne pouvaient etre consultes qu'en
les telechargeant au prealable. Un bouton **Voir en grand** a ete ajoute a
cote de "Telecharger le fichier" : il ouvre l'image dans une fenetre
d'apercu directement dans l'ecran, et le PDF dans un nouvel onglet du
navigateur (qui l'affiche nativement), sans forcer de telechargement.

**Verifie** (navigateur reel) : sur les trois documents de test (image,
PDF, .docx), le bouton "Voir en grand" apparait uniquement pour l'image et
le PDF (absent pour le .docx, qui n'a pas d'apercu possible) ; le clic sur
l'image ouvre bien une fenetre d'apercu avec l'image chargee.

**3. Le bouton "Fiche" accede directement au detail du produit**

Cliquer sur "Fiche" dans la liste des produits chargeait bien le detail du
produit en bas de page, mais il fallait ensuite scroller manuellement pour
le voir. Le clic sur "Fiche" fait maintenant defiler la page automatiquement
jusqu'a la fiche.

**Verifie** (navigateur reel) : clic sur "Fiche" depuis le haut de la liste
des produits - la page defile automatiquement (scrollY passe de 0 a une
position affichant la fiche) sans intervention manuelle.

## Fiche produit : formats de fichiers acceptes affiches (media et pieces jointes)

Sur les onglets **Media** et **Pieces jointes** d'une fiche produit, rien
n'indiquait quels fichiers etaient acceptes : un fichier refuse (un .txt
par exemple) l'etait sans que l'ecran ait prevenu de quoi que ce soit au
prealable.

Le serveur a toujours limite les televersements a une liste precise
d'extensions (verifiees non seulement par leur nom mais aussi par leur
contenu reel, pour la securite) : images (jpg, jpeg, png, gif, webp), PDF,
Word (doc, docx), Excel (xls, xlsx) et CSV - le format .txt n'en a jamais
fait partie.

Ajoute sur les deux onglets :
- un texte d'aide sous le champ, rappelant la liste des formats acceptes
  et la taille maximale (15 Mo) ;
- le selecteur de fichiers du navigateur filtre desormais directement sur
  ces formats (les fichiers non-conformes apparaissent grises quand on
  parcourt ses dossiers, au lieu d'etre proposes puis refuses).

**Verifie** : sur un vrai serveur, un fichier .png est accepte et un
fichier .txt est refuse avec un message explicite ("Type de fichier non
autorise : .txt") - ce comportement serveur existait deja, seul l'ecran ne
le disait pas a l'avance.

## Mouvements de stock : le motif restait parfois affiche en anglais

Sur l'ecran **Mouvements** (et l'onglet Mouvements d'une fiche produit),
la colonne "Motif" affichait parfois des codes techniques non traduits
(ex: `PO_RECEIPT`, `INITIAL_STOCK`, `SERIAL_OUT`...), alors que le reste
de l'ecran est en francais. Le champ de saisie du motif lui-meme
suggerait carrement de taper un code en anglais ("INVENTORY/PO_RECEIPT/
etc").

Deux choses distinctes ici :
- Les motifs **generes automatiquement** par l'application (reception
  d'une commande d'achat, sortie sur un bon de livraison, finalisation
  d'un inventaire, stock initial d'un produit, mouvements lies a un
  numero de serie...) sont desormais traduits dans la colonne "Motif",
  comme le sont deja les colonnes "Type" ou "Statut" ailleurs dans
  l'application.
- Le champ "Code motif" du formulaire de saisie reste un champ libre (on
  peut toujours taper ce qu'on veut) - mais son exemple suggere
  desormais des motifs en francais ("Casse", "Perte", "Correction
  inventaire"...) proposes automatiquement pendant la frappe, plutot que
  des codes techniques en anglais.

**Verifie** : un mouvement genere par une reception de commande affiche
"Reception commande achat" (au lieu de `PO_RECEIPT`) dans l'historique ;
un motif saisi librement ("Casse") reste affiche tel quel.

## Correctif : la ligne "Produit" du tableau de saisie d'un bon de livraison se chevauchait

Sur l'ecran **Livraisons**, des que le catalogue depassait une douzaine de
produits, la colonne "Produit" du tableau de saisie affichait bien le champ
de filtrage ("Filtrer (140 entrees)...") mais la liste deroulante juste en
dessous debordait par-dessus les colonnes suivantes (Variante, N° Serie,
Quantite...) au lieu de rester proprement dans sa colonne - un peu comme si
les champs "flottaient" les uns sur les autres.

Cause : le champ de filtrage est ajoute par JavaScript juste avant la liste
deroulante qu'il filtre, sans aucun espace entre les deux. Dans les
formulaires habituels (Demandes achat, Commandes achat...), ca ne se
voyait pas car le champ et sa liste sont a l'interieur d'un bloc qui les
empile deja verticalement. Mais dans le tableau de saisie d'une livraison,
rien ne forcait cet empilement : le navigateur considerait le champ de
filtrage et la liste deroulante comme un seul bloc insecable, sur la meme
ligne - et laissait la liste deborder de sa colonne plutot que de passer a
la ligne suivante.

Corrige au niveau du champ de filtrage lui-meme (pas seulement pour
l'ecran Livraisons, donc) : il commence desormais toujours sur sa propre
ligne, quel que soit l'endroit de l'application ou une liste deroulante
assez longue pour meriter un filtre est utilisee.

**Verifie** : reproduit puis corrige dans un vrai navigateur (Chromium,
capture d'ecran et mesure exacte de la position des champs a l'appui) sur
l'ecran Livraisons avec un catalogue de plus de 20 produits - la liste
deroulante des produits reste desormais bien dans sa colonne, sans deborder
sur les colonnes voisines, que le produit soit choisi directement ou via
le filtre de recherche.

## Correctif : le champ "Variante" des demandes et commandes d'achat n'avait pas de titre

Sur les ecrans **Demandes achat** et **Commandes achat**, des qu'un produit
a variantes etait choisi dans le formulaire "Ajouter la ligne", la liste
deroulante des variantes apparaissait bien a cote du champ Produit - mais
sans aucun libelle "Variante" au-dessus, contrairement a tous les autres
champs du formulaire (Quantite, Cout prefere, etc.). Le champ etait donc
present et fonctionnel, mais on ne pouvait pas deviner a quoi il servait
juste en le regardant.

Cause : la liste deroulante des variantes portait directement la classe qui
la cache tant qu'aucun produit a variantes n'est choisi
(`<select class="hidden">`), sans etre entouree d'une etiquette
`<label><span>Variante</span>...</label>` comme le sont tous les autres
champs du formulaire. Une fois la liste affichee (produit a variantes
choisi), elle se retrouvait donc seule dans sa case du formulaire, sans
titre - exactement ce qui apparait sur les captures d'ecran transmises. Ce
n'etait pas lie a la liste "Produit" avec filtre de recherche (qui, elle,
s'affiche correctement) : les deux champs sont simplement independants l'un
de l'autre.

Corrige en entourant la liste des variantes d'une etiquette avec son titre,
comme partout ailleurs dans l'application - le titre "Variante" s'affiche
desormais correctement des qu'un produit a variantes est selectionne, sur
les deux ecrans.

**Verifie** : reproduit puis corrige dans un vrai navigateur (Chromium,
capture d'ecran a l'appui) sur les deux ecrans, avec un catalogue de plus
de 12 produits (pour retrouver le champ "Produit" avec filtre, comme sur
les captures transmises) dont un produit a variantes - le titre "Variante"
apparait desormais bien au-dessus de la liste, que le produit soit choisi
directement dans la liste ou via le filtre de recherche.

## Inventaires : la finalisation ajuste le stock selon le comptage - est-ce normal ?

Question posee directement : un inventaire qui, a la finalisation,
augmente ou diminue le stock selon l'ecart constate, est-ce un comportement
normal pour un logiciel de gestion de stock, et est-ce legal de proceder
ainsi ?

**C'est le comportement attendu, et c'est la raison d'etre d'un inventaire
physique.** Un inventaire sert precisement a faire correspondre le stock
theorique (ce que le logiciel croit avoir) au stock reel (ce qui est
physiquement present) : casse non enregistree, erreur de saisie anterieure,
vol, produit mal range... le stock theorique finit toujours par diverger un
peu du reel avec le temps, et l'inventaire est le mecanisme qui resynchronise
les deux. Toute application de gestion de stock serieuse (Dolibarr, SAP,
Odoo, etc.) fonctionne sur ce meme principe : compter, comparer a l'attendu,
ajuster.

Pour la partie legale : Claude n'est pas comptable ni juriste, et ce point
merite d'etre confirme aupres d'un expert-comptable si un doute subsiste.
Ce qui peut etre dit factuellement sur ce que fait l'application : en
France, l'inventaire physique des stocks est une obligation comptable
(article L123-12 du code de commerce - "vérifier l'existence et la valeur
des éléments actifs et passifs du patrimoine"), donc ajuster le stock
informatique pour qu'il reflete le comptage physique n'est pas seulement
normal, c'est ce que la loi attend. Ce qui compte pour la conformite n'est
pas de savoir SI l'ajustement doit avoir lieu, mais qu'il soit **trace** :
c'est deja le cas ici - chaque ajustement genere un mouvement de stock de
type "Ajustement" avec le motif "INVENTORY" et l'identifiant de la session
qui l'a produit (visible dans l'historique des mouvements), et chaque
comptage individuel reste visible avec qui l'a saisi et quand (renforce par
l'ajout ci-dessus : meme un comptage remplace par une correction reste
visible, il n'est jamais silencieusement efface - seule une suppression
manuelle et explicite, avant finalisation, le retire).

## Numeros de serie : date d'entree et date de sortie (utile pour la garantie)

La fiche d'un numero de serie (que ce soit dans le tableau ou dans le
resultat de "Rechercher un article par numero de serie") affiche desormais
la date d'enregistrement ("Entree le") et, si l'exemplaire est actuellement
sorti, la date a laquelle il est sorti ("Sorti le") - utile pour verifier une
garantie sans avoir a chercher dans l'historique des mouvements.

La date de sortie s'appuie sur la derniere mise a jour du numero de serie,
fiable tant que le statut actuel est bien "sorti" (mise a jour a chaque
sortie ou remise en stock, que ce soit via une livraison ou le bouton
"Marquer sorti"). Si l'exemplaire est revenu en stock, la date de sortie
n'a plus de sens et n'est donc plus affichee.

Le resultat de la recherche par numero de serie indique aussi desormais, si
l'exemplaire est sorti, **a qui il a ete vendu et sur quel BL** ("Vendu a :
Client X (BL-0042 du 12/03/2026)") - directement dans la fiche, sans avoir a
lire le tableau "Historique des ventes" juste en dessous. C'est la derniere
livraison NON annulee qui est retenue : une livraison annulee remet
l'exemplaire en stock, donc si le statut est toujours "sorti", ce n'est pas
elle qui l'explique - une livraison plus ancienne ou plus recente, non
annulee, est la bonne reponse. Un exemplaire sorti par le bouton "Marquer
sorti" (sans passer par une livraison) l'indique clairement : "Sorti sans
livraison associee (sortie manuelle ou regularisation)".

**Verifie** : trois scenarios testes - vendu (avec une livraison annulee plus
recente dans l'historique, pour s'assurer qu'elle est bien ignoree), sorti
sans aucune livraison, et en stock (aucune mention de vente, meme avec un
historique de livraisons annulees).

## Livraisons : voir les produits d'un bon de livraison depuis l'historique

Dans l'historique des bons de livraison, impossible jusqu'ici de savoir quels
produits un BL contenait sans rouvrir son impression. Un bouton "Produits
livres" apparait desormais a cote du numero de chaque BL et ouvre une petite
fenetre listant les lignes (produit, variante eventuelle, numero de serie
eventuel, quantite, prix unitaire).

Techniquement, ce n'est pas une liste deroulante (`<select>`) classique : un
`<select>` charge au clic se serait ouvert vide le temps du chargement (rien
n'affiche "Chargement..." dans une liste deroulante native pendant qu'on
l'observe). La popup utilisee ici est le meme mecanisme deja utilise pour le
detail d'une demande ou d'une commande d'achat - elle se remplit a la
demande (un seul BL a la fois, pas un chargement de toutes les lignes de
tous les BL affiches) et affiche un etat de chargement clair.

**Verifie** : test simule le clic sur "Produits livres", verifie que la
popup s'ouvre avec le bon numero de BL, le produit simple et son numero de
serie, le produit a variante avec sa variante, et les quantites - sans appel
reseau pour les BL qu'on ne consulte pas.

## Correctif : "Remettre en stock" un numero de serie echouait ("Reference invalide")

Depuis l'ecran Numeros de serie, cliquer sur "Remettre en stock" (pour un
exemplaire marque "sorti") ouvrait une fenetre pour choisir l'entrepot de
retour, puis echouait systematiquement avec *"Reference invalide : l'element
lie n'existe pas ou plus"*.

Cause : cette fenetre ne renvoyait qu'un simple identifiant d'entrepot, alors
que le code qui l'appelle attendait un objet avec l'entrepot ET
l'emplacement. L'entrepot envoye au serveur valait donc toujours "absent",
remplace silencieusement par 0 cote serveur - un entrepot qui n'existe pas,
d'ou le rejet par la base de donnees (contrainte de cle etrangere).

La fenetre "Ou cet article revient-il ?" propose desormais aussi le choix de
l'emplacement (comme partout ailleurs dans l'application) et transmet
reellement l'entrepot choisi.

**Verifie** : reproduction exacte de l'erreur d'origine avec l'ancien envoi
(entrepot absent -> "Reference invalide"), puis avec le nouvel envoi
(entrepot et emplacement transmis) -> remise en stock reussie, sur une base
reelle. Verifie egalement par un test qui simule l'ouverture de la fenetre,
le choix de l'entrepot puis de l'emplacement, et la validation.

## Correctif majeur : une sortie avec numero de serie retirait 2 articles au lieu d'1

Scenario signale : stock a 2 (une entree de 2), un numero de serie enregistre
en regularisation (l'article etait deja compte), puis une sortie de quantite
1 avec ce numero de serie coche sur l'ecran Mouvements. Resultat observe :
le stock tombait a 0 au lieu de 1.

Cause : l'ecran Mouvements enregistre deux choses l'une apres l'autre pour
une sortie avec numeros de serie coches - le mouvement de sortie
(quantite totale, avec le motif/la note/le client saisis) ET un appel
"marquer sorti" par numero de serie coche (pour que chaque exemplaire change
de statut). Le premier retirait deja la quantite du stock ; le second, en
plus de changer le statut du SN, retirait *lui aussi* 1 du stock - la meme
sortie etait donc decomptee deux fois. Le meme souci existait deja et avait
ete corrige cote entree (un mouvement d'entree + un enregistrement de SN
"qui ne recompte pas" via `creates_stock_entry: false`) ; le cote sortie
avait ete oublie.

Le "marquer sorti" appele depuis l'ecran Mouvements passe desormais un
drapeau (`skip_stock_move`) qui lui dit de changer uniquement le statut du
numero de serie, sans toucher au stock - puisque le mouvement de sortie
s'en est deja charge. Le bouton "Marquer sorti" independant, sur l'ecran
Numeros de serie (quand on sort un exemplaire hors du flux Mouvements), lui,
continue de deplacer le stock lui-meme exactement comme avant : rien ne
change pour cet usage-la.

**Verifie** : sur une base reelle, stock 2 -> SN en regularisation -> sortie
de 1 avec ce SN coche -> stock a 1 (au lieu de 0 avant le correctif) et le SN
passe bien au statut "sorti". Le mark-out "autonome" (sans passer par
Mouvements) continue lui aussi de retirer exactement 1, comme avant. Verifie
egalement par un test qui simule le remplissage et la soumission reelle du
formulaire Mouvements (coche le SN, valide) : un seul mouvement de sortie
envoye, un seul appel "marquer sorti" avec le drapeau, quantite finale
correcte.

## Confirmation a l'enregistrement d'un mouvement de stock

Valider un mouvement (entree, sortie, transfert, ajustement) ne montrait
aucune confirmation : le formulaire se vidait juste et la ligne apparaissait
dans l'historique en bas de l'ecran, sans autre indication qu'il fallait
aller verifier soi-meme un peu plus bas. Un message de confirmation
s'affiche desormais au-dessus du formulaire apres l'enregistrement, par
exemple *"Mouvement enregistre (Sortie, quantite 1)."*.

## Listes deroulantes avec filtre : la selection automatique ne se propageait pas

Au-dela de 12 entrees, une liste deroulante (produit, emplacement...) affiche
un champ de filtre : on tape, et si un seul resultat correspond, il est
selectionne automatiquement. Ce cas-la ne declenchait pas l'evenement
`change` du navigateur - contrairement a une selection faite directement
dans la liste (au clic ou au clavier). Tout ce qui reagit a ce choix pour
mettre a jour un autre champ restait donc **muet quand on passait par le
filtre** : sur l'ecran Numeros de serie par exemple, choisir un produit a
variantes directement dans la liste faisait apparaitre le choix de la
variante, mais le meme choix fait via le filtre ne l'affichait pas.

Le filtre declenche desormais lui-meme l'evenement `change` quand il
selectionne automatiquement un resultat unique - exactement comme une
selection manuelle. Cela corrige le meme souci partout ou ce mecanisme est
utilise (numeros de serie, mouvements, demandes d'achat, commandes...), pas
seulement sur l'ecran ou il a ete signale.

**Verifie** : sur l'ecran Numeros de serie, filtrer jusqu'a un produit unique
a variantes fait bien apparaitre et se peupler le champ variante, exactement
comme un choix direct dans la liste.

## Numeros de serie : possible pour une variante, pas seulement pour le produit

L'ecran "Numeros de serie" permettait d'enregistrer un SN pour un produit,
mais pas pour une variante precise (taille, couleur, millesime...). Cote
serveur, `product_serials.variant_id` existait deja et etait deja utilise -
recherche par SN, historique de livraison, mouvements de stock - mais le
formulaire de creation ne demandait jamais quelle variante, et n'importait
donc rien depuis un produit a variantes : impossible de savoir *quel
exemplaire de quelle taille/couleur* portait un SN donne.

Le formulaire propose desormais un champ **"Variante"** juste apres le choix
du produit. Il reste cache pour un produit simple (rien ne change dans ce
cas), et apparait automatiquement - rempli avec les variantes actives du
produit choisi - des que celui-ci utilise des variantes ; il devient alors
obligatoire, comme partout ailleurs dans l'application (Mouvements, Demandes
d'achat, Commandes, Inventaires). La quantite en stock deplacee par
l'enregistrement d'un SN va bien sur la ligne de stock de la variante
choisie, et plus seulement sur celle du produit.

Le tableau des numeros de serie enregistres et la fiche "Rechercher un
article par numero de serie" affichent maintenant la variante quand il y en
a une (ex : *SN-00012345 - variante : M / Rouge*).

**Verifie** : sur un produit sans variantes, le champ reste cache et rien ne
change ; sur un produit a variantes, le champ apparait, se peuple avec les
bonnes variantes, et bloque l'enregistrement tant qu'aucune n'est choisie ;
une fois choisie, l'API enregistre bien le SN avec son `variant_id`, et sur
une base reelle la ligne de stock de la variante concernee (et non celle du
produit) est bien celle qui augmente.

## Stock initial : rangement direct a l'emplacement

Le stock initial saisi a la creation d'un produit arrivait dans l'entrepot
mais **"non range"** : aucune zone, aucun emplacement. Il fallait enchainer
un transfert interne juste apres pour le placer, alors qu'on sait
parfaitement ou on le met au moment de la saisie.

Le formulaire produit propose desormais, a la creation, un troisieme champ :
**"Stock initial - emplacement (optionnel)"**. La liste se remplit avec les
emplacements de l'entrepot choisi juste au-dessus (regroupes par zone, comme
partout ailleurs) et se met a jour si l'on change d'entrepot - impossible de
ranger un article dans une allee qui n'existe pas la ou il arrive.

Laisse vide, le comportement reste celui d'avant : la quantite entre dans
l'entrepot sans emplacement precis. Le message de confirmation dit
desormais lequel des deux s'est produit : *"Produit cree avec un stock
initial de 5, range en A2"* ou *"... non range dans l'entrepot"*.

Techniquement, c'est le meme mouvement d'entree qu'avant, avec son
emplacement de destination renseigne : rien de nouveau cote serveur, et
l'operation reste tracee et auditee comme n'importe quel mouvement.

**Verifie** : la liste des emplacements suit l'entrepot choisi ; le mouvement
part avec le bon emplacement ; et sur une base reelle, la ligne de stock
creee porte bien l'emplacement (`A2`, 5 unites) au lieu d'un stock non range.
La verification de paquet enchaine desormais creation de produit ->
mouvement d'entree, le chemin complet du stock initial.

## Correctif : stock initial ignore a la creation d'un produit

Creer un produit en renseignant "Stock initial - quantite" affichait
**"Cannot access 'initialWarehouseId' before initialization"**. Le produit
etait bien cree, mais **avec un stock a 0** : le mouvement d'entree n'etait
jamais enregistre.

**Cause** : les deux valeurs du stock initial etaient lues dans le code
APRES le bloc qui s'en sert (et apres l'envoi du produit a l'API). En
JavaScript, utiliser une constante `const` avant sa declaration leve une
erreur - celle qui s'affichait. Le produit venant d'etre cree, l'ecran
donnait donc un resultat a moitie faux : article present, stock absent, et un
message technique a la place de la confirmation.

Les deux valeurs sont desormais extraites **avant** l'appel a l'API. Effet de
bord corrige au passage : les champs `initial_warehouse_id` et
`initial_quantity`, qui ne sont pas des colonnes de `products`, partaient
malgre tout dans le payload de creation.

### Ce que la verification ne couvrait pas

Les verifications portaient sur l'API (lectures **et** ecritures) et sur
l'affichage des ecrans - mais **aucune ne SOUMETTAIT un formulaire**. Or
c'est precisement le chemin en cause : le formulaire produit, rempli comme un
utilisateur le remplit, avec un stock initial.

Un test le fait desormais dans un DOM simule : il remplit le formulaire,
declenche l'envoi, et verifie que **deux** appels partent - la creation du
produit puis le mouvement d'entree, avec la bonne quantite et le bon entrepot
- qu'aucune erreur JavaScript n'est levee, et que le message affiche est bien
la confirmation. Rejoue sur le paquet precedent, il reproduit exactement le
defaut : un seul appel, aucun mouvement, message d'erreur.

## Correctif : creation de produit impossible ("le champ statut est obligatoire")

Enregistrer un nouveau produit depuis l'ecran echouait avec
**"Le champ 'status' est obligatoire"** - un champ qui ne figure PAS dans le
formulaire. Aucune creation de produit n'etait possible depuis
l'application.

**Cause** : le champ `status` (ACTIVE/INACTIVE) a ete retire du formulaire
produit, remplace par l'interrupteur unique `is_active` (il faisait doublon).
La liste des champs obligatoires cote serveur, elle, n'a pas suivi : elle
exigeait toujours `status`. L'interface ne l'envoyait plus, le serveur le
reclamait - et le message parlait d'un champ introuvable a l'ecran.

- `status` retire des champs obligatoires du produit. La colonne reste en
  base (import CSV, installations existantes) avec sa valeur par defaut.
- `ProductRepository` **aligne `status` sur `is_active`** a la creation comme
  a la modification : un produit cree inactif ne peut plus etre marque ACTIVE
  dans cette colonne. Une valeur explicitement fournie (import CSV) reste
  prioritaire.

### Pourquoi les verifications ne l'avaient pas vu

La verification de paquet ne faisait que **lire** : elle chargeait tous les
ecrans (GET) et concluait que tout allait bien. Or ici, tout s'affichait
parfaitement - c'est l'**enregistrement** qui etait casse.

Elle effectue desormais aussi des **ecritures**, avec exactement les champs
que les formulaires envoient : creation d'une categorie, d'un tag, d'un
**produit**, d'un entrepot, d'un fournisseur et d'un client. Un champ exige
par le serveur mais absent d'un formulaire est detecte immediatement, avant
livraison.

## Profils utilisateur : libelles francais et droits affiches

Le formulaire d'un utilisateur proposait une liste de **codes techniques**
(`ADMIN`, `MANAGER`, `STOREKEEPER`, `EMPLOYEE`), sans la moindre indication
de ce que chacun autorise. On attribuait donc un profil au juge.

- **Libelles en francais partout** : Administrateur, Responsable, Magasinier,
  Acheteur, Employe, Lecture seule - dans la liste deroulante comme dans la
  colonne Profil de la liste des utilisateurs.
- **Aide sous le champ** : le profil choisi affiche immediatement ce qu'il
  permet ("Tout ce qui touche au stock physique : mouvements, numeros de
  serie, livraisons, inventaires. Pas d'achats, pas de catalogue, pas
  d'administration.").
- **Tableau "Profils et droits"** sur l'ecran Utilisateurs : pour chaque
  profil, le resume et la **liste exacte des ecrans ou il peut enregistrer**.

Ce tableau n'est pas une documentation ecrite a la main : il est **calcule a
partir de la matrice que l'application applique reellement**
(`ROLE_MATRIX`, qui alimente aussi `canWrite`). Il ne peut donc pas decrire
autre chose que le comportement reel. Cote serveur, `RoleMiddleware`
(`backend/public/index.php`) pose les memes regles : un profil qui n'a pas le
droit se voit refuser l'operation meme en contournant l'interface. Toute
evolution doit etre faite des deux cotes.

### Deux incoherences corrigees au passage

- **Le profil "Employe" n'existait pour personne.** L'installateur le cree
  (`EMPLOYEE`), mais ni le frontend ni le backend ne le connaissaient : un
  utilisateur ainsi cree se retrouvait en lecture seule **de fait**, sans que
  personne l'ait decide ni annonce. Il est desormais un profil a part
  entiere, documente comme "consultation uniquement".
- **Le profil "Acheteur" n'etait pas creable.** `BUYER` est implemente
  (achats, fournisseurs, clients) et reconnu par le backend, mais
  l'installateur ne creait pas la ligne : il fallait l'ajouter a la main en
  base pour pouvoir l'attribuer. Il fait maintenant partie des profils
  installes par defaut.

Un profil ajoute directement en base et inconnu de l'application reste
possible : il est alors traite en **lecture seule**, et le formulaire le dit
explicitement plutot que de laisser croire a des droits.

## Incident : toute l'API en erreur 500 (signatures de methodes)

Symptome : **toutes** les routes de l'API repondent 500 en meme temps
(`/auth/me`, `/lookups/options`, `/settings`, `/dashboard/stats`...), la page
affiche "Le dashboard n'a pas pu etre charge", et la reponse du serveur est
**vide** - aucun message, meme avec `APP_DEBUG=1`.

**Cause** : `PdoCrudRepository::buildWhere()` a recu un parametre
supplementaire (`string $prefix = ''`, pour les jointures de libelles), sans
que les classes filles qui redefinissent cette methode soient mises a jour.
En PHP, une methode fille dont la signature differe de la methode parente est
une **erreur fatale au chargement de la classe** : elle survient avant tout
code applicatif, donc sur toutes les routes a la fois. `ProductRepository` et
`ProductVariantRepository` etaient concernes (`UserRepository` avait deja ete
corrige).

**Pourquoi `php -l` ne l'a pas vu** : `php -l` verifie la SYNTAXE d'un fichier
isole. Une incompatibilite entre une classe et son parent ne se voit qu'au
chargement des deux classes ensemble, donc a l'execution.

### Ce qui a ete mis en place pour que ca ne se reproduise pas

Le fichier `backend/storage/logs/php-error.log` **n'existe pas tant que tout
fonctionne** : il est cree a la premiere erreur fatale. Le dossier, lui, est
livre avec l'application (avec un `LISEZ-MOI.txt` et un `.htaccess` de
refus), pour qu'on puisse verifier ses droits d'ecriture AVANT d'en avoir
besoin. S'il n'est pas accessible en ecriture (hebergement mutualise
verrouille), le detail part dans le journal d'erreurs PHP de l'hebergeur :
rien n'est perdu.

- **Filet de securite dans `backend/bootstrap.php`**
  (`register_shutdown_function`) : les erreurs que le gestionnaire
  d'exceptions ne voit pas - syntaxe, fichier manquant, signature
  incompatible - renvoient desormais un JSON explicite
  (`Erreur fatale du serveur. Detail enregistre dans
  backend/storage/logs/php-error.log`) et sont **journalisees** avec fichier
  et numero de ligne. Avec `APP_DEBUG=1`, le detail figure aussi dans la
  reponse. Fini le 500 muet.
- **Verification de paquet par appel reel de l'API** : avant livraison, le
  paquet est demarre et une vingtaine de routes sont appelees (connexion,
  lookups, reglages, tableau de bord, produits, variantes, mouvements,
  numeros de serie, achats, livraisons, inventaires, tags, utilisateurs,
  imports). Un `php -l` vert ne suffit pas : seule l'execution reelle revele
  ce genre de panne.

### Si l'ecran affiche de nouveau une erreur generale

1. Ouvrir `backend/storage/logs/php-error.log` : la derniere ligne nomme le
   fichier et la ligne fautifs.
2. A defaut, passer `APP_DEBUG=1` dans `backend/.env`, recharger, lire le
   detail dans la reponse - **puis remettre `APP_DEBUG=0`**.
3. Verifier que le deploiement est complet : un seul fichier oublie
   (ex: une classe ajoutee par une mise a jour) produit exactement le meme
   symptome.

## Zones et emplacements : ce que chacun fait, et ou il apparait

Rappel du modele, qui expliquait a lui seul plusieurs surprises : **une zone
ne stocke rien**. C'est l'**emplacement** qui porte le stock, les numeros de
serie et les mouvements ; la zone ne sert qu'a regrouper des emplacements.
Une zone sans aucun emplacement n'est donc proposee nulle part a la saisie -
et rien ne le disait, d'ou l'impression qu'elle "n'apparait pas".

- **L'ecran Zones affiche desormais le nombre d'emplacements** de chaque
  zone, et signale en rouge `0 - zone inutilisable a la saisie`. Le probleme
  se voit d'un coup d'oeil au lieu d'etre decouvert au moment d'enregistrer
  un numero de serie.
- **Toutes les listes deroulantes d'emplacement sont regroupees par zone** :
  le nom de la zone apparait en intitule de groupe, au-dessus de ses
  emplacements ("Reception : A1 - Allee 1, A2 - Allee 2"). Elles n'affichaient
  que des codes (C1, C2...), les zones semblaient absentes de l'application.
  Applique partout : mouvements, fiche produit, numeros de serie, comptage
  d'inventaire. Les emplacements sans zone sont regroupes sous "Hors zone",
  en fin de liste.
- **Le filtre des listes longues cherche aussi dans le nom de la zone** :
  taper "reception" remonte les emplacements de cette zone, et le nom de la
  zone reste rappele a cote de chaque ligne filtree.
- **Message adapte quand l'entrepot n'a que des zones** : "Aucun emplacement
  (2 zone(s) definie(s)) - une zone ne se choisit pas ici, cree un
  emplacement par zone dans Logistique > Emplacements". Si tu ne raisonnes
  qu'en zones, la marche a suivre est donc : un emplacement par zone, portant
  le meme nom.

L'ecran Emplacements, lui, affiche deja le **nom** de la zone (et non son
identifiant) ainsi que la description : si ta liste montre encore `1`, `2`,
`3` dans la colonne Zone et aucune description, c'est le **cache du
navigateur** qui sert une ancienne version - voir la section sur les assets
versionnes ci-dessous.

**Verifie** : ecran Emplacements (zone nommee + description, "aucune zone"
pour un emplacement orphelin) ; ecran Zones (comptage exact, alerte sur la
zone vide) ; listes deroulantes groupees dans les mouvements et les numeros
de serie ; message specifique sur un entrepot qui n'a que des zones.

## Catalogue produit : plus de defilement horizontal

Le tableau des produits comptait **dix-sept colonnes** : il depassait la
largeur de l'ecran et imposait une barre de defilement horizontale, donc on
ne lisait jamais une ligne en entier. Mesure avant correction, sur un ecran
de 1366 px : la page reclamait **1687 px**.

- Les colonnes secondaires sont **masquees par defaut** (`secondary: true`) :
  ID, code barre, marque, unite, TVA, valorisation, variantes. Restent celles
  qu'on parcourt des yeux - SKU, nom, categorie, fournisseur, stock, prix,
  actif, emplacements, tags. Un bouton **"Toutes les colonnes"** les ramene
  toutes, et elles figurent de toute facon sur la fiche du produit.
- `min-width: 700px` retiree du tableau : cette valeur figee forcait un
  defilement des que l'ecran etait plus etroit.
- `min-width: 0` sur `.table-wrap`, `.panel`, `.content-panel` et
  `.workspace`. **C'est la correction de fond** : un enfant de flex/grid
  refuse par defaut de devenir plus etroit que son contenu
  (`min-width: auto`), donc un tableau large poussait TOUTE LA PAGE au lieu
  de defiler dans son propre cadre.
- Les textes longs reviennent a la ligne (`overflow-wrap: break-word`, et non
  `anywhere`, qui coupait au milieu des mots et separait le montant de son
  symbole).
- Les filtres de la barre d'outils ne s'etirent plus sur toute la largeur
  (ils heritaient du `width: 100%` des formulaires) et tiennent sur une
  ligne.

**Mesure apres correction**, dans un navigateur reel (Chromium), sur la liste
produit et sur la fiche produit ouverte (5 tableaux), a 1280, 1366 et 1600 px
de large : **aucun debordement de page, aucune barre horizontale**. En vue
"Toutes les colonnes", le seul tableau trop large defile dans son propre
cadre sans entrainer la page - comportement attendu pour un choix explicite.

## Couleur d'un tag : palette, pas hexadecimal

Le champ couleur d'un tag propose **douze pastilles nommees** (Rouge, Orange,
Ambre, Jaune, Vert, Emeraude, Cyan, Bleu, Indigo, Violet, Rose, Gris), la
pipette du navigateur pour une teinte libre, et le code hexadecimal affiche
a cote **en lecture** - utile pour reproduire une couleur de charte, mais
plus personne n'a a le taper. La couleur par defaut d'un nouveau tag est
`#6366f1` et non le noir du champ natif.

Le libelle du badge passe automatiquement en noir ou en blanc selon la
luminance du fond (formule WCAG) : sur un jaune ou un cyan clair, un texte
blanc devenait illisible.

### Si l'ecran n'affiche pas la derniere version

Les fichiers `app-clean.js` et `clean.css` etaient references **sans numero
de version** : apres une mise a jour, le navigateur continuait de servir sa
copie en cache. L'application deployee etait la nouvelle, l'ecran affichait
l'ancien comportement, sans le moindre message - et il fallait penser a vider
le cache. Leur URL porte desormais la date de modification du fichier
(`assetUrl()`), le navigateur recharge donc de lui-meme des que le fichier
change.

Reserve : un module importe depuis un fichier JS (`http-client.js`, importe
par `app-clean.js`) garde une URL ecrite dans le code JavaScript et ne passe
pas par ce mecanisme. Ces fichiers changent rarement ; en cas de doute apres
une mise a jour, un rechargement force (Ctrl+F5) suffit.

## Transfert interne : deplacer un article d'un emplacement a un autre

Depuis que le stock est suivi par emplacement, ranger une palette de l'allee
A1 vers A2 est une operation courante. Elle etait pourtant **impossible** :
le transfert exigeait un entrepot de destination **different** de l'entrepot
source ("Un entrepot de destination valide est requis pour un transfert"), et
il n'y en a pas quand on reste chez soi. Il fallait enchainer une sortie puis
une entree - deux mouvements sans lien, un historique faux, et un ecart de
stock a la moindre interruption entre les deux.

Un transfert **sans entrepot de destination** est desormais un transfert
**interne** : meme entrepot, de l'emplacement source vers l'emplacement de
destination. Le champ s'appelle maintenant "Entrepot destination (vide =
transfert dans le meme entrepot)", et la liste des emplacements de
destination se remplit alors avec ceux de l'entrepot source - elle restait
vide auparavant tant qu'un second entrepot n'etait pas choisi.

Garde-fous : l'emplacement de destination est **obligatoire** (sinon rien ne
bougerait), il doit **differer** de l'emplacement source, et la quantite doit
etre disponible **a l'emplacement source** precisement. Les deux ecrans qui
enregistrent un mouvement (ecran Mouvements et onglet Stock de la fiche
produit) suivent la meme regle.

### "J'en transfere 300 et il m'en compte 600"

Les quantites, elles, etaient justes - c'est l'**historique** qui trompait.
Un transfert entre deux entrepots ecrit **deux lignes** : la sortie de
l'entrepot source, et l'entree dans l'entrepot d'arrivee. C'est necessaire
(chaque entrepot doit voir le mouvement dans son propre historique), mais
rien ne signalait que la seconde etait la contrepartie de la premiere : on
lisait "Transfert 300" puis "Entree 300" et on croyait avoir recu deux fois
la marchandise.

La ligne generee s'affiche desormais **"Entree (arrivee d'un transfert)"**.
Le transfert interne, lui, n'ecrit **qu'une seule ligne** : il n'y a qu'un
entrepot.

**Verifie sur une base reelle** : entree de 300 en A1, transfert interne de
300 vers A2 -> total toujours 300, reparti A1=0 / A2=300, une seule ligne de
mouvement ; transfert externe de 300 vers un second entrepot -> total
toujours 300 (0 ici, 300 la-bas), et les deux lignes d'historique attendues ;
refus documente sans emplacement de destination, avec un emplacement
identique a la source, ou pour une quantite superieure au stock de
l'emplacement.

## Un seul seuil de stock, au lieu de quatre

La fiche produit demandait **quatre** valeurs de seuil : "Seuil alerte"
(`reorder_level`), "Stock mini" (`min_stock`), "Stock maxi" (`max_stock`) et
"Stock securite" (`safety_stock`). Dans les faits :

- `reorder_level` et `min_stock` faisaient **exactement la meme chose** :
  l'alerte se declenchait sous le **plus eleve des deux**. Deux champs, un
  seul role, et une valeur concurrente invisible ;
- `max_stock` et `safety_stock` n'etaient lus **nulle part** - ni alerte, ni
  rapport, ni controle a l'entree. Stockes, affiches, sans le moindre effet.
  Saisir un "stock de securite" en croyant se proteger ne protegeait de rien.

Le formulaire ne demande plus qu'un seuil, libelle sans ambiguite : **"Seuil
d'alerte (alerte des que le stock descend a cette valeur)"**. Le code ne lit
plus que `reorder_level`, dans les trois endroits qui s'en servaient :
l'alerte generee a chaque mouvement (`StockService`), la liste de l'ecran
Alertes (`ProductRepository::lowStock`) et le compteur du tableau de bord
(`DashboardRepository`) - ces deux derniers comptaient la meme chose et
doivent continuer a le faire.

**Aucune alerte ne se desactive au passage.** La migration
`202602270015_single_stock_threshold` remonte `reorder_level` au plus eleve
des deux valeurs existantes : un article qui alertait a 10 via `min_stock`
continue d'alerter a 10, desormais visible dans le champ unique. Les colonnes
`min_stock`, `max_stock` et `safety_stock` **restent en base** - aucune
donnee saisie n'est perdue, elles ne sont simplement plus demandees ni lues.

Meme menage sur les **categories** : "Seuil mini defaut" et "Seuil maxi
defaut" (`default_min_stock` / `default_max_stock`) etaient stockes mais
n'etaient appliques nulle part - creer un produit dans une categorie n'en
reprenait aucune valeur. Retires du formulaire, colonnes conservees en base.

### "Taxe defaut" de la categorie : branchee, pas retiree

Troisieme reglage inerte de la categorie, `default_tax_id` - mais celui-la
meritait d'etre branche plutot que supprime : reprendre la TVA de la
categorie evite de la ressaisir sur chaque fiche, et c'est le genre
d'erreur qui se voit a la facturation.

Un produit cree **sans TVA explicite** reprend desormais celle de sa
categorie, aux trois endroits ou un produit peut naitre :

- **le formulaire** : choisir une categorie pre-remplit le champ TVA, donc
  l'utilisateur VOIT le taux propose et peut le changer avant d'enregistrer,
  plutot que de decouvrir apres coup une TVA qu'il n'a pas choisie ;
- **l'API** (`ProductRepository::create`), qui couvre aussi tout script
  externe ;
- **l'import CSV**, dont le fichier ne porte aucune colonne TVA : c'etait le
  seul moyen qu'un import en masse arrive avec des taux corrects.

Regles, dans les trois cas : la valeur saisie **prime toujours** ; le defaut
ne s'applique qu'a la **creation** (reecrire silencieusement une fiche
existante serait pire que de ne rien faire) ; un defaut pointant une taxe
supprimee depuis est ignore plutot que d'ecrire une reference fantome ; et
reimporter un produit existant ne touche pas a sa TVA.

**Verifie** : categorie avec defaut et TVA vide -> le taux est repris ;
categorie avec defaut mais TVA saisie -> la saisie est conservee ; categorie
sans defaut -> rien ; taxe supprimee -> champ laisse vide. Teste dans les
trois chemins (formulaire, API, import CSV).

### Pourquoi pas un vrai calcul de reapprovisionnement

Dans un stock, ces notions ont un sens **quand le calcul existe derriere** :
le stock de securite absorbe les aleas, le point de commande vaut stock de
securite + consommation pendant le delai de reappro, et le stock maxi donne
la quantite a commander. Cela suppose de suivre les delais fournisseurs et
les consommations, ce que l'application ne fait pas. Proposer les champs sans
le calcul donnait l'illusion d'un pilotage fin la ou il n'y avait qu'un seul
seuil reellement actif. Le jour ou ces donnees existeront, le champ maxi
pourra etre rebranche (alerte de surstock, quantite suggeree en demande
d'achat) - la colonne est toujours la.

**Verifie** : un produit historique (seuil 3, `min_stock` 10) alerte toujours
a 10 apres migration ; un produit passe sous son seuil par un mouvement de
sortie declenche bien l'alerte ; le compteur du tableau de bord et la liste
des alertes affichent le meme nombre ; et abaisser le seuil visible a 2
desactive reellement l'alerte, alors que `min_stock` vaut toujours 10 en
base - c'est-a-dire que le champ affiche dit maintenant la verite.

## Douchette : etiquette reellement scannable, et scan qui ouvre la fiche

### L'ancienne etiquette n'etait pas un code barre

Les barres etaient dessinees a partir des **bits ASCII bruts** du code : un
octet, huit barres, un separateur. Cela RESSEMBLAIT a un code barre, mais il
n'y avait ni caractere de depart, ni cle de controle, ni zone de silence, ni
largeurs normalisees. **Aucune douchette ne pouvait le lire** - verifie : le
decodeur zbar ne trouve rien dans l'ancienne image.

L'etiquette utilise desormais du **Code 128** (norme ISO/IEC 15417), encode
par `Code128Encoder` : caractere de depart, cle de controle modulo 103,
symbole STOP, zone de silence de 12 modules et largeurs conformes. Le jeu C
est employe pour un code entierement numerique de longueur paire (deux
chiffres par symbole, donc un symbole deux fois plus court), le jeu B sinon -
qui accepte les lettres, indispensable pour un SKU du type `MAT-PLAN-001`.

Le Code 128 est le symbole le plus adapte a un stock : alphanumerique, dense,
et lu sans configuration par tous les lecteurs du commerce.

**Verification** : les etiquettes generees sont converties en image puis
relues par `zbarimg`. `MAT-PLAN` -> `MAT-PLAN`, `3760001234567` ->
`3760001234567`, `BUR-CHAISE-01` -> `BUR-CHAISE-01`. Ce n'est pas une
relecture de mon propre encodeur : c'est un decodeur independant qui lit
l'image, comme le ferait la douchette.

L'etiquette porte le nom du produit, les barres, le code en clair (saisie
manuelle possible si l'etiquette est abimee), le SKU et le prix. Sa largeur
s'adapte a la longueur du code au lieu d'etre figee a 520 points.

### Le champ "Code barre" d'une fiche produit

C'est un champ libre, rempli de deux facons :

- **a la main**, en recopiant le code imprime sur l'article (EAN du
  fabricant, par exemple) ;
- **a la douchette**, en scannant ce meme code : le lecteur se comporte comme
  un clavier, il suffit de cliquer dans le champ et de scanner.

Laisse **vide**, l'etiquette generee par l'application encode le **SKU** a la
place : un article sans code barre fabricant reste donc etiquetable et
scannable, avec sa propre reference.

**Correctif douchette sur tous les formulaires.** Une douchette termine son
envoi par Entree. Dans un formulaire HTML, Entree dans un champ texte
declenche la **soumission implicite** : scanner un code barre dans une fiche
produit a moitie remplie l'enregistrait prematurement, ou affichait une
erreur de champ obligatoire sans que l'utilisateur comprenne ce qui venait
de se passer. Entree passe desormais au **champ suivant** - comportement
habituel d'une saisie au kilometre : on scanne, le curseur avance.
L'enregistrement reste un clic explicite sur "Enregistrer", et Entree reste
libre dans les zones de texte multiligne (aller a la ligne).

### Unicite du code barre

Deux articles portant le meme code barre rendent le scan ambigu : la
douchette remonte deux resultats et n'ouvre aucune fiche. Un code barre deja
utilise par un AUTRE article est donc refuse, avec un message qui **nomme
l'article en conflit** ("Ce code barre est deja utilise par : Article A
(UNI-A)") - sans quoi il faudrait le chercher a la main.

Le controle est **applicatif** (`CrudService::assertUniqueFields`), pas une
contrainte SQL, et c'est deliberé :

- une base existante peut deja contenir des doublons, aucune contrainte
  n'ayant jamais existe. Une contrainte SQL rendrait ces lignes
  **immodifiables** - impossible de corriger le prix d'un article tant que
  son doublon n'est pas resolu ;
- en modification, la valeur n'est donc verifiee que si elle **change**.
  Modifier un article en doublon sans toucher a son code barre reste
  possible ; seule une saisie qui creerait ou deplacerait l'ambiguite est
  bloquee.

Un code barre **vide** n'entre jamais en conflit : plusieurs articles sans
code barre est un cas normal (leur etiquette encode le SKU).

Le controle s'applique aux **trois** chemins d'ecriture : l'ecran Produits,
l'ecran Variantes (meme ambiguite entre deux variantes), et **l'import
CSV** - ou la ligne fautive est rejetee en nommant l'article en conflit,
l'import poursuivant les lignes suivantes. Sans cela, un import en masse
pouvait creer des dizaines de doublons indetectables jusqu'au premier scan.

`CrudService` accepte pour cela une liste generique de colonnes uniques
(`['barcode' => 'code barre']`), reutilisable pour un autre referentiel sans
code specifique.

**Verifie** : creation d'un doublon refusee (409) ; deux articles sans code
barre acceptes ; modification du prix d'un doublon **historique** toujours
possible ; changement de code vers un code deja pris refuse ; changement vers
un code libre accepte ; import CSV rejetant la seule ligne en doublon et
important les deux autres ; et meme controle sur les variantes.

### Ce que fait un scan

Une douchette USB ou Bluetooth se comporte comme un **clavier** : elle tape
le code puis envoie Entree. Il n'y a rien a installer ni a configurer.

1. Cliquer une fois dans le champ de recherche en haut de l'ecran.
2. Scanner l'etiquette.
3. La liste produit est filtree sur le code, et **si ce code designe un seul
   article et correspond exactement a son code barre ou a son SKU, sa fiche
   s'ouvre directement**.

Le champ reste selectionne apres chaque scan : on enchaine les articles sans
toucher a la souris. Le scan fonctionne depuis n'importe quel ecran (la
touche Entree bascule sur Produits), et une recherche par mot ("velo") ou un
code qui remonte plusieurs articles laissent simplement la liste filtree,
sans ouvrir de fiche a tort.

**Correction liee** : la fiche affichee doit toujours correspondre a un
produit de la liste. Un scan qui ne trouvait rien laissait auparavant la
fiche du produit precedent a l'ecran sous une liste vide - en reception, on
croit avoir scanne l'article qu'on a sous les yeux.

### Ce que ce n'est pas (encore)

Le scan ouvre la fiche ; il ne saisit pas de mouvement tout seul. Enregistrer
une entree ou une sortie reste un geste explicite depuis la fiche ou l'ecran
Mouvements. Un mode "scan en rafale" pour un inventaire ou une reception -
scanner vingt articles a la suite pour incrementer des quantites - est un
chantier separe, a ouvrir si l'usage le demande.

## Fiche produit : etiquette cassee, et apercu des medias

**L'image de l'onglet Etiquette ne s'affichait pas.** L'etiquette est un SVG
genere par l'API, recupere par `fetch` avec le jeton d'authentification (le
fichier n'est pas joignable par une URL publique), puis affiche via
`URL.createObjectURL()` - donc une URL `blob:`. Or la politique de securite
du contenu envoyee par le frontend declarait `img-src 'self' data:` : le
navigateur refusait l'image **silencieusement**, sans erreur dans
l'application, seulement une ligne dans la console. D'ou l'image cassee.
`blob:` est desormais autorise pour les images. L'endpoint, lui, etait
correct depuis le debut (SVG valide, `Content-Type: image/svg+xml`).

**Medias et pieces jointes sont bien raccordes** - verifie de bout en bout
sur une base reelle : televersement, apparition dans la liste, et
telechargement rendant un fichier **octet pour octet identique** a
l'original, pour les deux. Les routes utilisees par l'ecran
(`POST /products/{id}/media/upload`, `POST /attachments/upload`,
`GET /product-media/{id}/download`, `GET /attachments/{id}/download`)
existent et repondent.

Deux choses corrigees au passage :

- **L'onglet Media n'affichait aucun apercu** : une photo produit n'etait
  qu'une ligne de tableau avec un nom de fichier, il fallait la telecharger
  pour savoir ce qu'elle montrait. Une colonne Apercu affiche desormais une
  vignette pour les medias image (chargee par la meme route authentifiee que
  le bouton Telecharger ; les documents gardent un tiret).
- **Le chemin absolu du fichier sur le serveur etait renvoye au navigateur.**
  `GET /products/{id}` faisait un `SELECT *` sur `product_media` et livrait
  `file_path`, soit `/home/.../backend/public/uploads/...`, a tout
  utilisateur connecte. Le frontend ne s'en sert pas : les colonnes sont
  maintenant listees explicitement.

**Dossier `uploads/` : acces direct desormais refuse.** Il se trouve sous
`backend/public/`, donc une piece jointe restait joignable par son URL, sans
aucune authentification, des que celle-ci fuitait (historique, copier-coller,
journal de proxy). Les noms de fichiers sont aleatoires, ce qui rendait la
chose peu probable, mais ce n'est pas une protection. Le `.htaccess` du
dossier interdit maintenant l'acces direct ; les telechargements passent par
l'API authentifiee, qui verifie la session avant de streamer le fichier -
c'est deja ce que fait l'application, rien ne change pour l'utilisateur.
(Il interdisait deja l'execution de tout script depose dans ce dossier.)

## Import CSV : modele telechargeable et colonnes exactes

L'ecran **Importations CSV** affichait une seule ligne listant les en-tetes de
toutes les entites a la suite. Il affiche maintenant, pour l'entite
selectionnee, un tableau des colonnes attendues : nom exact, obligatoire ou
non, ce qu'on y met, et un exemple. Un bouton **"Telecharger le modele"**
genere le fichier CSV pret a remplir (en-tetes exacts + une ligne d'exemple,
UTF-8 avec BOM pour qu'Excel n'abime pas les accents). Le modele est construit
dans le navigateur, sans route serveur supplementaire.

Un classeur Excel `modele-import-gestion-stock.xlsx` (un onglet par entite,
plus un mode d'emploi) est egalement fourni hors application.

### Colonnes par entite

**Produits** (`products`) : `sku`*, `name`*, `category_name`*, `supplier_name`,
`barcode`, `description`, `unit_price`, `cost_price`, `reorder_level`,
`status`. La categorie et le fournisseur cites sont **crees automatiquement**
s'ils n'existent pas. Un `sku` deja present met la fiche a jour.

**Fournisseurs** (`suppliers`) : `name`*, `contact_name`, `phone`, `email`,
`address`. Un nom deja present est mis a jour.

**Clients** (`customers`) : `name`*, `code`, `email`, `phone`, `address`,
`status`. Avec un `code`, la fiche est mise a jour ; **sans `code`, une
nouvelle fiche est creee a chaque import**.

**Stocks initiaux** (`initial-stocks`) : `sku`*, `warehouse_code`*,
`quantity`. Le SKU et le code entrepot doivent **deja exister**. La quantite
**remplace** le stock existant sans emplacement precis, elle ne s'y ajoute pas.

(`*` = obligatoire.) L'ordre des colonnes est libre, les colonnes
facultatives peuvent etre absentes, le separateur peut etre `;` ou `,`
(detection automatique), et les prix acceptent la virgule francaise.

### Trois defauts corriges en testant ce modele

- **Un `.xlsx` depose directement etait accepte** puis lu comme du texte :
  import "reussi" rempli de lignes absurdes, ou erreur incomprehensible. Le
  stockage de fichiers autorise `.xlsx` parce qu'il sert aussi aux pieces
  jointes ; l'import verifie desormais l'extension lui-meme et repond quoi
  faire ("Fichier > Enregistrer sous > CSV UTF-8").
- **Une colonne facultative presente mais vide cassait la ligne.** Un modele
  contient toutes les colonnes, y compris celles qu'on ne remplit pas.
  `status` vide envoyait `''` dans une colonne ENUM et MySQL repondait
  `Data truncated for column 'status'` - message illisible pour une ligne
  parfaitement legitime. Vide vaut maintenant `ACTIVE`, comme dans le
  formulaire de saisie.
- **Une faute de frappe sur le statut** (`ACTIF` au lieu de `ACTIVE`) donnait
  la meme erreur MySQL. Elle donne maintenant : *La colonne "status" doit
  valoir ACTIVE ou INACTIVE (ou rester vide), valeur recue : ACTIF*. Les
  autres colonnes facultatives laissees vides sont enregistrees a `NULL` et
  non a chaine vide.

Verifie de bout en bout : les quatre CSV exportes depuis le classeur Excel
importes sur une base reelle (prix `89,90` conserve avec ses centimes, code
barre `3760001234567` non transforme en notation scientifique), reimportes une
seconde fois sans creer de doublon ni gonfler le stock, plus les cas d'erreur
ci-dessus.

## Achats : les listes ne gardent que ce qui reste a traiter

Les deux ecrans d'achat affichaient **toutes** les lignes depuis la creation
de la base. Une demande convertie en commande ou refusee, une commande
entierement recue ou annulee : il n'y a plus rien a en faire, mais elles
continuaient de s'empiler devant les quelques lignes reellement en cours. Au
bout de quelques mois d'utilisation, l'ecran devient inutilisable.

Chaque ecran a maintenant **deux vues**, avec un bouton pour passer de l'une
a l'autre :

| Ecran | Vue par defaut | Vue "passees" |
| --- | --- | --- |
| Demandes achat | tout sauf converties et refusees | `CONVERTED`, `REJECTED` |
| Commandes achat | tout sauf recues et annulees | `RECEIVED`, `CANCELLED` |

Le bouton annonce le nombre de lignes de l'autre vue ("Voir les demandes
passees (37)"), pour savoir ce qu'on y trouvera avant de cliquer.

**Rien n'est supprime ni archive en base** : c'est un simple filtre
d'affichage, l'historique reste entier et consultable en un clic. Le detail
d'une ligne passee s'ouvre normalement.

**Le filtre est applique cote serveur** (`?scope=open` / `?scope=archived` /
`?scope=all` sur `GET /purchase-requests` et `GET /purchase-orders`, plus un
`?status=` exact si besoin). Un filtre applique dans le navigateur n'aurait
trie que les 20 lignes de la premiere page - donc rien du tout des que le
volume monte. Sans parametre, l'API se comporte exactement comme avant.

**Pagination ajoutee sur ces deux ecrans**, qui n'en avaient pas : ils
affichaient les 20 premieres lignes renvoyees par l'API, sans barre de
navigation ni indication qu'il en existait d'autres. Meme barre que les
ecrans de referentiels (25/50/100 par page), et le changement de vue remet
la pagination a la premiere page.

**Les listes deroulantes ne suivent pas la vue affichee.** Le selecteur de
commande du changement de statut et celui de la reception proposent
toujours les commandes **en cours**, quelle que soit la vue ou la page
consultee : on ne receptionne pas une commande deja recue ou annulee (le
backend le refuse de toute facon). Meme chose pour la liste des demandes
convertibles a la creation d'une commande. Elles etaient jusqu'ici
construites a partir des 20 lignes de la premiere page - une commande plus
ancienne devenait invisible et donc non receptionnable.

## Variantes "dimensions" pour le materiel

Migration `202602270014_dimension_variants`, reglage
`dimension_variants_enabled`. Troisieme "saveur" de variantes, sur le meme
principe que taille/couleur et millesime/contenance : quatre colonnes
supplementaires sur `product_variants` - `width`, `height`, `depth`,
`weight` - et rien d'autre a changer, puisque le stock, les mouvements, les
alertes, les livraisons, les achats et les inventaires ne raisonnent qu'en
`variant_id`.

**Valeurs libres, et c'est voulu.** Ces quatre colonnes sont des `VARCHAR`,
pas des `DECIMAL`. Un utilisateur doit pouvoir saisir "120 cm", "2 m",
"3/4 pouce", "1,20 x 0,80" ou "sur mesure" sans qu'une unite lui soit
imposee. Ces valeurs sont des libelles de variante, pas des donnees de
calcul : rien dans l'application ne les additionne ni ne les convertit.

**Les deux niveaux coexistent.** La fiche produit garde ses champs
numeriques `width_cm` / `height_cm` / `depth_cm` / `weight_kg` : ils portent
les cotes d'un article qui n'existe qu'en une seule taille. Les dimensions
de variante portent les cotes de chaque declinaison d'un article qui en a
plusieurs, chacune avec son propre SKU, son propre prix et son propre stock.
Selon les articles, on utilise l'un, l'autre, ou les deux.

**Affichage.** Le libelle de variante devient `L 120 cm / H 90 cm / P 60 cm
/ 23,5 kg`, dans les listes, les mouvements, les livraisons, les inventaires
et les messages d'alerte de stock bas - la meme regle de priorite est
appliquee cote frontend (`variantDescriptor`) et cote backend
(`StockService`) : vetement, puis bouteille, puis dimensions, puis le SKU a
defaut.

**Generation en lot.** Le generateur de variantes accepte les quatre
nouvelles listes (largeurs, hauteurs, profondeurs, poids) comme axes du
produit cartesien : 4 largeurs x 3 profondeurs = 12 references en une
operation. Aucune validation de format n'est appliquee sur ces axes, par
construction.

**Donnees de demo.** Cinq variantes de dimensions sont livrees dans
`catalog-demo.sql` (un tableau blanc en trois formats, un caisson en deux
profondeurs), avec du stock, en `NOT EXISTS` comme le reste du fichier.

L'option est a `0` par defaut : une installation existante ne voit
strictement aucun changement tant qu'elle n'est pas activee dans l'ecran
Parametres.

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

## Super administrateur : le tout premier compte a des droits reserves

**Demande** : le tout premier compte cree lors de l'installation
(`frontend/install.php`) doit etre "super admin". Les comptes crees ensuite
restent "administrateur". L'administrateur garde acces a tout, **sauf**
Donnees de demo et Migrations, desormais reserves au super administrateur.

**Ce qui a change** :
- Nouveau role `SUPER_ADMIN` (table `roles`), cree par `install.php` en
  meme temps que les autres roles.
- `install.php` attribue ce role au tout premier compte cree pendant
  l'installation (au lieu de `ADMIN` auparavant). Tous les comptes crees
  ensuite depuis l'ecran Utilisateurs restent `ADMIN` (ou un autre profil
  existant) comme avant - rien ne change pour eux.
- Cote API (`RoleMiddleware`), `SUPER_ADMIN` et `ADMIN` restent traites de
  facon identique partout : gestion des produits, du stock, des achats, des
  utilisateurs, des parametres... **la seule difference** concerne deux
  pages independantes de l'API, qui ne faisaient deja pas partie du meme
  systeme d'acces :
  - `frontend/demo-data.php` (Donnees de demo)
  - `frontend/migrate.php` (Migrations)

  Ces deux pages verifiaient auparavant `role_code = 'ADMIN'`. Elles
  verifient maintenant `role_code = 'SUPER_ADMIN'` et renvoient une erreur
  403 "Reserve au Super administrateur" a un compte Administrateur qui
  tenterait d'y acceder directement par son URL. Leurs liens sont egalement
  masques du menu pour un compte Administrateur (`applyNavAccess()` dans
  `app-clean.js`).
- L'ecran Utilisateurs (liste deroulante "Profil") ne propose plus jamais
  "Super administrateur" - ni a la creation, ni a la modification d'un
  compte (`RoleRepository::allAssignable()` cote lecture, verification
  serveur dans `UserService` cote ecriture pour bloquer aussi un appel API
  direct). Impossible donc pour un Administrateur de s'auto-promouvoir ou
  de creer un second super administrateur depuis cet ecran.
- **Installations existantes (mise a jour, pas installation neuve)** :
  aucun compte n'y est encore `SUPER_ADMIN` puisque le role vient d'etre
  cree. Pour eviter que ces deux pages ne deviennent inaccessibles a tout le
  monde du jour au lendemain, une verification automatique (au premier
  chargement de l'une des deux pages) cree le role s'il n'existe pas encore
  et promeut alors le compte Administrateur le plus ancien (le tout premier
  cree) en Super administrateur - sans aucune action requise. La migration
  `202602270016_super_admin_role.sql` fait la meme promotion des la mise a
  jour de la base (`migrate.php`), sans attendre qu'un admin ouvre l'une des
  deux pages.

**Verifie** :
- Installation neuve (formulaire complet via navigateur reel) : le tout
  premier compte cree obtient bien le role `SUPER_ADMIN` en base.
- Creation d'un deuxieme compte (Administrateur) depuis l'ecran
  Utilisateurs : la liste deroulante "Profil" ne propose pas "Super
  administrateur".
- Ce compte Administrateur : lien "Donnees de demo" et "Migrations" absents
  du menu ; acces direct par l'URL a ces deux pages renvoie bien une erreur
  403 "Reserve au Super administrateur".
- Base existante (compte Administrateur, aucun `SUPER_ADMIN` en base) :
  premiere visite de `migrate.php` par ce compte -> page accessible (pas de
  403) et le compte est bien promu `SUPER_ADMIN` en base, verifie par
  requete SQL directe.
- Migration `202602270016` : application via `migrate.php` (sans erreur),
  puis annulation ("Annuler le dernier lot") verifiee correcte : le role
  `SUPER_ADMIN` n'est pas supprime tant qu'un compte l'utilise encore
  (protection explicite dans le script down).
- Suite complete de tests API/BDD (`smoke_api.sh`, une quarantaine de
  verifications sur produits, stock, achats, inventaires, pieces jointes...)
  rejouee apres ces changements : aucune regression.

### Correctif : un Administrateur pouvait retrograder ou supprimer un Super administrateur

**Trouve en verifiant le point ci-dessus** : donner a l'Administrateur les
memes droits qu'au Super administrateur sur l'ecran Utilisateurs (pour que
rien ne change pour lui) avait un effet de bord non voulu - un
Administrateur pouvait, via cet ecran ou un appel API direct sur
`PUT/DELETE /api/v1/users/{id}`, changer le role du compte Super
administrateur (le retrograder en Administrateur), le desactiver,
reinitialiser son mot de passe, ou le supprimer purement et simplement. Rien
ne protegeait le compte Super administrateur une fois cree, ce qui aurait
permis a n'importe quel Administrateur de neutraliser la seule distinction
que cette fonctionnalite est censee garantir.

**Correctif** : `UserService` refuse desormais toute action (changement de
role, activation/desactivation, reinitialisation de mot de passe,
suppression) menee par un simple Administrateur sur un compte dont le role
actuel est `SUPER_ADMIN`, avec le message "Seul un Super administrateur peut
modifier ce compte" (HTTP 403). Un compte Super administrateur reste
librement modifiable par un autre Super administrateur (utile s'il y en a
plusieurs, par exemple apres une auto-promotion sur une ancienne
installation - voir plus haut). Un Administrateur garde par ailleurs tous
ses droits habituels sur les comptes qui ne sont pas Super administrateur.

**Verifie** (via l'API reelle, sur une base de test) :
- Connecte en tant qu'Administrateur simple : tentative de changer le role
  du compte Super administrateur -> 403 ; tentative de le desactiver -> 403 ;
  tentative de reinitialiser son mot de passe -> 403 ; tentative de le
  supprimer -> 403.
- Connecte en tant que Super administrateur : modification d'un autre compte
  Super administrateur -> reussie (200).
- Connecte en tant qu'Administrateur simple : modification d'un compte
  Administrateur ordinaire -> toujours reussie (200), aucun changement de
  comportement pour l'usage normal.
- Suite complete `smoke_api.sh` rejouee apres ce correctif : aucune
  regression.

## Correctif de livraison : l'installateur etait verrouille dans les paquets livres

En travaillant sur le point ci-dessus, un probleme distinct et plus grave a
ete decouvert : deux fichiers, `config/.installed` et `config/install.key`,
etaient presents dans l'arborescence de travail (residus d'un test
anterieur) et donc **inclus dans chaque paquet livre depuis le debut de
cette session** (verifie en inspectant un zip livre precedemment).

- `config/.installed` fait considerer `install.php` comme "deja installe"
  et repond 403 a toute tentative d'installation - **un client recevant un
  de ces paquets n'aurait jamais pu lancer l'installateur**.
- `config/install.key` etait un fichier vide (0 octet). Meme sans le point
  precedent, cela aurait empeche toute soumission du formulaire
  d'installation de reussir (la cle saisie ne peut jamais correspondre a
  une cle vide).

Ces deux fichiers ont ete supprimes de l'arborescence de travail. Ils sont
generes automatiquement par l'installation elle-meme et ne doivent **jamais**
faire partie d'un paquet livre. Verifie via `install.php` : la page affiche
de nouveau correctement les instructions de creation de la cle
d'installation lorsque celle-ci est absente.

**Important pour la suite** : si `config/.installed` ou `config/install.key`
reapparaissent un jour dans l'arborescence de travail (par exemple apres un
test d'installation local), bien les supprimer avant de construire un
nouveau paquet.

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
