# Gestion de stock complète
# Gestion Stock - Servia — Fonctionnalites completes

Ce document liste l'ensemble des fonctionnalites de l'application telles
qu'elles existent aujourd'hui, apres les evolutions recentes (liaison achats,
tags produits, numeros de serie, dashboard interactif...). Il complete le
README.md (installation, architecture, securite) qui reste la reference pour
ces sujets-la.

---

## 1. Authentification et acces

- Connexion par email/mot de passe, session en cookie httpOnly + Secure +
  SameSite=Strict (jeton jamais accessible en JS).
- Expiration glissante de session (30 jours d'inactivite).
- Roles: SUPER_ADMIN, ADMIN, MANAGER, BUYER, STOREKEEPER - chaque role voit
  uniquement les modules de navigation qui le concernent.
- Protection anti-brute-force: 5 echecs / 15 min (par email et par IP) ->
  blocage temporaire (HTTP 429), fonctionne sur tout hebergement.
- Reinitialisation de mot de passe par un admin, ou changement personnel
  ("Mon compte") - invalide les sessions actives dans les deux cas.

## 2. Tableau de bord

- KPIs en un coup d'oeil: valeur de stock, nombre de produits, ruptures,
  stock bas, commandes d'achat en retard/ouvertes, demandes d'achat,
  entrepots.
- **Vignettes cliquables**: chaque KPI redirige directement vers la page
  correspondante (Produits, Alertes, Commandes achat, Demandes achat,
  Entrepots), avec effet visuel au survol et navigation clavier
  (Entree/Espace).
- Graphiques (tendance des mouvements, sorties).

## 3. Recherche globale (barre du haut)

- Recherche unique disponible sur toutes les pages.
- Cherche dans: SKU, code-barres, nom produit, description produit **et
  numeros de serie** (si un SN correspond, le produit proprietaire remonte
  dans les resultats).
- Appui sur Entree -> bascule automatiquement sur la page Produits filtree.

## 4. Referentiels

- **Produits**: fiche complete (SKU, code-barres, categorie, marque, unite,
  fournisseur, prix, methode de valorisation, stock par entrepot), fiche
  detaillee dediee, import/export, colonne "Tags" avec badges colores.
  - **Tags**: creation libre (nom + couleur), assignation multiple par
    produit via un champ liste-a-selection-multiple, filtre dedie au-dessus
    du tableau Produits, affichage dans la fiche produit et dans la liste.
  - **Numeros de serie**: un SN optionnel par exemplaire physique (pas par
    produit). Enregistrement par lot (plusieurs SN d'un coup, ex: reception),
    statut IN_STOCK / OUT, rattachement a un entrepot.
    Recherche dediee par SN exact avec, en plus des infos produit/statut,
    l'**historique complet des ventes**: date, client, numero de BL et
    statut du BL pour chaque livraison ou ce SN est apparu.
- Categories (avec categorie parente optionnelle), Marques, Unites, Taxes.
- **Zones** (secteurs larges d'un entrepot, ex "Reception", "Zone froide")
  et **Emplacements** (adresse precise dans une zone, ex "A-12-03", avec
  capacite) - hierarchie Entrepot > Zone > Emplacement, utilisee pour tracer
  les mouvements de stock a l'interieur d'un entrepot.

## 5. Tiers

- Fournisseurs et Clients: fiches completes, statut actif/inactif.

## 6. Stock

- Mouvements: entrees, sorties, transferts (avec emplacement source/
  destination optionnel), ajustements.
- Sessions d'inventaire.
- Alertes automatiques (rupture, stock bas) - accessibles depuis le
  dashboard.

## 7. Achats

- **Demandes d'achat**: creation, statuts (Brouillon, Soumise, Approuvee,
  Rejetee, Convertie).
- **Commandes d'achat**:
  - Peuvent etre creees **a partir d'une demande d'achat existante**: un
    menu deroulant liste les demandes convertibles (Soumise/Approuvee), la
    selection **pre-remplit automatiquement** entrepot, produit, quantite
    (et cout prefere si renseigne).
  - A la creation de la commande, la demande liee passe **automatiquement**
    au statut "Convertie" et disparait de la liste des demandes
    selectionnables (evite qu'elle serve deux fois par erreur).
  - Liste des commandes: colonne "Demande liee" pour tracer l'origine.
  - Reception partielle ou totale, suivi des statuts.

## 8. Livraisons (Bons de Livraison)

- Creation multi-lignes (produit + quantite + prix), sortie de stock
  automatique a la validation.
- **Numero de serie optionnel par ligne**: menu dynamique liste uniquement
  les SN en stock du produit choisi sur cette ligne; en choisir un fige la
  quantite de la ligne a 1 (un SN = un exemplaire).
  - A la validation du BL, le SN livre passe automatiquement en statut
    "Sorti", rattache a ce client/cette date via le BL.
  - A l'annulation d'un BL, les SN concernes repassent automatiquement en
    stock.
- **Impression / export PDF du BL**: en-tete societe (logo + nom), infos
  client et entrepot, tableau des lignes avec **colonne "N Serie"** (affiche
  le SN si renseigne, "-" sinon), total.
- Annulation d'un BL: re-credite le stock (et les SN, voir ci-dessus).

## 9. Pilotage

- Rapports, exports CSV.
- Journal d'audit consultable dans l'UI (admin uniquement): qui a fait quoi,
  filtrable par utilisateur/action.

## 10. Administration

- Gestion des roles et utilisateurs.
- Import CSV multi-entites, pieces jointes, etiquettes/code-barres (voir
  README pour le detail technique).

---

## Historique des evolutions recentes (pour memoire)

Ordre chronologique des ajouts/corrections majeurs realises apres la mise en
production initiale:

1. Correctifs de stabilite initiaux (authentification, validations de
   formulaires, suppression en double, recherche produit).
2. Liaison Demande d'achat <-> Commande d'achat avec conversion automatique
   de statut.
3. Dashboard: vignettes KPI cliquables vers les modules correspondants.
4. Systeme de Tags produits (creation, assignation multiple, affichage,
   filtre).
5. Numeros de serie par exemplaire (creation par lot, recherche, integration
   a la recherche globale).
6. Integration des numeros de serie aux Bons de Livraison (selection a la
   ligne, sortie/retour automatique du statut, impression, historique de
   vente par client/date).

---
