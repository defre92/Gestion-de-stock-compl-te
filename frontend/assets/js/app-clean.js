import { apiRequest, clearAuth, fetchAuthenticatedBlob, uploadRequest } from './http-client.js';

const state = {
    user: null,
    lookups: null,
    module: 'dashboard',
    globalQuery: '',
    tagFilter: '',
    activeProductId: null,
    pendingSerialProductId: null,
    pendingVariantProductId: null,
    // Methode de valorisation proposee par defaut a la creation d'un produit
    // (reglage `default_valuation_method` de l'ecran Parametres). Reste
    // modifiable produit par produit : ce n'est qu'une pre-selection.
    defaultValuationMethod: 'CUMP',
    // Page courante de chaque ecran CRUD, et nombre de lignes par page commun
    // a tous. Sans pagination, l'API appliquait son defaut (per_page = 20) et
    // chaque ecran ne montrait que les 20 enregistrements les plus recents,
    // sans aucun moyen de voir les suivants.
    crudPages: {},
    crudPerPage: 25,
    // Vue "toutes les colonnes" par module (voir visibleColumns).
    allColumns: {},
    // Vue courante des deux ecrans d'achat : 'open' = ce qu'il reste a
    // traiter (defaut), 'archived' = ce qui est termine (demandes converties
    // ou refusees, commandes recues ou annulees). Sans ca, une demande
    // convertie il y a six mois continuait d'encombrer la liste de travail.
    purchaseScopes: { 'purchase-requests': 'open', 'purchase-orders': 'open' },
    // Filtre entrepot de l'ecran Produits. Quand il est actif, la colonne
    // Stock n'affiche que la quantite de cet entrepot - sinon on lirait un
    // total tous entrepots confondus a cote d'un filtre "entrepot X".
    warehouseFilter: '',
    // Filtres Categorie/Fournisseur/Emplacement de l'ecran Produits, ajoutes
    // a cote d'Entrepot et Tags qui existaient deja. L'emplacement depend
    // d'un entrepot choisi (un emplacement appartient a un seul entrepot),
    // comme partout ailleurs dans l'application (voir fillLocationOptions).
    categoryFilter: '',
    supplierFilter: '',
    locationFilter: '',
    // Filtres par attribut de variante (Taille, Couleur, Marque, Type...),
    // un par menu deroulant - ecran Variantes (grille) et ecran Mouvements
    // (historique). Cles = colonnes de product_variants (voir
    // VARIANT_ATTRIBUTE_DEFS) ; combinables entre elles (ET logique).
    variantAttributeFilters: {},
    movementVariantAttributeFilters: {},
    // Valeurs distinctes actuellement en base pour chaque attribut, pour
    // remplir les menus deroulants ci-dessus (voir refreshVariantAttributeValues).
    variantAttributeValues: null,
    // Annee affichee par la page Statistiques (onglet Rapports). null =
    // laisse le backend choisir (annee en cours, ou la plus recente ayant
    // des ventes - voir ReportService::salesStats).
    reportsYear: null,
    // Mois affiche/exporte par la page Statistiques (1-12). Purement
    // cote frontend : contrairement a l'annee, tous les mois sont toujours
    // proposes au telechargement, meme sans aucune vente dessus.
    reportsMonth: null,
};

const dashboardCharts = {
    movementTrend: null,
    outgoing: null,
};

// Graphiques de la page Statistiques (onglet Rapports) - meme raison d'etre
// que dashboardCharts : Chart.js exige de detruire une instance existante
// avant de redessiner sur le meme <canvas>, sinon le graphique precedent
// reste visible en fantome derriere le nouveau.
const reportsCharts = {
    monthlyRevenue: null,
    yearlyRevenue: null,
};

const MONTH_LABELS_FR = ['Janv', 'Fevr', 'Mars', 'Avr', 'Mai', 'Juin', 'Juil', 'Aout', 'Sept', 'Oct', 'Nov', 'Dec'];
// Noms complets, pour le selecteur de mois de l'export CSV (les abreges
// ci-dessus ne servent qu'aux libelles d'axe des graphiques).
const MONTH_LABELS_FULL_FR = ['Janvier', 'Fevrier', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Aout', 'Septembre', 'Octobre', 'Novembre', 'Decembre'];

const moduleTitles = {
    dashboard: 'Tableau de bord',
    products: 'Produits',
    'product-variants': 'Variantes',
    categories: 'Categories',
    brands: 'Marques',
    units: 'Unites',
    taxes: 'Taxes',
    tags: 'Tags',
    suppliers: 'Fournisseurs',
    customers: 'Clients',
    warehouses: 'Entrepots',
    'warehouse-zones': 'Zones',
    'warehouse-locations': 'Emplacements',
    users: 'Utilisateurs',
    audits: "Journal d'audit",
    account: 'Mon compte',
    movements: 'Mouvements',
    'product-serials': 'Numeros de serie',
    deliveries: 'Livraisons',
    inventories: 'Inventaires',
    alerts: 'Alertes',
    'purchase-requests': 'Demandes achat',
    'purchase-orders': 'Commandes achat',
    settings: 'Parametres',
    imports: 'Importations CSV',
    reports: 'Rapports',
};

// Ecrans ou la recherche globale (barre en haut, #globalSearch) s'applique.
// Chacun de ces modules passe le texte tape en filtre `q` a son propre
// endpoint (voir renderCrud) : la recherche porte donc sur l'onglet
// actuellement affiche, pas systematiquement sur Produits comme avant.
// `settings` en est volontairement exclu : ce module se filtre par cle exacte
// (setting_key), pas par recherche libre.
const GLOBAL_SEARCH_MODULES = [
    'products', 'product-variants', 'categories', 'brands', 'units', 'taxes',
    'tags', 'suppliers', 'customers', 'warehouses', 'warehouse-zones',
    'warehouse-locations', 'users',
];

// Catalogue des themes de couleur - doit rester synchronise avec
// config/themes.php (memes cles, memes libelles). Le back-end reste la
// source de verite pour la validation (route-frontend.php n'accepte que ces
// cles) ; ce catalogue cote front ne sert qu'a dessiner les vignettes de
// choix dans Parametres > Apparence.
const THEME_CATALOG = {
    emeraude: { label: 'Emeraude', primary: '#0f8f74', sidebar: ['#0d2532', '#0d443d', '#0e3b5a'] },
    ocean: { label: 'Ocean', primary: '#2563eb', sidebar: ['#0b1e3a', '#0d2f52', '#0b3a63'] },
    violet: { label: 'Violet', primary: '#7c3aed', sidebar: ['#1e1033', '#2d1854', '#3a1f6e'] },
    ardoise: { label: 'Ardoise', primary: '#475569', sidebar: ['#0f172a', '#1e293b', '#334155'] },
    rubis: { label: 'Rubis', primary: '#dc2626', sidebar: ['#2a0e0e', '#4a1414', '#5c1a1a'] },
    ambre: { label: 'Ambre', primary: '#d97706', sidebar: ['#2a1a06', '#452b0a', '#5c380d'] },
    framboise: { label: 'Framboise', primary: '#db2777', sidebar: ['#2a0e1c', '#4a1430', '#5c1a3c'] },
    indigo: { label: 'Indigo (nuit)', primary: '#4f46e5', sidebar: ['#0e1029', '#191c47', '#22265c'] },
};

const crudModules = {
    categories: {
        endpoint: '/categories',
        label: 'categorie',
        fields: [
            { key: 'parent_id', label: 'Categorie parent', type: 'select', optionsFrom: 'categories', optionLabel: 'name' },
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'description', label: 'Description', type: 'textarea' },
            // default_min_stock / default_max_stock retires du formulaire :
            // comme les seuils multiples de la fiche produit, ils etaient
            // stockes mais n'etaient appliques nulle part - creer un produit
            // dans une categorie n'en reprenait aucune valeur. Les colonnes
            // restent en base.
            { key: 'default_tax_id', label: 'Taxe defaut', type: 'select', optionsFrom: 'taxes', optionLabel: 'name' },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'name', label: 'Nom' },
            // Le nom de la categorie parente, pas son identifiant : "Parent : 3"
            // obligeait a aller verifier a quoi correspond le 3.
            { key: 'parent_name', label: 'Parent', format: (value) => (value ? sanitize(value) : '<span class="muted">-</span>') },
            { key: 'updated_at', label: 'Maj' },
        ],
    },
    brands: {
        endpoint: '/brands',
        label: 'marque',
        fields: [
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'description', label: 'Description', type: 'textarea' },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'name', label: 'Nom' },
            { key: 'description', label: 'Description' },
        ],
    },
    units: {
        endpoint: '/units',
        label: 'unite',
        fields: [
            { key: 'code', label: 'Code', type: 'text', required: true },
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'symbol', label: 'Symbole', type: 'text' },
            { key: 'base_unit', label: 'Unite base', type: 'text' },
            { key: 'conversion_factor', label: 'Conversion', type: 'number', step: '0.000001' },
            { key: 'is_active', label: 'Actif', type: 'select', options: [
                { value: '1', label: 'Oui' },
                { value: '0', label: 'Non' },
            ] },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'code', label: 'Code' },
            { key: 'name', label: 'Nom' },
            { key: 'symbol', label: 'Symbole' },
            { key: 'conversion_factor', label: 'Conversion' },
        ],
    },
    taxes: {
        endpoint: '/taxes',
        label: 'taxe',
        fields: [
            { key: 'code', label: 'Code', type: 'text', required: true },
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'rate', label: 'Taux', type: 'number', step: '0.001', required: true },
            { key: 'is_default', label: 'Par defaut', type: 'select', options: [
                { value: '1', label: 'Oui' },
                { value: '0', label: 'Non' },
            ] },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'code', label: 'Code' },
            { key: 'name', label: 'Nom' },
            { key: 'rate', label: 'Taux' },
            { key: 'is_default', label: 'Defaut', format: (v) => (Number(v) === 1 ? 'Oui' : 'Non') },
        ],
    },
    tags: {
        endpoint: '/tags',
        label: 'tag',
        fields: [
            { key: 'name', label: 'Nom', type: 'text', required: true },
            // Palette de pastilles + pipette : saisir "#6366f1" a la main
            // n'a aucun sens pour un utilisateur qui veut juste "du rouge".
            { key: 'color', label: 'Couleur', type: 'color', defaultValue: '#6366f1' },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'name', label: 'Nom' },
            // Apercu du tag tel qu'il apparaitra sur une fiche produit,
            // plutot que le code hexadecimal brut : "#6366f1" ne dit rien a
            // personne, une pastille coloree se lit d'un coup d'oeil.
            { key: 'color', label: 'Couleur', format: (value, row) => renderTagBadges([{ name: row.name, color: value }]) },
        ],
    },
    suppliers: {
        endpoint: '/suppliers',
        label: 'fournisseur',
        fields: [
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'contact_name', label: 'Contact', type: 'text' },
            { key: 'phone', label: 'Telephone', type: 'text' },
            { key: 'email', label: 'Email', type: 'email' },
            { key: 'address', label: 'Adresse', type: 'textarea' },
            { key: 'lead_time_days', label: 'Delai jours', type: 'number' },
            { key: 'payment_terms', label: 'Conditions', type: 'text' },
            { key: 'website', label: 'Site web', type: 'text' },
            { key: 'status', label: 'Statut', type: 'select', required: true, options: [
                { value: 'ACTIVE', label: 'ACTIVE' },
                { value: 'INACTIVE', label: 'INACTIVE' },
            ] },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'name', label: 'Nom' },
            { key: 'contact_name', label: 'Contact' },
            { key: 'phone', label: 'Telephone' },
            { key: 'email', label: 'Email' },
            { key: 'status', label: 'Statut' },
        ],
    },
    products: {
        endpoint: '/products',
        label: 'produit',
        get fields() {
            const fields = [
            { key: 'sku', label: 'SKU', type: 'text', required: true },
            // Champ libre : saisie au clavier ou lecture a la douchette, qui se
            // comporte comme un clavier. Laisse vide, l'etiquette generee
            // encode le SKU a la place (voir BarcodeController).
            { key: 'barcode', label: 'Code barre', type: 'text', hint: 'Saisis-le, ou scanne le code imprime sur l\'article avec la douchette. Laisse vide pour que l\'etiquette encode le SKU.' },
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'description', label: 'Description', type: 'textarea' },
            { key: 'category_id', label: 'Categorie', type: 'select', optionsFrom: 'categories', optionLabel: 'name', required: true },
            { key: 'supplier_id', label: 'Fournisseur', type: 'select', optionsFrom: 'suppliers', optionLabel: 'name' },
            { key: 'unit_id', label: 'Unite', type: 'select', optionsFrom: 'units', optionLabel: 'code' },
            { key: 'brand_id', label: 'Marque', type: 'select', optionsFrom: 'brands', optionLabel: 'name' },
            // Retires du formulaire (Conditionnement, Poids, Largeur, Hauteur,
            // Profondeur) : ces 5 champs etaient enregistres en base mais
            // n'etaient affiches NULLE PART (ni fiche produit, ni listes, ni
            // export/import CSV, ni etiquette) - meme defaut que les anciens
            // "stock mini/maxi/securite" (migration 202602270015). Pour le
            // poids et les 3 dimensions, l'equivalent utile existe deja et
            // reste disponible : les champs LIBRES du module Variantes
            // (largeur/hauteur/profondeur/poids, quand l'option correspondante
            // est activee dans Parametres) - memes champs que "taille" ou "cl"
            // un peu plus haut, qui ne se saisissent pas non plus ici.
            // Les colonnes products.pack_size/weight_kg/width_cm/height_cm/
            // depth_cm RESTENT en base : aucune donnee saisie n'est perdue.
            { key: 'unit_price', label: 'Prix vente', type: 'number', step: '0.01' },
            { key: 'cost_price', label: 'Prix achat', type: 'number', step: '0.01' },
            { key: 'tax_id', label: 'Taxe (TVA)', type: 'select', optionsFrom: 'taxes', optionLabel: 'name' },
            // UN SEUL seuil. Le formulaire en demandait quatre : "Seuil
            // alerte", "Stock mini", "Stock maxi" et "Stock securite". Les
            // deux premiers faisaient la meme chose (l'alerte se declenchait
            // sous le plus eleve des deux), les deux autres n'etaient lus
            // nulle part - saisir un "stock de securite" n'avait aucun effet.
            // Les colonnes restent en base (aucune donnee perdue), voir la
            // migration 202602270015.
            { key: 'reorder_level', label: 'Seuil d\'alerte (alerte des que le stock descend a cette valeur)', type: 'number' },
            { key: 'valuation_method', label: 'Valorisation', type: 'select', defaultValue: state.defaultValuationMethod, options: [
                { value: 'CUMP', label: 'CUMP (cout moyen pondere)' },
                { value: 'FIFO', label: 'FIFO (premier entre, premier sorti)' },
            ] },
            // Champ unique de mise en service du produit. La colonne
            // `products.status` (ACTIVE/INACTIVE) du schema initial faisait
            // doublon avec `is_active` (migration 202602270002, ajoutee juste
            // apres) et n'etait lue nulle part : elle est retiree du formulaire.
            // La colonne reste en base et l'import CSV continue de la remplir,
            // rien n'est casse pour l'existant.
            { key: 'is_active', label: 'Produit actif (un produit inactif reste consultable mais disparait des listes de saisie)', type: 'select', options: [
                { value: '1', label: 'Oui' },
                { value: '0', label: 'Non' },
            ] },
            ];

            // Le choix "ce produit a des variantes" n'a de sens que si au moins
            // une des deux options est activee dans Parametres (sinon le module
            // Variantes est masque et le champ n'aurait nulle part ou etre
            // exploite). Le libelle s'adapte a l'option reellement active.
            //
            // Ce champ ne fait que BASCULER le produit en mode "a variantes" :
            // il n'y a jamais eu de champ ici pour saisir les valeurs (taille,
            // couleur, contenance en cl...) elles-memes - normal, un produit a
            // variantes en a generalement plusieurs (ex: 3 tailles x 4
            // couleurs), ce qui ne rentre pas dans un champ unique de sa fiche.
            // Ces valeurs se saisissent dans le module dedie "Variantes" (ou
            // le generateur en lot cree toutes les combinaisons d'un coup).
            // Ce que ce champ n'indiquait pas assez clairement : le champ
            // "Oui" se contentait de dire "gerer les variantes dans le module
            // dedie" sans dire OU se trouve ce module ni ce qu'on y trouve -
            // d'ou l'ajout de l'indice ci-dessous.
            if (anyVariantsEnabled()) {
                fields.push({ key: 'has_variants', label: `Ce produit a des variantes (${variantsAttributesLabel()})`, type: 'select', options: [
                    { value: '0', label: 'Non' },
                    { value: '1', label: 'Oui - gerer les variantes dans le module dedie' },
                ], hint: `Les valeurs precises (${variantsAttributesLabel()}) ne se saisissent pas ici : une fois "Oui" choisi et le produit enregistre, utilise le menu <strong>Variantes</strong> pour les ajouter une par une ou en lot (toutes les combinaisons possibles generees d'un coup).` });
            }

            fields.push({ key: 'tag_ids', label: 'Tags', type: 'multiselect', optionsFrom: 'tags', optionLabel: 'name', valueFrom: 'tags' });

            // Stock initial : un produit n'appartient pas a un entrepot, c'est
            // son STOCK qui y est reparti. Jusqu'ici il fallait creer le
            // produit puis aller faire un mouvement d'entree dans un autre
            // ecran. Ces deux champs evitent cet aller-retour ; ils ne sont
            // proposes qu'a la CREATION (createOnly), car modifier un stock se
            // fait par un mouvement trace, jamais en editant une fiche.
            fields.push(
                { key: 'initial_warehouse_id', label: 'Stock initial - entrepot (optionnel)', type: 'select', optionsFrom: 'warehouses', optionLabel: 'name', createOnly: true },
                // Emplacement du stock initial : sans lui, les quantites
                // saisies a la creation arrivaient "non rangees" dans
                // l'entrepot, et il fallait faire un transfert interne juste
                // apres pour les placer. La liste se remplit avec les
                // emplacements de l'entrepot choisi (voir
                // setupInitialStockLocation).
                { key: 'initial_location_id', label: 'Stock initial - emplacement (optionnel)', type: 'select', optionsFrom: 'warehouse_locations', optionLabel: 'code', createOnly: true },
                { key: 'initial_quantity', label: 'Stock initial - quantite', type: 'number', createOnly: true },
            );

            return fields;
        },
        // `secondary: true` = colonne masquee par defaut. Avec dix-sept
        // colonnes, le tableau depassait la largeur de l'ecran et imposait une
        // barre de defilement horizontale : on ne lisait jamais une ligne en
        // entier. Les colonnes gardees sont celles qu'on parcourt des yeux
        // (quoi, combien, ou, a quel prix) ; les autres restent accessibles
        // d'un clic sur "Toutes les colonnes", et figurent de toute facon sur
        // la fiche du produit.
        columns: [
            { key: 'id', label: 'ID', secondary: true },
            { key: 'sku', label: 'SKU' },
            { key: 'barcode', label: 'Code barre', secondary: true },
            { key: 'name', label: 'Nom' },
            // Detail des variantes (declinaisons existantes), pas juste
            // "a des variantes: oui/non" (voir has_variants plus bas) :
            // reutilise variantDescriptor(), la meme regle de priorite que
            // partout ailleurs (vetement, bouteille, dimensions, materiel).
            { key: 'variants_summary', label: 'Variantes', secondary: true, format: (_v, row) => renderVariantsSummary(row.variants) },
            { key: 'category_name', label: 'Categorie' },
            { key: 'brand_name', label: 'Marque', secondary: true },
            { key: 'unit_code', label: 'Unite', secondary: true },
            { key: 'supplier_name', label: 'Fournisseur' },
            { key: 'stock_total', label: 'Stock' },
            { key: 'unit_price', label: 'Prix', format: (value) => formatMoney(value) },
            { key: 'tax_rate', label: 'TVA', secondary: true, format: (value) => (value !== null && value !== undefined ? `${Number(value)}%` : '-') },
            { key: 'valuation_method', label: 'Valorisation', secondary: true },
            { key: 'is_active', label: 'Actif', format: (v) => (Number(v) === 1 ? 'Oui' : 'Non') },
            // Ou aller chercher l'article, sans ouvrir sa fiche.
            { key: 'location_summary', label: 'Emplacements', format: (value) => (value ? sanitize(value) : '<span class="muted">non range</span>') },
            { key: 'has_variants', label: 'Variantes (oui/non)', secondary: true, format: (v) => (Number(v) === 1 ? 'Oui' : 'Non') },
            { key: 'tags', label: 'Tags', format: (value) => renderTagBadges(value) },
        ],
    },
    'product-variants': {
        endpoint: '/product-variants',
        label: 'variante',
        get fields() {
            const fields = [
                { key: 'product_id', label: 'Produit', type: 'select', optionsFrom: 'products', optionLabel: 'name', required: true },
                { key: 'sku', label: 'SKU variante', type: 'text', required: true },
                { key: 'barcode', label: 'Code barre', type: 'text', hint: 'Propre a cette variante. Scanne-le directement depuis l\'article si tu l\'as sous la main.' },
            ];
            // N'affiche que les champs correspondant aux options reellement
            // activees (Parametres) - si aucune des deux n'est active, ce
            // module est de toute facon masque du menu (voir applyVariantsVisibility).
            if (state.clothingVariantsEnabled) {
                fields.push(
                    { key: 'size', label: 'Taille / Pointure', type: 'text' },
                    { key: 'color', label: 'Couleur', type: 'text' },
                );
            }
            if (state.bottleVariantsEnabled) {
                fields.push(
                    { key: 'vintage', label: 'Millesime', type: 'number' },
                    { key: 'volume_cl', label: 'Contenance en cl', type: 'number' },
                );
            }
            // Dimensions LIBRES (texte) : materiel, mobilier, decoupe, tissu au
            // metre... L'unite fait partie de la valeur saisie ("120 cm",
            // "2 m", "3/4 pouce", "sur mesure"), rien n'est impose. Les champs
            // numeriques Largeur/Hauteur/Profondeur/Poids de la FICHE PRODUIT
            // restent disponibles en parallele pour les cotes d'un article sans
            // variante : les deux coexistent selon les articles.
            if (state.dimensionVariantsEnabled) {
                fields.push(
                    { key: 'width', label: 'Largeur (unite libre, ex: 120 cm)', type: 'text' },
                    { key: 'height', label: 'Hauteur (unite libre, ex: 200 cm)', type: 'text' },
                    { key: 'depth', label: 'Profondeur (unite libre, ex: 60 cm)', type: 'text' },
                    { key: 'weight', label: 'Poids (unite libre, ex: 12,5 kg)', type: 'text' },
                );
            }
            // Quatrieme saveur : materiel electrique/mecanique. Champs texte
            // libres (unite comprise dans la saisie), voir la migration
            // 202602270018_technical_variants.sql.
            if (state.technicalVariantsEnabled) {
                fields.push(
                    { key: 'puissance', label: 'Puissance (ex: 1200 W)', type: 'text' },
                    { key: 'marque', label: 'Marque', type: 'text' },
                    { key: 'type', label: 'Type', type: 'text' },
                    { key: 'vitesse', label: 'Vitesse (ex: 3000 tr/min)', type: 'text' },
                    { key: 'tension', label: 'Tension (ex: 230 V)', type: 'text' },
                    { key: 'forme', label: 'Forme', type: 'text' },
                );
            }
            fields.push(
                { key: 'unit_price', label: 'Prix (vide = prix du produit)', type: 'number', step: '0.01' },
                { key: 'is_active', label: 'Actif', type: 'select', options: [
                    { value: '1', label: 'Oui' },
                    { value: '0', label: 'Non' },
                ] },
            );
            return fields;
        },
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'product_name', label: 'Produit' },
            { key: 'sku', label: 'SKU variante' },
            { key: 'descriptor', label: 'Variante', format: (_v, row) => variantDescriptor(row) },
            { key: 'stock_total', label: 'Stock' },
            { key: 'unit_price', label: 'Prix', format: (value) => (value !== null && value !== undefined && value !== '' ? formatMoney(value) : '-') },
            { key: 'is_active', label: 'Actif', format: (v) => (Number(v) === 1 ? 'Oui' : 'Non') },
        ],
    },
    customers: {
        endpoint: '/customers',
        label: 'client',
        fields: [
            { key: 'code', label: 'Code', type: 'text' },
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'email', label: 'Email', type: 'email' },
            { key: 'phone', label: 'Telephone', type: 'text' },
            { key: 'address', label: 'Adresse', type: 'textarea' },
            { key: 'status', label: 'Statut', type: 'select', required: true, options: [
                { value: 'ACTIVE', label: 'ACTIVE' },
                { value: 'INACTIVE', label: 'INACTIVE' },
            ] },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'code', label: 'Code' },
            { key: 'name', label: 'Nom' },
            { key: 'email', label: 'Email' },
            { key: 'status', label: 'Statut' },
        ],
    },
    warehouses: {
        endpoint: '/warehouses',
        label: 'entrepot',
        fields: [
            { key: 'code', label: 'Code', type: 'text', required: true },
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'location', label: 'Localisation', type: 'text' },
            { key: 'is_default', label: 'Par defaut', type: 'select', options: [
                { value: '1', label: 'Oui' },
                { value: '0', label: 'Non' },
            ] },
            { key: 'status', label: 'Statut', type: 'select', required: true, options: [
                { value: 'ACTIVE', label: 'ACTIVE' },
                { value: 'INACTIVE', label: 'INACTIVE' },
            ] },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'code', label: 'Code' },
            { key: 'name', label: 'Nom' },
            { key: 'location', label: 'Localisation' },
            { key: 'status', label: 'Statut' },
        ],
    },
    'warehouse-zones': {
        endpoint: '/warehouse-zones',
        label: 'zone',
        fields: [
            { key: 'warehouse_id', label: 'Entrepot', type: 'select', optionsFrom: 'warehouses', optionLabel: 'name', required: true },
            { key: 'code', label: 'Code', type: 'text', required: true },
            { key: 'name', label: 'Nom', type: 'text', required: true },
        ],
        columns: [
            { key: 'id', label: 'ID', secondary: true },
            { key: 'warehouse_name', label: 'Entrepot' },
            { key: 'code', label: 'Code' },
            { key: 'name', label: 'Nom' },
            // Une zone ne stocke rien par elle-meme : le stock, les numeros de
            // serie et les mouvements sont portes par les EMPLACEMENTS. Une
            // zone sans emplacement n'est donc proposee nulle part a la
            // saisie, ce que rien n'indiquait.
            { key: 'location_count', label: 'Emplacements', format: (value) => (
                Number(value ?? 0) > 0
                    ? String(Number(value))
                    : '<span class="feedback is-error" style="padding:0">0 - zone inutilisable a la saisie</span>'
            ) },
        ],
    },
    'warehouse-locations': {
        endpoint: '/warehouse-locations',
        label: 'emplacement',
        fields: [
            { key: 'warehouse_id', label: 'Entrepot', type: 'select', optionsFrom: 'warehouses', optionLabel: 'name', required: true },
            { key: 'zone_id', label: 'Zone', type: 'select', optionsFrom: 'warehouse_zones', optionLabel: 'name' },
            { key: 'code', label: 'Code', type: 'text', required: true },
            { key: 'description', label: 'Description', type: 'text' },
            { key: 'capacity', label: 'Capacite', type: 'number', step: '0.01' },
            { key: 'is_active', label: 'Actif', type: 'select', options: [
                { value: '1', label: 'Oui' },
                { value: '0', label: 'Non' },
            ] },
        ],
        columns: [
            { key: 'id', label: 'ID', secondary: true },
            { key: 'warehouse_name', label: 'Entrepot' },
            { key: 'zone_name', label: 'Zone', format: (value) => (value ? sanitize(value) : '<span class="muted">aucune zone</span>') },
            { key: 'code', label: 'Code' },
            { key: 'description', label: 'Description' },
            { key: 'capacity', label: 'Capacite' },
            { key: 'is_active', label: 'Actif', format: (v) => (Number(v) === 1 ? 'Oui' : 'Non') },
        ],
    },
    users: {
        endpoint: '/users',
        label: 'utilisateur',
        fields: [
            { key: 'full_name', label: 'Nom complet', type: 'text', required: true },
            { key: 'email', label: 'Email', type: 'email', required: true },
            { key: 'password', label: 'Mot de passe', type: 'password', requiredOnCreate: true },
            // optionLabel: 'code' affichait les codes techniques bruts
            // (ADMIN, STOREKEEPER...). localizeOptions les traduit via
            // ROLE_MATRIX, seule source de verite des droits.
            { key: 'role', label: 'Profil', type: 'select', optionsFrom: 'roles', optionValue: 'code', optionLabel: 'code', localizeOptions: 'role', required: true },
            { key: 'is_active', label: 'Actif', type: 'select', options: [
                { value: '1', label: 'Oui' },
                { value: '0', label: 'Non' },
            ] },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'full_name', label: 'Nom' },
            { key: 'email', label: 'Email' },
            { key: 'role_code', label: 'Profil', format: (value) => sanitize(roleLabel(value)) },
            { key: 'is_active', label: 'Actif', format: (v) => (Number(v) === 1 ? 'Oui' : 'Non') },
            { key: 'created_at', label: 'Creation' },
        ],
    },
    settings: {
        endpoint: '/settings',
        label: 'parametre',
        fields: [
            { key: 'setting_key', label: 'Cle', type: 'text', required: true },
            { key: 'setting_value', label: 'Valeur', type: 'textarea', required: true },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'setting_key', label: 'Cle' },
            { key: 'setting_value', label: 'Valeur' },
            { key: 'updated_at', label: 'Maj' },
        ],
    },
};

boot().catch((error) => {
    console.error(error);
    const root = document.getElementById('appContent');
    if (root) {
        root.innerHTML = `
            <section class="panel">
                <h4>Erreur de chargement</h4>
                <p class="muted">Le dashboard n'a pas pu etre charge. Verifie l'API et la base de donnees, puis recharge la page.</p>
                <p class="feedback is-error">${sanitize(error?.message ?? 'Erreur inconnue')}</p>
                <div class="panel-actions">
                    <button class="btn btn-primary" id="retryBoot">Recharger</button>
                    <button class="btn btn-soft" id="forceLogout">Se reconnecter</button>
                </div>
            </section>
        `;

        document.getElementById('retryBoot')?.addEventListener('click', () => {
            window.location.reload();
        });
        document.getElementById('forceLogout')?.addEventListener('click', () => {
            clearAuth();
            window.location.replace(`${window.APP_CONFIG.frontendBaseUrl}/logout.php`);
        });
        return;
    }

    clearAuth();
    window.location.replace(`${window.APP_CONFIG.frontendBaseUrl}/logout.php`);
});

async function boot() {
    const [
        meResponse,
        lookupResponse,
        clothingSettingResponse,
        bottleSettingResponse,
        dimensionSettingResponse,
        technicalSettingResponse,
        valuationSettingResponse,
        productColumnsSettingResponse,
    ] = await Promise.all([
        apiRequest('/auth/me'),
        apiRequest('/lookups/options'),
        apiRequest('/settings?setting_key=clothing_variants_enabled').catch(() => null),
        apiRequest('/settings?setting_key=bottle_variants_enabled').catch(() => null),
        apiRequest('/settings?setting_key=dimension_variants_enabled').catch(() => null),
        apiRequest('/settings?setting_key=technical_variants_enabled').catch(() => null),
        apiRequest('/settings?setting_key=default_valuation_method').catch(() => null),
        apiRequest('/settings?setting_key=product_list_columns').catch(() => null),
    ]);

    state.user = meResponse.data;
    state.lookups = lookupResponse.data;
    const clothingRow = normalizeRows(clothingSettingResponse)[0];
    const bottleRow = normalizeRows(bottleSettingResponse)[0];
    const dimensionRow = normalizeRows(dimensionSettingResponse)[0];
    const technicalRow = normalizeRows(technicalSettingResponse)[0];
    state.clothingVariantsEnabled = String(clothingRow?.setting_value ?? '0') === '1';
    state.bottleVariantsEnabled = String(bottleRow?.setting_value ?? '0') === '1';
    state.dimensionVariantsEnabled = String(dimensionRow?.setting_value ?? '0') === '1';
    state.technicalVariantsEnabled = String(technicalRow?.setting_value ?? '0') === '1';
    syncValuationSettingState(normalizeRows(valuationSettingResponse)[0]?.setting_value);
    syncProductColumnsSettingState(normalizeRows(productColumnsSettingResponse)[0]?.setting_value);

    const userPill = document.getElementById('userPill');
    userPill.textContent = `${state.user.full_name} | ${localizeValue(state.user.role)}`;
    userPill.addEventListener('click', () => {
        setActiveNav('account');
        renderModule('account');
    });

    setupNavigation();
    applyNavAccess();

    // Les ecrans sont reconstruits par innerHTML un peu partout (renderCrud,
    // renderMovements, fiche produit, modales...). Plutot que d'ajouter un
    // appel apres chacun d'eux - et d'en oublier au prochain ecran ajoute -
    // on observe le document : toute liste deroulante longue qui apparait
    // recoit son champ de filtrage, d'ou qu'elle vienne.
    const selectObserver = new MutationObserver(() => {
        enhanceSelects(document.body);
    });
    selectObserver.observe(document.body, { childList: true, subtree: true });
    applyVariantsVisibility();
    setupGlobalSearch();
    const params = new URLSearchParams(window.location.search);
    const requestedModule = params.get('module') ?? 'dashboard';
    const initialModule = normalizeModule(requestedModule);
    setActiveNav(initialModule);
    await renderModule(initialModule, false);
}

function syncValuationSettingState(settingValue) {
    // Seules deux valeurs sont exploitables (contrainte de la colonne
    // products.valuation_method) : toute autre saisie retombe sur CUMP plutot
    // que de proposer un choix invalide dans le formulaire produit.
    const value = String(settingValue ?? '').trim().toUpperCase();
    state.defaultValuationMethod = value === 'FIFO' ? 'FIFO' : 'CUMP';
}

/**
 * Colonnes personnalisees de l'ecran Produits (reglage `product_list_columns`,
 * ecran Parametres > "Colonnes du tableau Produits"). Valeur JSON (tableau de
 * cles de colonnes) ou absente/vide : dans ce dernier cas, comportement
 * inchange (vue "essentielles"/"toutes les colonnes" existante) - voir
 * visibleColumns().
 */
function syncProductColumnsSettingState(settingValue) {
    if (!settingValue) {
        state.productListColumns = null;
        return;
    }

    try {
        const parsed = JSON.parse(settingValue);
        state.productListColumns = Array.isArray(parsed) && parsed.length > 0 ? parsed : null;
    } catch (_) {
        state.productListColumns = null;
    }
}

function variantsAttributesLabel() {
    // Decrit les attributs de variante reellement disponibles, pour ne pas
    // parler de "taille/couleur" quand seule l'option bouteille est active.
    const parts = [];
    if (state.clothingVariantsEnabled) {
        parts.push('taille/couleur');
    }
    if (state.bottleVariantsEnabled) {
        parts.push('millesime/contenance');
    }
    if (state.dimensionVariantsEnabled) {
        parts.push('largeur/hauteur/profondeur/poids');
    }
    if (state.technicalVariantsEnabled) {
        parts.push('puissance/marque/type/vitesse/tension/forme');
    }
    return parts.length === 0 ? 'aucune option activee' : parts.join(' ou ');
}

// Les reglages qui pilotent le module Variantes. Regroupes ici pour qu'une
// quatrieme "saveur" ne demande pas de repasser sur chaque appel.
const VARIANT_SETTING_KEYS = ['clothing_variants_enabled', 'bottle_variants_enabled', 'dimension_variants_enabled', 'technical_variants_enabled'];

/** Au moins une "saveur" de variantes est-elle activee dans Parametres ? */
function anyVariantsEnabled() {
    return Boolean(state.clothingVariantsEnabled || state.bottleVariantsEnabled || state.dimensionVariantsEnabled || state.technicalVariantsEnabled);
}

function syncVariantsSettingState(settingKey, settingValue) {
    const enabled = String(settingValue ?? '0') === '1';
    if (settingKey === 'clothing_variants_enabled') {
        state.clothingVariantsEnabled = enabled;
    } else if (settingKey === 'bottle_variants_enabled') {
        state.bottleVariantsEnabled = enabled;
    } else if (settingKey === 'dimension_variants_enabled') {
        state.dimensionVariantsEnabled = enabled;
    } else if (settingKey === 'technical_variants_enabled') {
        state.technicalVariantsEnabled = enabled;
    }

    // Reaffiche/masque immediatement le lien "Variantes" sans attendre un
    // rechargement complet de la page.
    const hasEitherEnabled = anyVariantsEnabled();
    const existingLink = document.querySelector('[data-module="product-variants"]');
    if (hasEitherEnabled && !existingLink) {
        const productsLink = document.querySelector('[data-module="products"]');
        if (productsLink) {
            const link = document.createElement('button');
            link.dataset.module = 'product-variants';
            link.className = 'nav-item';
            link.innerHTML = '<i class="bi bi-palette"></i><span>Variantes</span>';
            productsLink.insertAdjacentElement('afterend', link);
        }
    } else if (!hasEitherEnabled && existingLink) {
        existingLink.remove();
    }
}

function applyVariantsVisibility() {
    // Module optionnel (vetement: taille/couleur, bouteille:
    // millesime/contenance, OU materiel: largeur/hauteur/profondeur/poids) :
    // masque le lien de navigation tant qu'aucune de ces options n'est
    // activee dans Parametres.
    if (!anyVariantsEnabled()) {
        document.querySelector('[data-module="product-variants"]')?.remove();
    }
}

function applyNavAccess() {
    const isAdmin = canWrite('users');
    if (!isAdmin) {
        const hiddenModules = ['users', 'settings', 'imports', 'audits'];
        hiddenModules.forEach((module) => {
            const btn = document.querySelector(`[data-module="${module}"]`);
            btn?.remove();
        });
    }

    // Donnees de demo et Migrations restent reserves au Super administrateur
    // meme pour un Administrateur (qui a pourtant tous les autres droits
    // ci-dessus) : c'est le seul cas ou ADMIN et SUPER_ADMIN divergent. Le
    // serveur applique la meme regle de son cote (voir demo-data.php et
    // migrate.php) : masquer le lien ici n'est qu'un confort d'affichage,
    // pas la seule protection.
    const isSuperAdmin = String(state.user?.role ?? '').toUpperCase() === 'SUPER_ADMIN';
    if (!isSuperAdmin) {
        document.getElementById('demoDataNavLink')?.remove();
        document.getElementById('migrateNavLink')?.remove();
    }
}

function setupNavigation() {
    const nav = document.getElementById('mainNav');
    nav?.addEventListener('click', async (event) => {
        const button = event.target.closest('[data-module]');
        if (!button) {
            return;
        }

        const module = button.getAttribute('data-module');
        if (!module || module === state.module) {
            return;
        }

        setActiveNav(module);
        await renderModule(module);
    });
}

let globalSearchTimer = null;
// Un seul rendu de recherche a la fois. Sans cette serialisation, deux
// requetes lancees a 300 ms d'intervalle peuvent revenir dans le desordre :
// la reponse lente pour "vel" repeint l'ecran APRES la reponse rapide pour
// "velo", et la liste affichee ne correspond plus a ce qui est tape.
// Ici, une saisie arrivee pendant un chargement est simplement memorisee et
// traitee juste apres - la boucle se termine donc toujours sur la derniere
// valeur saisie.
let globalSearchRunning = false;
let globalSearchPending = null;

async function runGlobalSearch(rawValue) {
    globalSearchPending = String(rawValue ?? '').trim();
    if (globalSearchRunning) {
        return;
    }

    globalSearchRunning = true;
    try {
        while (globalSearchPending !== null) {
            const value = globalSearchPending;
            globalSearchPending = null;

            // La recherche porte sur l'onglet actuellement affiche (voir
            // GLOBAL_SEARCH_MODULES) : elle ne bascule plus systematiquement
            // sur Produits comme avant.
            if (!GLOBAL_SEARCH_MODULES.includes(state.module)) {
                continue;
            }

            state.globalQuery = value;
            // Nouvelle recherche = nouveau jeu de resultats : rester page 3
            // afficherait une page vide.
            state.crudPages[state.module] = 1;
            await renderModule(state.module, false);
        }
    } finally {
        globalSearchRunning = false;
    }
}

/**
 * Recherche validee par Entree - c'est aussi ce que produit une douchette,
 * qui se comporte comme un clavier : elle "tape" le code puis envoie Entree.
 *
 * Sur l'ecran Produits uniquement : si le code tape designe UN SEUL article
 * et qu'il correspond exactement a son code barre ou a son SKU, sa fiche
 * s'ouvre directement - c'est le geste attendu apres un scan. Une recherche
 * par mot ("velo"), un code qui remonte plusieurs articles, ou une recherche
 * sur un autre onglet, laisse simplement la liste filtree - aucune fiche ne
 * s'ouvre a tort.
 */
async function submitGlobalSearch(rawValue) {
    const query = String(rawValue ?? '').trim();
    await runGlobalSearch(query);

    if (query === '' || state.module !== 'products') {
        return;
    }

    const rows = Array.isArray(state.lastProductRows) ? state.lastProductRows : [];
    if (rows.length !== 1) {
        return;
    }

    const row = rows[0];
    const needle = query.toLowerCase();
    const exact = [row.barcode, row.sku]
        .some((value) => String(value ?? '').trim().toLowerCase() === needle);
    if (!exact) {
        return;
    }

    state.activeProductId = Number(row.id);
    await renderProductDetail(Number(row.id));
    document.getElementById('productDetailPane')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function setupGlobalSearch() {
    const input = document.getElementById('globalSearch');

    // Recherche au fil de la frappe. Le delai evite une requete par touche :
    // on n'interroge l'API qu'une fois la saisie stabilisee.
    input?.addEventListener('input', () => {
        // Rien a chercher sur un ecran qui ne le supporte pas (le champ est
        // de toute facon desactive, voir renderModule) - et sur un ecran qui
        // le supporte, la saisie filtre CET ecran, pas systematiquement
        // Produits.
        if (!GLOBAL_SEARCH_MODULES.includes(state.module)) {
            return;
        }

        window.clearTimeout(globalSearchTimer);
        globalSearchTimer = window.setTimeout(() => {
            runGlobalSearch(input.value);
        }, 300);
    });

    input?.addEventListener('keydown', async (event) => {
        if (event.key === 'Escape') {
            input.value = '';
            window.clearTimeout(globalSearchTimer);
            if (GLOBAL_SEARCH_MODULES.includes(state.module)) {
                await runGlobalSearch('');
            }
            return;
        }

        if (event.key !== 'Enter') {
            return;
        }

        event.preventDefault();
        window.clearTimeout(globalSearchTimer);
        await submitGlobalSearch(input.value);
        // Le champ est vide pour le scan suivant, mais on garde le focus :
        // en caisse ou en reception, on enchaine les articles sans toucher a
        // la souris.
        input.select();
    });
}

/**
 * Droits d'ECRITURE par profil, et description affichee a l'utilisateur.
 *
 * Une seule et meme source pour les deux : le tableau "qui peut quoi" montre
 * a l'administrateur est CALCULE a partir de cette matrice, il ne peut donc
 * pas raconter autre chose que ce que l'application applique reellement.
 * Cote serveur, les memes regles sont posees par RoleMiddleware
 * (backend/public/index.php) - toute modification doit etre faite des deux
 * cotes.
 *
 * `all: true` = tous les ecrans, administration comprise.
 */
const ROLE_MATRIX = {
    // Reserve au tout premier compte de l'installation (voir install.php) :
    // jamais propose dans le selecteur de profil de l'ecran Utilisateurs
    // (voir RoleRepository::allAssignable() cote serveur, qui l'exclut de la
    // liste deroulante - la meme regle est donc appliquee des deux cotes).
    SUPER_ADMIN: {
        label: 'Super administrateur',
        summary: "Tous les droits de l'Administrateur, plus deux ecrans qui lui sont reserves : Donnees de demo et Migrations.",
        all: true,
    },
    ADMIN: {
        label: 'Administrateur',
        // Seule difference avec SUPER_ADMIN : ni Donnees de demo, ni
        // Migrations (masques du menu et refuses cote serveur si contournes
        // - voir applyNavAccess() et demo-data.php/migrate.php). Tout le
        // reste (utilisateurs, parametres, catalogue...) reste identique.
        summary: "Tous les droits, y compris la gestion des utilisateurs et des parametres - a l'exception de Donnees de demo et Migrations, reserves au Super administrateur.",
        all: true,
    },
    MANAGER: {
        label: 'Responsable',
        summary: "Le stock au quotidien, plus les achats et les fournisseurs. Ne gere ni les utilisateurs, ni les parametres, ni le catalogue produit.",
        modules: ['movements', 'product-serials', 'product-variants', 'deliveries', 'inventories', 'alerts', 'purchase-requests', 'purchase-orders', 'suppliers'],
    },
    STOREKEEPER: {
        label: 'Magasinier',
        summary: "Tout ce qui touche au stock physique : mouvements, numeros de serie, livraisons, inventaires. Pas d'achats, pas de catalogue, pas d'administration.",
        modules: ['movements', 'product-serials', 'product-variants', 'deliveries', 'inventories', 'alerts'],
    },
    BUYER: {
        label: 'Acheteur',
        summary: "Les achats et les tiers : demandes, commandes, fournisseurs, clients. Ne touche pas au stock.",
        modules: ['suppliers', 'customers', 'purchase-requests', 'purchase-orders'],
    },
    // EMPLOYEE est cree par l'installateur : il DOIT figurer ici, sinon un
    // utilisateur "Employe" tombe dans le cas "profil inconnu" - lecture
    // seule de fait, mais sans que personne l'ait decide ni annonce.
    EMPLOYEE: {
        label: 'Employe',
        summary: "Consultation uniquement : il voit les ecrans, mais ne peut rien enregistrer. A donner a quelqu'un qui doit juste chercher une reference ou un stock.",
        modules: [],
    },
    VIEWER: {
        label: 'Lecture seule',
        summary: "Consultation uniquement : aucun enregistrement n'est possible, sur aucun ecran.",
        modules: [],
    },
};

function canWrite(module) {
    const role = String(state.user?.role ?? '').toUpperCase();
    const profile = ROLE_MATRIX[role];
    if (!profile) {
        // Profil inconnu de l'application (ajoute directement en base) :
        // lecture seule, jamais d'ecriture par defaut.
        return false;
    }

    return profile.all === true || (profile.modules ?? []).includes(module);
}

/** Libelle francais d'un code de profil, code brut si inconnu. */
function roleLabel(code) {
    const key = String(code ?? '').toUpperCase();
    return ROLE_MATRIX[key]?.label ?? code;
}

/**
 * Tableau "qui peut quoi", affiche sur l'ecran Utilisateurs.
 *
 * Sans lui, l'administrateur choisissait un profil dans une liste de codes
 * techniques (ADMIN, STOREKEEPER...) sans aucune indication de ce que
 * chacun autorise - donc au jugé.
 */
function renderRoleMatrix() {
    const rows = Object.entries(ROLE_MATRIX).map(([code, profile]) => {
        const ecrans = profile.all === true
            ? '<strong>tous les ecrans</strong>'
            : ((profile.modules ?? []).length === 0
                ? '<span class="muted">aucun (consultation seule)</span>'
                : profile.modules.map((module) => sanitize(moduleTitles[module] ?? module)).join(', '));

        return `
            <tr>
                <td><strong>${sanitize(profile.label)}</strong><br><code>${sanitize(code)}</code></td>
                <td>${sanitize(profile.summary)}</td>
                <td>${ecrans}</td>
            </tr>`;
    }).join('');

    return `
        <section class="panel">
            <div class="panel-head"><h4>Profils et droits</h4></div>
            <p class="muted">
                Tout utilisateur connecte peut CONSULTER les ecrans auxquels il accede ;
                le tableau ci-dessous liste ce qu'il peut en plus <strong>creer, modifier ou
                supprimer</strong>. Les memes regles sont appliquees par le serveur : un profil
                qui n'a pas le droit se voit refuser l'operation meme en contournant l'interface.
            </p>
            <div class="table-wrap">
                <table class="data-table">
                    <thead><tr><th>Profil</th><th>En resume</th><th>Ecrans ou il peut enregistrer</th></tr></thead>
                    <tbody>${rows}</tbody>
                </table>
            </div>
        </section>
    `;
}

function setActiveNav(module) {
    const nav = document.getElementById('mainNav');
    if (!nav) {
        return;
    }

    for (const item of nav.querySelectorAll('.nav-item')) {
        item.classList.remove('is-active');
    }

    const target = nav.querySelector(`[data-module="${module}"]`);
    if (target) {
        target.classList.add('is-active');
    }
}

function normalizeModule(module) {
    if (moduleTitles[module]) {
        return module;
    }

    return 'dashboard';
}

function syncUrlModule(module) {
    const url = new URL(window.location.href);
    url.searchParams.set('module', module);
    window.history.replaceState({}, '', url);
}

async function renderModule(module, updateUrl = true) {
    // On normalise toujours le module pour eviter les routes UI invalides.
    const normalized = normalizeModule(module);

    // La recherche globale s'applique a l'onglet affiche (voir
    // GLOBAL_SEARCH_MODULES). En le quittant on la vide, champ compris :
    // sinon on revenait sur ce module avec "velo" toujours ecrit et la liste
    // toujours filtree, sans comprendre pourquoi - et pire, le mot restait
    // affiche pendant qu'on consultait un autre ecran ou il ne s'appliquait
    // plus.
    if (GLOBAL_SEARCH_MODULES.includes(state.module) && normalized !== state.module) {
        state.globalQuery = '';
        state.crudPages[state.module] = 1;
        const searchInput = document.getElementById('globalSearch');
        if (searchInput) {
            searchInput.value = '';
        }
    }
    if (state.module === 'products' && normalized !== 'products') {
        state.tagFilter = '';
        state.warehouseFilter = '';
        state.categoryFilter = '';
        state.supplierFilter = '';
        state.locationFilter = '';
    }

    state.module = normalized;

    if (updateUrl) {
        syncUrlModule(normalized);
    }

    document.getElementById('pageTitle').textContent = moduleTitles[normalized] ?? normalized;

    const globalSearchInput = document.getElementById('globalSearch');
    if (globalSearchInput) {
        const searchable = GLOBAL_SEARCH_MODULES.includes(normalized);
        globalSearchInput.disabled = !searchable;
        globalSearchInput.placeholder = normalized === 'products'
            ? 'Recherche ou scan douchette : nom, SKU, code barre'
            : searchable
                ? `Rechercher dans ${moduleTitles[normalized] ?? normalized}...`
                : 'Recherche indisponible sur cet ecran';
    }

    if (normalized === 'dashboard') {
        await renderDashboard();
        return;
    }

    if (normalized === 'movements') {
        await renderMovements();
        return;
    }

    if (normalized === 'product-serials') {
        await renderProductSerials();
        return;
    }

    if (normalized === 'deliveries') {
        await renderDeliveries();
        return;
    }

    if (normalized === 'inventories') {
        await renderInventories();
        return;
    }

    if (normalized === 'audits') {
        await renderAudits();
        return;
    }

    if (normalized === 'account') {
        await renderAccount();
        return;
    }

    if (normalized === 'alerts') {
        await renderAlerts();
        return;
    }

    if (normalized === 'purchase-requests') {
        await renderPurchaseRequests();
        return;
    }

    if (normalized === 'purchase-orders') {
        await renderPurchaseOrders();
        return;
    }

    if (normalized === 'reports') {
        await renderReports();
        return;
    }

    if (normalized === 'imports') {
        await renderImports();
        return;
    }

    if (crudModules[normalized]) {
        await renderCrud(normalized);
    }
}

async function renderDashboard() {
    // Vue d'ensemble: KPIs + graphiques + dernieres activites.
    const root = document.getElementById('appContent');
    const response = await apiRequest('/dashboard/stats');
    const data = response.data;

    const kpis = [
        { label: 'Valeur stock', value: formatMoney(data.totals.stock_value), icon: 'bi-cash-stack', theme: 'kpi-teal', target: 'products' },
        { label: 'Produits', value: data.totals.products, icon: 'bi-box-seam', theme: 'kpi-blue', target: 'products' },
        { label: 'Ruptures', value: data.totals.out_of_stock, icon: 'bi-exclamation-triangle', theme: 'kpi-red', target: 'alerts' },
        { label: 'Stock bas', value: data.totals.low_stock, icon: 'bi-thermometer-half', theme: 'kpi-orange', target: 'alerts' },
        { label: 'Commandes en retard', value: data.totals.delayed_po, icon: 'bi-clock-history', theme: 'kpi-violet', target: 'purchase-orders' },
        { label: 'Commandes ouvertes', value: data.totals.purchase_orders_pending, icon: 'bi-cart-check', theme: 'kpi-cyan', target: 'purchase-orders' },
        { label: 'Demandes achat', value: data.totals.purchase_requests_open, icon: 'bi-file-earmark-text', theme: 'kpi-slate', target: 'purchase-requests' },
        { label: 'Entrepots', value: data.totals.warehouses, icon: 'bi-building', theme: 'kpi-gold', target: 'warehouses' },
    ];

    root.innerHTML = `
        <div class="kpi-grid">
            ${kpis.map((item) => `
                <article class="kpi-card ${item.theme} kpi-clickable" data-target="${item.target}" role="button" tabindex="0">
                    <div class="kpi-head"><strong>${item.label}</strong><i class="bi ${item.icon}"></i></div>
                    <p class="kpi-value">${sanitize(item.value)}</p>
                    <p class="kpi-label">Mise a jour temps reel</p>
                </article>
            `).join('')}
        </div>

        <div class="chart-grid">
            <section class="panel">
                <h4>Tendance des mouvements</h4>
                <p class="dashboard-subtitle">Volumes de mouvements recents</p>
                <div class="chart-canvas-wrap"><canvas id="movementTrendChart"></canvas></div>
            </section>
            <section class="panel">
                <h4>Top sorties</h4>
                <p class="dashboard-subtitle">Produits les plus sortants</p>
                <div class="chart-canvas-wrap"><canvas id="topOutgoingChart"></canvas></div>
            </section>
        </div>

        <div class="panel-grid">
            <section class="panel">
                <h4>Derniers mouvements</h4>
                ${renderSimpleTable(data.recent_movements, [
                    ['created_at', 'Date'],
                    ['type', 'Type'],
                    ['sku', 'SKU'],
                    ['product_name', 'Produit'],
                    ['quantity', 'Quantite'],
                    ['warehouse_code', 'Source'],
                    ['destination_warehouse_code', 'Destination'],
                ])}
            </section>

            <section class="panel">
                <h4>Top sorties/transferts</h4>
                ${renderSimpleTable(data.top_outgoing, [
                    ['sku', 'SKU'],
                    ['name', 'Produit'], 
                    ['qty_out', 'Quantite'],
                ])}
            </section>
        </div>
    `;

    renderDashboardCharts(data);

    // #appContent (root) persiste entre deux visites du tableau de bord :
    // on retire l'ecouteur precedent avant d'en attacher un nouveau, pour
    // eviter le meme piege d'accumulation que sur les boutons Supprimer.
    if (root._dashboardClickHandler) {
        root.removeEventListener('click', root._dashboardClickHandler);
    }

    const dashboardClickHandler = async (event) => {
        const card = event.target.closest('.kpi-clickable');
        if (!card) {
            return;
        }

        const target = card.dataset.target;
        if (!target) {
            return;
        }

        setActiveNav(target);
        await renderModule(target);
    };

    root._dashboardClickHandler = dashboardClickHandler;
    root.addEventListener('click', dashboardClickHandler);

    if (root._dashboardKeyHandler) {
        root.removeEventListener('keydown', root._dashboardKeyHandler);
    }

    const dashboardKeyHandler = async (event) => {
        if (event.key !== 'Enter' && event.key !== ' ') {
            return;
        }

        const card = event.target.closest('.kpi-clickable');
        if (!card) {
            return;
        }

        event.preventDefault();
        const target = card.dataset.target;
        if (!target) {
            return;
        }

        setActiveNav(target);
        await renderModule(target);
    };

    root._dashboardKeyHandler = dashboardKeyHandler;
    root.addEventListener('keydown', dashboardKeyHandler);
}

function renderDashboardCharts(data) {
    // Si Chart.js n'est pas charge, on garde une page stable sans casser l'UI.
    if (typeof window.Chart === 'undefined') {
        return;
    }

    destroyDashboardCharts();

    const recent = Array.isArray(data.recent_movements) ? [...data.recent_movements].reverse() : [];
    const labels = recent.map((row) => String(row.created_at ?? '').slice(0, 16).replace('T', ' '));
    const quantities = recent.map((row) => Math.abs(Number(row.quantity ?? 0)));

    const trendCanvas = document.getElementById('movementTrendChart');
    if (trendCanvas) {
        dashboardCharts.movementTrend = new window.Chart(trendCanvas, {
            type: 'line',
            data: {
                labels,
                datasets: [{
                    label: 'Quantite',
                    data: quantities,
                    borderColor: '#0f8f74',
                    backgroundColor: 'rgba(15, 143, 116, 0.16)',
                    tension: 0.3,
                    fill: true,
                    borderWidth: 2,
                    pointRadius: 3,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    x: { grid: { color: 'rgba(16,34,45,0.08)' } },
                    y: { beginAtZero: true, grid: { color: 'rgba(16,34,45,0.08)' } },
                },
            },
        });
    }

    const top = Array.isArray(data.top_outgoing) ? data.top_outgoing.slice(0, 8) : [];
    const outCanvas = document.getElementById('topOutgoingChart');
    if (outCanvas) {
        dashboardCharts.outgoing = new window.Chart(outCanvas, {
            type: 'bar',
            data: {
                labels: top.map((row) => row.sku ?? '-'),
                datasets: [{
                    label: 'Sorties',
                    data: top.map((row) => Number(row.qty_out ?? 0)),
                    backgroundColor: ['#186bb2', '#0ea88a', '#f78c35', '#6a59e6', '#df4d5c', '#1f9fb0', '#cc9b24', '#374b60'],
                    borderRadius: 8,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    x: { grid: { display: false } },
                    y: { beginAtZero: true, grid: { color: 'rgba(16,34,45,0.08)' } },
                },
            },
        });
    }
}

function destroyDashboardCharts() {
    if (dashboardCharts.movementTrend) {
        dashboardCharts.movementTrend.destroy();
        dashboardCharts.movementTrend = null;
    }
    if (dashboardCharts.outgoing) {
        dashboardCharts.outgoing.destroy();
        dashboardCharts.outgoing = null;
    }
}

// Libelle francais (avec article) de chaque entite journalisee - sert a
// batir une phrase lisible ("a supprime le produit «X»") plutot que
// d'afficher le nom technique de table ("product") tel quel.
const AUDIT_ENTITY_LABELS = {
    category: 'la catégorie',
    supplier: 'le fournisseur',
    product: 'le produit',
    product_variant: 'la variante produit',
    brand: 'la marque',
    unit: "l'unité",
    tax: 'la taxe',
    tag: 'le tag',
    customer: 'le client',
    warehouse: "l'entrepôt",
    warehouse_zone: "la zone d'entrepôt",
    warehouse_location: "l'emplacement",
    app_setting: 'le paramètre',
    product_media: 'le média produit',
    stock_alert: "l'alerte de stock",
    import_job: "l'import",
    user: "l'utilisateur",
    delivery: 'la livraison',
    inventory_session: "la session d'inventaire",
    inventory_session_item: 'la ligne de comptage',
    product_serial: 'le numéro de série',
    purchase_order: "la commande d'achat",
    purchase_request: "la demande d'achat",
    stock_movement: 'le mouvement de stock',
    document_attachment: 'la pièce jointe',
    auth: 'la session',
};

// Verbe francais associe a chaque action journalisee. Couvre TOUTES les
// actions ecrites par le backend (voir les appels a AuditRepository::log
// dans backend/src/Application/Services/*.php) - une action non listee ici
// retombe sur son nom brut en minuscules (voir describeAuditEntry).
const AUDIT_ACTION_VERBS = {
    CREATE: 'a créé',
    UPDATE: 'a modifié',
    UPDATE_STATUS: 'a changé le statut de',
    DELETE: 'a supprimé',
    UPLOAD: 'a téléversé',
    LOGIN: "s'est connecté",
    LOGOUT: "s'est déconnecté",
    RESET_PASSWORD: 'a réinitialisé le mot de passe de',
    CHANGE_PASSWORD: 'a changé son mot de passe',
    CANCEL: 'a annulé',
    RECEIVE: 'a réceptionné',
    FINALIZE: 'a finalisé',
    IMPORT: 'a importé des données pour',
    IMPORT_COUNTS: 'a importé un comptage Excel pour',
    COUNT: 'a saisi un comptage pour',
    MARK_OUT: 'a marqué comme sorti',
    MARK_IN_STOCK: 'a remis en stock',
    CONVERT: 'a converti',
};

// Options du filtre "Action" (valeur envoyee au backend + libelle francais
// affiche). Liste explicite plutot que derivee de AUDIT_ACTION_VERBS : un
// verbe a l'infinitif se lit mieux dans une liste deroulante qu'un verbe
// conjugue ("Créer" plutot que "a créé").
const AUDIT_ACTION_OPTIONS = [
    ['CREATE', 'Création'],
    ['UPDATE', 'Modification'],
    ['UPDATE_STATUS', 'Changement de statut'],
    ['DELETE', 'Suppression'],
    ['UPLOAD', 'Téléversement de fichier'],
    ['LOGIN', 'Connexion'],
    ['LOGOUT', 'Déconnexion'],
    ['RESET_PASSWORD', 'Réinitialisation de mot de passe'],
    ['CHANGE_PASSWORD', 'Changement de mot de passe'],
    ['CANCEL', 'Annulation'],
    ['RECEIVE', 'Réception'],
    ['FINALIZE', 'Finalisation'],
    ['IMPORT', 'Import de données'],
    ['IMPORT_COUNTS', 'Import de comptage Excel'],
    ['COUNT', 'Saisie de comptage'],
    ['MARK_OUT', 'Sortie de numéro de série'],
    ['MARK_IN_STOCK', 'Remise en stock'],
    ['CONVERT', 'Conversion'],
].map(([value, label]) => ({ value, label }));

/**
 * Cherche un libelle affichable (nom/code/...) pour un id dans un
 * referentiel de state.lookups (state.lookups.products, .warehouses,
 * .warehouse_locations, ...). Renvoie null si l'id est absent, vide, ou
 * introuvable dans le referentiel (par ex. si refreshLookups() n'a pas ete
 * appele) - describeAuditEntry retombe alors sur l'identifiant technique.
 */
function auditLookupLabel(collection, id) {
    if (id === null || id === undefined || id === '') {
        return null;
    }
    const list = state.lookups?.[collection] ?? [];
    const match = list.find((item) => String(item.id) === String(id));
    if (!match) {
        return null;
    }
    return match.name ?? match.code ?? match.full_name ?? match.sku ?? null;
}

/**
 * Construit une phrase francaise unique et comprehensible pour une ligne du
 * journal d'audit ("Fred a supprimé le produit «Chaise Oslo»"), a partir du
 * payload_json enregistre par AuditRepository::log(). Objectif du ticket :
 * comprendre immediatement ce qu'a fait un utilisateur, sans avoir a
 * recouper manuellement action/entite/ID/JSON brut.
 */
function describeAuditEntry(row) {
    const action = String(row.action ?? '');
    const entityType = String(row.entity_type ?? '');
    const verb = AUDIT_ACTION_VERBS[action] ?? action.toLowerCase().replace(/_/g, ' ');
    const entityLabel = AUDIT_ENTITY_LABELS[entityType] ?? entityType;
    const actor = sanitize(row.user_name ?? row.user_email ?? 'Un compte système');

    let payload = {};
    if (row.payload_json) {
        try {
            payload = JSON.parse(row.payload_json) ?? {};
        } catch {
            payload = {};
        }
    }

    // Connexion/deconnexion : pas d'entite ciblee, la phrase s'arrete au verbe.
    if (entityType === 'auth') {
        return `${actor} ${verb}.`;
    }

    if (action === 'CHANGE_PASSWORD') {
        return `${actor} a changé son propre mot de passe.`;
    }

    let identifier = null;

    switch (entityType) {
        case 'product':
        case 'product_variant':
            identifier = payload.name ?? payload.sku ?? payload.label ?? null;
            break;
        case 'user':
            identifier = payload.target_email ?? payload.email ?? payload.full_name ?? null;
            break;
        case 'delivery':
            identifier = payload.delivery_number ?? null;
            break;
        case 'purchase_order':
            identifier = payload.order_number
                ?? (payload.status ? `nouveau statut : ${payload.status}` : null);
            break;
        case 'purchase_request':
            identifier = payload.request_number
                ?? (payload.converted_to_purchase_order ? `convertie en commande #${payload.converted_to_purchase_order}` : null)
                ?? (payload.status ? `nouveau statut : ${payload.status}` : null);
            break;
        case 'inventory_session':
            identifier = payload.code
                ?? (action === 'IMPORT_COUNTS'
                    ? `${payload.success ?? 0}/${payload.total ?? 0} ligne(s), ${payload.failed ?? 0} erreur(s)`
                    : null);
            break;
        case 'inventory_session_item': {
            const productName = auditLookupLabel('products', payload.product_id);
            identifier = productName
                ? `${productName}${payload.counted_qty !== undefined ? ` (compté : ${payload.counted_qty})` : ''}`
                : null;
            break;
        }
        case 'product_serial':
            identifier = payload.serial_number
                ?? (payload.product_id ? `${payload.count ?? 1} unité(s) - ${auditLookupLabel('products', payload.product_id) ?? 'produit #' + payload.product_id}` : null);
            break;
        case 'document_attachment':
            identifier = payload.file_name ?? null;
            break;
        case 'import_job':
            identifier = payload.entity
                ? `${payload.entity} (${payload.success ?? 0}/${payload.total ?? 0} ligne(s))`
                : null;
            break;
        case 'stock_movement': {
            const productName = auditLookupLabel('products', payload.product_id);
            const warehouseName = auditLookupLabel('warehouses', payload.warehouse_id);
            const typeLabel = { IN: 'entrée', OUT: 'sortie', TRANSFER: 'transfert', ADJUSTMENT: 'ajustement' }[payload.type] ?? payload.type;
            const parts = [];
            if (typeLabel) {
                parts.push(typeLabel);
            }
            if (payload.quantity !== undefined && payload.quantity !== null) {
                parts.push(`de ${payload.quantity}`);
            }
            if (productName) {
                parts.push(`- ${productName}`);
            }
            if (warehouseName) {
                parts.push(`(${warehouseName})`);
            }
            identifier = parts.length > 0 ? parts.join(' ') : null;
            break;
        }
        default:
            identifier = payload.label ?? payload.name ?? payload.full_name ?? payload.code ?? payload.email ?? null;
    }

    const safeIdentifier = identifier !== null ? sanitize(String(identifier)) : null;
    const target = safeIdentifier
        ? `${entityLabel} « ${safeIdentifier} »`
        : `${entityLabel} #${row.entity_id ?? '?'}`;

    return `${actor} ${verb} ${target}.`;
}

async function renderAudits() {
    // Journal d'audit en lecture seule (qui a fait quoi) - reserve aux admins,
    // deja filtre par le middleware cote backend, on ne fait ici que l'affichage.
    const root = document.getElementById('appContent');

    const filters = state.auditFilters ?? { user_id: '', action: '' };
    state.auditFilters = filters;

    // refreshLookups() alimente state.lookups.products/warehouses/... : sans
    // cet appel, describeAuditEntry() ne peut pas resoudre un product_id ou
    // warehouse_id en nom lisible dans les mouvements de stock (l'ecran
    // Audit n'appelait jusqu'ici jamais refreshLookups()).
    const [usersResponse, auditsResponse] = await Promise.all([
        apiRequest('/users' + toQueryString({ per_page: 200 })),
        apiRequest('/audits' + toQueryString({ ...filters, per_page: 100 })),
        refreshLookups(),
    ]);

    const users = normalizeRows(usersResponse);
    const rows = normalizeRows(auditsResponse);

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head">
                <h4>Journal d'audit</h4>
            </div>
            <form id="auditFilterForm" class="form-grid">
                <label>
                    <span>Utilisateur</span>
                    <select name="user_id">
                        <option value="">Tous</option>
                        ${users.map((u) => `<option value="${u.id}" ${String(filters.user_id) === String(u.id) ? 'selected' : ''}>${sanitize(u.full_name)}</option>`).join('')}
                    </select>
                </label>
                <label>
                    <span>Action</span>
                    <select name="action">
                        <option value="">Toutes</option>
                        ${AUDIT_ACTION_OPTIONS.map((a) => `<option value="${a.value}" ${filters.action === a.value ? 'selected' : ''}>${sanitize(a.label)}</option>`).join('')}
                    </select>
                </label>
                <div class="full form-actions">
                    <button type="submit" class="btn btn-primary">Filtrer</button>
                    <button type="button" id="auditFilterReset" class="btn btn-soft">Reinitialiser</button>
                    <button type="button" id="auditClearAll" class="btn btn-danger">Vider le journal</button>
                </div>
            </form>
        </section>

        <section class="panel">
            <h4>Historique (100 dernieres entrees)</h4>
            ${renderSimpleTable(rows, [
                ['created_at', 'Date'],
                ['description', 'Ce qui s\'est passé', (value, row) => describeAuditEntry(row)],
                ['ip_address', 'IP', (value) => sanitize(value ?? '')],
                ['payload_json', 'Détail technique', (value, row) => (value
                    ? `<details><summary>${sanitize(row.entity_type ?? '')} #${sanitize(String(row.entity_id ?? ''))}</summary><code>${sanitize(value)}</code></details>`
                    : ''),
                ],
            ])}
        </section>
    `;

    const form = document.getElementById('auditFilterForm');
    form?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const data = new FormData(form);
        state.auditFilters = {
            user_id: String(data.get('user_id') ?? ''),
            action: String(data.get('action') ?? ''),
        };
        await renderAudits();
    });

    document.getElementById('auditFilterReset')?.addEventListener('click', async () => {
        state.auditFilters = { user_id: '', action: '' };
        await renderAudits();
    });

    document.getElementById('auditClearAll')?.addEventListener('click', async () => {
        const confirmText = prompt('Cette action va supprimer definitivement TOUT le journal d\'audit (l\'historique de qui a fait quoi). Tape SUPPRIMER pour confirmer :');
        if (confirmText !== 'SUPPRIMER') {
            if (confirmText !== null) {
                alert('Confirmation invalide, rien n\'a ete supprime.');
            }
            return;
        }
        try {
            const result = await apiRequest('/audits', { method: 'DELETE' });
            alert(`Journal d'audit vide (${result?.deleted_count ?? 0} entree(s) supprimee(s)).`);
            state.auditFilters = { user_id: '', action: '' };
            await renderAudits();
        } catch (err) {
            alert("Echec de la suppression du journal d'audit : " + (err?.message ?? err));
        }
    });
}

async function renderAccount() {
    // Changement de mot de passe personnel, accessible a tout utilisateur
    // connecte (pas reserve aux admins, contrairement a la reinitialisation
    // depuis la fiche utilisateur).
    const root = document.getElementById('appContent');

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head">
                <h4>Mon compte</h4>
            </div>
            <p class="muted">Connecte en tant que ${sanitize(state.user?.full_name ?? '')} (${sanitize(state.user?.email ?? '')}).</p>
        </section>

        <section class="panel">
            <h4>Changer mon mot de passe</h4>
            <form id="changePasswordForm" class="form-grid">
                <label>
                    <span>Mot de passe actuel</span>
                    <input type="password" name="current_password" required autocomplete="current-password">
                </label>
                <label>
                    <span>Nouveau mot de passe (10 caracteres min.)</span>
                    <input type="password" name="new_password" required minlength="10" autocomplete="new-password">
                </label>
                <label>
                    <span>Confirmation</span>
                    <input type="password" name="confirm_password" required minlength="10" autocomplete="new-password">
                </label>
                <p class="full muted">Tu seras deconnecte de toutes tes sessions apres le changement (y compris celle-ci) et devras te reconnecter.</p>
                <div class="full form-actions">
                    <button type="submit" class="btn btn-primary">Changer le mot de passe</button>
                </div>
            </form>
            <p id="changePasswordFeedback" class="feedback"></p>
        </section>
    `;

    const form = document.getElementById('changePasswordForm');
    const feedback = document.getElementById('changePasswordFeedback');

    form?.addEventListener('submit', async (event) => {
        event.preventDefault();
        feedback.textContent = '';
        feedback.classList.remove('is-error');

        const data = new FormData(form);
        const currentPassword = String(data.get('current_password') ?? '');
        const newPassword = String(data.get('new_password') ?? '');
        const confirmPassword = String(data.get('confirm_password') ?? '');

        if (newPassword !== confirmPassword) {
            feedback.textContent = 'Les deux mots de passe ne correspondent pas.';
            feedback.classList.add('is-error');
            return;
        }

        try {
            await apiRequest('/me/password', {
                method: 'POST',
                body: { current_password: currentPassword, new_password: newPassword },
            });
            clearAuth();
            window.location.replace(`${window.APP_CONFIG.frontendBaseUrl}/logout.php`);
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });
}

async function renderCrud(module) {
    // Ecran standard CRUD pour tous les referentiels.
    const config = crudModules[module];
    const root = document.getElementById('appContent');
    const writable = canWrite(module);

    // Le theme de couleur est un reglage comme un autre (table app_settings,
    // cle "tenant_theme"), mais il merite des vignettes cliquables plutot que
    // de demander a l'admin de saisir la cle a la main dans le tableau
    // generique juste en dessous.
    let currentThemeRow = null;
    // Meme principe pour les colonnes du tableau Produits (reglage
    // product_list_columns) : une case a cocher par colonne plutot que de
    // demander a l'admin de taper un JSON a la main.
    let currentProductColumnsRow = null;
    if (module === 'settings') {
        try {
            const themeResponse = await apiRequest('/settings?setting_key=tenant_theme');
            currentThemeRow = normalizeRows(themeResponse)[0] ?? null;
        } catch (_) {
            currentThemeRow = null;
        }
        try {
            const productColumnsResponse = await apiRequest('/settings?setting_key=product_list_columns');
            currentProductColumnsRow = normalizeRows(productColumnsResponse)[0] ?? null;
        } catch (_) {
            currentProductColumnsRow = null;
        }
    }

    const query = {
        page: state.crudPages[module] ?? 1,
        per_page: state.crudPerPage,
    };
    // Recherche globale (barre en haut) : s'applique a l'ecran affiche, pas
    // seulement a Produits (voir GLOBAL_SEARCH_MODULES / runGlobalSearch).
    if (GLOBAL_SEARCH_MODULES.includes(module) && state.globalQuery !== '') {
        query.q = state.globalQuery;
    }
    if (module === 'products' && state.tagFilter !== '') {
        query.tag_id = state.tagFilter;
    }
    if (module === 'products' && state.warehouseFilter !== '') {
        query.warehouse_id = state.warehouseFilter;
    }
    if (module === 'products' && state.categoryFilter !== '') {
        query.category_id = state.categoryFilter;
    }
    if (module === 'products' && state.supplierFilter !== '') {
        query.supplier_id = state.supplierFilter;
    }
    if (module === 'products' && state.locationFilter !== '') {
        query.location_id = state.locationFilter;
    }
    if (module === 'product-variants' && state.pendingVariantProductId) {
        query.product_id = state.pendingVariantProductId;
        state.pendingVariantProductId = null;
        query.page = 1;
        state.crudPages[module] = 1;
    }
    if (module === 'product-variants') {
        // Filtre par attribut (Taille, Couleur, Marque, Type...) - un ou
        // plusieurs menus a la fois, voir renderVariantAttributeFilters().
        await refreshVariantAttributeValues();
        Object.entries(state.variantAttributeFilters).forEach(([key, value]) => {
            if (value !== '') {
                query[key] = value;
            }
        });
    }

    let response = await apiRequest(config.endpoint + toQueryString(query));
    let meta = response?.meta ?? null;

    // Apres des suppressions, la page courante peut ne plus exister (on etait
    // page 3 et il ne reste que 2 pages) : l'API renverrait une liste vide.
    // On se replie alors sur la derniere page reellement disponible.
    if (meta && query.page > 1 && normalizeRows(response).length === 0 && meta.last_page >= 1) {
        query.page = meta.last_page;
        state.crudPages[module] = meta.last_page;
        response = await apiRequest(config.endpoint + toQueryString(query));
        meta = response?.meta ?? null;
    }

    const rows = normalizeRows(response);

    // Memorise le resultat produit courant : la recherche par douchette s'en
    // sert pour savoir si le code scanne designe un seul et unique article,
    // sans refaire un appel a l'API.
    if (module === 'products') {
        state.lastProductRows = rows;
    }

    const tagFilterOptions = module === 'products'
        ? (state.lookups?.tags ?? []).map((tag) => `<option value="${tag.id}" ${String(tag.id) === String(state.tagFilter) ? 'selected' : ''}>${sanitize(tag.name)}</option>`).join('')
        : '';

    const warehouseFilterOptions = module === 'products'
        ? (state.lookups?.warehouses ?? []).map((w) => `<option value="${w.id}" ${String(w.id) === String(state.warehouseFilter) ? 'selected' : ''}>${sanitize(w.name ?? w.code)}</option>`).join('')
        : '';

    const categoryFilterOptions = module === 'products'
        ? (state.lookups?.categories ?? []).map((c) => `<option value="${c.id}" ${String(c.id) === String(state.categoryFilter) ? 'selected' : ''}>${sanitize(c.name)}</option>`).join('')
        : '';

    const supplierFilterOptions = module === 'products'
        ? (state.lookups?.suppliers ?? []).map((s) => `<option value="${s.id}" ${String(s.id) === String(state.supplierFilter) ? 'selected' : ''}>${sanitize(s.name)}</option>`).join('')
        : '';

    // L'emplacement appartient a un seul entrepot (voir fillLocationOptions) :
    // le filtre reste desactive tant qu'un entrepot n'est pas choisi, comme
    // partout ailleurs dans l'application ou un emplacement se saisit.
    const locationFilterOptions = module === 'products' && state.warehouseFilter !== ''
        ? (state.lookups?.warehouse_locations ?? [])
            .filter((loc) => String(loc.warehouse_id) === String(state.warehouseFilter))
            .map((loc) => `<option value="${loc.id}" ${String(loc.id) === String(state.locationFilter) ? 'selected' : ''}>${sanitize(loc.description ? `${loc.code} - ${loc.description}` : loc.code)}</option>`)
            .join('')
        : '';

    // Le libelle de la colonne dit d'ou vient le chiffre : sans ca, un total
    // filtre et un total global se ressemblent trop.
    const filteredWarehouse = (state.lookups?.warehouses ?? []).find((w) => String(w.id) === String(state.warehouseFilter));
    if (module === 'products') {
        const stockColumn = config.columns.find((column) => column.key === 'stock_total');
        if (stockColumn) {
            stockColumn.label = filteredWarehouse ? `Stock (${filteredWarehouse.name ?? filteredWarehouse.code})` : 'Stock (tous entrepots)';
        }
    }

    root.innerHTML = `
        ${module === 'settings' ? `
        <section class="panel">
            <h4>Apparence</h4>
            <p class="muted">Theme de couleur de l'application (boutons, liens, barre laterale, elements actifs). S'applique a tous les utilisateurs.</p>
            ${writable ? `
            <form id="appearanceForm">
                <div class="theme-grid">
                    ${Object.entries(THEME_CATALOG).map(([themeKey, theme]) => `
                        <label class="theme-swatch">
                            <input type="radio" name="tenant_theme" value="${themeKey}" ${(currentThemeRow?.setting_value || 'emeraude') === themeKey ? 'checked' : ''}>
                            <span class="theme-preview" style="background: linear-gradient(135deg, ${theme.sidebar[0]}, ${theme.primary})"></span>
                            <span class="theme-name">${sanitize(theme.label)}</span>
                        </label>
                    `).join('')}
                </div>
                <button type="submit" class="btn btn-primary" style="margin-top: 0.8rem;">Enregistrer</button>
            </form>
            <p id="appearanceFeedback" class="feedback"></p>
            ` : '<p class="muted">Acces reserve aux administrateurs.</p>'}
        </section>
        <section class="panel">
            <h4>Colonnes du tableau Produits</h4>
            <p class="muted">Choisis les colonnes affichees dans l'ecran Produits. Laisse tout decoche pour revenir a l'affichage par defaut (colonnes essentielles / toutes les colonnes).</p>
            ${writable ? `
            <form id="productColumnsForm" class="form-grid">
                <div class="full" style="display:flex; flex-wrap:wrap; gap:0.6rem 1.4rem;">
                    ${crudModules.products.columns.filter((column) => column.key !== 'id').map((column) => `
                        <label style="display:flex; align-items:center; gap:0.4rem; font-weight:normal;">
                            <input type="checkbox" name="product_columns" value="${column.key}" ${(state.productListColumns ?? []).includes(column.key) ? 'checked' : ''}>
                            ${sanitize(column.label)}
                        </label>
                    `).join('')}
                </div>
                <div class="full form-actions">
                    <button type="submit" class="btn btn-primary">Enregistrer</button>
                    <button type="button" class="btn btn-soft" id="resetProductColumnsBtn">Revenir a l'affichage par defaut</button>
                </div>
            </form>
            <p id="productColumnsFeedback" class="feedback"></p>
            ` : '<p class="muted">Acces reserve aux administrateurs.</p>'}
        </section>
        ` : ''}
        <section class="panel">
            <div class="panel-head">
                <h4>Gestion ${config.label}</h4>
                <div class="panel-actions">
                    ${module === 'products' ? `<select id="productCategoryFilter"><option value="">Toutes les categories</option>${categoryFilterOptions}</select>` : ''}
                    ${module === 'products' ? `<select id="productSupplierFilter"><option value="">Tous les fournisseurs</option>${supplierFilterOptions}</select>` : ''}
                    ${module === 'products' ? `<select id="productWarehouseFilter"><option value="">Tous les entrepots</option>${warehouseFilterOptions}</select>` : ''}
                    ${module === 'products' ? `<select id="productLocationFilter" ${state.warehouseFilter === '' ? 'disabled' : ''}><option value="">${state.warehouseFilter === '' ? "Choisis d'abord un entrepot" : 'Tous les emplacements'}</option>${locationFilterOptions}</select>` : ''}
                    ${module === 'products' ? `<select id="productTagFilter"><option value="">Tous les tags</option>${tagFilterOptions}</select>` : ''}
                    ${module === 'products' ? '<button class="btn btn-soft" id="clearProductSearch">Effacer filtres</button>' : ''}
                    ${config.columns.some((column) => column.secondary) && !(module === 'products' && Array.isArray(state.productListColumns))
                        ? `<button class="btn btn-soft" id="toggleColumnsBtn">${state.allColumns[module] ? 'Colonnes essentielles' : 'Toutes les colonnes'}</button>`
                        : ''}
                    ${writable ? '<button class="btn btn-primary" id="createBtn">Nouveau</button>' : ''}
                </div>
            </div>

            ${module === 'product-variants' && renderVariantAttributeFilters('variantGrid', state.variantAttributeFilters) !== '' ? `
            <div class="panel-actions" style="margin-top: -0.4rem; margin-bottom: 0.8rem; flex-wrap: wrap;">
                <span class="muted" style="align-self: center;">Filtrer par attribut :</span>
                ${renderVariantAttributeFilters('variantGrid', state.variantAttributeFilters)}
                <button class="btn btn-soft" id="clearVariantAttributeFilters">Effacer filtres attribut</button>
            </div>
            ` : ''}

            <form id="crudForm" class="form-grid hidden"></form>
            <div id="crudFeedback" class="feedback"></div>

            ${renderCrudTable(config, rows, writable, module)}
            ${renderPaginationBar(meta, rows.length)}
        </section>
        ${module === 'users' ? renderRoleMatrix() : ''}
        ${module === 'products' ? '<section class="panel" id="productDetailPane"><h4>Fiche produit</h4><p class="muted">Selectionne un produit pour afficher sa fiche detaillee.</p></section>' : ''}
        ${module === 'customers' ? '<section class="panel" id="customerHistoryPane"><h4>Historique client</h4><p class="muted">Selectionne un client pour afficher ses livraisons (bons de livraison).</p></section>' : ''}
        ${module === 'product-variants' && writable ? renderVariantGenerator() : ''}
    `;

    const form = document.getElementById('crudForm');
    const feedback = document.getElementById('crudFeedback');
    let editId = null;
    let resetPasswordId = null;

    if (module === 'products') {
        document.getElementById('productTagFilter')?.addEventListener('change', async (event) => {
            state.tagFilter = event.target.value;
            state.crudPages.products = 1;
            await renderCrud('products');
        });

        document.getElementById('productWarehouseFilter')?.addEventListener('change', async (event) => {
            state.warehouseFilter = event.target.value;
            // Un emplacement appartient a un seul entrepot : en changeant
            // d'entrepot, l'emplacement precedemment choisi n'a plus de sens
            // (et pourrait meme appartenir a un autre entrepot).
            state.locationFilter = '';
            state.crudPages.products = 1;
            await renderCrud('products');
        });

        document.getElementById('productCategoryFilter')?.addEventListener('change', async (event) => {
            state.categoryFilter = event.target.value;
            state.crudPages.products = 1;
            await renderCrud('products');
        });

        document.getElementById('productSupplierFilter')?.addEventListener('change', async (event) => {
            state.supplierFilter = event.target.value;
            state.crudPages.products = 1;
            await renderCrud('products');
        });

        document.getElementById('productLocationFilter')?.addEventListener('change', async (event) => {
            state.locationFilter = event.target.value;
            state.crudPages.products = 1;
            await renderCrud('products');
        });

        document.getElementById('clearProductSearch')?.addEventListener('click', async () => {
            state.globalQuery = '';
            state.tagFilter = '';
            state.warehouseFilter = '';
            state.categoryFilter = '';
            state.supplierFilter = '';
            state.locationFilter = '';
            state.crudPages.products = 1;
            const input = document.getElementById('globalSearch');
            if (input) {
                input.value = '';
            }
            await renderCrud('products');
        });
    }

    setupPagination(module, meta);

    if (module === 'product-variants') {
        attachVariantAttributeFilterListeners('variantGrid', state.variantAttributeFilters, async () => {
            state.crudPages['product-variants'] = 1;
            await renderCrud('product-variants');
        });
        document.getElementById('clearVariantAttributeFilters')?.addEventListener('click', async () => {
            state.variantAttributeFilters = {};
            state.crudPages['product-variants'] = 1;
            await renderCrud('product-variants');
        });
    }

    if (module === 'product-variants' && writable) {
        setupVariantGenerator();
    }

    if (writable) {
        document.getElementById('toggleColumnsBtn')?.addEventListener('click', async () => {
            state.allColumns[module] = !state.allColumns[module];
            await renderCrud(module);
        });

        const createBtn = document.getElementById('createBtn');

        createBtn?.addEventListener('click', () => {
            editId = null;
            resetPasswordId = null;
            feedback.textContent = '';
            form.classList.remove('hidden');
            form.innerHTML = buildFormFields(config.fields, null, false) + formActions();
            setupCategoryDefaultTax(module, form);
            setupScannerFriendlyForm(form);
            setupColorFields(form);
            setupRoleHint(form);
            setupInitialStockLocation(module, form);
        });

        // IMPORTANT: #appContent (root) n'est jamais recree entre deux rendus du
        // module (seul son contenu innerHTML change), contrairement au formulaire
        // ou aux boutons qui sont regeneres a chaque appel. Si on se contentait
        // d'un addEventListener classique ici, chaque nouveau rendu (apres une
        // creation, une modification OU une suppression, qui rappellent
        // renderCrud) empilerait un ecouteur supplementaire sur le meme root,
        // faisant executer le clic autant de fois qu'il y a d'ecouteurs
        // accumules: plusieurs popups de confirmation, suppressions multiples,
        // application qui semble figee. On retire donc l'ecouteur precedent
        // (memorise sur l'element lui-meme) avant d'en attacher un nouveau.
        if (root._crudClickHandler) {
            root.removeEventListener('click', root._crudClickHandler);
        }

        const crudClickHandler = async (event) => {
            const editBtn = event.target.closest('[data-action="edit"]');
            const viewBtn = event.target.closest('[data-action="view"]');
            const historyBtn = event.target.closest('[data-action="history"]');
            if (viewBtn) {
                const id = Number(viewBtn.dataset.id);
                state.activeProductId = id;
                await renderProductDetail(id);
                // La fiche produit s'affiche en bas de la liste : sans ceci,
                // il fallait defiler soi-meme a chaque clic sur "Fiche" pour
                // la voir apparaitre.
                document.getElementById('productDetailPane')?.scrollIntoView?.({ behavior: 'smooth', block: 'start' });
                return;
            }

            if (historyBtn) {
                const id = Number(historyBtn.dataset.id);
                await renderCustomerHistory(id);
                // Meme logique que la fiche produit ci-dessus : l'historique
                // s'affiche en bas de la liste, on y amene la vue directement.
                document.getElementById('customerHistoryPane')?.scrollIntoView?.({ behavior: 'smooth', block: 'start' });
                return;
            }

            if (editBtn) {
                const id = Number(editBtn.dataset.id);
                const itemResponse = await apiRequest(`${config.endpoint}/${id}`);
                const item = itemResponse.data;

                editId = id;
                resetPasswordId = null;
                feedback.textContent = '';
                form.classList.remove('hidden');
                form.innerHTML = buildFormFields(config.fields, item, true) + formActions();
                setupCategoryDefaultTax(module, form);
                setupScannerFriendlyForm(form);
                setupColorFields(form);
                setupRoleHint(form);
                setupInitialStockLocation(module, form);
                return;
            }

            const resetPasswordBtn = event.target.closest('[data-action="reset-password"]');
            if (resetPasswordBtn) {
                const id = Number(resetPasswordBtn.dataset.id);

                editId = null;
                resetPasswordId = id;
                feedback.textContent = '';
                form.classList.remove('hidden');
                form.innerHTML = `
                    <label>
                        <span>Nouveau mot de passe (10 caracteres min.)</span>
                        <input type="password" name="new_password" required minlength="10" autocomplete="new-password">
                    </label>
                    <label>
                        <span>Confirmation</span>
                        <input type="password" name="confirm_password" required minlength="10" autocomplete="new-password">
                    </label>
                    <p class="full muted">L'utilisateur sera deconnecte de toutes ses sessions actives.</p>
                    ${formActions()}
                `;
                return;
            }

            const deleteBtn = event.target.closest('[data-action="delete"]');
            if (deleteBtn) {
                if (deleteBtn.disabled) {
                    return;
                }

                const id = Number(deleteBtn.dataset.id);
                if (!window.confirm('Confirmer la suppression ?')) {
                    return;
                }

                const deletedSettingKey = module === 'settings'
                    ? rows.find((r) => Number(r.id) === id)?.setting_key
                    : null;

                deleteBtn.disabled = true;
                try {
                    await apiRequest(`${config.endpoint}/${id}`, { method: 'DELETE' });
                    await refreshLookups();
                    if (VARIANT_SETTING_KEYS.includes(deletedSettingKey)) {
                        syncVariantsSettingState(deletedSettingKey, '0');
                    }
                    await renderCrud(module);
                } catch (error) {
                    feedback.textContent = error.message;
                    feedback.classList.add('is-error');
                    deleteBtn.disabled = false;
                }
            }
        };

        root._crudClickHandler = crudClickHandler;
        root.addEventListener('click', crudClickHandler);

        form.addEventListener('submit', async (event) => {
            event.preventDefault();

            if (resetPasswordId !== null) {
                const newPassword = String(form.elements.new_password?.value ?? '');
                const confirmPassword = String(form.elements.confirm_password?.value ?? '');

                if (newPassword !== confirmPassword) {
                    feedback.textContent = 'Les deux mots de passe ne correspondent pas.';
                    feedback.classList.add('is-error');
                    return;
                }

                try {
                    await apiRequest(`${config.endpoint}/${resetPasswordId}/reset-password`, {
                        method: 'POST',
                        body: { password: newPassword },
                    });
                    resetPasswordId = null;
                    await renderCrud(module);
                } catch (error) {
                    feedback.textContent = error.message;
                    feedback.classList.add('is-error');
                }
                return;
            }

            const payload = collectFormPayload(config.fields, form, editId !== null);
            if (module === 'users' && editId !== null && !payload.password) {
                delete payload.password;
            }

            // Stock initial : ces deux champs ne sont pas des colonnes de
            // `products`. On les sort du payload AVANT l'envoi, et on les
            // traite ensuite par un vrai mouvement d'entree - trace, audite,
            // et coherent avec le reste de l'application.
            //
            // Ces deux constantes doivent etre declarees ICI, avant l'appel a
            // l'API : declarees plus bas, elles etaient utilisees avant leur
            // initialisation ("Cannot access 'initialWarehouseId' before
            // initialization"). Le produit etait alors bien cree, mais le
            // mouvement d'entree n'etait jamais enregistre - produit a 0 en
            // stock, avec un message d'erreur incomprehensible.
            const initialWarehouseId = module === 'products' && editId === null
                ? Number(payload.initial_warehouse_id ?? 0) || null
                : null;
            const initialQuantity = module === 'products' && editId === null
                ? Number(payload.initial_quantity ?? 0) || 0
                : 0;
            const initialLocationId = module === 'products' && editId === null
                ? Number(payload.initial_location_id ?? 0) || null
                : null;
            delete payload.initial_warehouse_id;
            delete payload.initial_quantity;
            delete payload.initial_location_id;

            const path = editId === null ? config.endpoint : `${config.endpoint}/${editId}`;
            const method = editId === null ? 'POST' : 'PUT';

            const submitBtn = form.querySelector('button[type="submit"]');
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.textContent = 'Enregistrement...';
            }

            try {
                const saveResponse = await apiRequest(path, { method, body: payload });
                await refreshLookups();
                if (module === 'settings' && VARIANT_SETTING_KEYS.includes(payload.setting_key)) {
                    syncVariantsSettingState(payload.setting_key, payload.setting_value);
                }
                if (module === 'settings' && payload.setting_key === 'default_valuation_method') {
                    syncValuationSettingState(payload.setting_value);
                }

                // Un produit "a variantes" fraichement cree n'a encore aucune
                // variante : il est inutilisable en mouvement tant qu'on n'est
                // pas passe par le module dedie. On propose donc le raccourci
                // au lieu de laisser l'utilisateur deviner l'etape suivante.
                const newProductId = module === 'products' && editId === null
                    ? Number(saveResponse?.data?.id ?? saveResponse?.id ?? 0) || null
                    : null;

                const createdProductId = newProductId !== null && String(payload.has_variants ?? '0') === '1'
                    ? newProductId
                    : null;

                let initialStockError = null;
                if (newProductId !== null && initialWarehouseId && initialQuantity > 0) {
                    if (String(payload.has_variants ?? '0') === '1') {
                        // Un produit a variantes ne porte pas de stock en
                        // propre : la quantite appartient a chaque variante.
                        initialStockError = "Le stock initial n'a pas ete enregistre : ce produit utilise des variantes, la quantite se saisit variante par variante.";
                    } else {
                        try {
                            await apiRequest('/stock/movements', {
                                method: 'POST',
                                body: {
                                    product_id: newProductId,
                                    warehouse_id: initialWarehouseId,
                                    // Une entree range a l'emplacement de
                                    // destination (voir StockService) : le
                                    // stock initial arrive donc directement
                                    // dans l'allee choisie, ou "non range" si
                                    // aucun emplacement n'a ete precise.
                                    destination_location_id: initialLocationId,
                                    type: 'IN',
                                    quantity: initialQuantity,
                                    reason_code: 'INITIAL_STOCK',
                                    notes: 'Stock initial saisi a la creation du produit',
                                },
                            });
                        } catch (stockError) {
                            initialStockError = `Produit cree, mais le stock initial n'a pas pu etre enregistre : ${stockError.message}`;
                        }
                    }
                }

                const wasCreate = editId === null;
                if (wasCreate) {
                    // La nouvelle ligne apparait en tete de liste (tri par id
                    // decroissant) : rester sur une page interieure la rendrait
                    // invisible juste apres l'avoir creee.
                    state.crudPages[module] = 1;
                }
                await renderCrud(module);
                // renderCrud reconstruit tout le panneau (dont le formulaire),
                // on recupere donc le nouveau champ de feedback pour y
                // afficher la confirmation - l'ancien a ete remplace.
                const freshFeedback = document.getElementById('crudFeedback');
                if (freshFeedback) {
                    freshFeedback.textContent = wasCreate ? 'Cree avec succes.' : 'Modifie avec succes.';
                    freshFeedback.classList.remove('is-error');
                    freshFeedback.classList.add('is-success');

                    if (initialStockError) {
                        freshFeedback.textContent = initialStockError;
                        freshFeedback.classList.remove('is-success');
                        freshFeedback.classList.add('is-error');
                    } else if (initialWarehouseId && initialQuantity > 0) {
                        const placed = (state.lookups?.warehouse_locations ?? [])
                            .find((row) => String(row.id) === String(initialLocationId));
                        freshFeedback.textContent = placed
                            ? `Produit cree avec un stock initial de ${initialQuantity}, range en ${placed.code} (mouvement d'entree enregistre).`
                            : `Produit cree avec un stock initial de ${initialQuantity}, non range dans l'entrepot (mouvement d'entree enregistre).`;
                    }

                    if (createdProductId) {
                        freshFeedback.textContent = 'Produit cree. Il utilise des variantes : ajoute-les pour pouvoir enregistrer des mouvements de stock.';
                        const gotoBtn = document.createElement('button');
                        gotoBtn.type = 'button';
                        gotoBtn.className = 'btn btn-primary';
                        gotoBtn.style.marginLeft = '12px';
                        gotoBtn.textContent = 'Ajouter les variantes';
                        gotoBtn.addEventListener('click', async () => {
                            state.pendingVariantProductId = createdProductId;
                            setActiveNav('product-variants');
                            await renderModule('product-variants');
                        });
                        freshFeedback.appendChild(gotoBtn);
                    }
                }
            } catch (error) {
                feedback.textContent = error.message;
                feedback.classList.add('is-error');
                if (submitBtn) {
                    submitBtn.disabled = false;
                    submitBtn.textContent = 'Enregistrer';
                }
            }
        });

        form.addEventListener('click', (event) => {
            const cancelBtn = event.target.closest('[data-action="cancel"]');
            if (!cancelBtn) {
                return;
            }

            form.classList.add('hidden');
            form.innerHTML = '';
            editId = null;
            resetPasswordId = null;
        });
    }

    if (module === 'products' && state.activeProductId) {
        // La fiche ouverte doit toujours correspondre a un produit de la liste
        // affichee. Sans ce controle, un scan qui ne trouve rien laissait la
        // fiche du produit precedent a l'ecran, sous une liste vide : en
        // reception, on croit avoir scanne l'article qu'on a sous les yeux.
        const stillListed = rows.some((row) => String(row.id) === String(state.activeProductId));
        if (stillListed) {
            await renderProductDetail(state.activeProductId);
        } else {
            state.activeProductId = null;
        }
    }

    if (module === 'settings' && writable) {
        document.getElementById('appearanceForm')?.addEventListener('submit', async (event) => {
            event.preventDefault();
            const appearanceFeedback = document.getElementById('appearanceFeedback');
            const submitBtn = event.target.querySelector('button[type="submit"]');
            const theme = event.target.tenant_theme.value;
            appearanceFeedback.textContent = '';
            appearanceFeedback.classList.remove('is-error');
            submitBtn.disabled = true;
            try {
                if (currentThemeRow?.id) {
                    await apiRequest(`/settings/${currentThemeRow.id}`, {
                        method: 'PUT',
                        body: { setting_value: theme },
                    });
                } else {
                    await apiRequest('/settings', {
                        method: 'POST',
                        body: { setting_key: 'tenant_theme', setting_value: theme },
                    });
                }
                // On relit la ligne (id compris) au lieu de re-rendre tout
                // l'ecran : un re-rendu remplacerait immediatement ce message
                // de confirmation par un formulaire flambant neuf, et il ne
                // resterait jamais assez longtemps a l'ecran pour etre lu.
                // Garder l'id a jour permet aussi un 2e enregistrement dans la
                // foulee (PUT) plutot qu'un POST en doublon sur une cle unique.
                const refreshed = await apiRequest('/settings?setting_key=tenant_theme');
                currentThemeRow = normalizeRows(refreshed)[0] ?? currentThemeRow;
                appearanceFeedback.textContent = 'Theme enregistre. Recharge la page pour le voir applique partout.';
                submitBtn.disabled = false;
            } catch (error) {
                appearanceFeedback.textContent = error.message;
                appearanceFeedback.classList.add('is-error');
                submitBtn.disabled = false;
            }
        });

        const saveProductColumns = async (columnKeys) => {
            const productColumnsFeedback = document.getElementById('productColumnsFeedback');
            productColumnsFeedback.textContent = '';
            productColumnsFeedback.classList.remove('is-error');
            const value = JSON.stringify(columnKeys);
            try {
                if (currentProductColumnsRow?.id) {
                    if (columnKeys.length === 0) {
                        // Retour a l'affichage par defaut : on supprime la
                        // ligne plutot que d'y laisser un tableau vide, pour
                        // qu'aucune ambiguite ne subsiste avec "0 colonne
                        // affichee" (voir syncProductColumnsSettingState).
                        await apiRequest(`/settings/${currentProductColumnsRow.id}`, { method: 'DELETE' });
                        currentProductColumnsRow = null;
                    } else {
                        await apiRequest(`/settings/${currentProductColumnsRow.id}`, {
                            method: 'PUT',
                            body: { setting_value: value },
                        });
                    }
                } else if (columnKeys.length > 0) {
                    await apiRequest('/settings', {
                        method: 'POST',
                        body: { setting_key: 'product_list_columns', setting_value: value },
                    });
                }

                const refreshed = await apiRequest('/settings?setting_key=product_list_columns');
                currentProductColumnsRow = normalizeRows(refreshed)[0] ?? null;
                syncProductColumnsSettingState(currentProductColumnsRow?.setting_value);
                productColumnsFeedback.textContent = columnKeys.length > 0
                    ? 'Colonnes enregistrees.'
                    : 'Affichage par defaut restaure.';
            } catch (error) {
                productColumnsFeedback.textContent = error.message;
                productColumnsFeedback.classList.add('is-error');
            }
        };

        document.getElementById('productColumnsForm')?.addEventListener('submit', async (event) => {
            event.preventDefault();
            const checked = Array.from(event.target.querySelectorAll('input[name="product_columns"]:checked')).map((el) => el.value);
            await saveProductColumns(checked);
        });

        document.getElementById('resetProductColumnsBtn')?.addEventListener('click', async () => {
            await saveProductColumns([]);
            document.querySelectorAll('#productColumnsForm input[name="product_columns"]').forEach((el) => {
                el.checked = false;
            });
        });
    }
}

async function renderMovements() {
    // Journal des mouvements + creation rapide.
    const root = document.getElementById('appContent');

    // Filtre par attribut de variante (Marque, Type, Puissance...) applique a
    // l'historique - un ou plusieurs menus a la fois, prefixe "variant_" cote
    // API (voir StockController::movements / StockMovementRepository).
    const movementFilterQuery = {};
    Object.entries(state.movementVariantAttributeFilters).forEach(([key, value]) => {
        if (value !== '') {
            movementFilterQuery['variant_' + key] = value;
        }
    });

    const [listResponse] = await Promise.all([
        apiRequest('/stock/movements' + toQueryString(movementFilterQuery)),
        refreshLookups(),
        refreshVariantAttributeValues(),
    ]);

    const rows = normalizeRows(listResponse);
    const writable = canWrite('movements');

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head">
                <h4>Nouveau mouvement de stock</h4>
            </div>
            ${writable ? `
            <form id="movementForm" class="form-grid">
                ${selectField('product_id', 'Produit', state.lookups.products, 'id', 'name', true)}
                <div class="full hidden" id="movementVariantWrap">
                    <div class="panel-actions hidden" id="movementVariantFilterWrap" style="justify-content:flex-start; margin-bottom:0.5rem;"></div>
                    <label><span>Variante</span><select name="variant_id" id="movementVariantSelect"></select></label>
                    <small class="field-hint">Ce produit utilise des variantes : choisis celle concernee par ce mouvement. Beaucoup de variantes ? Filtre par attribut ci-dessus pour retrouver plus vite le bon article.</small>
                    <div class="hidden" id="movementMultiToggleWrap" style="margin-top: 0.6rem;">
                        <button type="button" class="btn btn-soft" id="movementMultiToggle">Deplacer plusieurs variantes a la fois &rarr;</button>
                    </div>
                </div>
                <div class="full hidden" id="movementVariantMultiWrap">
                    <span>Variantes a deplacer (toutes cochees par defaut)</span>
                    <div id="movementVariantMultiList" class="serial-checklist"></div>
                    <small class="field-hint">Decoche celles a ne pas deplacer. Pour chaque variante cochee, la quantite disponible a l'emplacement source choisi (ou dans tout l'entrepot si aucun emplacement precis) est deplacee automatiquement.</small>
                    <button type="button" class="btn btn-soft" id="movementMultiBackBtn">&larr; Revenir a une seule variante</button>
                </div>
                ${selectField('warehouse_id', 'Entrepot source', state.lookups.warehouses, 'id', 'name', true)}
                <label><span>Emplacement source (optionnel)</span>
                    <select name="source_location_id" id="movementSourceLocation" disabled>
                        <option value="">Choisis d'abord un entrepot</option>
                    </select></label>
                ${selectField('destination_warehouse_id', 'Entrepot destination (vide = transfert dans le meme entrepot)', state.lookups.warehouses, 'id', 'name', false)}
                <label><span>Emplacement destination (optionnel)</span>
                    <select name="destination_location_id" id="movementDestinationLocation" disabled>
                        <option value="">Choisis d'abord un entrepot</option>
                    </select></label>
                <label><span>Type</span><select name="type" required>
                    <option value="IN">Entree</option>
                    <option value="OUT">Sortie</option>
                    <option value="ADJUSTMENT">Ajustement</option>
                    <option value="TRANSFER">Transfert</option>
                </select></label>
                <div id="movementQuantityWrap">
                    <label><span>Quantite</span><input type="number" name="quantity" id="movementQuantityInput" min="1" required></label>
                </div>
                <div class="full hidden" id="movementUnitCostWrap">
                    <label><span>Cout unitaire (optionnel)</span><input type="number" name="unit_cost" min="0" step="0.01" placeholder="Laisser vide = cout actuel du produit"></label>
                    <small class="field-hint">Sert a la valorisation du stock (CUMP/FIFO - voir la fiche produit). Laisse vide, le cout actuel du produit est repris tel quel.</small>
                </div>
                ${selectField('customer_id', 'Client (sortie)', state.lookups.customers, 'id', 'name', false)}
                <div class="full" id="movementSerialsInWrap">
                    <label>
                        <span>Numeros de serie (optionnel, un par ligne)</span>
                        <textarea name="serial_numbers" rows="3" placeholder="SN-00012345&#10;SN-00012346"></textarea>
                    </label>
                    <small class="field-hint">Uniquement pour une entree (IN). Si renseigne, le nombre de lignes doit correspondre a la quantite.</small>
                </div>
                <div class="full hidden" id="movementSerialsOutWrap">
                    <span>Numeros de serie a sortir (optionnel)</span>
                    <div id="movementSerialOutList" class="serial-checklist"></div>
                    <small class="field-hint">Coche les exemplaires precis qui sortent. Choisis d'abord produit + entrepot source. Si des cases sont cochees, leur nombre doit correspondre a la quantite. Ils seront marques "sorti" automatiquement.</small>
                </div>
                <label><span>Code motif (optionnel)</span><input type="text" name="reason_code" list="reasonCodeSuggestions" placeholder="Ex: Casse, Perte, Correction"></label>
                <datalist id="reasonCodeSuggestions">
                    <option value="Casse">
                    <option value="Perte">
                    <option value="Vol">
                    <option value="Correction inventaire">
                    <option value="Retour client">
                    <option value="Echantillon">
                    <option value="Demonstration">
                </datalist>
                <label class="full"><span>Note</span><textarea name="notes"></textarea></label>
                <button type="submit" class="btn btn-primary">Enregistrer mouvement</button>
                <p id="movementFeedback" class="feedback"></p>
            </form>
            ` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>

        <section class="panel">
            <div class="panel-head">
                <h4>Historique mouvements</h4>
            </div>
            ${renderVariantAttributeFilters('movementHist', state.movementVariantAttributeFilters) !== '' ? `
            <div class="panel-actions" style="margin-top: -0.4rem; margin-bottom: 0.8rem; flex-wrap: wrap;">
                <span class="muted" style="align-self: center;">Filtrer par attribut de variante :</span>
                ${renderVariantAttributeFilters('movementHist', state.movementVariantAttributeFilters)}
                <button class="btn btn-soft" id="clearMovementAttributeFilters">Effacer filtres attribut</button>
            </div>
            ` : ''}
            ${renderSimpleTable(rows, [
                ['created_at', 'Date'],
                // Un transfert entre deux entrepots ecrit DEUX lignes : la
                // sortie de l'entrepot source et l'entree dans l'entrepot
                // d'arrivee - chacun doit voir le mouvement dans son propre
                // historique. Sans mention, la seconde ligne se lit comme une
                // entree independante et on croit avoir recu deux fois la
                // quantite. Le transfert interne (changement d'emplacement),
                // lui, n'ecrit qu'une seule ligne.
                ['type', 'Type', (value, row) => (
                    String(value) === 'IN' && String(row.reference_type ?? '') === 'TRANSFER'
                        ? 'Entree (arrivee d\'un transfert)'
                        : sanitize(localizeValue(value, 'type'))
                )],
                ['product_name', 'Produit'],
                ['variant_sku', 'Variante', (v, row) => (row.variant_id ? sanitize(variantDescriptor(row)) : '-')],
                ['quantity', 'Quantite'],
                ['unit_cost', 'Cout unitaire', (value) => (value === null || value === undefined ? '-' : formatMoney(value))],
                ['balance_after', 'Stock apres'],
                ['warehouse_name', 'Source'],
                ['source_location_code', 'Empl. source'],
                ['destination_warehouse_name', 'Destination'],
                ['destination_location_code', 'Empl. dest.'],
                ['customer_name', 'Client'],
                ['reason_code', 'Motif'],
                ['moved_by_name', 'Operateur'],
            ])}
        </section>
    `;

    const form = document.getElementById('movementForm');
    const feedback = document.getElementById('movementFeedback');
    const typeSelect = form?.elements.namedItem('type');
    const productSelect = form?.elements.namedItem('product_id');
    const warehouseSelect = form?.elements.namedItem('warehouse_id');
    const serialsInWrap = document.getElementById('movementSerialsInWrap');
    const serialsOutWrap = document.getElementById('movementSerialsOutWrap');
    const serialOutList = document.getElementById('movementSerialOutList');
    const variantWrap = document.getElementById('movementVariantWrap');
    const variantSelect = document.getElementById('movementVariantSelect');
    const multiToggleWrap = document.getElementById('movementMultiToggleWrap');
    const multiToggle = document.getElementById('movementMultiToggle');
    const variantMultiWrap = document.getElementById('movementVariantMultiWrap');
    const variantMultiList = document.getElementById('movementVariantMultiList');
    const multiBackBtn = document.getElementById('movementMultiBackBtn');
    const quantityWrap = document.getElementById('movementQuantityWrap');
    const quantityInput = document.getElementById('movementQuantityInput');
    const variantFilterWrap = document.getElementById('movementVariantFilterWrap');
    let availableOutSerialCount = 0;
    let multiMode = false;
    let lastLoadedVariants = [];
    // Filtre rapide (client, sans appel API) par attribut de variante -
    // reduit lastLoadedVariants avant de construire le select / la checklist.
    // Remis a zero a chaque changement de produit (voir loadVariantOptions).
    let variantFilterValues = {};

    // "Deplacer plusieurs variantes a la fois" : uniquement pertinent sur une
    // sortie ou un transfert (il faut du stock existant a deplacer - une
    // entree ou un ajustement n'ont pas de "stock disponible" a reprendre
    // automatiquement).
    const isMultiCapableType = () => ['OUT', 'TRANSFER'].includes(String(typeSelect?.value ?? ''));

    const loadMultiVariantChecklist = async () => {
        if (!variantMultiList) {
            return;
        }
        const productId = productSelect?.value;
        if (!productId) {
            variantMultiList.innerHTML = '<p class="muted">Choisis d\'abord un produit.</p>';
            return;
        }
        variantMultiList.innerHTML = '<p class="muted">Chargement...</p>';
        const detail = await apiRequest(`/products/${productId}`);
        const stockByWarehouse = Array.isArray(detail?.data?.stock_by_warehouse) ? detail.data.stock_by_warehouse : [];
        const availability = computeVariantAvailability(
            stockByWarehouse,
            warehouseSelect?.value ?? '',
            document.getElementById('movementSourceLocation')?.value ?? ''
        );
        const filteredVariants = filterVariantsByAttributes(lastLoadedVariants, variantFilterValues);
        variantMultiList.innerHTML = filteredVariants.length === 0
            ? `<p class="muted">${lastLoadedVariants.length === 0 ? 'Aucune variante active pour ce produit' : 'Aucune variante ne correspond au filtre choisi'}</p>`
            : filteredVariants.map((v) => {
                const available = availability.get(String(v.id)) ?? 0;
                // Toutes cochees par defaut : le but du mode multi-variantes
                // est de tout deplacer en un clic, l'utilisateur decoche
                // seulement les exceptions (voir la demande d'origine).
                return `
                    <label class="checklist-item">
                        <input type="checkbox" class="movement-variant-multi-checkbox" value="${v.id}" data-available="${available}" ${available <= 0 ? 'disabled' : 'checked'}>
                        ${sanitize(variantDescriptor(v))} (disponible ici : ${available})
                    </label>
                `;
            }).join('');
    };

    const applyVariantMode = () => {
        const productId = productSelect?.value;
        const product = state.lookups.products.find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;
        const multiCapable = hasVariants && isMultiCapableType() && !!productId;

        multiToggleWrap?.classList.toggle('hidden', !multiCapable);
        if (!multiCapable && multiMode) {
            multiMode = false;
        }

        variantWrap.classList.toggle('hidden', !hasVariants || multiMode);
        variantSelect.required = hasVariants && !multiMode;
        variantMultiWrap?.classList.toggle('hidden', !multiMode);
        quantityWrap?.classList.toggle('hidden', multiMode);
        if (quantityInput) {
            quantityInput.required = !multiMode;
        }

        if (multiMode) {
            loadMultiVariantChecklist();
        }
    };

    multiToggle?.addEventListener('click', () => {
        multiMode = true;
        applyVariantMode();
    });
    multiBackBtn?.addEventListener('click', () => {
        multiMode = false;
        applyVariantMode();
    });

    // Reconstruit uniquement le <select> Variante a partir de
    // lastLoadedVariants + variantFilterValues - appele au chargement et a
    // chaque changement d'un menu de filtre rapide (pas de nouvel appel API,
    // la liste complete est deja en memoire).
    const renderFilteredVariantSelect = () => {
        if (!variantSelect) {
            return;
        }
        const previousValue = variantSelect.value;
        const filteredVariants = filterVariantsByAttributes(lastLoadedVariants, variantFilterValues);
        if (lastLoadedVariants.length === 0) {
            variantSelect.innerHTML = '<option value="">Aucune variante active pour ce produit</option>';
        } else if (filteredVariants.length === 0) {
            variantSelect.innerHTML = '<option value="">Aucune variante ne correspond au filtre choisi</option>';
        } else {
            variantSelect.innerHTML = filteredVariants.map((v) => {
                const descriptors = variantDescriptor(v);
                return `<option value="${v.id}">${sanitize(descriptors)} (stock: ${v.stock_total ?? 0})</option>`;
            }).join('');
            // Garde la selection en cours si elle correspond toujours au
            // filtre (evite de perdre le choix quand on affine juste un
            // deuxieme attribut) ; sinon, laisse le tout premier resultat.
            if (filteredVariants.some((v) => String(v.id) === String(previousValue))) {
                variantSelect.value = previousValue;
            }
        }
    };

    const loadVariantOptions = async () => {
        if (!variantWrap || !variantSelect) {
            return;
        }
        const productId = productSelect?.value;
        const product = state.lookups.products.find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;

        if (!hasVariants || !productId) {
            variantSelect.innerHTML = '';
            lastLoadedVariants = [];
            variantFilterValues = {};
            if (variantFilterWrap) {
                variantFilterWrap.innerHTML = '';
                variantFilterWrap.classList.add('hidden');
            }
            applyVariantMode();
            return;
        }

        variantSelect.innerHTML = '<option value="">Chargement...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=5000`);
        const variants = normalizeRows(response);
        lastLoadedVariants = variants;
        // Nouveau produit choisi : les filtres precedents (ex: Marque=Bosch
        // sur un autre produit) n'ont plus de sens, on repart de zero.
        variantFilterValues = {};
        renderQuickVariantAttributeFilters(variantFilterWrap, variants, variantFilterValues, () => {
            renderFilteredVariantSelect();
            if (multiMode) {
                loadMultiVariantChecklist();
            }
        });
        renderFilteredVariantSelect();
        applyVariantMode();
    };

    const loadOutSerialOptions = async () => {
        if (!serialOutList || typeSelect?.value !== 'OUT') {
            return;
        }
        const productId = productSelect?.value;
        const warehouseId = warehouseSelect?.value;
        availableOutSerialCount = 0;
        if (!productId) {
            serialOutList.innerHTML = '<p class="muted">Choisis d\'abord un produit.</p>';
            return;
        }

        serialOutList.innerHTML = '<p class="muted">Chargement...</p>';
        const query = `product_id=${productId}&status=IN_STOCK&per_page=5000${warehouseId ? `&warehouse_id=${warehouseId}` : ''}`;
        const response = await apiRequest(`/product-serials?${query}`);
        const available = normalizeRows(response);
        availableOutSerialCount = available.length;

        serialOutList.innerHTML = available.length === 0
            ? '<p class="muted">Aucun numero de serie en stock pour ce produit/entrepot.</p>'
            : available.map((serial) => `
                <label class="checklist-item">
                    <input type="checkbox" class="movement-serial-out-checkbox" value="${serial.id}">
                    ${sanitize(serial.serial_number)}
                </label>
            `).join('');
    };

    const unitCostWrap = document.getElementById('movementUnitCostWrap');

    const toggleSerialsWrap = () => {
        const isIn = typeSelect?.value === 'IN';
        // En mode multi-variantes, les numeros de serie a sortir ne sont pas
        // proposes : on ne sait pas a quelle variante (donc a quel exemplaire)
        // rattacher chaque case cochee. Pour du materiel serialise, on garde
        // le mode variante unique.
        const isOut = typeSelect?.value === 'OUT' && !multiMode;
        serialsInWrap?.classList.toggle('hidden', !isIn);
        serialsOutWrap?.classList.toggle('hidden', !isOut);
        unitCostWrap?.classList.toggle('hidden', !isIn);
        if (isOut) {
            loadOutSerialOptions();
        }
    };
    toggleSerialsWrap();
    typeSelect?.addEventListener('change', toggleSerialsWrap);
    typeSelect?.addEventListener('change', applyVariantMode);
    productSelect?.addEventListener('change', loadOutSerialOptions);
    warehouseSelect?.addEventListener('change', loadOutSerialOptions);
    productSelect?.addEventListener('change', loadVariantOptions);
    loadVariantOptions();

    // Emplacements : ils dependent de l'entrepot choisi. Pour un transfert,
    // l'emplacement de destination appartient a l'entrepot de destination ;
    // pour tout autre mouvement, il n'y a qu'un entrepot, donc les deux listes
    // pointent le meme.
    const sourceLocationSelect = document.getElementById('movementSourceLocation');
    const destinationLocationSelect = document.getElementById('movementDestinationLocation');
    const destinationWarehouseSelect = form?.elements.namedItem('destination_warehouse_id');

    const refreshLocations = () => {
        fillLocationOptions(sourceLocationSelect, warehouseSelect?.value ?? '');
        // Transfert SANS entrepot de destination = transfert interne : les
        // emplacements proposes sont ceux de l'entrepot source. Auparavant la
        // liste restait vide tant qu'un second entrepot n'etait pas choisi,
        // donc on ne pouvait pas simplement deplacer un article d'une allee a
        // une autre.
        const isTransfer = String(typeSelect?.value ?? '') === 'TRANSFER';
        const destinationWarehouse = isTransfer && String(destinationWarehouseSelect?.value ?? '') !== ''
            ? destinationWarehouseSelect.value
            : (warehouseSelect?.value ?? '');
        fillLocationOptions(destinationLocationSelect, destinationWarehouse);
        if (multiMode) {
            loadMultiVariantChecklist();
        }
    };

    warehouseSelect?.addEventListener('change', refreshLocations);
    destinationWarehouseSelect?.addEventListener('change', refreshLocations);
    typeSelect?.addEventListener('change', refreshLocations);
    // Le choix de l'emplacement source ne recharge pas la liste (fillLocationOptions
    // ne l'ecoute pas), mais change la disponibilite affichee en mode multi-variantes.
    sourceLocationSelect?.addEventListener('change', () => {
        if (multiMode) {
            loadMultiVariantChecklist();
        }
    });
    refreshLocations();

    form?.addEventListener('submit', async (event) => {
        event.preventDefault();
        feedback.textContent = '';
        feedback.classList.remove('is-error');

        const data = new FormData(form);

        if (multiMode) {
            const customerId = data.get('customer_id') ? Number(data.get('customer_id')) : null;
            const type = String(data.get('type'));
            const productId = Number(data.get('product_id'));
            const warehouseId = Number(data.get('warehouse_id'));
            const checked = Array.from(document.querySelectorAll('.movement-variant-multi-checkbox:checked'));

            if (checked.length === 0) {
                feedback.textContent = 'Coche au moins une variante a deplacer.';
                feedback.classList.add('is-error');
                return;
            }

            const basePayload = {
                product_id: productId,
                warehouse_id: warehouseId,
                destination_warehouse_id: data.get('destination_warehouse_id') ? Number(data.get('destination_warehouse_id')) : null,
                source_location_id: data.get('source_location_id') ? Number(data.get('source_location_id')) : null,
                destination_location_id: data.get('destination_location_id') ? Number(data.get('destination_location_id')) : null,
                type,
                reason_code: String(data.get('reason_code') ?? ''),
                notes: String(data.get('notes') ?? ''),
                reference_type: customerId ? 'CUSTOMER' : null,
                reference_id: customerId,
            };

            let successCount = 0;
            const failures = [];
            for (const checkbox of checked) {
                const available = Number(checkbox.dataset.available ?? 0);
                if (available <= 0) {
                    continue;
                }
                try {
                    await apiRequest('/stock/movements', {
                        method: 'POST',
                        body: { ...basePayload, variant_id: Number(checkbox.value), quantity: available },
                    });
                    successCount += 1;
                } catch (error) {
                    failures.push(`${checkbox.parentElement?.textContent?.trim() ?? checkbox.value} : ${error.message}`);
                }
            }

            await renderMovements();
            const freshFeedback = document.getElementById('movementFeedback');
            if (freshFeedback) {
                freshFeedback.textContent = failures.length > 0
                    ? `${successCount} mouvement(s) enregistre(s). Echecs :\n${failures.join('\n')}`
                    : `${successCount} mouvement(s) enregistre(s) (une ligne par variante deplacee).`;
                freshFeedback.classList.toggle('is-error', failures.length > 0);
                freshFeedback.classList.toggle('is-success', failures.length === 0);
            }
            return;
        }

        const customerId = data.get('customer_id') ? Number(data.get('customer_id')) : null;
        const type = String(data.get('type'));
        const productId = Number(data.get('product_id'));
        const warehouseId = Number(data.get('warehouse_id'));
        const quantity = Number(data.get('quantity'));
        const serialNumbers = String(data.get('serial_numbers') ?? '')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        const serialIdsOut = Array.from(document.querySelectorAll('.movement-serial-out-checkbox:checked'))
            .map((el) => el.value)
            .filter(Boolean);

        if (serialNumbers.length > 0) {
            if (type !== 'IN') {
                feedback.textContent = 'Les numeros de serie ne se saisissent que sur une entree (IN).';
                feedback.classList.add('is-error');
                return;
            }
            if (serialNumbers.length !== quantity) {
                feedback.textContent = `Tu as saisi ${serialNumbers.length} numero(s) de serie pour une quantite de ${quantity}. Les deux doivent correspondre.`;
                feedback.classList.add('is-error');
                return;
            }
        }

        if (serialIdsOut.length > 0 && serialIdsOut.length !== quantity) {
            feedback.textContent = `Tu as coche ${serialIdsOut.length} numero(s) de serie pour une quantite de ${quantity}. Les deux doivent correspondre.`;
            feedback.classList.add('is-error');
            return;
        }

        if (type === 'OUT' && serialIdsOut.length === 0 && availableOutSerialCount > 0) {
            const proceed = window.confirm(
                `Ce produit a des numeros de serie en stock mais tu n'en as coche aucun: aucun ne sera marque "sorti". Continuer quand meme ?`
            );
            if (!proceed) {
                return;
            }
        }

        const variantId = variantSelect && !variantWrap?.classList.contains('hidden') && variantSelect.value
            ? Number(variantSelect.value)
            : null;
        if (variantSelect && !variantWrap?.classList.contains('hidden') && !variantSelect.value) {
            feedback.textContent = 'Ce produit utilise des variantes : choisis-en une.';
            feedback.classList.add('is-error');
            return;
        }

        const payload = {
            product_id: productId,
            variant_id: variantId,
            warehouse_id: warehouseId,
            destination_warehouse_id: data.get('destination_warehouse_id') ? Number(data.get('destination_warehouse_id')) : null,
            source_location_id: data.get('source_location_id') ? Number(data.get('source_location_id')) : null,
            destination_location_id: data.get('destination_location_id') ? Number(data.get('destination_location_id')) : null,
            type,
            quantity,
            unit_cost: data.get('unit_cost') ? Number(data.get('unit_cost')) : null,
            reason_code: String(data.get('reason_code') ?? ''),
            notes: String(data.get('notes') ?? ''),
            reference_type: customerId ? 'CUSTOMER' : null,
            reference_id: customerId,
        };

        try {
            await apiRequest('/stock/movements', { method: 'POST', body: payload });

            if (serialNumbers.length > 0) {
                try {
                    await apiRequest('/product-serials', {
                        method: 'POST',
                        body: {
                            product_id: productId,
                            variant_id: variantId,
                            warehouse_id: warehouseId,
                            serial_numbers: serialNumbers,
                            // Le mouvement d'entree vient d'etre enregistre par
                            // l'appel precedent : sans ce drapeau, la quantite
                            // serait comptee deux fois.
                            creates_stock_entry: false,
                        },
                    });
                } catch (serialError) {
                    await renderMovements();
                    window.alert(`Mouvement enregistre, mais erreur sur les numeros de serie: ${serialError.message}`);
                    return;
                }
            }

            if (serialIdsOut.length > 0) {
                const failures = [];
                for (const serialId of serialIdsOut) {
                    try {
                        // Le mouvement de sortie ci-dessus a deja retire la
                        // quantite totale du stock : sans ce drapeau, chaque
                        // mark-out la retirait une seconde fois (1 coche +
                        // quantite 1 = 2 articles retires au lieu d'1).
                        await apiRequest(`/product-serials/${serialId}/mark-out`, { method: 'POST', body: { skip_stock_move: true } });
                    } catch (serialError) {
                        failures.push(`#${serialId}: ${serialError.message}`);
                    }
                }
                await renderMovements();
                const freshFeedback = document.getElementById('movementFeedback');
                if (failures.length > 0) {
                    window.alert(`Mouvement enregistre, mais erreur sur certains numeros de serie:\n${failures.join('\n')}`);
                } else if (freshFeedback) {
                    freshFeedback.textContent = `Mouvement enregistre (${VALUE_LABELS[type] ?? type}, quantite ${quantity}).`;
                    freshFeedback.classList.remove('is-error');
                    freshFeedback.classList.add('is-success');
                }
                return;
            }

            await renderMovements();
            const freshFeedback = document.getElementById('movementFeedback');
            if (freshFeedback) {
                freshFeedback.textContent = `Mouvement enregistre (${VALUE_LABELS[type] ?? type}, quantite ${quantity}).`;
                freshFeedback.classList.remove('is-error');
                freshFeedback.classList.add('is-success');
            }
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    attachVariantAttributeFilterListeners('movementHist', state.movementVariantAttributeFilters, async () => {
        await renderMovements();
    });
    document.getElementById('clearMovementAttributeFilters')?.addEventListener('click', async () => {
        state.movementVariantAttributeFilters = {};
        await renderMovements();
    });
}

async function renderProductSerials() {
    // Numeros de serie: un SN par exemplaire physique (ex: materiel informatique).
    // Champ optionnel au global (une sortie de stock classique n'en a pas besoin),
    // mais permet de retrouver precisement un exemplaire donne.
    const root = document.getElementById('appContent');

    // Raccourci depuis la fiche produit (bouton "Numeros de serie de ce produit"):
    // on consomme la valeur une seule fois pour pre-filtrer la liste et
    // pre-selectionner le produit dans le formulaire de creation.
    const presetProductId = state.pendingSerialProductId ?? null;
    state.pendingSerialProductId = null;

    const [listResponse] = await Promise.all([
        apiRequest(presetProductId ? `/product-serials?product_id=${presetProductId}` : '/product-serials'),
        refreshLookups(),
    ]);

    const rows = normalizeRows(listResponse);
    const writable = canWrite('product-serials');
    const presetProductName = presetProductId
        ? (state.lookups.products ?? []).find((p) => String(p.id) === String(presetProductId))?.name
        : null;

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head"><h4>Rechercher un article par numero de serie</h4></div>
            <form id="serialSearchForm" class="form-grid">
                <label><span>Numero de serie</span><input type="text" name="serial_number" placeholder="Ex: SN-00012345" required></label>
                <button type="submit" class="btn btn-primary">Rechercher</button>
            </form>
            <div id="serialSearchResult"></div>
        </section>

        <section class="panel">
            <div class="panel-head"><h4>Enregistrer des numeros de serie</h4></div>
            ${writable ? `
            <form id="serialCreateForm" class="form-grid">
                ${selectField('product_id', 'Produit', state.lookups.products, 'id', 'name', true, presetProductId ?? '')}
                <div class="full hidden" id="serialCreateVariantWrap">
                    <label><span>Variante</span><select name="variant_id" id="serialCreateVariantSelect"></select></label>
                </div>
                ${selectField('warehouse_id', 'Entrepot de stockage', state.lookups.warehouses, 'id', 'name', true)}
                <label><span>Emplacement (optionnel)</span>
                    <select name="location_id" id="serialCreateLocation" disabled>
                        <option value="">Choisis d'abord un entrepot</option>
                    </select></label>
                <small class="full field-hint">
                    Un numero de serie designe un objet physique unique : il ne
                    pourra etre livre que depuis cet entrepot, et l'emplacement
                    indique dans quelle allee aller le chercher. Verifie-les
                    avant d'enregistrer un lot.
                </small>
                <label class="full">
                    <span>Numero(s) de serie (un par ligne, pour enregistrer plusieurs exemplaires recus en une fois)</span>
                    <textarea name="serial_numbers" rows="4" placeholder="SN-00012345&#10;SN-00012346" required></textarea>
                </label>
                <label class="full">
                    <span>Que represente cet enregistrement ?</span>
                    <select name="creates_stock_entry">
                        <option value="1">Ces articles arrivent : ajouter la quantite au stock</option>
                        <option value="0">Ces articles sont deja comptes dans le stock (regularisation)</option>
                    </select>
                </label>
                <small class="full field-hint">
                    Un numero de serie represente un article physique. Choisis la
                    premiere option a la reception d'une commande, la seconde si tu
                    ne fais que noter apres coup les numeros d'un stock deja saisi -
                    sinon la quantite serait comptee deux fois.
                </small>
                <button type="submit" class="btn btn-primary">Enregistrer</button>
                <p id="serialCreateFeedback" class="feedback"></p>
            </form>
            ` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>

        <section class="panel">
            <div class="panel-head">
                <h4>Numeros de serie enregistres ${presetProductName ? `- ${sanitize(presetProductName)}` : ''}</h4>
                ${presetProductId ? '<button type="button" class="btn btn-soft" id="clearSerialProductFilter">Voir tous les produits</button>' : ''}
            </div>
            ${renderSimpleTable(rows, [
                ['serial_number', 'Numero de serie'],
                ['product_name', 'Produit'],
                ['variant_sku', 'Variante', (v, row) => (row.variant_id ? sanitize(variantDescriptor(row)) : '-')],
                ['warehouse_name', 'Entrepot'],
                ['location_code', 'Emplacement', (value) => sanitize(value || '-')],
                ['status', 'Statut'],
                ['created_at', 'Entree le'],
                // Utile pour la garantie : quand un exemplaire est sorti (vendu ou
                // retire), on veut savoir quand sans avoir a rouvrir la recherche
                // par SN. `updated_at` reflete la derniere fois que le statut a
                // change (mark-out ou livraison) - fiable tant que le statut
                // actuel est bien "sorti".
                ['updated_at', 'Sorti le', (value, row) => (row.status === 'OUT' ? sanitize(value) : '-')],
                ...(writable ? [['id', 'Actions', (value, row) => `
                    ${row.status === 'IN_STOCK'
                        ? `<button class="btn btn-soft" data-mark-out="${value}">Marquer sorti</button>`
                        : `<button class="btn btn-soft" data-mark-in="${value}">Remettre en stock</button>`}
                    <button class="btn btn-soft" data-delete-serial="${value}" data-serial-status="${sanitize(row.status)}" data-serial-number="${sanitize(row.serial_number)}">Supprimer</button>
                `]] : []),
            ])}
        </section>
    `;

    document.getElementById('clearSerialProductFilter')?.addEventListener('click', async () => {
        state.pendingSerialProductId = null;
        await renderProductSerials();
    });

    const searchForm = document.getElementById('serialSearchForm');
    const searchResult = document.getElementById('serialSearchResult');
    searchForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const data = new FormData(searchForm);
        const serialNumber = String(data.get('serial_number') ?? '').trim();

        try {
            const response = await apiRequest(`/product-serials/search?serial_number=${encodeURIComponent(serialNumber)}`);
            const found = response.data;
            const history = found.delivery_history ?? [];
            // Le client/BL "actuel" pour un exemplaire sorti : la livraison la
            // plus recente qui n'a pas ete annulee (une livraison annulee
            // remet l'exemplaire en stock - s'il est toujours "sorti", ce
            // n'est donc pas elle qui l'explique). L'historique complet reste
            // affiche plus bas pour un exemplaire revendu plusieurs fois.
            const currentDelivery = found.status === 'OUT'
                ? history.find((entry) => entry.delivery_status !== 'CANCELLED') ?? null
                : null;
            const historyRows = history.map((entry) => `
                <tr>
                    <td>${sanitize(entry.delivered_at)}</td>
                    <td>${sanitize(entry.customer_name)}</td>
                    <td>${sanitize(entry.delivery_number)}</td>
                    <td>${sanitize(entry.delivery_status)}</td>
                </tr>
            `).join('');

            searchResult.innerHTML = `
                <div class="panel-soft">
                    <p><strong>${sanitize(found.product_name)}</strong> (${sanitize(found.sku)})${found.variant_id ? ` - variante : ${sanitize(variantDescriptor(found))}` : ''}</p>
                    <p>Numero de serie: ${sanitize(found.serial_number)}</p>
                    <p>Statut: ${sanitize(localizeValue(found.status, 'status'))}</p>
                    <p>Entrepot: ${sanitize(found.warehouse_name ?? '-')}</p>
                    <p>Emplacement: ${sanitize(found.location_code ?? 'Non precise')}${found.location_description ? ` (${sanitize(found.location_description)})` : ''}</p>
                    <p>Entree le: ${sanitize(found.created_at)}</p>
                    ${found.status === 'OUT' ? `<p>Sorti le: ${sanitize(found.updated_at)}</p>` : ''}
                    ${found.status === 'OUT' ? (currentDelivery
                        ? `<p>Vendu a : <strong>${sanitize(currentDelivery.customer_name)}</strong> (BL ${sanitize(currentDelivery.delivery_number)} du ${sanitize(currentDelivery.delivered_at)})</p>`
                        : `<p>Sorti sans livraison associee (sortie manuelle ou regularisation).</p>`
                    ) : ''}
                </div>
                <div class="table-wrap" style="margin-top:12px">
                    <h5>Historique des ventes</h5>
                    ${history.length > 0 ? `
                        <table class="data-table">
                            <thead><tr><th>Date</th><th>Client</th><th>N° BL</th><th>Statut BL</th></tr></thead>
                            <tbody>${historyRows}</tbody>
                        </table>
                    ` : '<p class="muted">Cet exemplaire n\'a jamais ete livre a un client.</p>'}
                </div>
            `;
        } catch (error) {
            searchResult.innerHTML = `<p class="feedback is-error">${sanitize(error.message)}</p>`;
        }
    });

    const createForm = document.getElementById('serialCreateForm');

    // Les emplacements proposes sont ceux de l'entrepot choisi.
    const serialWarehouseSelect = createForm?.elements.namedItem('warehouse_id');
    const serialLocationSelect = document.getElementById('serialCreateLocation');
    const syncSerialLocations = () => fillLocationOptions(serialLocationSelect, serialWarehouseSelect?.value ?? '');
    serialWarehouseSelect?.addEventListener('change', syncSerialLocations);
    syncSerialLocations();

    // Un produit a variantes (taille/couleur/etc.) n'a pas de stock au niveau
    // du produit lui-meme : chaque numero de serie designe un exemplaire
    // physique d'UNE variante precise. Le backend acceptait deja variant_id
    // a la creation (product_serials.variant_id existe et est deja utilise
    // pour les mouvements de stock et l'historique), mais cet ecran ne le
    // demandait jamais : impossible d'enregistrer un SN pour une variante.
    const serialProductSelect = createForm?.elements.namedItem('product_id');
    const serialVariantWrap = document.getElementById('serialCreateVariantWrap');
    const serialVariantSelect = document.getElementById('serialCreateVariantSelect');
    const loadSerialVariantOptions = async () => {
        if (!serialVariantWrap || !serialVariantSelect) {
            return;
        }
        const productId = serialProductSelect?.value;
        const product = state.lookups.products.find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;
        serialVariantWrap.classList.toggle('hidden', !hasVariants);
        serialVariantSelect.required = hasVariants;

        if (!hasVariants || !productId) {
            serialVariantSelect.innerHTML = '';
            return;
        }

        serialVariantSelect.innerHTML = '<option value="">Chargement...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=5000`);
        const variants = normalizeRows(response);
        serialVariantSelect.innerHTML = variants.length === 0
            ? '<option value="">Aucune variante active pour ce produit</option>'
            : '<option value="">Choisir...</option>' + variants.map((v) => `<option value="${v.id}">${sanitize(variantDescriptor(v))}</option>`).join('');
    };
    serialProductSelect?.addEventListener('change', loadSerialVariantOptions);
    loadSerialVariantOptions();

    const createFeedback = document.getElementById('serialCreateFeedback');
    createForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        createFeedback.textContent = '';

        const data = new FormData(createForm);
        const warehouseId = data.get('warehouse_id') ? Number(data.get('warehouse_id')) : null;
        const serialNumbers = String(data.get('serial_numbers') ?? '')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);

        const productId = Number(data.get('product_id'));
        const selectedProduct = state.lookups.products.find((p) => String(p.id) === String(productId));
        if (Number(selectedProduct?.has_variants) === 1 && !serialVariantSelect?.value) {
            createFeedback.textContent = 'Ce produit utilise des variantes : precise laquelle avant d\'enregistrer.';
            createFeedback.classList.add('is-error');
            return;
        }

        const payload = {
            product_id: productId,
            variant_id: serialVariantSelect?.value ? Number(serialVariantSelect.value) : null,
            warehouse_id: warehouseId,
            serial_numbers: serialNumbers,
            location_id: data.get('location_id') ? Number(data.get('location_id')) : null,
            creates_stock_entry: String(data.get('creates_stock_entry') ?? '1') === '1',
        };

        try {
            await apiRequest('/product-serials', { method: 'POST', body: payload });
            await renderProductSerials();
        } catch (error) {
            createFeedback.textContent = error.message;
            createFeedback.classList.add('is-error');
        }
    });

    root.querySelectorAll('[data-mark-out]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            try {
                await apiRequest(`/product-serials/${btn.dataset.markOut}/mark-out`, { method: 'POST', body: {} });
                await renderProductSerials();
            } catch (error) {
                window.alert(error.message);
            }
        });
    });

    root.querySelectorAll('[data-mark-in]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            // Avant : window.prompt('Id de l'entrepot ?') - il fallait
            // connaitre l'identifiant numerique de l'entrepot et le taper a la
            // main, sans aucune verification. Taper 3 au lieu de 1 remettait
            // l'article en stock au mauvais endroit, en silence.
            const destination = await askWarehouse('Ou cet article revient-il ?');
            if (!destination) {
                return;
            }
            try {
                await apiRequest(`/product-serials/${btn.dataset.markIn}/mark-in-stock`, {
                    method: 'POST',
                    body: { warehouse_id: destination.warehouseId, location_id: destination.locationId },
                });
                await renderProductSerials();
            } catch (error) {
                window.alert(error.message);
            }
        });
    });

    root.querySelectorAll('[data-delete-serial]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            const enStock = btn.dataset.serialStatus === 'IN_STOCK';

            // Un numero deja sorti n'est plus compte dans la quantite : sa
            // suppression ne peut pas la modifier, aucune question a poser.
            if (!enStock) {
                if (!window.confirm(`Supprimer le numero de serie ${btn.dataset.serialNumber} ?`)) {
                    return;
                }

                try {
                    await apiRequest(`/product-serials/${btn.dataset.deleteSerial}`, { method: 'DELETE' });
                    await renderProductSerials();
                } catch (error) {
                    window.alert(error.message);
                }
                return;
            }

            // En stock : la reponse change la quantite. On ne peut pas la
            // deviner, et compter sur l'utilisateur pour "penser a ajuster"
            // apres coup ne marche jamais. On pose donc la question dans ses
            // termes a lui, au moment ou il decide.
            const choix = await askChoice(
                `Supprimer le numero de serie ${btn.dataset.serialNumber}`,
                'Ce numero est actuellement en stock. Que s\'est-il passe ?',
                [
                    { value: 'typo', label: 'Erreur de saisie - l\'article est toujours en stock', hint: 'La quantite en stock ne change pas.' },
                    { value: 'gone', label: 'L\'article n\'est plus la (casse, perdu, jamais recu)', hint: 'La quantite en stock sera diminuee de 1.' },
                ]
            );

            if (!choix) {
                return;
            }

            try {
                const suffixe = choix === 'gone' ? '?adjust_stock=1' : '';
                await apiRequest(`/product-serials/${btn.dataset.deleteSerial}${suffixe}`, { method: 'DELETE' });
                await renderProductSerials();
            } catch (error) {
                window.alert(error.message);
            }
        });
    });
}

async function renderDeliveries() {
    // Bons de livraison: creation multi-lignes, decrement stock, impression/PDF.
    const root = document.getElementById('appContent');
    await refreshLookups();

    const listResponse = await apiRequest('/deliveries');
    const rows = normalizeRows(listResponse);
    const writable = canWrite('deliveries');

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head"><h4>Nouvelle livraison (BL)</h4></div>
            ${writable ? `
            <form id="deliveryForm" class="form-grid">
                ${selectField('customer_id', 'Client', state.lookups.customers, 'id', 'name', true)}
                ${selectField('warehouse_id', 'Entrepot', state.lookups.warehouses, 'id', 'name', true)}
                <label><span>Emplacement source (optionnel)</span>
                    <select name="location_id" id="deliveryLocation" disabled>
                        <option value="">Choisis d'abord un entrepot</option>
                    </select></label>
                <small class="field-hint full">S'applique aux lignes sans numero de serie (un numero de serie sort toujours de l'emplacement ou il se trouve reellement). Laisse vide pour sortir sans emplacement precis (comme avant).</small>
                <label class="full"><span>Notes</span><textarea name="notes"></textarea></label>
            </form>
            <div class="table-wrap">
                <table class="data-table" id="deliveryLinesTable">
                    <thead><tr><th>Produit</th><th>Variante</th><th>N° Serie (optionnel)</th><th>Quantite</th><th>Prix unitaire</th><th></th></tr></thead>
                    <tbody id="deliveryLinesBody"></tbody>
                </table>
            </div>
            <div class="panel-actions">
                <button type="button" class="btn btn-soft" id="addDeliveryLineBtn">+ Ajouter une ligne</button>
                <button type="submit" form="deliveryForm" class="btn btn-primary" id="submitDeliveryBtn">Creer le BL (sort le stock)</button>
            </div>
            <p id="deliveryFeedback" class="feedback"></p>
            ` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>

        <section class="panel">
            <h4>Bons de livraison</h4>
            ${renderSimpleTable(rows, [
                ['delivery_number', 'Numero', (value, row) => `
                    ${sanitize(value)}
                    <button type="button" class="btn btn-soft btn-sm" data-view-delivery-lines="${row.id}">Produits livres</button>
                `],
                ['customer_name', 'Client'],
                ['warehouse_name', 'Entrepot'],
                ['status', 'Statut'],
                ['total_amount', 'Montant', (value) => formatMoney(value)],
                ['delivered_at', 'Date'],
                ['id', 'Actions', (value, row) => `
                    <button type="button" class="btn btn-soft btn-sm" data-print-delivery="${value}">Imprimer</button>
                    ${writable && row.status === 'VALIDATED' ? `<button type="button" class="btn btn-soft btn-sm" data-cancel-delivery="${value}">Annuler</button>` : ''}
                `],
            ])}
        </section>
    `;

    const linesBody = document.getElementById('deliveryLinesBody');
    const products = state.lookups.products ?? [];

    const deliveryWarehouseSelect = document.querySelector('#deliveryForm select[name="warehouse_id"]');
    const deliveryLocationSelect = document.getElementById('deliveryLocation');
    const syncDeliveryLocations = () => fillLocationOptions(deliveryLocationSelect, deliveryWarehouseSelect?.value ?? '');
    deliveryWarehouseSelect?.addEventListener('change', syncDeliveryLocations);
    syncDeliveryLocations();

    const addLineRow = () => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td>${selectField('line_product_id', '', products, 'id', 'name', true)}</td>
            <td><select class="line-variant-id"><option value="">-</option></select></td>
            <td>
                <select class="line-serial-id">
                    <option value="">Aucun (sortie standard)</option>
                </select>
            </td>
            <td><input type="number" class="line-quantity" min="1" value="1" required></td>
            <td><input type="number" class="line-unit-price" min="0" step="0.01" value="0" required></td>
            <td><button type="button" class="btn btn-soft btn-sm remove-line-btn">Retirer</button></td>
        `;

        const productSelect = row.querySelector('select[name="line_product_id"]');
        const variantSelect = row.querySelector('.line-variant-id');
        const serialSelect = row.querySelector('.line-serial-id');
        const quantityInput = row.querySelector('.line-quantity');

        const refreshVariantsForProduct = async () => {
            const productId = productSelect?.value;
            const product = products.find((p) => String(p.id) === String(productId));
            const hasVariants = Number(product?.has_variants) === 1;
            variantSelect.classList.toggle('hidden', !hasVariants);
            variantSelect.required = hasVariants;
            variantSelect.innerHTML = '<option value="">-</option>';
            if (!hasVariants || !productId) {
                return;
            }
            variantSelect.innerHTML = '<option value="">Choisir...</option>';
            try {
                const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=5000`);
                const variants = normalizeRows(response);
                variantSelect.innerHTML = '<option value="">Choisir...</option>' + variants.map((v) => {
                    const descriptors = variantDescriptor(v);
                    return `<option value="${v.id}">${sanitize(descriptors)} (stock: ${v.stock_total ?? 0})</option>`;
                }).join('');
            } catch (error) {
                // Pas bloquant.
            }
        };

        // Un numero de serie identifie un exemplaire unique: des qu'on en
        // choisit un, la quantite est forcement 1 (et se debloque si on
        // revient a "Aucun").
        const refreshSerialsForProduct = async () => {
            const productId = productSelect?.value;
            serialSelect.innerHTML = '<option value="">Aucun (sortie standard)</option>';
            if (!productId) {
                return;
            }

            try {
                const response = await apiRequest(`/product-serials?product_id=${productId}&status=IN_STOCK&per_page=5000`);
                const serials = normalizeRows(response);
                serialSelect.innerHTML = '<option value="">Aucun (sortie standard)</option>'
                    + serials.map((serial) => `<option value="${serial.id}">${sanitize(serial.serial_number)}</option>`).join('');
            } catch (error) {
                // Pas bloquant: on laisse juste "Aucun" si la recherche echoue.
            }
        };

        productSelect?.addEventListener('change', refreshSerialsForProduct);
        productSelect?.addEventListener('change', refreshVariantsForProduct);
        serialSelect.addEventListener('change', () => {
            if (serialSelect.value) {
                quantityInput.value = '1';
                quantityInput.setAttribute('readonly', 'readonly');
            } else {
                quantityInput.removeAttribute('readonly');
            }
        });

        row.querySelector('.remove-line-btn')?.addEventListener('click', () => row.remove());
        linesBody?.appendChild(row);
        refreshSerialsForProduct();
        refreshVariantsForProduct();
    };

    document.getElementById('addDeliveryLineBtn')?.addEventListener('click', addLineRow);
    if (writable) {
        addLineRow();
    }

    const form = document.getElementById('deliveryForm');
    const feedback = document.getElementById('deliveryFeedback');

    form?.addEventListener('submit', async (event) => {
        event.preventDefault();
        feedback.textContent = '';

        const data = new FormData(form);
        const lines = [...linesBody.querySelectorAll('tr')].map((row) => ({
            product_id: Number(row.querySelector('select[name="line_product_id"]')?.value),
            variant_id: row.querySelector('.line-variant-id')?.value
                ? Number(row.querySelector('.line-variant-id').value)
                : null,
            serial_id: row.querySelector('.line-serial-id')?.value
                ? Number(row.querySelector('.line-serial-id').value)
                : null,
            quantity: Number(row.querySelector('.line-quantity')?.value),
            unit_price: Number(row.querySelector('.line-unit-price')?.value),
        }));

        if (lines.length === 0 || lines.some((line) => !line.product_id || !line.quantity)) {
            feedback.textContent = 'Ajoute au moins une ligne valide (produit + quantite).';
            feedback.classList.add('is-error');
            return;
        }

        const missingVariant = lines.some((line) => {
            const product = products.find((p) => Number(p.id) === line.product_id);
            return Number(product?.has_variants) === 1 && !line.variant_id;
        });
        if (missingVariant) {
            feedback.textContent = 'Un produit a variantes est present sans variante choisie.';
            feedback.classList.add('is-error');
            return;
        }

        const payload = {
            customer_id: Number(data.get('customer_id')),
            warehouse_id: Number(data.get('warehouse_id')),
            location_id: data.get('location_id') ? Number(data.get('location_id')) : null,
            notes: String(data.get('notes') ?? ''),
            lines,
        };

        try {
            await apiRequest('/deliveries', { method: 'POST', body: payload });
            await renderDeliveries();
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    root.querySelectorAll('[data-print-delivery]').forEach((button) => {
        button.addEventListener('click', async () => {
            const deliveryId = button.getAttribute('data-print-delivery');
            // Ouverture synchrone (dans le meme tick que le clic) pour eviter
            // le blocage popup des navigateurs sur les window.open() post-await.
            const win = window.open('', '_blank');
            if (!win) {
                window.alert("Le navigateur a bloque l'ouverture de la fenetre d'impression. Autorise les popups pour ce site.");
                return;
            }
            win.document.write('<p style="font-family:sans-serif;padding:40px;">Chargement du bon de livraison...</p>');
            try {
                const response = await apiRequest(`/deliveries/${deliveryId}`);
                renderDeliveryPrintDocument(win, response.data);
            } catch (error) {
                win.document.body.innerHTML = `<p style="font-family:sans-serif;padding:40px;color:#b00;">Erreur: ${sanitize(error.message)}</p>`;
            }
        });
    });

    root.querySelectorAll('[data-cancel-delivery]').forEach((button) => {
        button.addEventListener('click', async () => {
            if (!window.confirm('Annuler ce BL ? Le stock sera re-credite.')) {
                return;
            }
            const deliveryId = button.getAttribute('data-cancel-delivery');
            try {
                await apiRequest(`/deliveries/${deliveryId}/cancel`, { method: 'POST', body: {} });
                await renderDeliveries();
            } catch (error) {
                window.alert(error.message);
            }
        });
    });

    // "Produits livres" : le detail (lignes) n'est pas dans la liste paginee
    // (couteux a charger pour chaque BL quand on ne le consulte pas), donc
    // recupere a la demande. Une vraie liste deroulante (<select>) aurait pu
    // s'ouvrir vide le temps du chargement - une popup, comme pour les
    // demandes/commandes d'achat, affiche "Chargement..." puis le contenu
    // sans ce defaut.
    root.querySelectorAll('[data-view-delivery-lines]').forEach((button) => {
        button.addEventListener('click', async () => {
            const deliveryId = button.getAttribute('data-view-delivery-lines');
            try {
                const detail = await apiRequest(`/deliveries/${deliveryId}`);
                const delivery = detail.data;
                const linesHtml = (delivery.lines ?? []).map((line) => `
                    <tr>
                        <td>${sanitize(line.sku)}</td>
                        <td>${sanitize(line.product_name)}${line.variant_id ? ` - ${sanitize(variantDescriptor({ ...line, sku: line.variant_sku }))}` : ''}</td>
                        <td>${line.serial_number ? sanitize(line.serial_number) : '-'}</td>
                        <td>${Number(line.quantity)}</td>
                        <td>${formatMoney(line.unit_price)}</td>
                    </tr>
                `).join('');
                showModal(`Produits livres - BL ${delivery.delivery_number}`, `
                    <table class="simple-table">
                        <thead><tr><th>SKU</th><th>Produit</th><th>N° Serie</th><th>Qte</th><th>PU</th></tr></thead>
                        <tbody>${linesHtml || '<tr><td colspan="5">Aucune ligne</td></tr>'}</tbody>
                    </table>
                `);
            } catch (error) {
                window.alert(error.message);
            }
        });
    });
}

function renderDeliveryPrintDocument(win, delivery) {
    // Ecrit le document imprimable dans une fenetre deja ouverte (evite le
    // blocage popup) et attache le bouton d'impression en JS (pas d'onclick
    // inline, plus robuste face aux bloqueurs de contenu).
    const lines = delivery.lines ?? [];
    const rows = lines.map((line) => `
        <tr>
            <td>${sanitize(line.sku)}</td>
            <td>${sanitize(line.product_name)}</td>
            <td>${line.serial_number ? sanitize(line.serial_number) : '-'}</td>
            <td style="text-align:right">${sanitize(line.quantity)}</td>
            <td style="text-align:right">${formatMoney(line.unit_price)}</td>
            <td style="text-align:right">${formatMoney(line.line_total)}</td>
        </tr>
    `).join('');

    const companyName = sanitize(window.APP_CONFIG?.companyName || '');
    const logoUrl = window.APP_CONFIG?.logoUrl || '';

    win.document.open();
    win.document.write(`
        <!DOCTYPE html>
        <html lang="fr">
        <head>
            <meta charset="utf-8">
            <title>BL ${sanitize(delivery.delivery_number)}</title>
            <style>
                body { font-family: Arial, sans-serif; color: #1a1a1a; margin: 40px; }
                h1 { font-size: 22px; margin-bottom: 0; }
                .muted { color: #666; }
                .brand-header { display: flex; align-items: center; gap: 16px; margin-bottom: 12px; }
                .brand-header img { height: 56px; width: auto; object-fit: contain; }
                .brand-header .brand-name { font-size: 18px; font-weight: bold; }
                .header-grid { display: flex; justify-content: space-between; margin: 24px 0; }
                table { width: 100%; border-collapse: collapse; margin-top: 20px; }
                th, td { border: 1px solid #ccc; padding: 8px; font-size: 14px; }
                th { background: #f2f2f2; text-align: left; }
                tfoot td { font-weight: bold; }
                #printBtn { margin-top: 24px; padding: 10px 18px; font-size: 14px; cursor: pointer; }
                @media print { .no-print { display: none; } }
            </style>
        </head>
        <body>
            <div class="brand-header">
                ${logoUrl ? `<img src="${sanitize(logoUrl)}" alt="${companyName}">` : ''}
                ${companyName ? `<span class="brand-name">${companyName}</span>` : ''}
            </div>
            <h1>Bon de livraison ${sanitize(delivery.delivery_number)}</h1>
            <p class="muted">Date: ${sanitize(delivery.delivered_at)} - Statut: ${sanitize(delivery.status)}</p>
            <div class="header-grid">
                <div>
                    <strong>Client</strong><br>
                    ${sanitize(delivery.customer_name)}<br>
                    ${sanitize(delivery.customer_address || '')}<br>
                    ${sanitize(delivery.customer_phone || '')} ${sanitize(delivery.customer_email || '')}
                </div>
                <div>
                    <strong>Expedie depuis</strong><br>
                    ${sanitize(delivery.warehouse_name)}
                </div>
            </div>
            <table>
                <thead><tr><th>SKU</th><th>Produit</th><th>N° Serie</th><th>Qte</th><th>Prix unit.</th><th>Total</th></tr></thead>
                <tbody>${rows}</tbody>
                <tfoot><tr><td colspan="5" style="text-align:right">Total</td><td style="text-align:right">${formatMoney(delivery.total_amount)}</td></tr></tfoot>
            </table>
            ${delivery.notes ? `<p><strong>Notes:</strong> ${sanitize(delivery.notes)}</p>` : ''}
            <button type="button" class="no-print" id="printBtn">Imprimer / Enregistrer en PDF</button>
        </body>
        </html>
    `);
    win.document.close();

    const printBtn = win.document.getElementById('printBtn');
    printBtn?.addEventListener('click', () => win.print());
    win.focus();
}

async function renderAlerts() {
    // Alertes calculees + alertes persistantes.
    const root = document.getElementById('appContent');
    const [computed, persistentResponse] = await Promise.all([
        apiRequest('/stock/alerts'),
        apiRequest('/alerts'),
    ]);
    const persistentRows = normalizeRows(persistentResponse);

    root.innerHTML = `
        <section class="panel">
            <h4>Stock bas / rupture</h4>
            ${renderSimpleTable(computed.data.low_stock ?? [], [
                ['sku', 'SKU'],
                ['name', 'Produit'],
                ['stock_total', 'Stock'],
                ['reorder_level', "Seuil d'alerte"],
            ])}
        </section>
        <section class="panel">
            <h4>Commandes d'achat en retard</h4>
            ${renderSimpleTable(computed.data.delayed_po ?? [], [
                ['order_number', 'Commande'],
                ['supplier_name', 'Fournisseur'],
                ['expected_at', 'Date attendue'],
            ])}
        </section>
        <section class="panel">
            <h4>Alertes persistantes</h4>
            ${renderSimpleTable(persistentRows, [
                ['id', 'ID'],
                ['alert_type', 'Type'],
                ['severity', 'Severite'],
                ['message', 'Message'],
                ['status', 'Statut'],
                ['created_at', 'Date'],
            ])}
        </section>
    `;
}

async function renderInventories() {
    // Sessions inventaire: creation, puis on rentre dans une session pour
    // saisir/voir les comptages et la finaliser (renderInventorySessionDetail).
    const root = document.getElementById('appContent');
    await refreshLookups();

    const sessionsResponse = await apiRequest('/inventories');
    const sessions = normalizeRows(sessionsResponse);
    const writable = canWrite('inventories');

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head"><h4>Nouvelle session inventaire</h4></div>
            ${writable ? `
            <form id="inventorySessionForm" class="form-grid">
                ${selectField('warehouse_id', 'Entrepot', state.lookups.warehouses, 'id', 'name', true)}
                <label><span>Mode</span><select name="counting_mode"><option value="GLOBAL">Global</option><option value="CYCLE">Tournant</option></select></label>
                <label class="full"><span>Notes</span><textarea name="notes"></textarea></label>
                <button type="submit" class="btn btn-primary">Creer une session</button>
                <p id="inventorySessionFeedback" class="feedback"></p>
            </form>` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>
        <section class="panel">
            <h4>Sessions</h4>
            ${renderSimpleTable(sessions, [
                ['code', 'Code'],
                ['warehouse_name', 'Entrepot'],
                ['status', 'Statut'],
                ['counting_mode', 'Mode'],
                ['started_at', 'Debut'],
                ['ended_at', 'Fin'],
                ['id', 'Comptages', (value) => `<button type="button" class="btn btn-soft" data-open-session="${value}">Voir / Compter</button>`],
            ])}
        </section>
    `;

    const sessionForm = document.getElementById('inventorySessionForm');
    sessionForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const feedback = document.getElementById('inventorySessionFeedback');
        feedback.textContent = '';
        const data = new FormData(sessionForm);

        try {
            const created = await apiRequest('/inventories', {
                method: 'POST',
                body: {
                    warehouse_id: Number(data.get('warehouse_id')),
                    counting_mode: String(data.get('counting_mode') ?? 'GLOBAL'),
                    notes: String(data.get('notes') ?? ''),
                },
            });
            // On rentre directement dans la session fraichement creee, plutot
            // que de reafficher juste la liste: c'est la qu'on va saisir les
            // comptages.
            await renderInventorySessionDetail(created.id);
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    root.querySelectorAll('[data-open-session]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            await renderInventorySessionDetail(Number(btn.dataset.openSession));
        });
    });
}

async function renderInventorySessionDetail(sessionId) {
    // Vue detail d'une session: on y voit tous les comptages deja saisis
    // (c'est ce qui manquait avant - on pouvait ajouter un comptage mais
    // jamais le revoir), on peut en ajouter d'autres, et finaliser.
    const root = document.getElementById('appContent');
    await refreshLookups();

    const response = await apiRequest(`/inventories/${sessionId}`);
    const session = response.data;
    const items = Array.isArray(session.items) ? session.items : [];
    const writable = canWrite('inventories');
    const isEditable = ['IN_PROGRESS', 'DRAFT'].includes(session.status);

    // Un meme produit (+ variante + emplacement) peut avoir ete compte
    // plusieurs fois dans la session (recomptage apres une erreur de saisie):
    // c'est ainsi qu'on "corrige" un comptage aujourd'hui, voir plus bas. Sans
    // indication, deux lignes pour le meme produit dans ce tableau ne disent
    // pas laquelle des deux la finalisation va reellement appliquer - c'est
    // toujours la plus recente (voir InventoryService::finalize, meme regle
    // reproduite ici). `items` arrive deja trie du plus recent au plus ancien
    // (ORDER BY id DESC cote backend) : la premiere occurrence d'une cle est
    // donc forcement la plus recente.
    const seenCountKeys = new Set();
    const isEditableAndWritable = writable && isEditable;
    const itemsHtml = items.map((item) => {
        const diff = Number(item.difference_qty);
        const diffClass = diff === 0 ? '' : (diff > 0 ? 'is-positive' : 'is-error');
        const diffLabel = diff > 0 ? `+${diff}` : String(diff);
        const key = `${item.product_id}-${item.variant_id ?? '0'}-${item.location_id ?? '0'}`;
        const isActive = !seenCountKeys.has(key);
        seenCountKeys.add(key);
        return `
            <tr class="${isActive ? '' : 'is-muted-row'}">
                <td>${sanitize(item.sku)}</td>
                <td>${sanitize(item.product_name)}</td>
                <td>${item.variant_id ? sanitize(variantDescriptor({ ...item, sku: item.variant_sku })) : '-'}</td>
                <td>${Number(item.expected_qty)}</td>
                <td>${Number(item.counted_qty)}</td>
                <td class="${diffClass}">${diffLabel}</td>
                <td>${sanitize(item.location_code ?? '-')}</td>
                <td>${sanitize(item.counted_by_name ?? '-')}</td>
                <td>${sanitize(item.counted_at)}</td>
                <td>${isActive
                    ? '<span class="status-badge">Applique a la finalisation</span>'
                    : '<span class="muted">Remplace par un comptage plus recent</span>'}</td>
                ${isEditableAndWritable ? `<td>
                    <button type="button" class="btn btn-soft btn-sm" data-correct-count="${item.id}" data-product-id="${item.product_id}" data-variant-id="${item.variant_id ?? ''}" data-location-id="${item.location_id ?? ''}" data-counted-qty="${item.counted_qty}">Corriger</button>
                    <button type="button" class="btn btn-soft btn-sm" data-delete-count="${item.id}" data-sku="${sanitize(item.sku)}">Supprimer</button>
                </td>` : ''}
            </tr>
        `;
    }).join('');

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head">
                <h4>Session ${sanitize(session.code)}</h4>
                <button type="button" id="backToInventoryList" class="btn btn-soft">Retour a la liste</button>
            </div>
            <p><strong>Entrepot:</strong> ${sanitize(session.warehouse_name)}</p>
            <p><strong>Statut:</strong> <span class="status-badge">${sanitize(session.status)}</span></p>
            <p><strong>Mode:</strong> ${sanitize(session.counting_mode)}</p>
            <p><strong>Debut:</strong> ${sanitize(session.started_at)}${session.ended_at ? ` &nbsp;|&nbsp; <strong>Fin:</strong> ${sanitize(session.ended_at)}` : ''}</p>
            ${session.notes ? `<p><strong>Notes:</strong> ${sanitize(session.notes)}</p>` : ''}
        </section>

        <section class="panel">
            <div class="panel-head">
                <h4>Comptages saisis (${items.length})</h4>
                <button type="button" id="exportInventoryBtn" class="btn btn-soft">Exporter en Excel</button>
            </div>
            <p class="muted">
                Si un produit est compte plusieurs fois, seul le dernier comptage saisi pour ce
                produit sera applique a la finalisation - la colonne "Statut" ci-dessous dit
                lequel. Pour corriger une quantite mal saisie, utilise "Corriger" (pre-remplit un
                nouveau comptage avec le meme produit) plutot que de tout ressaisir a la main ; le
                comptage d'origine reste visible, remplace, pour garder une trace de la
                correction. "Supprimer" retire completement une ligne saisie par erreur (mauvais
                produit choisi) - possible uniquement avant la finalisation.
            </p>
            <div class="table-wrap">
                <table class="data-table">
                    <thead><tr><th>SKU</th><th>Produit</th><th>Variante</th><th>Attendu</th><th>Compte</th><th>Ecart</th><th>Emplacement</th><th>Compte par</th><th>Date</th><th>Statut</th>${isEditableAndWritable ? '<th>Actions</th>' : ''}</tr></thead>
                    <tbody>${itemsHtml || `<tr><td colspan="${isEditableAndWritable ? 11 : 10}">Aucun comptage saisi pour le moment.</td></tr>`}</tbody>
                </table>
            </div>
        </section>

        ${writable && isEditable ? `
        <section class="panel">
            <div class="panel-head">
                <h4>Comptage sur Excel</h4>
            </div>
            <p class="muted">
                Telecharge la feuille de comptage de l'entrepot ${sanitize(session.warehouse_name)} (une ligne par
                produit/variante/emplacement), compte directement dedans en remplissant la colonne
                "Quantite comptee", puis reimporte-la ici : chaque ligne remplie devient un comptage,
                exactement comme si tu l'avais saisi a la main. Une ligne laissee vide est ignoree -
                tu peux donc ne compter qu'une partie de l'entrepot, reimporter, puis recompter le
                reste plus tard et reimporter a nouveau. Ne modifie pas les colonnes "ID ..." : elles
                servent a retrouver le bon produit/variante/emplacement a la reimportation. Une fois
                tous les comptages faits, clique "Finaliser la session" plus bas pour clore
                l'inventaire avec les correctifs.
            </p>
            <div class="panel-actions">
                <button type="button" class="btn btn-soft" id="downloadCountSheetBtn">Telecharger la feuille de comptage</button>
            </div>
            <form id="importCountSheetForm" class="form-grid" style="margin-top: 0.8rem;">
                <label><span>Feuille de comptage remplie (.xlsx)</span><input type="file" name="file" accept=".xlsx" required></label>
                <button type="submit" class="btn btn-primary">Reimporter les comptages</button>
                <p id="importCountSheetFeedback" class="feedback full"></p>
            </form>
        </section>

        <section class="panel hidden" id="inventoryRemainingPanel">
            <div class="panel-head">
                <h4>Reste a compter</h4>
                <span class="muted" id="inventoryRemainingCounter"></span>
            </div>
            <p class="muted">
                Inventaire global : voici les articles ayant du stock dans cet
                entrepot et qui n'ont pas encore ete comptes. Aucun comptage
                n'est pre-rempli - un article laisse ici n'est simplement pas
                ajuste a la finalisation, son stock reste inchange.
            </p>
            <div id="inventoryRemainingList"></div>
        </section>

        <section class="panel">
            <div class="panel-head"><h4>Ajouter un comptage - entrepot ${sanitize(session.warehouse_name)}</h4></div>
            <p class="muted">
                Un inventaire ne porte que sur un entrepot. La quantite attendue
                est celle du produit <strong>dans ${sanitize(session.warehouse_name)}</strong> :
                un produit stocke ailleurs y apparait donc a 0.
            </p>
            <form id="inventoryCountForm" class="form-grid">
                ${selectField('product_id', 'Produit', state.lookups.products, 'id', 'name', true)}
                <p class="full feedback hidden" id="inventoryStockHint"></p>
                <div class="full hidden" id="inventoryVariantWrap">
                    <label><span>Variante</span><select name="variant_id" id="inventoryVariantSelect"></select></label>
                    <small class="field-hint">Ce produit utilise des variantes : compte chacune separement.</small>
                </div>
                <label><span>Quantite comptee</span><input type="number" name="counted_qty" min="0" required></label>
                <label><span>Emplacement (optionnel)</span>
                    <select name="location_id" id="inventoryCountLocation"></select></label>
                <small class="full field-hint">
                    Sans emplacement, tu comptes le produit dans tout l'entrepot.
                    Avec un emplacement, tu ne comptes que cette allee et l'ecart
                    ne portera que sur elle.
                </small>
                <label class="full"><span>Notes</span><textarea name="notes"></textarea></label>
                <button type="submit" class="btn btn-primary">Ajouter comptage</button>
                <p id="inventoryCountFeedback" class="feedback"></p>
            </form>
        </section>

        <section class="panel">
            <div class="panel-head"><h4>Finaliser la session</h4></div>
            <p class="muted">
                La finalisation genere un mouvement de stock d'ajustement pour
                chaque produit dont l'ecart n'est pas nul, puis verrouille la
                session (plus aucun comptage possible ensuite).
            </p>
            <button type="button" id="inventoryFinalizeBtn" class="btn btn-primary">Finaliser la session</button>
            <p id="inventoryFinalizeFeedback" class="feedback"></p>
        </section>
        ` : (!isEditable ? '<section class="panel"><p class="muted">Cette session est terminee, plus aucune saisie possible.</p></section>' : '')}
    `;

    document.getElementById('backToInventoryList')?.addEventListener('click', async () => {
        await renderInventories();
    });

    document.getElementById('exportInventoryBtn')?.addEventListener('click', async () => {
        try {
            await downloadCsv(`/inventories/${sessionId}/export.xlsx`, `inventaire-${session.code}.xlsx`);
        } catch (error) {
            window.alert(error.message);
        }
    });

    document.getElementById('downloadCountSheetBtn')?.addEventListener('click', async () => {
        try {
            await downloadCsv(`/inventories/${sessionId}/count-sheet.xlsx`, `comptage-${session.code}.xlsx`);
        } catch (error) {
            window.alert(error.message);
        }
    });

    document.getElementById('importCountSheetForm')?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const feedback = document.getElementById('importCountSheetFeedback');
        feedback.textContent = '';
        feedback.classList.remove('is-error');

        const data = new FormData(event.target);
        const file = data.get('file');
        if (!(file instanceof File) || !file.name) {
            feedback.textContent = 'Choisis le fichier .xlsx rempli.';
            feedback.classList.add('is-error');
            return;
        }

        const payload = new FormData();
        payload.append('file', file);

        try {
            const response = await uploadRequest(`/inventories/${sessionId}/import-counts`, payload);
            const summary = response.data ?? {};
            const parts = [`${summary.success_rows ?? 0} comptage(s) importe(s)`];
            if (summary.skipped_rows) {
                parts.push(`${summary.skipped_rows} ligne(s) vide(s) ignoree(s)`);
            }
            if (summary.failed_rows) {
                parts.push(`${summary.failed_rows} en erreur`);
            }
            feedback.textContent = parts.join(', ') + '.';
            feedback.classList.toggle('is-error', (summary.failed_rows ?? 0) > 0);
            if (Array.isArray(summary.errors) && summary.errors.length > 0) {
                window.alert(`Certaines lignes n'ont pas pu etre importees :\n${summary.errors.join('\n')}`);
            }
            // Comme apres l'ajout d'un comptage manuel, on recharge la session
            // pour voir tout de suite les comptages importes dans le tableau.
            await renderInventorySessionDetail(sessionId);
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    // Les emplacements proposes sont ceux de l'entrepot de la session : une
    // session d'inventaire ne porte que sur un entrepot.
    fillLocationOptions(document.getElementById('inventoryCountLocation'), session.warehouse_id);

    // Chargement differe : le panneau n'a de sens qu'en mode GLOBAL, et le
    // backend le dit lui-meme via `applicable`.
    if (writable && isEditable) {
        loadInventoryRemaining(sessionId);
    }

    const countForm = document.getElementById('inventoryCountForm');
    const countVariantWrap = document.getElementById('inventoryVariantWrap');
    const countVariantSelect = document.getElementById('inventoryVariantSelect');

    // Le backend acceptait deja variant_id dans le comptage, mais l'ecran ne
    // le proposait pas : impossible de compter separement deux tailles du meme
    // produit, alors que l'ecart d'inventaire est bien calcule par variante.
    countForm?.elements.product_id?.addEventListener('change', async (event) => {
        if (!countVariantWrap || !countVariantSelect) {
            return;
        }

        const productId = Number(event.target.value);
        const product = state.lookups.products.find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;

        countVariantWrap.classList.toggle('hidden', !hasVariants);
        countVariantSelect.required = hasVariants;

        // Garde-fou : compter un produit dans le mauvais entrepot est une
        // erreur silencieuse et couteuse. L'attendu vaut alors 0, l'ecart est
        // egal a la quantite saisie, et la finalisation CREE ce stock dans
        // l'entrepot de la session en laissant l'autre intact. On previent
        // avant, pendant que c'est rattrapable.
        await warnIfStockedElsewhere(productId, session);

        if (!hasVariants || !productId) {
            countVariantSelect.innerHTML = '';
            return;
        }

        countVariantSelect.innerHTML = '<option value="">Chargement...</option>';
        try {
            const variantsResponse = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=5000`);
            const variants = normalizeRows(variantsResponse);
            countVariantSelect.innerHTML = variants.length === 0
                ? '<option value="">Aucune variante active pour ce produit</option>'
                : variants.map((v) => `<option value="${v.id}">${sanitize(variantDescriptor(v))} - ${sanitize(v.sku)}</option>`).join('');
        } catch (error) {
            countVariantSelect.innerHTML = `<option value="">${sanitize(error.message)}</option>`;
        }
    });

    countForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const feedback = document.getElementById('inventoryCountFeedback');
        feedback.textContent = '';
        const data = new FormData(countForm);

        const variantVisible = countVariantWrap && !countVariantWrap.classList.contains('hidden');
        if (variantVisible && !countVariantSelect?.value) {
            feedback.textContent = 'Ce produit utilise des variantes : choisis-en une.';
            feedback.classList.add('is-error');
            return;
        }

        try {
            await apiRequest(`/inventories/${sessionId}/counts`, {
                method: 'POST',
                body: {
                    product_id: Number(data.get('product_id')),
                    variant_id: variantVisible && countVariantSelect?.value ? Number(countVariantSelect.value) : null,
                    counted_qty: Number(data.get('counted_qty')),
                    location_id: data.get('location_id') ? Number(data.get('location_id')) : null,
                    notes: String(data.get('notes') ?? ''),
                },
            });
            // On reste sur la meme session (au lieu de retomber sur la liste)
            // pour que le comptage qu'on vient d'ajouter soit visible tout de
            // suite et qu'on puisse enchainer sur le suivant.
            await renderInventorySessionDetail(sessionId);
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    // "Corriger" : pre-remplit le formulaire "Ajouter un comptage" avec le
    // meme produit/variante/emplacement, quantite comprise (il ne reste plus
    // qu'a la modifier). On ne modifie jamais la ligne existante en place -
    // voir la note au-dessus du tableau : un nouveau comptage est cree, plus
    // recent, et c'est lui qui comptera a la finalisation.
    root.querySelectorAll('[data-correct-count]').forEach((button) => {
        button.addEventListener('click', async () => {
            if (!countForm) {
                return;
            }
            const productId = button.getAttribute('data-product-id');
            const variantId = button.getAttribute('data-variant-id');
            const locationId = button.getAttribute('data-location-id');
            const countedQty = button.getAttribute('data-counted-qty');

            const productSelect = countForm.elements.namedItem('product_id');
            productSelect.value = productId;
            productSelect.dispatchEvent(new Event('change', { bubbles: true }));
            // Le choix de la variante depend du chargement (asynchrone) des
            // options declenche par le 'change' ci-dessus.
            await new Promise((resolve) => setTimeout(resolve, 250));
            if (variantId && countVariantSelect) {
                countVariantSelect.value = variantId;
            }
            const locationSelect = document.getElementById('inventoryCountLocation');
            if (locationSelect) {
                locationSelect.value = locationId;
            }
            countForm.elements.namedItem('counted_qty').value = countedQty;

            countForm.scrollIntoView?.({ behavior: 'smooth', block: 'center' });
            countForm.elements.namedItem('counted_qty').focus();
        });
    });

    // "Supprimer" : retire completement une ligne saisie par erreur (mauvais
    // produit choisi). Contrairement a "Corriger", ne cree rien de nouveau -
    // uniquement possible avant la finalisation (le backend le refuse aussi,
    // ceci n'est qu'un confort cote ecran).
    root.querySelectorAll('[data-delete-count]').forEach((button) => {
        button.addEventListener('click', async () => {
            const itemId = button.getAttribute('data-delete-count');
            const sku = button.getAttribute('data-sku');
            if (!window.confirm(`Supprimer le comptage de ${sku} ? Cette ligne ne sera plus prise en compte a la finalisation.`)) {
                return;
            }
            try {
                await apiRequest(`/inventories/${sessionId}/counts/${itemId}`, { method: 'DELETE' });
                await renderInventorySessionDetail(sessionId);
            } catch (error) {
                window.alert(error.message);
            }
        });
    });

    document.getElementById('inventoryFinalizeBtn')?.addEventListener('click', async () => {
        const feedback = document.getElementById('inventoryFinalizeFeedback');
        feedback.textContent = '';

        if (items.length === 0) {
            feedback.textContent = 'Ajoute au moins un comptage avant de finaliser.';
            feedback.classList.add('is-error');
            return;
        }

        const nonZero = items.filter((item) => Number(item.difference_qty) !== 0).length;
        const confirmMsg = nonZero > 0
            ? `${nonZero} produit(s) ont un ecart et vont generer un ajustement de stock. Finaliser quand meme ?`
            : 'Finaliser cette session (aucun ecart detecte) ?';

        if (!window.confirm(confirmMsg)) {
            return;
        }

        try {
            await apiRequest(`/inventories/${sessionId}/finalize`, { method: 'POST', body: {} });
            await renderInventorySessionDetail(sessionId);
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });
}

async function renderPurchaseRequests() {
    // Demandes d'achat: creation (plusieurs lignes produit possibles) et suivi.
    const root = document.getElementById('appContent');
    await refreshLookups();

    // Par defaut on n'affiche que les demandes encore a traiter : une demande
    // convertie en commande ou refusee n'a plus rien a apporter dans la liste
    // de travail, et au bout de quelques mois elle noierait les autres. Le
    // bouton de bascule donne acces aux demandes passees, sans rien supprimer.
    const scope = state.purchaseScopes['purchase-requests'] ?? 'open';
    const page = state.crudPages['purchase-requests'] ?? 1;
    const response = await apiRequest(`/purchase-requests${toQueryString({ scope, page, per_page: state.crudPerPage })}`);
    const rows = normalizeRows(response);
    const meta = response?.meta ?? null;
    const writable = canWrite('purchase-requests');

    // Lignes en cours de saisie pour la prochaine demande a creer.
    const draftItems = [];

    const renderDraftItemsTable = () => {
        if (draftItems.length === 0) {
            return '<p class="muted">Aucune ligne ajoutee.</p>';
        }
        const rowsHtml = draftItems.map((item, index) => `
            <tr>
                <td>${sanitize(item.product_label)}</td>
                <td>${Number(item.quantity_requested)}</td>
                <td>${item.preferred_unit_cost !== null ? formatMoney(item.preferred_unit_cost) : '-'}</td>
                <td><button type="button" class="btn btn-soft" data-remove-line="${index}">Retirer</button></td>
            </tr>
        `).join('');
        return `<table class="simple-table"><thead><tr><th>Produit</th><th>Quantite</th><th>Cout prefere</th><th></th></tr></thead><tbody>${rowsHtml}</tbody></table>`;
    };

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head"><h4>Nouvelle demande achat</h4></div>
            ${writable ? `
            <form id="requestHeaderForm" class="form-grid">
                ${selectField('warehouse_id', 'Entrepot', state.lookups.warehouses, 'id', 'name', true)}
                <label><span>Date besoin</span><input type="datetime-local" name="needed_at"></label>
                <label class="full"><span>Notes</span><textarea name="notes"></textarea></label>
            </form>
            <hr>
            <form id="requestLineForm" class="form-grid">
                ${selectField('product_id', 'Produit', state.lookups.products, 'id', 'name', true)}
                <label class="hidden" id="requestLineVariantWrap"><span>Variante</span><select name="variant_id" id="requestLineVariant"><option value="">-</option></select></label>
                <label><span>Quantite demandee</span><input type="number" name="quantity_requested" min="1" required></label>
                <label><span>Cout prefere</span><input type="number" name="preferred_unit_cost" min="0" step="0.01"></label>
                <button type="submit" class="btn btn-soft">Ajouter la ligne</button>
            </form>
            <div id="requestItemsPreview">${renderDraftItemsTable()}</div>
            <button type="button" id="createRequestBtn" class="btn btn-primary">Creer la demande</button>
            <p id="requestFeedback" class="feedback"></p>
            ` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>
        <section class="panel">
            <div class="panel-head">
                <h4>${scope === 'open' ? 'Demandes achat en cours' : 'Demandes achat passees (converties ou refusees)'}</h4>
                ${renderPurchaseScopeToggle('purchase-requests', meta)}
            </div>
            ${renderSimpleTable(rows, [
                ['request_number', 'Numero'],
                ['status', 'Statut'],
                ['warehouse_name', 'Entrepot'],
                ['requester_name', 'Demandeur'],
                ['requested_at', 'Date'],
                ['id', 'Detail', (value) => `<button type="button" class="btn btn-soft" data-view-request="${value}">Voir le detail</button>`],
            ])}
            ${renderPaginationBar(meta, rows.length)}
        </section>
    `;

    setupPagination('purchase-requests', meta, renderPurchaseRequests);
    setupPurchaseScopeToggle('purchase-requests', renderPurchaseRequests);

    const lineForm = document.getElementById('requestLineForm');
    const lineProductSelect = lineForm?.elements.namedItem('product_id');
    const lineVariantSelect = document.getElementById('requestLineVariant');
    const lineVariantWrap = document.getElementById('requestLineVariantWrap');

    const refreshLineVariants = async () => {
        const productId = lineProductSelect?.value;
        const product = (state.lookups.products ?? []).find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;
        lineVariantWrap?.classList.toggle('hidden', !hasVariants);
        lineVariantSelect.required = hasVariants;
        lineVariantSelect.innerHTML = '<option value="">-</option>';
        if (!hasVariants || !productId) {
            return;
        }
        lineVariantSelect.innerHTML = '<option value="">Choisir...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=5000`);
        const variants = normalizeRows(response);
        lineVariantSelect.innerHTML = '<option value="">Choisir...</option>' + variants.map((v) => {
            const descriptors = variantDescriptor(v);
            return `<option value="${v.id}">${sanitize(descriptors)} (stock: ${v.stock_total ?? 0})</option>`;
        }).join('');
    };
    lineProductSelect?.addEventListener('change', refreshLineVariants);

    lineForm?.addEventListener('submit', (event) => {
        event.preventDefault();
        const data = new FormData(lineForm);
        const productId = Number(data.get('product_id'));
        const quantity = Number(data.get('quantity_requested'));
        if (!productId || quantity <= 0) {
            return;
        }
        const product = (state.lookups.products ?? []).find((p) => Number(p.id) === productId);
        if (Number(product?.has_variants) === 1 && !lineVariantSelect.value) {
            window.alert('Ce produit a des variantes : choisis-en une.');
            return;
        }
        const variantId = lineVariantSelect.value ? Number(lineVariantSelect.value) : null;
        const variantLabel = variantId
            ? ` (${sanitize(lineVariantSelect.options[lineVariantSelect.selectedIndex].textContent.split(' (stock:')[0])})`
            : '';
        const cost = data.get('preferred_unit_cost') ? Number(data.get('preferred_unit_cost')) : null;
        draftItems.push({
            product_id: productId,
            variant_id: variantId,
            quantity_requested: quantity,
            preferred_unit_cost: cost,
            product_label: (product?.name ?? `#${productId}`) + variantLabel,
        });
        document.getElementById('requestItemsPreview').innerHTML = renderDraftItemsTable();
        lineForm.reset();
        refreshLineVariants();
    });

    document.getElementById('requestItemsPreview')?.addEventListener('click', (event) => {
        const btn = event.target.closest('[data-remove-line]');
        if (!btn) {
            return;
        }
        draftItems.splice(Number(btn.dataset.removeLine), 1);
        document.getElementById('requestItemsPreview').innerHTML = renderDraftItemsTable();
    });

    const feedback = document.getElementById('requestFeedback');
    document.getElementById('createRequestBtn')?.addEventListener('click', async () => {
        feedback.textContent = '';

        if (draftItems.length === 0) {
            feedback.textContent = 'Ajoute au moins une ligne produit.';
            feedback.classList.add('is-error');
            return;
        }

        const headerForm = document.getElementById('requestHeaderForm');
        const data = new FormData(headerForm);

        try {
            await apiRequest('/purchase-requests', {
                method: 'POST',
                body: {
                    warehouse_id: Number(data.get('warehouse_id')),
                    needed_at: data.get('needed_at') ? String(data.get('needed_at')).replace('T', ' ') + ':00' : null,
                    notes: String(data.get('notes') ?? ''),
                    items: draftItems.map((item) => ({
                        product_id: item.product_id,
                        variant_id: item.variant_id ?? null,
                        quantity_requested: item.quantity_requested,
                        preferred_unit_cost: item.preferred_unit_cost,
                    })),
                },
            });

            await renderPurchaseRequests();
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    root.querySelectorAll('[data-view-request]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            try {
                const detail = await apiRequest(`/purchase-requests/${btn.dataset.viewRequest}`);
                const note = detail.data;
                const itemsHtml = (note.items ?? []).map((item) => `
                    <tr>
                        <td>${sanitize(item.sku)}</td>
                        <td>${sanitize(item.product_name)}</td>
                        <td>${Number(item.quantity_requested)}</td>
                        <td>${item.preferred_unit_cost !== null ? formatMoney(item.preferred_unit_cost) : '-'}</td>
                    </tr>
                `).join('');
                showModal(`Demande ${note.request_number}`, `
                    <p><strong>Statut:</strong> ${sanitize(note.status)}</p>
                    <p><strong>Entrepot:</strong> ${sanitize(note.warehouse_name)}</p>
                    <p><strong>Demandeur:</strong> ${sanitize(note.requester_name)}</p>
                    ${note.notes ? `<p><strong>Notes:</strong> ${sanitize(note.notes)}</p>` : ''}
                    <table class="simple-table">
                        <thead><tr><th>SKU</th><th>Produit</th><th>Qte demandee</th><th>Cout prefere</th></tr></thead>
                        <tbody>${itemsHtml}</tbody>
                    </table>
                `);
            } catch (error) {
                window.alert(error.message);
            }
        });
    });
}

async function renderPurchaseOrders() {
    // Commandes d'achat: creation (plusieurs lignes produit), statut, reception.
    const root = document.getElementById('appContent');
    await refreshLookups();

    // Meme principe que pour les demandes : la liste affiche par defaut les
    // commandes en cours, les commandes recues ou annulees passent derriere le
    // bouton de bascule.
    const scope = state.purchaseScopes['purchase-orders'] ?? 'open';
    const page = state.crudPages['purchase-orders'] ?? 1;
    const listResponse = await apiRequest(`/purchase-orders${toQueryString({ scope, page, per_page: state.crudPerPage })}`);
    const rows = normalizeRows(listResponse);
    const meta = listResponse?.meta ?? null;
    const writable = canWrite('purchase-orders');

    // Les listes deroulantes "Commande" (changement de statut, reception) ne
    // suivent PAS la vue affichee : elles proposent toujours les commandes
    // encore en cours, quelle que soit la page ou la vue consultee. On ne
    // recoit pas une commande deja recue ou annulee, et il ne faut pas non
    // plus qu'elles soient limitees aux 25 lignes de la page courante.
    const openOrdersResponse = await apiRequest('/purchase-orders?scope=open&per_page=100');
    const orderOptions = normalizeRows(openOrdersResponse)
        .map((row) => `<option value="${row.id}">${sanitize(row.order_number)} | ${sanitize(localizeValue(row.status, 'status'))}</option>`)
        .join('');

    // Idem pour les demandes convertibles : uniquement celles qui restent a
    // traiter, sans dependre de la pagination de l'ecran des demandes.
    const requestsResponse = await apiRequest('/purchase-requests?scope=open&per_page=100');
    const requestRows = normalizeRows(requestsResponse);
    // Seules les demandes pas encore transformees en commande peuvent etre liees.
    const convertibleRequests = requestRows.filter((row) => ['SUBMITTED', 'APPROVED'].includes(row.status));
    state.purchaseRequestsById = Object.fromEntries(requestRows.map((row) => [String(row.id), row]));
    const requestOptions = convertibleRequests
        .map((row) => `<option value="${row.id}">${sanitize(row.request_number)} | ${sanitize(row.warehouse_name)}</option>`)
        .join('');

    // Lignes en cours de saisie pour la prochaine commande a creer.
    const draftItems = [];

    const renderDraftItemsTable = () => {
        if (draftItems.length === 0) {
            return '<p class="muted">Aucune ligne ajoutee.</p>';
        }
        const rowsHtml = draftItems.map((item, index) => `
            <tr>
                <td>${sanitize(item.product_label)}</td>
                <td>${Number(item.quantity_ordered)}</td>
                <td>${formatMoney(item.unit_cost)}</td>
                <td><button type="button" class="btn btn-soft" data-remove-line="${index}">Retirer</button></td>
            </tr>
        `).join('');
        return `<table class="simple-table"><thead><tr><th>Produit</th><th>Quantite</th><th>Prix unitaire</th><th></th></tr></thead><tbody>${rowsHtml}</tbody></table>`;
    };

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head"><h4>Nouvelle commande achat</h4></div>
            ${writable ? `
            <form id="orderHeaderForm" class="form-grid">
                <label><span>Demande d'achat (optionnel)</span><select name="purchase_request_id" id="orderRequestId"><option value="">Aucune</option>${requestOptions}</select></label>
                ${selectField('supplier_id', 'Fournisseur', state.lookups.suppliers, 'id', 'name', true)}
                ${selectField('warehouse_id', 'Entrepot', state.lookups.warehouses, 'id', 'name', true)}
                <label><span>Date attendue</span><input type="datetime-local" name="expected_at"></label>
                <label class="full"><span>Notes</span><textarea name="notes"></textarea></label>
            </form>
            <hr>
            <form id="orderLineForm" class="form-grid">
                ${selectField('product_id', 'Produit', state.lookups.products, 'id', 'name', true)}
                <label class="hidden" id="orderLineVariantWrap"><span>Variante</span><select name="variant_id" id="orderLineVariant"><option value="">-</option></select></label>
                <label><span>Quantite</span><input type="number" name="quantity_ordered" min="1" required></label>
                <label><span>Prix unitaire</span><input type="number" name="unit_cost" min="0" step="0.01" required></label>
                <button type="submit" class="btn btn-soft">Ajouter la ligne</button>
            </form>
            <div id="orderItemsPreview">${renderDraftItemsTable()}</div>
            <button type="button" id="createOrderBtn" class="btn btn-primary">Creer la commande</button>
            <p id="orderFeedback" class="feedback"></p>
            <hr>
            <form id="orderStatusForm" class="form-grid">
                <label><span>Commande</span><select name="purchase_order_id" required><option value="">Choisir</option>${orderOptions}</select></label>
                <label><span>Nouveau statut</span><select name="status" required>
                    <option value="PENDING">En attente</option>
                    <option value="PARTIAL">Partielle</option>
                    <option value="RECEIVED">Recue</option>
                    <option value="CANCELLED">Annulee</option>
                </select></label>
                <button type="submit" class="btn btn-soft">Mettre a jour statut</button>
                <p id="orderStatusFeedback" class="feedback"></p>
            </form>
            <hr>
            <form id="poReceiptForm" class="form-grid">
                <label><span>Commande</span><select name="purchase_order_id" id="receiptOrderId" required><option value="">Choisir</option>${orderOptions}</select></label>
                <label><span>Emplacement (optionnel)</span>
                    <select name="location_id" id="receiptLocation" disabled>
                        <option value="">Choisis d'abord une commande</option>
                    </select></label>
                <small class="field-hint full">S'applique aux lignes receptionnees ci-dessous. Laisse vide pour ranger sans emplacement precis (comme avant).</small>
                <div id="receiptItemsContainer" class="full"><p class="muted">Choisis une commande pour voir ses lignes restantes.</p></div>
                <button type="submit" class="btn btn-primary">Receptionner les lignes cochees</button>
                <p id="poReceiptFeedback" class="feedback"></p>
            </form>
            ` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>

        <section class="panel">
            <div class="panel-head">
                <h4>${scope === 'open' ? 'Commandes achat en cours' : 'Commandes achat passees (recues ou annulees)'}</h4>
                ${renderPurchaseScopeToggle('purchase-orders', meta)}
            </div>
            ${renderSimpleTable(rows, [
                ['order_number', 'Numero'],
                ['status', 'Statut'],
                ['purchase_request_number', 'Demande liee', (value) => value ? sanitize(value) : '-'],
                ['supplier_name', 'Fournisseur'],
                ['warehouse_name', 'Entrepot'],
                ['total_amount', 'Montant', (value) => formatMoney(value)],
                ['ordered_at', 'Date'],
                ['id', 'Detail', (value) => `<button type="button" class="btn btn-soft" data-view-order="${value}">Voir le detail</button>`],
            ])}
            ${renderPaginationBar(meta, rows.length)}
        </section>
    `;

    setupPagination('purchase-orders', meta, renderPurchaseOrders);
    setupPurchaseScopeToggle('purchase-orders', renderPurchaseOrders);

    const lineForm = document.getElementById('orderLineForm');
    const itemsPreview = document.getElementById('orderItemsPreview');
    const orderLineProductSelect = lineForm?.elements.namedItem('product_id');
    const orderLineVariantSelect = document.getElementById('orderLineVariant');
    const orderLineVariantWrap = document.getElementById('orderLineVariantWrap');

    const refreshOrderLineVariants = async () => {
        const productId = orderLineProductSelect?.value;
        const product = (state.lookups.products ?? []).find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;
        orderLineVariantWrap?.classList.toggle('hidden', !hasVariants);
        orderLineVariantSelect.required = hasVariants;
        orderLineVariantSelect.innerHTML = '<option value="">-</option>';
        if (!hasVariants || !productId) {
            return;
        }
        orderLineVariantSelect.innerHTML = '<option value="">Choisir...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=5000`);
        const variants = normalizeRows(response);
        orderLineVariantSelect.innerHTML = '<option value="">Choisir...</option>' + variants.map((v) => {
            const descriptors = variantDescriptor(v);
            return `<option value="${v.id}">${sanitize(descriptors)} (stock: ${v.stock_total ?? 0})</option>`;
        }).join('');
    };
    orderLineProductSelect?.addEventListener('change', refreshOrderLineVariants);

    lineForm?.addEventListener('submit', (event) => {
        event.preventDefault();
        const data = new FormData(lineForm);
        const productId = Number(data.get('product_id'));
        const quantity = Number(data.get('quantity_ordered'));
        const unitCost = Number(data.get('unit_cost'));
        if (!productId || quantity <= 0 || Number.isNaN(unitCost)) {
            return;
        }
        const product = (state.lookups.products ?? []).find((p) => Number(p.id) === productId);
        if (Number(product?.has_variants) === 1 && !orderLineVariantSelect.value) {
            window.alert('Ce produit a des variantes : choisis-en une.');
            return;
        }
        const variantId = orderLineVariantSelect.value ? Number(orderLineVariantSelect.value) : null;
        const variantLabel = variantId
            ? ` (${sanitize(orderLineVariantSelect.options[orderLineVariantSelect.selectedIndex].textContent.split(' (stock:')[0])})`
            : '';
        draftItems.push({
            product_id: productId,
            variant_id: variantId,
            quantity_ordered: quantity,
            unit_cost: unitCost,
            product_label: (product?.name ?? `#${productId}`) + variantLabel,
        });
        itemsPreview.innerHTML = renderDraftItemsTable();
        lineForm.reset();
        refreshOrderLineVariants();
    });

    itemsPreview?.addEventListener('click', (event) => {
        const btn = event.target.closest('[data-remove-line]');
        if (!btn) {
            return;
        }
        draftItems.splice(Number(btn.dataset.removeLine), 1);
        itemsPreview.innerHTML = renderDraftItemsTable();
    });

    const headerForm = document.getElementById('orderHeaderForm');
    const feedback = document.getElementById('orderFeedback');
    const requestSelect = document.getElementById('orderRequestId');

    requestSelect?.addEventListener('change', async () => {
        const requestId = requestSelect.value;
        if (!requestId) {
            return;
        }

        try {
            // On recharge le detail (avec toutes ses lignes) car la liste ne
            // contient pas les articles demandes. Toutes les lignes de la
            // demande sont reprises dans le brouillon de la commande.
            const detail = await apiRequest(`/purchase-requests/${requestId}`);
            const items = detail?.data?.items ?? [];

            const warehouseField = headerForm.elements.namedItem('warehouse_id');
            if (warehouseField) {
                warehouseField.value = String(detail.data.warehouse_id);
            }

            draftItems.length = 0;
            for (const item of items) {
                const product = (state.lookups.products ?? []).find((p) => Number(p.id) === Number(item.product_id));
                const variantLabel = item.variant_id
                    ? ` (${variantDescriptor(item)})`
                    : '';
                draftItems.push({
                    product_id: Number(item.product_id),
                    variant_id: item.variant_id ? Number(item.variant_id) : null,
                    quantity_ordered: Number(item.quantity_requested),
                    unit_cost: item.preferred_unit_cost !== null && item.preferred_unit_cost !== undefined
                        ? Number(item.preferred_unit_cost)
                        : 0,
                    product_label: (product?.name ?? sanitize(item.product_name ?? `#${item.product_id}`)) + variantLabel,
                });
            }
            itemsPreview.innerHTML = renderDraftItemsTable();
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    document.getElementById('createOrderBtn')?.addEventListener('click', async () => {
        feedback.textContent = '';

        if (draftItems.length === 0) {
            feedback.textContent = 'Ajoute au moins une ligne produit.';
            feedback.classList.add('is-error');
            return;
        }

        const data = new FormData(headerForm);
        const requestId = data.get('purchase_request_id');
        const payload = {
            supplier_id: Number(data.get('supplier_id')),
            warehouse_id: Number(data.get('warehouse_id')),
            purchase_request_id: requestId ? Number(requestId) : null,
            expected_at: data.get('expected_at') ? String(data.get('expected_at')).replace('T', ' ') + ':00' : null,
            notes: String(data.get('notes') ?? ''),
            items: draftItems.map((item) => ({
                product_id: item.product_id,
                variant_id: item.variant_id ?? null,
                quantity_ordered: item.quantity_ordered,
                unit_cost: item.unit_cost,
            })),
        };

        try {
            await apiRequest('/purchase-orders', { method: 'POST', body: payload });
            // La demande d'achat liee (le cas echeant) vient de passer en
            // "Convertie" cote serveur: on rafraichit tout le module pour
            // qu'elle disparaisse de la liste des demandes selectionnables.
            await renderPurchaseOrders();
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    const statusForm = document.getElementById('orderStatusForm');
    const statusFeedback = document.getElementById('orderStatusFeedback');
    statusForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        statusFeedback.textContent = '';

        const data = new FormData(statusForm);
        const orderId = Number(data.get('purchase_order_id'));
        const status = String(data.get('status') ?? '');

        try {
            await apiRequest(`/purchase-orders/${orderId}/status`, {
                method: 'POST',
                body: { status },
            });
            await renderPurchaseOrders();
        } catch (error) {
            statusFeedback.textContent = error.message;
            statusFeedback.classList.add('is-error');
        }
    });

    const receiptForm = document.getElementById('poReceiptForm');
    const receiptFeedback = document.getElementById('poReceiptFeedback');
    const receiptOrderSelect = document.getElementById('receiptOrderId');
    const receiptItemsContainer = document.getElementById('receiptItemsContainer');
    const receiptLocationSelect = document.getElementById('receiptLocation');

    const loadReceiptItems = async (orderId) => {
        if (!orderId) {
            receiptItemsContainer.innerHTML = '<p class="muted">Choisis une commande pour voir ses lignes restantes.</p>';
            fillLocationOptions(receiptLocationSelect, '');
            return;
        }

        const orderResponse = await apiRequest(`/purchase-orders/${orderId}`);
        const order = orderResponse.data ?? {};
        // L'emplacement propose est celui de l'entrepot de LA COMMANDE (fixe
        // pour toute la reception, comme le warehouse_id) : pas de sens de
        // proposer un emplacement d'un autre entrepot.
        fillLocationOptions(receiptLocationSelect, order.warehouse_id ?? '');
        const remainingItems = (order.items ?? [])
            .map((item) => {
                const ordered = Number(item.quantity_ordered ?? 0);
                const received = Number(item.quantity_received ?? 0);
                return { ...item, remaining: ordered - received };
            })
            .filter((item) => item.remaining > 0);

        if (remainingItems.length === 0) {
            receiptItemsContainer.innerHTML = '<p class="muted">Toutes les lignes de cette commande sont deja receptionnees.</p>';
            return;
        }

        const rowsHtml = remainingItems.map((item) => `
            <tr>
                <td><input type="checkbox" data-receipt-check="${item.id}" checked></td>
                <td>${sanitize(item.product_name)}</td>
                <td>${item.remaining} restant(s)</td>
                <td><input type="number" data-receipt-qty="${item.id}" min="1" max="${item.remaining}" value="${item.remaining}"></td>
            </tr>
        `).join('');

        receiptItemsContainer.innerHTML = `
            <p class="muted">Toutes les lignes sont cochees et pre-remplies avec la quantite restante - decoche ou ajuste celles qui ne sont pas (encore) livrees, puis valide une seule fois.</p>
            <table class="simple-table">
                <thead><tr><th>Recevoir</th><th>Produit</th><th>Reste a recevoir</th><th>Quantite recue</th></tr></thead>
                <tbody>${rowsHtml}</tbody>
            </table>
        `;
    };

    receiptOrderSelect?.addEventListener('change', async () => {
        await loadReceiptItems(Number(receiptOrderSelect.value));
    });

    receiptForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        receiptFeedback.textContent = '';

        const orderId = Number(receiptOrderSelect.value);
        const checkboxes = receiptItemsContainer.querySelectorAll('[data-receipt-check]:checked');
        const locationId = receiptLocationSelect?.value ? Number(receiptLocationSelect.value) : null;

        const items = Array.from(checkboxes).map((checkbox) => {
            const itemId = checkbox.getAttribute('data-receipt-check');
            const qtyInput = receiptItemsContainer.querySelector(`[data-receipt-qty="${itemId}"]`);
            return {
                item_id: Number(itemId),
                quantity_received: Number(qtyInput.value),
            };
        }).filter((item) => item.quantity_received > 0);

        if (!orderId || items.length === 0) {
            receiptFeedback.textContent = 'Coche au moins une ligne a receptionner.';
            receiptFeedback.classList.add('is-error');
            return;
        }

        try {
            await apiRequest(`/purchase-orders/${orderId}/receive`, {
                method: 'POST',
                body: { items, location_id: locationId },
            });
            await renderPurchaseOrders();
        } catch (error) {
            receiptFeedback.textContent = error.message;
            receiptFeedback.classList.add('is-error');
        }
    });

    root.querySelectorAll('[data-view-order]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            try {
                const detail = await apiRequest(`/purchase-orders/${btn.dataset.viewOrder}`);
                const order = detail.data;
                const itemsHtml = (order.items ?? []).map((item) => `
                    <tr>
                        <td>${sanitize(item.sku)}</td>
                        <td>${sanitize(item.product_name)}</td>
                        <td>${Number(item.quantity_ordered)}</td>
                        <td>${Number(item.quantity_received ?? 0)}</td>
                        <td>${formatMoney(item.unit_cost)}</td>
                    </tr>
                `).join('');
                showModal(`Commande ${order.order_number}`, `
                    <p><strong>Statut:</strong> ${sanitize(order.status)}</p>
                    <p><strong>Fournisseur:</strong> ${sanitize(order.supplier_name)}</p>
                    <p><strong>Entrepot:</strong> ${sanitize(order.warehouse_name)}</p>
                    <p><strong>Montant total:</strong> ${formatMoney(order.total_amount)}</p>
                    ${order.notes ? `<p><strong>Notes:</strong> ${sanitize(order.notes)}</p>` : ''}
                    <table class="simple-table">
                        <thead><tr><th>SKU</th><th>Produit</th><th>Qte commandee</th><th>Qte recue</th><th>Prix unitaire</th></tr></thead>
                        <tbody>${itemsHtml}</tbody>
                    </table>
                `);
            } catch (error) {
                window.alert(error.message);
            }
        });
    });
}

async function renderReports() {
    // Statistiques (style page d'accueil) + exports rapides en CSV.
    const root = document.getElementById('appContent');

    const response = await apiRequest('/reports/sales-stats' + toQueryString({ year: state.reportsYear || '' }));
    const data = response.data;
    // Le backend peut renvoyer une annee differente de celle demandee (ex:
    // premier chargement, aucune annee choisie) - on realigne l'etat pour
    // que le selecteur affiche la bonne valeur des le premier rendu.
    state.reportsYear = data.year;
    if (!state.reportsMonth) {
        state.reportsMonth = new Date().getMonth() + 1;
    }

    const summary = data.summary ?? { revenue: 0, deliveries_count: 0, average_basket: 0, customers_count: 0 };
    const availableYears = Array.isArray(data.available_years) && data.available_years.length > 0
        ? data.available_years
        : [data.year];

    const kpis = [
        { label: 'Chiffre d\'affaires', value: formatMoney(summary.revenue), icon: 'bi-cash-stack', theme: 'kpi-teal' },
        { label: 'Livraisons', value: summary.deliveries_count, icon: 'bi-truck', theme: 'kpi-blue' },
        { label: 'Panier moyen', value: formatMoney(summary.average_basket), icon: 'bi-basket', theme: 'kpi-orange' },
        { label: 'Clients actifs', value: summary.customers_count, icon: 'bi-people', theme: 'kpi-violet' },
    ];

    root.innerHTML = `
        <section class="panel">
            <div class="panel-actions" style="justify-content: space-between; align-items: center;">
                <h4 style="margin: 0;">Statistiques</h4>
                <label class="field-inline">
                    Annee
                    <select id="reportsYearSelect">
                        ${availableYears.map((y) => `<option value="${y}" ${y === data.year ? 'selected' : ''}>${y}</option>`).join('')}
                    </select>
                </label>
            </div>

            <div class="panel-actions">
                <button class="btn btn-soft" id="reportsYearCsvBtn" data-report="/reports/sales-stats-year.csv${toQueryString({ year: data.year })}" data-name="statistiques-${data.year}.csv">Telecharger les stats de l'annee ${data.year} (CSV)</button>
                <label class="field-inline">
                    Mois
                    <select id="reportsMonthSelect">
                        ${MONTH_LABELS_FULL_FR.map((label, idx) => `<option value="${idx + 1}" ${idx + 1 === state.reportsMonth ? 'selected' : ''}>${label}</option>`).join('')}
                    </select>
                </label>
                <button class="btn btn-soft" id="reportsMonthCsvBtn" data-report="/reports/sales-stats-month.csv${toQueryString({ year: data.year, month: state.reportsMonth })}" data-name="statistiques-${data.year}-${String(state.reportsMonth).padStart(2, '0')}.csv">Telecharger les stats du mois (CSV)</button>
            </div>

            <div class="kpi-grid">
                ${kpis.map((item) => `
                    <article class="kpi-card ${item.theme}">
                        <div class="kpi-head"><strong>${item.label}</strong><i class="bi ${item.icon}"></i></div>
                        <p class="kpi-value">${sanitize(item.value)}</p>
                        <p class="kpi-label">Annee ${data.year}</p>
                    </article>
                `).join('')}
            </div>
        </section>

        <div class="chart-grid">
            <section class="panel">
                <h4>Chiffre d'affaires par mois</h4>
                <p class="dashboard-subtitle">Ventes livrees (${data.year})</p>
                <div class="chart-canvas-wrap"><canvas id="reportsMonthlyChart"></canvas></div>
            </section>
            <section class="panel">
                <h4>Chiffre d'affaires par annee</h4>
                <p class="dashboard-subtitle">Tendance sur les dernieres annees</p>
                <div class="chart-canvas-wrap"><canvas id="reportsYearlyChart"></canvas></div>
            </section>
        </div>

        <div class="panel-grid">
            <section class="panel">
                <h4>Meilleurs clients</h4>
                ${renderSimpleTable(data.top_customers ?? [], [
                    ['name', 'Client'],
                    ['revenue', 'CA', (value) => formatMoney(value)],
                    ['deliveries_count', 'Livraisons'],
                ])}
            </section>

            <section class="panel">
                <h4>Articles les plus vendus</h4>
                ${renderSimpleTable(data.top_products ?? [], [
                    ['sku', 'SKU'],
                    ['name', 'Produit'],
                    ['qty', 'Quantite vendue'],
                    ['revenue', 'CA', (value) => formatMoney(value)],
                ])}
            </section>
        </div>

        <section class="panel">
            <h4>Rapport complet</h4>
            <p class="muted">Telecharge en une fois un fichier ZIP contenant tous les exports ci-dessous.</p>
            <div class="panel-actions">
                <button class="btn btn-primary" id="fullReportBtn" data-report="/reports/full.zip" data-name="rapport-complet.zip">Rapport complet (ZIP)</button>
                <p id="fullReportFeedback" class="feedback"></p>
            </div>
        </section>
        <section class="panel">
            <h4>Exports CSV par module</h4>
            <div class="panel-actions">
                <button class="btn btn-soft" data-report="/reports/stock.csv" data-name="stock-report.csv">Export stock</button>
                <button class="btn btn-soft" data-report="/reports/movements.csv" data-name="movements-report.csv">Export mouvements</button>
                <button class="btn btn-soft" data-report="/reports/purchases.csv" data-name="purchases-report.csv">Export achats</button>
                <button class="btn btn-soft" data-report="/reports/products.csv" data-name="products-report.csv">Export produits</button>
                <button class="btn btn-soft" data-report="/reports/suppliers.csv" data-name="suppliers-report.csv">Export fournisseurs</button>
                <button class="btn btn-soft" data-report="/reports/customers.csv" data-name="customers-report.csv">Export clients</button>
                <button class="btn btn-soft" data-report="/reports/deliveries.csv" data-name="deliveries-report.csv">Export livraisons</button>
                <button class="btn btn-soft" data-report="/reports/inventories.csv" data-name="inventories-report.csv">Export inventaires</button>
            </div>
        </section>
    `;

    renderReportsCharts(data);

    const yearSelect = document.getElementById('reportsYearSelect');
    if (yearSelect) {
        yearSelect.addEventListener('change', async () => {
            state.reportsYear = Number(yearSelect.value);
            await renderReports();
        });
    }

    const monthSelect = document.getElementById('reportsMonthSelect');
    if (monthSelect) {
        monthSelect.addEventListener('change', async () => {
            state.reportsMonth = Number(monthSelect.value);
            await renderReports();
        });
    }

    const fullReportFeedback = document.getElementById('fullReportFeedback');

    root.querySelectorAll('[data-report]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            const isFull = btn.id === 'fullReportBtn';
            btn.disabled = true;
            if (isFull) fullReportFeedback.textContent = 'Generation du rapport en cours...';
            try {
                await downloadCsv(btn.getAttribute('data-report'), btn.getAttribute('data-name') ?? 'report.csv');
                if (isFull) fullReportFeedback.textContent = '';
            } catch (error) {
                if (isFull) {
                    fullReportFeedback.textContent = error.message;
                    fullReportFeedback.classList.add('is-error');
                } else {
                    window.alert(error.message);
                }
            } finally {
                btn.disabled = false;
            }
        });
    });
}

function renderReportsCharts(data) {
    // Si Chart.js n'est pas charge, on garde une page stable sans casser l'UI.
    if (typeof window.Chart === 'undefined') {
        return;
    }

    destroyReportsCharts();

    const monthly = Array.isArray(data.monthly_revenue) ? data.monthly_revenue : [];
    const monthlyCanvas = document.getElementById('reportsMonthlyChart');
    if (monthlyCanvas) {
        reportsCharts.monthlyRevenue = new window.Chart(monthlyCanvas, {
            type: 'bar',
            data: {
                labels: monthly.map((row) => MONTH_LABELS_FR[(Number(row.month) || 1) - 1] ?? row.month),
                datasets: [{
                    label: 'CA',
                    data: monthly.map((row) => Number(row.revenue ?? 0)),
                    backgroundColor: '#186bb2',
                    borderRadius: 8,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    x: { grid: { display: false } },
                    y: { beginAtZero: true, grid: { color: 'rgba(16,34,45,0.08)' } },
                },
            },
        });
    }

    const yearly = Array.isArray(data.yearly_revenue) ? data.yearly_revenue : [];
    const yearlyCanvas = document.getElementById('reportsYearlyChart');
    if (yearlyCanvas) {
        reportsCharts.yearlyRevenue = new window.Chart(yearlyCanvas, {
            type: 'line',
            data: {
                labels: yearly.map((row) => String(row.year)),
                datasets: [{
                    label: 'CA',
                    data: yearly.map((row) => Number(row.revenue ?? 0)),
                    borderColor: '#0f8f74',
                    backgroundColor: 'rgba(15, 143, 116, 0.16)',
                    tension: 0.3,
                    fill: true,
                    borderWidth: 2,
                    pointRadius: 3,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: {
                    x: { grid: { color: 'rgba(16,34,45,0.08)' } },
                    y: { beginAtZero: true, grid: { color: 'rgba(16,34,45,0.08)' } },
                },
            },
        });
    }
}

function destroyReportsCharts() {
    if (reportsCharts.monthlyRevenue) {
        reportsCharts.monthlyRevenue.destroy();
        reportsCharts.monthlyRevenue = null;
    }
    if (reportsCharts.yearlyRevenue) {
        reportsCharts.yearlyRevenue.destroy();
        reportsCharts.yearlyRevenue = null;
    }
}

async function renderImports() {
    // Import CSV guide pour charger vite les donnees.
    const root = document.getElementById('appContent');
    const writable = canWrite('imports');
    if (!writable) {
        root.innerHTML = '<section class="panel"><h4>Importations CSV</h4><p class="muted">Acces reserve aux administrateurs.</p></section>';
        return;
    }

    const jobsResponse = await apiRequest('/import-jobs');
    const jobs = normalizeRows(jobsResponse);

    root.innerHTML = `
        <section class="panel">
            <h4>Importations CSV multi-entites</h4>
            ${writable ? `
            <form id="importForm" class="form-grid">
                <label><span>Entite</span><select name="entity" required>
                    <option value="products">Produits</option>
                    <option value="suppliers">Fournisseurs</option>
                    <option value="customers">Clients</option>
                    <option value="initial-stocks">Stocks initiaux</option>
                </select></label>
                <label><span>Fichier CSV</span><input type="file" name="file" accept=".csv,text/csv" required></label>
                <button type="submit" class="btn btn-primary">Importer</button>
                <button type="button" class="btn btn-soft" id="downloadTemplateBtn">Telecharger le modele de l'entite choisie</button>
                <p id="importFeedback" class="feedback"></p>
            </form>
            <div id="importTemplateHelp">${renderImportTemplateHelp('products')}</div>
            ` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>
        <section class="panel">
            <h4>Historique imports</h4>
            ${renderSimpleTable(jobs, [
                ['id', 'ID'],
                ['entity_type', 'Entite'],
                ['file_name', 'Fichier'],
                ['status', 'Statut'],
                ['total_rows', 'Total'],
                ['success_rows', 'OK'],
                ['failed_rows', 'KO'],
                ['created_at', 'Date'],
            ])}
        </section>
    `;

    const form = document.getElementById('importForm');
    const feedback = document.getElementById('importFeedback');

    // L'aide affichee suit l'entite choisie : les colonnes attendues ne sont
    // pas les memes, et une liste unique de tous les en-tetes de toutes les
    // entites (ce qui etait affiche avant) n'aide personne.
    const entitySelect = form?.elements.namedItem('entity');
    const helpBox = document.getElementById('importTemplateHelp');
    entitySelect?.addEventListener('change', () => {
        if (helpBox) {
            helpBox.innerHTML = renderImportTemplateHelp(String(entitySelect.value));
        }
    });

    document.getElementById('downloadTemplateBtn')?.addEventListener('click', () => {
        downloadImportTemplate(String(entitySelect?.value ?? 'products'));
    });

    form?.addEventListener('submit', async (event) => {
        event.preventDefault();
        feedback.textContent = '';

        const data = new FormData(form);
        const entity = String(data.get('entity') ?? '');
        const file = data.get('file');
        if (!(file instanceof File) || !file.name) {
            feedback.textContent = 'Choisis un fichier CSV';
            feedback.classList.add('is-error');
            return;
        }

        const payload = new FormData();
        payload.append('file', file);

        try {
            const response = await uploadRequest(`/imports/${entity}`, payload);
            const summary = response.data ?? {};
            feedback.classList.remove('is-error');
            feedback.textContent = `Import termine: ${summary.success_rows ?? 0} OK / ${summary.failed_rows ?? 0} KO`;
            await renderImports();
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });
}

// Colonnes attendues par l'import CSV, par entite. Source de verite cote
// interface : elles doivent correspondre exactement a ce que lit
// ImportService::importRow (backend). Les colonnes obligatoires sont marquees
// required, les autres peuvent etre laissees vides ou absentes.
const IMPORT_TEMPLATES = {
    products: {
        label: 'Produits',
        columns: [
            { key: 'sku', required: true, help: 'Reference unique. Un SKU deja present met le produit a jour.', sample: 'MAT-PLAN-001' },
            { key: 'name', required: true, help: 'Nom du produit.', sample: 'Plan de travail stratifie' },
            { key: 'category_name', required: true, help: 'Nom de la categorie. Creee automatiquement si elle n\'existe pas.', sample: 'Materiel' },
            { key: 'supplier_name', required: false, help: 'Nom du fournisseur. Cree automatiquement si besoin.', sample: 'Bois Diffusion' },
            { key: 'barcode', required: false, help: 'Code barre (EAN, UPC...).', sample: '3760001234567' },
            { key: 'description', required: false, help: 'Description libre.', sample: 'Chant ABS, epaisseur 38 mm' },
            { key: 'unit_price', required: false, help: 'Prix de vente. La virgule decimale est acceptee.', sample: '89,90' },
            { key: 'cost_price', required: false, help: 'Prix d\'achat.', sample: '54,30' },
            { key: 'reorder_level', required: false, help: 'Seuil de reapprovisionnement (entier).', sample: '5' },
            { key: 'status', required: false, help: 'ACTIVE ou INACTIVE. Vide = ACTIVE.', sample: 'ACTIVE' },
        ],
    },
    suppliers: {
        label: 'Fournisseurs',
        columns: [
            { key: 'name', required: true, help: 'Nom du fournisseur. Un nom deja present est mis a jour.', sample: 'Bois Diffusion' },
            { key: 'contact_name', required: false, help: 'Personne a contacter.', sample: 'Marie Dupont' },
            { key: 'phone', required: false, help: 'Telephone.', sample: '+32 81 00 00 00' },
            { key: 'email', required: false, help: 'Adresse e-mail.', sample: 'contact@bois-diffusion.be' },
            { key: 'address', required: false, help: 'Adresse postale.', sample: 'Rue du Chantier 12, 5000 Namur' },
        ],
    },
    customers: {
        label: 'Clients',
        columns: [
            { key: 'name', required: true, help: 'Nom du client.', sample: 'Menuiserie Lambert' },
            { key: 'code', required: false, help: 'Code client. S\'il est renseigne, un code deja present est mis a jour ; sinon une nouvelle fiche est creee a chaque import.', sample: 'CLI-001' },
            { key: 'email', required: false, help: 'Adresse e-mail.', sample: 'info@menuiserie-lambert.be' },
            { key: 'phone', required: false, help: 'Telephone.', sample: '+32 2 000 00 00' },
            { key: 'address', required: false, help: 'Adresse postale.', sample: 'Chaussee de Wavre 300, 1040 Bruxelles' },
            { key: 'status', required: false, help: 'ACTIVE ou INACTIVE. Vide = ACTIVE.', sample: 'ACTIVE' },
        ],
    },
    'initial-stocks': {
        label: 'Stocks initiaux',
        columns: [
            { key: 'sku', required: true, help: 'SKU d\'un produit DEJA existant. Importe les produits d\'abord.', sample: 'MAT-PLAN-001' },
            { key: 'warehouse_code', required: true, help: 'Code de l\'entrepot (ecran Entrepots), pas son nom.', sample: 'WH-002' },
            { key: 'quantity', required: false, help: 'Quantite. REMPLACE le stock existant sans emplacement precis, ce n\'est pas un ajout.', sample: '12' },
        ],
    },
};

function renderImportTemplateHelp(entity) {
    const template = IMPORT_TEMPLATES[entity] ?? IMPORT_TEMPLATES.products;
    const rows = template.columns.map((column) => `
        <tr>
            <td><code>${sanitize(column.key)}</code></td>
            <td>${column.required ? '<strong>obligatoire</strong>' : 'facultative'}</td>
            <td>${sanitize(column.help)}</td>
            <td>${sanitize(column.sample)}</td>
        </tr>
    `).join('');

    return `
        <p class="muted">
            Colonnes attendues pour <strong>${sanitize(template.label)}</strong>. L'ordre des colonnes
            n'a pas d'importance, les colonnes facultatives peuvent etre absentes.
            Separateur point-virgule ou virgule, fichier en UTF-8
            (dans Excel : Fichier &gt; Enregistrer sous &gt; CSV UTF-8).
        </p>
        <div class="table-wrap">
            <table class="data-table">
                <thead><tr><th>Colonne</th><th>Obligatoire</th><th>Contenu</th><th>Exemple</th></tr></thead>
                <tbody>${rows}</tbody>
            </table>
        </div>
    `;
}

/**
 * Genere et telecharge le modele CSV de l'entite choisie : en-tetes exacts
 * plus une ligne d'exemple. Entierement cote navigateur, aucune route
 * supplementaire cote serveur.
 */
function downloadImportTemplate(entity) {
    const template = IMPORT_TEMPLATES[entity] ?? IMPORT_TEMPLATES.products;
    const escape = (value) => (/[";\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value);
    const header = template.columns.map((column) => escape(column.key)).join(';');
    const sample = template.columns.map((column) => escape(column.sample)).join(';');

    // BOM UTF-8 : sans lui, Excel ouvre le fichier en Windows-1252 et casse
    // les accents. Le lecteur CSV du backend retire ce BOM a la lecture.
    const content = `\uFEFF${header}\n${sample}\n`;
    const blob = new Blob([content], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `modele-import-${entity}.csv`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
}

async function renderProductDetail(productId) {
    // Fiche produit multi-onglets (stock, documents, etiquette).
    //
    // "Media" et "Pieces jointes" etaient jusqu'ici deux onglets separes,
    // avec chacun son propre formulaire d'envoi et sa propre liste - alors
    // qu'ils font exactement la meme chose du point de vue de l'utilisateur
    // (joindre un fichier a ce produit). Fusionnes en un seul onglet
    // "Documents", sur la base du systeme "Media" (qui avait deja
    // l'apercu miniature des images). Le systeme "Pieces jointes" reste
    // disponible cote serveur (il est generique, pas limite aux produits)
    // pour un usage futur ailleurs dans l'application, mais n'est plus
    // propose ici pour eviter le doublon.
    const pane = document.getElementById('productDetailPane');
    if (!pane) {
        return;
    }

    const [productResponse, movementResponse, costLayersResponse] = await Promise.all([
        apiRequest(`/products/${productId}`),
        apiRequest(`/stock/movements?product_id=${productId}&per_page=20`),
        apiRequest(`/products/${productId}/cost-layers`).catch(() => null),
    ]);

    const product = productResponse.data;
    const movements = normalizeRows(movementResponse);
    const costLayers = normalizeRows(costLayersResponse);
    const isFifo = String(product.valuation_method ?? '').toUpperCase() === 'FIFO';
    const media = Array.isArray(product?.media) ? product.media : [];
    const stockRows = Array.isArray(product?.stock_by_warehouse) ? product.stock_by_warehouse : [];
    const canManageProduct = canWrite('products');
    const canMoveStock = canWrite('movements');

    pane.innerHTML = `
        <div class="panel-head">
            <h4>Fiche produit: ${sanitize(product.name)} (${sanitize(product.sku)})</h4>
        </div>
        <div class="tabs" id="productTabs">
            <button class="btn btn-soft is-tab-active" data-tab="info">Infos</button>
            <button class="btn btn-soft" data-tab="stock">Stock</button>
            <button class="btn btn-soft" data-tab="moves">Mouvements</button>
            <button class="btn btn-soft" data-tab="media">Documents</button>
            <button class="btn btn-soft" data-tab="label">Etiquette</button>
        </div>
        <div class="tab-panel" data-tab-panel="info">
            <div class="cards-grid">
                <article class="metric-card"><p>Categorie</p><h3>${sanitize(product.category_name)}</h3></article>
                <article class="metric-card"><p>Fournisseur</p><h3>${sanitize(product.supplier_name)}</h3></article>
                <article class="metric-card"><p>Stock total</p><h3>${sanitize(product.stock_total)}</h3></article>
                <article class="metric-card"><p>Prix vente</p><h3>${formatMoney(product.unit_price)}</h3></article>
                <article class="metric-card"><p>Prix achat (${sanitize(product.valuation_method)})</p><h3>${formatMoney(product.cost_price)}</h3></article>
                <article class="metric-card"><p>Code-barres</p><h3>${sanitize(product.barcode || '-')}</h3></article>
            </div>
            <p class="muted">${sanitize(product.description)}</p>
            <p>${renderTagBadges(product.tags)}</p>
            <div class="hint-box">
                ${isFifo
                    ? "Valorisation FIFO : le prix d'achat ci-dessus est la moyenne des lots encore en stock (voir ci-dessous). Chaque sortie consomme d'abord le lot le plus ancien."
                    : "Valorisation CUMP : le prix d'achat ci-dessus est recalcule automatiquement en moyenne ponderee a chaque reception de stock (commande fournisseur ou entree manuelle avec un cout)."}
            </div>
            ${isFifo ? `
            <h4 style="margin-top: 1rem;">Lots en stock (du plus ancien au plus recent)</h4>
            ${costLayers.length === 0
                ? '<p class="muted">Aucun lot en stock actuellement.</p>'
                : renderSimpleTable(costLayers, [
                    ['created_at', 'Reçu le'],
                    ['quantity_remaining', 'Quantite restante'],
                    ['unit_cost', 'Cout unitaire', (value) => formatMoney(value)],
                    ['source_type', 'Origine', (value) => sanitize(localizeValue(value, 'reference_type'))],
                ])}
            ` : ''}
        </div>
        <div class="tab-panel hidden" data-tab-panel="stock">
            ${renderProductLocationSummary(stockRows)}
            ${renderSimpleTable(stockRows, [
                ['warehouse_code', 'Code'],
                ['warehouse_name', 'Entrepot'],
                ['variant_label', 'Variante'],
                ['zone_name', 'Zone', (value) => sanitize(value || '-')],
                ['location_code', 'Emplacement', (value, row) => sanitize(
                    value ? (row.location_description ? `${value} - ${row.location_description}` : value) : 'Non precise')],
                ['quantity', 'Quantite'],
                ['reserved_quantity', 'Reserve'],
            ])}
            <div class="panel-actions">
                <button type="button" class="btn btn-soft" id="gotoProductSerialsBtn">Numeros de serie de ce produit</button>
                ${Number(product.has_variants) === 1 ? `<button type="button" class="btn btn-soft" id="gotoProductVariantsBtn">Gerer les variantes de ce produit</button>` : ''}
            </div>
            ${canMoveStock ? `
            <form id="productMoveForm" class="form-grid">
                ${selectField('warehouse_id', 'Entrepot source', state.lookups.warehouses, 'id', 'name', true)}
                <label><span>Emplacement source (optionnel)</span>
                    <select name="source_location_id" id="productMoveSourceLocation" disabled>
                        <option value="">Choisis d'abord un entrepot</option>
                    </select></label>
                ${selectField('destination_warehouse_id', 'Entrepot destination (vide = transfert dans le meme entrepot)', state.lookups.warehouses, 'id', 'name', false)}
                <label><span>Emplacement destination (optionnel)</span>
                    <select name="destination_location_id" id="productMoveDestinationLocation" disabled>
                        <option value="">Choisis d'abord un entrepot</option>
                    </select></label>
                <div class="full ${Number(product.has_variants) === 1 ? '' : 'hidden'}" id="productMoveVariantWrap">
                    <label><span>Variante</span><select name="variant_id" id="productMoveVariantSelect" ${Number(product.has_variants) === 1 ? 'required' : ''}></select></label>
                    <small class="field-hint">Ce produit utilise des variantes : choisis celle concernee par ce mouvement.</small>
                    <div class="hidden" id="productMoveMultiToggleWrap" style="margin-top: 0.6rem;">
                        <button type="button" class="btn btn-soft" id="productMoveMultiToggle">Deplacer plusieurs variantes a la fois &rarr;</button>
                    </div>
                </div>
                <div class="full hidden" id="productMoveVariantMultiWrap">
                    <span>Variantes a deplacer (toutes cochees par defaut)</span>
                    <div id="productMoveVariantMultiList" class="serial-checklist"></div>
                    <small class="field-hint">Decoche celles a ne pas deplacer. Pour chaque variante cochee, la quantite disponible a l'emplacement source choisi (ou dans tout l'entrepot si aucun emplacement precis) est deplacee automatiquement.</small>
                    <button type="button" class="btn btn-soft" id="productMoveMultiBackBtn">&larr; Revenir a une seule variante</button>
                </div>
                <label><span>Type</span><select name="type" required>
                    <option value="IN">Entree</option>
                    <option value="OUT">Sortie</option>
                    <option value="ADJUSTMENT">Ajustement</option>
                    <option value="TRANSFER">Transfert</option>
                </select></label>
                <div id="productMoveQuantityWrap">
                    <label><span>Quantite</span><input type="number" min="1" name="quantity" id="productMoveQuantityInput" required></label>
                </div>
                ${selectField('customer_id', 'Client (sortie)', state.lookups.customers, 'id', 'name', false)}
                <div class="full" id="productMoveSerialsInWrap">
                    <label>
                        <span>Numeros de serie (optionnel, un par ligne)</span>
                        <textarea name="serial_numbers" rows="3" placeholder="SN-00012345&#10;SN-00012346"></textarea>
                    </label>
                    <small class="field-hint">Uniquement pour une entree (IN). Si renseigne, le nombre de lignes doit correspondre a la quantite.</small>
                </div>
                <div class="full hidden" id="productMoveSerialsOutWrap">
                    <span>Numeros de serie a sortir (optionnel)</span>
                    <div id="productMoveSerialOutList" class="serial-checklist"></div>
                    <small class="field-hint">Coche les exemplaires precis qui sortent. Si des cases sont cochees, leur nombre doit correspondre a la quantite. Ils seront marques "sorti" automatiquement.</small>
                </div>
                <label><span>Motif (optionnel)</span><input type="text" name="reason_code" list="reasonCodeSuggestions" placeholder="Ex: Casse, Perte, Correction"></label>
                <datalist id="reasonCodeSuggestions">
                    <option value="Casse">
                    <option value="Perte">
                    <option value="Vol">
                    <option value="Correction inventaire">
                    <option value="Retour client">
                    <option value="Echantillon">
                    <option value="Demonstration">
                </datalist>
                <button type="submit" class="btn btn-primary">Creer mouvement</button>
                <p class="feedback" id="productMoveFeedback"></p>
            </form>` : '<p class="muted">Pas de droit ecriture mouvement.</p>'}
        </div>
        <div class="tab-panel hidden" data-tab-panel="moves">
            ${renderSimpleTable(movements, [
                ['created_at', 'Date'],
                ['type', 'Type'],
                ['variant_sku', 'Variante', (v, row) => (row.variant_id ? sanitize(variantDescriptor(row)) : '-')],
                ['quantity', 'Quantite'],
                ['warehouse_name', 'Source'],
                ['source_location_code', 'Empl. source'],
                ['destination_warehouse_name', 'Destination'],
                ['destination_location_code', 'Empl. dest.'],
                ['customer_name', 'Client'],
                ['reason_code', 'Motif'],
                ['moved_by_name', 'Par'],
            ])}
        </div>
        <div class="tab-panel hidden" data-tab-panel="media">
            ${canManageProduct ? `
            <form id="productMediaUploadForm" class="form-grid">
                <label><span>Fichier</span><input type="file" name="file" accept="${UPLOAD_ACCEPT_ATTR}" required></label>
                <small class="field-hint full">${UPLOAD_HINT_TEXT}</small>
                <button type="submit" class="btn btn-primary">Televerser un document</button>
                <p class="feedback" id="mediaUploadFeedback"></p>
            </form>` : '<p class="muted">Pas de droit upload document.</p>'}
            ${renderDownloadTable(media, 'media')}
        </div>
        <div class="tab-panel hidden" data-tab-panel="label">
            <div id="barcodePreview" class="label-preview muted">Chargement etiquette...</div>
            <div class="panel-actions">
                <button class="btn btn-soft" id="refreshLabelBtn">Regenerer</button>
                <button class="btn btn-primary" id="printLabelBtn">Imprimer</button>
            </div>
        </div>
    `;

    pane.querySelectorAll('#productTabs [data-tab]').forEach((button) => {
        button.addEventListener('click', () => {
            const tab = button.getAttribute('data-tab');
            pane.querySelectorAll('#productTabs [data-tab]').forEach((btn) => btn.classList.remove('is-tab-active'));
            button.classList.add('is-tab-active');
            pane.querySelectorAll('[data-tab-panel]').forEach((panel) => {
                panel.classList.toggle('hidden', panel.getAttribute('data-tab-panel') !== tab);
            });
        });
    });

    const moveForm = document.getElementById('productMoveForm');
    const moveTypeSelect = moveForm?.elements.namedItem('type');
    const moveWarehouseSelect = moveForm?.elements.namedItem('warehouse_id');
    const productMoveSerialsInWrap = document.getElementById('productMoveSerialsInWrap');
    const productMoveSerialsOutWrap = document.getElementById('productMoveSerialsOutWrap');
    const productMoveSerialOutList = document.getElementById('productMoveSerialOutList');
    const productMoveVariantSelect = document.getElementById('productMoveVariantSelect');
    const productMoveMultiToggleWrap = document.getElementById('productMoveMultiToggleWrap');
    const productMoveMultiToggle = document.getElementById('productMoveMultiToggle');
    const productMoveVariantMultiWrap = document.getElementById('productMoveVariantMultiWrap');
    const productMoveVariantMultiList = document.getElementById('productMoveVariantMultiList');
    const productMoveMultiBackBtn = document.getElementById('productMoveMultiBackBtn');
    const productMoveQuantityWrap = document.getElementById('productMoveQuantityWrap');
    const productMoveQuantityInput = document.getElementById('productMoveQuantityInput');
    let productMoveAvailableOutSerialCount = 0;
    let productMoveMultiMode = false;
    let productMoveLastVariants = [];

    const isProductMoveMultiCapableType = () => ['OUT', 'TRANSFER'].includes(String(moveTypeSelect?.value ?? ''));

    const loadProductMoveMultiVariantChecklist = () => {
        if (!productMoveVariantMultiList) {
            return;
        }
        const availability = computeVariantAvailability(
            stockRows,
            moveWarehouseSelect?.value ?? '',
            document.getElementById('productMoveSourceLocation')?.value ?? ''
        );
        productMoveVariantMultiList.innerHTML = productMoveLastVariants.length === 0
            ? '<p class="muted">Aucune variante active pour ce produit</p>'
            : productMoveLastVariants.map((v) => {
                const available = availability.get(String(v.id)) ?? 0;
                // Toutes cochees par defaut : voir la meme remarque sur
                // l'ecran Mouvements.
                return `
                    <label class="checklist-item">
                        <input type="checkbox" class="product-move-variant-multi-checkbox" value="${v.id}" data-available="${available}" ${available <= 0 ? 'disabled' : 'checked'}>
                        ${sanitize(variantDescriptor(v))} (disponible ici : ${available})
                    </label>
                `;
            }).join('');
    };

    const applyProductMoveVariantMode = () => {
        if (Number(product.has_variants) !== 1) {
            return;
        }
        const multiCapable = isProductMoveMultiCapableType();
        productMoveMultiToggleWrap?.classList.toggle('hidden', !multiCapable);
        if (!multiCapable && productMoveMultiMode) {
            productMoveMultiMode = false;
        }

        document.getElementById('productMoveVariantWrap')?.classList.toggle('hidden', productMoveMultiMode);
        if (productMoveVariantSelect) {
            productMoveVariantSelect.required = !productMoveMultiMode;
        }
        productMoveVariantMultiWrap?.classList.toggle('hidden', !productMoveMultiMode);
        productMoveQuantityWrap?.classList.toggle('hidden', productMoveMultiMode);
        if (productMoveQuantityInput) {
            productMoveQuantityInput.required = !productMoveMultiMode;
        }

        if (productMoveMultiMode) {
            loadProductMoveMultiVariantChecklist();
        }
    };

    productMoveMultiToggle?.addEventListener('click', () => {
        productMoveMultiMode = true;
        applyProductMoveVariantMode();
    });
    productMoveMultiBackBtn?.addEventListener('click', () => {
        productMoveMultiMode = false;
        applyProductMoveVariantMode();
    });

    const loadProductMoveVariantOptions = async () => {
        if (!productMoveVariantSelect || Number(product.has_variants) !== 1) {
            return;
        }
        productMoveVariantSelect.innerHTML = '<option value="">Chargement...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=5000`);
        const variants = normalizeRows(response);
        productMoveLastVariants = variants;
        productMoveVariantSelect.innerHTML = variants.length === 0
            ? '<option value="">Aucune variante active pour ce produit</option>'
            : '<option value="">Choisir...</option>' + variants.map((v) => {
                const descriptors = variantDescriptor(v);
                return `<option value="${v.id}">${sanitize(descriptors)} (stock: ${v.stock_total ?? 0})</option>`;
            }).join('');
        applyProductMoveVariantMode();
    };

    const loadProductMoveOutSerialOptions = async () => {
        if (!productMoveSerialOutList || moveTypeSelect?.value !== 'OUT') {
            return;
        }
        const warehouseId = moveWarehouseSelect?.value;
        productMoveSerialOutList.innerHTML = '<p class="muted">Chargement...</p>';
        const query = `product_id=${productId}&status=IN_STOCK&per_page=5000${warehouseId ? `&warehouse_id=${warehouseId}` : ''}`;
        const response = await apiRequest(`/product-serials?${query}`);
        const available = normalizeRows(response);
        productMoveAvailableOutSerialCount = available.length;

        productMoveSerialOutList.innerHTML = available.length === 0
            ? '<p class="muted">Aucun numero de serie en stock pour ce produit/entrepot.</p>'
            : available.map((serial) => `
                <label class="checklist-item">
                    <input type="checkbox" class="product-move-serial-out-checkbox" value="${serial.id}">
                    ${sanitize(serial.serial_number)}
                </label>
            `).join('');
    };

    const toggleProductMoveSerialsWrap = () => {
        const isIn = moveTypeSelect?.value === 'IN';
        // En mode multi-variantes, pas de numeros de serie a sortir : voir la
        // meme remarque sur l'ecran Mouvements.
        const isOut = moveTypeSelect?.value === 'OUT' && !productMoveMultiMode;
        productMoveSerialsInWrap?.classList.toggle('hidden', !isIn);
        productMoveSerialsOutWrap?.classList.toggle('hidden', !isOut);
        if (isOut) {
            loadProductMoveOutSerialOptions();
        }
    };
    toggleProductMoveSerialsWrap();
    moveTypeSelect?.addEventListener('change', toggleProductMoveSerialsWrap);
    moveTypeSelect?.addEventListener('change', applyProductMoveVariantMode);
    moveWarehouseSelect?.addEventListener('change', loadProductMoveOutSerialOptions);
    loadProductMoveVariantOptions();

    // Meme logique que sur l'ecran Mouvements : les emplacements proposes sont
    // ceux de l'entrepot concerne, la destination suivant l'entrepot de
    // destination quand il s'agit d'un transfert.
    const moveSourceLocation = document.getElementById('productMoveSourceLocation');
    const moveDestinationLocation = document.getElementById('productMoveDestinationLocation');
    const moveDestinationWarehouse = moveForm?.elements.namedItem('destination_warehouse_id');

    const refreshProductMoveLocations = () => {
        fillLocationOptions(moveSourceLocation, moveWarehouseSelect?.value ?? '');
        // Meme regle que l'ecran Mouvements : un transfert sans entrepot de
        // destination est un transfert INTERNE, les emplacements proposes sont
        // alors ceux de l'entrepot source.
        const isTransfer = String(moveTypeSelect?.value ?? '') === 'TRANSFER';
        const destinationWarehouse = isTransfer && String(moveDestinationWarehouse?.value ?? '') !== ''
            ? moveDestinationWarehouse.value
            : (moveWarehouseSelect?.value ?? '');
        fillLocationOptions(moveDestinationLocation, destinationWarehouse);
        if (productMoveMultiMode) {
            loadProductMoveMultiVariantChecklist();
        }
    };

    moveWarehouseSelect?.addEventListener('change', refreshProductMoveLocations);
    moveDestinationWarehouse?.addEventListener('change', refreshProductMoveLocations);
    moveTypeSelect?.addEventListener('change', refreshProductMoveLocations);
    moveSourceLocation?.addEventListener('change', () => {
        if (productMoveMultiMode) {
            loadProductMoveMultiVariantChecklist();
        }
    });
    refreshProductMoveLocations();

    moveForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const feedback = document.getElementById('productMoveFeedback');
        feedback.textContent = '';
        feedback.classList.remove('is-error');
        const data = new FormData(moveForm);

        if (productMoveMultiMode) {
            const customerId = data.get('customer_id') ? Number(data.get('customer_id')) : null;
            const type = String(data.get('type') ?? 'IN');
            const warehouseId = Number(data.get('warehouse_id'));
            const checked = Array.from(document.querySelectorAll('.product-move-variant-multi-checkbox:checked'));

            if (checked.length === 0) {
                feedback.textContent = 'Coche au moins une variante a deplacer.';
                feedback.classList.add('is-error');
                return;
            }

            const basePayload = {
                product_id: productId,
                warehouse_id: warehouseId,
                destination_warehouse_id: data.get('destination_warehouse_id') ? Number(data.get('destination_warehouse_id')) : null,
                source_location_id: data.get('source_location_id') ? Number(data.get('source_location_id')) : null,
                destination_location_id: data.get('destination_location_id') ? Number(data.get('destination_location_id')) : null,
                type,
                reason_code: String(data.get('reason_code') ?? ''),
                reference_type: customerId ? 'CUSTOMER' : null,
                reference_id: customerId,
            };

            let successCount = 0;
            const failures = [];
            for (const checkbox of checked) {
                const available = Number(checkbox.dataset.available ?? 0);
                if (available <= 0) {
                    continue;
                }
                try {
                    await apiRequest('/stock/movements', {
                        method: 'POST',
                        body: { ...basePayload, variant_id: Number(checkbox.value), quantity: available },
                    });
                    successCount += 1;
                } catch (error) {
                    failures.push(`${checkbox.parentElement?.textContent?.trim() ?? checkbox.value} : ${error.message}`);
                }
            }

            await renderProductDetail(productId);
            if (failures.length > 0) {
                window.alert(`${successCount} mouvement(s) enregistre(s). Echecs :\n${failures.join('\n')}`);
            }
            return;
        }

        const customerId = data.get('customer_id') ? Number(data.get('customer_id')) : null;
        const type = String(data.get('type') ?? 'IN');
        const warehouseId = Number(data.get('warehouse_id'));
        const quantity = Number(data.get('quantity'));
        const serialNumbers = String(data.get('serial_numbers') ?? '')
            .split('\n')
            .map((line) => line.trim())
            .filter(Boolean);
        const serialIdsOut = Array.from(document.querySelectorAll('.product-move-serial-out-checkbox:checked'))
            .map((el) => el.value)
            .filter(Boolean);

        if (serialNumbers.length > 0) {
            if (type !== 'IN') {
                feedback.textContent = 'Les numeros de serie ne se saisissent que sur une entree (IN).';
                feedback.classList.add('is-error');
                return;
            }
            if (serialNumbers.length !== quantity) {
                feedback.textContent = `Tu as saisi ${serialNumbers.length} numero(s) de serie pour une quantite de ${quantity}. Les deux doivent correspondre.`;
                feedback.classList.add('is-error');
                return;
            }
        }

        if (serialIdsOut.length > 0 && serialIdsOut.length !== quantity) {
            feedback.textContent = `Tu as coche ${serialIdsOut.length} numero(s) de serie pour une quantite de ${quantity}. Les deux doivent correspondre.`;
            feedback.classList.add('is-error');
            return;
        }

        if (type === 'OUT' && serialIdsOut.length === 0 && productMoveAvailableOutSerialCount > 0) {
            const proceed = window.confirm(
                `Ce produit a des numeros de serie en stock mais tu n'en as coche aucun: aucun ne sera marque "sorti". Continuer quand meme ?`
            );
            if (!proceed) {
                return;
            }
        }


        if (Number(product.has_variants) === 1 && !productMoveVariantSelect?.value) {
            feedback.textContent = 'Ce produit utilise des variantes : choisis-en une.';
            feedback.classList.add('is-error');
            return;
        }

        try {
            await apiRequest('/stock/movements', {
                method: 'POST',
                body: {
                    product_id: productId,
                    variant_id: productMoveVariantSelect?.value ? Number(productMoveVariantSelect.value) : null,
                    warehouse_id: warehouseId,
                    destination_warehouse_id: data.get('destination_warehouse_id') ? Number(data.get('destination_warehouse_id')) : null,
                    source_location_id: data.get('source_location_id') ? Number(data.get('source_location_id')) : null,
                    destination_location_id: data.get('destination_location_id') ? Number(data.get('destination_location_id')) : null,
                    type,
                    quantity,
                    reason_code: String(data.get('reason_code') ?? ''),
                    reference_type: customerId ? 'CUSTOMER' : null,
                    reference_id: customerId,
                },
            });

            if (serialNumbers.length > 0) {
                try {
                    await apiRequest('/product-serials', {
                        method: 'POST',
                        body: {
                            product_id: productId,
                            variant_id: productMoveVariantSelect?.value ? Number(productMoveVariantSelect.value) : null,
                            warehouse_id: warehouseId,
                            serial_numbers: serialNumbers,
                            // Le mouvement d'entree vient d'etre enregistre par
                            // l'appel precedent : sans ce drapeau, la quantite
                            // serait comptee deux fois.
                            creates_stock_entry: false,
                        },
                    });
                } catch (serialError) {
                    await renderProductDetail(productId);
                    window.alert(`Mouvement enregistre, mais erreur sur les numeros de serie: ${serialError.message}`);
                    return;
                }
            }

            if (serialIdsOut.length > 0) {
                const failures = [];
                for (const serialId of serialIdsOut) {
                    try {
                        await apiRequest(`/product-serials/${serialId}/mark-out`, { method: 'POST', body: {} });
                    } catch (serialError) {
                        failures.push(`#${serialId}: ${serialError.message}`);
                    }
                }
                await renderProductDetail(productId);
                if (failures.length > 0) {
                    window.alert(`Mouvement enregistre, mais erreur sur certains numeros de serie:\n${failures.join('\n')}`);
                }
                return;
            }

            await renderProductDetail(productId);
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    document.getElementById('gotoProductSerialsBtn')?.addEventListener('click', async () => {
        state.pendingSerialProductId = productId;
        setActiveNav('product-serials');
        await renderModule('product-serials');
    });

    document.getElementById('gotoProductVariantsBtn')?.addEventListener('click', async () => {
        state.pendingVariantProductId = productId;
        setActiveNav('product-variants');
        await renderModule('product-variants');
    });

    const mediaForm = document.getElementById('productMediaUploadForm');
    mediaForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const feedback = document.getElementById('mediaUploadFeedback');
        feedback.textContent = '';
        const data = new FormData(mediaForm);
        const file = data.get('file');

        try {
            const payload = new FormData();
            // Ex-onglet "Media" : demandait avant de choisir soi-meme le type
            // (Image/Document). Deduit desormais automatiquement du fichier
            // choisi - un detail que l'utilisateur n'a pas a gerer lui-meme.
            const isImage = file instanceof Blob && String(file.type ?? '').startsWith('image/');
            payload.append('media_type', isImage ? 'IMAGE' : 'DOCUMENT');
            payload.append('file', file);
            await uploadRequest(`/products/${productId}/media/upload`, payload);
            await renderProductDetail(productId);
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    pane.querySelectorAll('[data-download-type]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            const kind = btn.getAttribute('data-download-type');
            const id = Number(btn.getAttribute('data-download-id'));
            const name = btn.getAttribute('data-download-name') ?? 'file.bin';
            const path = kind === 'media' ? `/product-media/${id}/download` : `/attachments/${id}/download`;
            await authenticatedDownload(path, name);
        });
    });

    // "Voir en grand" : une image ou un PDF s'affiche directement (modale
    // pour une image, nouvel onglet pour un PDF - le navigateur sait deja
    // l'afficher nativement) au lieu d'obliger a telecharger le fichier
    // rien que pour savoir ce qu'il contient.
    pane.querySelectorAll('[data-view-type]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            const kind = btn.getAttribute('data-view-type');
            const id = Number(btn.getAttribute('data-view-id'));
            const mime = btn.getAttribute('data-view-mime') ?? '';
            const name = btn.getAttribute('data-view-name') ?? 'fichier';
            const path = kind === 'media' ? `/product-media/${id}/download` : `/attachments/${id}/download`;
            try {
                const blob = await fetchAuthenticatedBlob(path);
                const url = URL.createObjectURL(blob);
                if (mime === 'application/pdf') {
                    window.open(url, '_blank');
                } else {
                    showModal(name, `<img src="${url}" alt="${sanitize(name)}" style="max-width:100%;max-height:75vh;display:block;margin:0 auto;">`);
                }
            } catch (error) {
                window.alert(error.message);
            }
        });
    });

    const refreshLabelBtn = document.getElementById('refreshLabelBtn');
    refreshLabelBtn?.addEventListener('click', async () => {
        await loadLabelPreview(productId);
    });

    const printLabelBtn = document.getElementById('printLabelBtn');
    printLabelBtn?.addEventListener('click', async () => {
        const blob = await fetchAuthenticatedBlob(`/products/${productId}/label.svg`);
        const url = URL.createObjectURL(blob);
        const win = window.open(url, '_blank');
        if (win) {
            win.addEventListener('load', () => win.print(), { once: true });
        }
    });

    await loadMediaThumbnails();
    await loadLabelPreview(productId);
}

/**
 * Historique d'un client : ses bons de livraison (BL).
 *
 * Il n'existe pas de "commandes client" dans cette application - les
 * commandes (purchase_orders) sont passees AUPRES des fournisseurs, jamais
 * par un client (voir le module Achats). Le seul historique transactionnel
 * cote client, ce sont les livraisons : chaque livraison EST le bon de
 * livraison (numero, lignes de produits livres, entrepot, statut, montant).
 * "Commandes, livraisons, BL" se resume donc ici a cette seule liste.
 */
async function renderCustomerHistory(customerId) {
    const pane = document.getElementById('customerHistoryPane');
    if (!pane) {
        return;
    }

    pane.innerHTML = '<h4>Historique client</h4><p class="muted">Chargement...</p>';

    const [customerResponse, deliveriesResponse] = await Promise.all([
        apiRequest(`/customers/${customerId}`),
        apiRequest(`/deliveries?customer_id=${customerId}&per_page=100`),
    ]);

    const customer = customerResponse.data;
    const deliveries = normalizeRows(deliveriesResponse);

    pane.innerHTML = `
        <div class="panel-head">
            <h4>Historique: ${sanitize(customer.name)}${customer.code ? ` (${sanitize(customer.code)})` : ''}</h4>
        </div>
        <p class="muted">Bons de livraison de ce client - aucune commande cote client n'existe dans l'application (les commandes sont passees aupres des fournisseurs, voir le module Achats).</p>
        ${renderSimpleTable(deliveries, [
            ['delivery_number', 'N° BL', (value, row) => `
                ${sanitize(value)}
                <button type="button" class="btn btn-soft btn-sm" data-view-customer-delivery-lines="${row.id}">Produits livres</button>
            `],
            ['warehouse_name', 'Entrepot'],
            ['status', 'Statut'],
            ['total_amount', 'Montant', (value) => formatMoney(value)],
            ['delivered_at', 'Date'],
        ])}
    `;

    pane.querySelectorAll('[data-view-customer-delivery-lines]').forEach((button) => {
        button.addEventListener('click', async () => {
            const deliveryId = button.getAttribute('data-view-customer-delivery-lines');
            try {
                const detail = await apiRequest(`/deliveries/${deliveryId}`);
                const delivery = detail.data;
                const linesHtml = (delivery.lines ?? []).map((line) => `
                    <tr>
                        <td>${sanitize(line.sku)}</td>
                        <td>${sanitize(line.product_name)}${line.variant_id ? ` - ${sanitize(variantDescriptor({ ...line, sku: line.variant_sku }))}` : ''}</td>
                        <td>${line.serial_number ? sanitize(line.serial_number) : '-'}</td>
                        <td>${Number(line.quantity)}</td>
                        <td>${formatMoney(line.unit_price)}</td>
                    </tr>
                `).join('');
                showModal(`Produits livres - BL ${delivery.delivery_number}`, `
                    <table class="simple-table">
                        <thead><tr><th>SKU</th><th>Produit</th><th>N° Serie</th><th>Qte</th><th>PU</th></tr></thead>
                        <tbody>${linesHtml || '<tr><td colspan="5">Aucune ligne</td></tr>'}</tbody>
                    </table>
                `);
            } catch (error) {
                window.alert(error.message);
            }
        });
    });
}

function renderDownloadTable(rows, type) {
    // Pour les medias, une colonne d'apercu : une photo produit listee par son
    // seul nom de fichier oblige a la telecharger pour savoir ce qu'elle
    // montre. Les vignettes sont chargees ensuite (voir loadMediaThumbnails),
    // car le fichier n'est accessible qu'authentifie.
    const withPreview = type === 'media';
    const body = rows.map((row) => {
        const mimeType = String(row.mime_type ?? '');
        const isImage = mimeType.startsWith('image/');
        // Une image ou un PDF s'affichent nativement dans le navigateur : pas
        // besoin de forcer un telechargement juste pour y jeter un oeil. Les
        // autres formats (Word, Excel, CSV) n'ont pas d'affichage natif fiable
        // dans un navigateur : le telechargement reste la seule option.
        const canView = isImage || mimeType === 'application/pdf';
        const preview = withPreview
            ? `<td class="media-thumb">${isImage
                ? `<span data-media-thumb="${row.id}" class="muted">...</span>`
                : '<span class="muted">-</span>'}</td>`
            : '';
        return `
        <tr>
            <td>${sanitize(row.id)}</td>
            ${preview}
            <td>${sanitize(row.file_name)}</td>
            <td>${sanitize(mimeType)}</td>
            <td>${sanitize(row.created_at ?? '')}</td>
            <td class="actions">
                ${canView ? `<button class="btn btn-soft" data-view-type="${type}" data-view-id="${row.id}" data-view-mime="${sanitize(mimeType)}" data-view-name="${sanitize(row.file_name ?? 'fichier')}">Voir en grand</button>` : ''}
                <button class="btn btn-soft" data-download-type="${type}" data-download-id="${row.id}" data-download-name="${sanitize(row.file_name ?? 'file.bin')}">Telecharger le fichier</button>
            </td>
        </tr>
    `;
    }).join('');

    const columnCount = withPreview ? 6 : 5;

    return `
        <div class="table-wrap">
            <table class="data-table">
                <thead><tr><th>ID</th>${withPreview ? '<th>Apercu</th>' : ''}<th>Fichier</th><th>Type</th><th>Date</th><th>Action</th></tr></thead>
                <tbody>${body || `<tr><td colspan="${columnCount}">Aucune donnee</td></tr>`}</tbody>
            </table>
        </div>
    `;
}

/**
 * Charge les vignettes des medias image de la fiche produit.
 *
 * Le fichier n'est pas joignable par une URL publique (le dossier uploads
 * refuse l'acces direct) : on passe par la meme route authentifiee que le
 * bouton Telecharger, et on affiche le resultat via un objet blob. L'URL est
 * liberee des que l'image est affichee, pour ne pas accumuler des blobs a
 * chaque ouverture de fiche.
 */
async function loadMediaThumbnails() {
    const holders = [...document.querySelectorAll('[data-media-thumb]')];
    for (const holder of holders) {
        const id = holder.getAttribute('data-media-thumb');
        try {
            const blob = await fetchAuthenticatedBlob(`/product-media/${id}/download`);
            const url = URL.createObjectURL(blob);
            const img = document.createElement('img');
            img.alt = 'Apercu du media';
            img.style.maxWidth = '80px';
            img.style.maxHeight = '60px';
            img.addEventListener('load', () => URL.revokeObjectURL(url), { once: true });
            img.addEventListener('error', () => {
                URL.revokeObjectURL(url);
                holder.textContent = 'apercu indisponible';
            }, { once: true });
            img.src = url;
            holder.replaceChildren(img);
        } catch (_) {
            holder.textContent = 'apercu indisponible';
        }
    }
}

async function loadLabelPreview(productId) {
    const target = document.getElementById('barcodePreview');
    if (!target) {
        return;
    }

    try {
        const blob = await fetchAuthenticatedBlob(`/products/${productId}/label.svg`);
        const url = URL.createObjectURL(blob);
        target.innerHTML = `<img src="${url}" alt="Label produit" style="max-width:100%;height:auto;">`;
    } catch (error) {
        target.innerHTML = `<p class="feedback is-error">${sanitize(error.message)}</p>`;
    }
}

async function authenticatedDownload(path, fileName) {
    const blob = await fetchAuthenticatedBlob(path);
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    link.click();
    URL.revokeObjectURL(url);
}

async function downloadCsv(path, fileName) {
    // L'export CSV renvoie un contenu different (Content-Type text/csv) mais
    // les memes regles d'authentification/erreur s'appliquent: on reutilise
    // le meme helper que les autres telechargements authentifies.
    let blob;
    try {
        blob = await fetchAuthenticatedBlob(path);
    } catch (_) {
        throw new Error('Export impossible');
    }

    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    link.click();
    URL.revokeObjectURL(url);
}

// ---------------------------------------------------------------------------
// Generateur de variantes en lot
// ---------------------------------------------------------------------------
// Creer 5 tailles x 4 couleurs a la main represente 20 saisies identiques a
// 90%. Ce generateur produit toutes les combinaisons d'un coup. Il est
// volontairement 100% frontend : il enchaine les memes POST /product-variants
// que le formulaire unitaire, un par combinaison. Pas de nouvelle route, pas
// de migration, pas de transaction cote serveur - et donc aucun risque pour
// l'existant. La contrepartie est qu'un lot peut aboutir partiellement ; le
// rapport de fin liste precisement ce qui est passe et ce qui a echoue, et
// relancer le meme lot ignore ce qui existe deja (aucun doublon).

// Rapport conserve entre deux rendus : renderCrud() reconstruit tout le
// panneau apres la generation, on le reaffiche donc apres coup.
let lastVariantGenerationReport = null;

// Plus un blocage dur : au-dela de ce seuil, on demande juste une
// confirmation (un lot tres volumineux enchaine une requete par variante et
// peut prendre plusieurs minutes) au lieu de refuser purement et simplement.
// Aucune limite n'empeche de generer un lot plus grand si l'utilisateur
// confirme.
const VARIANT_GENERATOR_WARN_THRESHOLD = 500;

function renderVariantGenerator() {
    const clothing = state.clothingVariantsEnabled;
    const bottle = state.bottleVariantsEnabled;
    const dimension = state.dimensionVariantsEnabled;
    const technical = state.technicalVariantsEnabled;

    const attributeFields = [];
    if (clothing) {
        attributeFields.push(`
            <label><span>Tailles / pointures</span>
                <input type="text" name="gen_sizes" placeholder="S, M, L, XL"></label>`);
        attributeFields.push(`
            <label><span>Couleurs</span>
                <input type="text" name="gen_colors" placeholder="Rouge, Bleu, Noir"></label>`);
    }
    if (bottle) {
        attributeFields.push(`
            <label><span>Millesimes</span>
                <input type="text" name="gen_vintages" placeholder="2018, 2019, 2020"></label>`);
        attributeFields.push(`
            <label><span>Contenances en cl (nombres entiers)</span>
                <input type="text" name="gen_volumes" placeholder="37, 75, 150"></label>`);
    }
    if (dimension) {
        attributeFields.push(`
            <label><span>Largeurs (unite libre)</span>
                <input type="text" name="gen_widths" placeholder="60 cm, 80 cm, 1 m"></label>`);
        attributeFields.push(`
            <label><span>Hauteurs (unite libre)</span>
                <input type="text" name="gen_heights" placeholder="180 cm, 200 cm"></label>`);
        attributeFields.push(`
            <label><span>Profondeurs (unite libre)</span>
                <input type="text" name="gen_depths" placeholder="40 cm, 60 cm"></label>`);
        attributeFields.push(`
            <label><span>Poids (unite libre)</span>
                <input type="text" name="gen_weights" placeholder="12,5 kg, 25 kg"></label>`);
    }
    if (technical) {
        attributeFields.push(`
            <label><span>Puissances (unite libre)</span>
                <input type="text" name="gen_puissances" placeholder="800 W, 1200 W"></label>`);
        attributeFields.push(`
            <label><span>Marques</span>
                <input type="text" name="gen_marques" placeholder="Bosch, Makita"></label>`);
        attributeFields.push(`
            <label><span>Types</span>
                <input type="text" name="gen_types" placeholder="Standard, Pro"></label>`);
        attributeFields.push(`
            <label><span>Vitesses (unite libre)</span>
                <input type="text" name="gen_vitesses" placeholder="1500 tr/min, 3000 tr/min"></label>`);
        attributeFields.push(`
            <label><span>Tensions (unite libre)</span>
                <input type="text" name="gen_tensions" placeholder="12 V, 230 V"></label>`);
        attributeFields.push(`
            <label><span>Formes</span>
                <input type="text" name="gen_formes" placeholder="Ronde, Rectangulaire"></label>`);
    }

    const report = lastVariantGenerationReport;
    lastVariantGenerationReport = null;

    return `
        <section class="panel" id="variantGeneratorPanel">
            <div class="panel-head">
                <h4>Generer des variantes en lot</h4>
            </div>
            <p class="muted">
                Saisis les valeurs separees par des virgules (ou une par ligne).
                Toutes les combinaisons possibles seront creees. Laisse un champ
                vide pour l'exclure des combinaisons.
            </p>
            <form id="variantGeneratorForm" class="form-grid">
                ${selectField('gen_product_id', 'Produit', state.lookups.products, 'id', 'name', true)}
                <label><span>Prefixe des SKU</span>
                    <input type="text" name="gen_prefix" id="genPrefix" placeholder="Choisis d'abord un produit"></label>
                ${attributeFields.join('')}
                <label><span>Prix (vide = prix du produit)</span>
                    <input type="number" step="0.01" name="gen_price"></label>
                <div class="full form-actions">
                    <button type="button" class="btn btn-soft" id="genPreviewBtn">Previsualiser</button>
                    <button type="submit" class="btn btn-primary" id="genSubmitBtn" disabled>Generer</button>
                </div>
            </form>
            <p id="genFeedback" class="feedback ${report ? (report.isError ? 'is-error' : 'is-success') : ''}">${report ? sanitize(report.message) : ''}</p>
            <div id="genPreview">${report?.html ?? ''}</div>
        </section>
    `;
}

/** "S, M , L" ou "S\nM\nL" -> ['S','M','L'], doublons et vides ecartes. */
function parseVariantList(raw) {
    const seen = new Set();
    const values = [];

    for (const part of String(raw ?? '').split(/[,;\n\r]+/)) {
        const value = part.trim();
        if (value === '') {
            continue;
        }

        const dedupeKey = value.toLocaleUpperCase('fr-FR');
        if (seen.has(dedupeKey)) {
            continue;
        }

        seen.add(dedupeKey);
        values.push(value);
    }

    return values;
}

/** "Rouge fonce" -> "ROUGE-FONCE" : composant de SKU lisible et sans accent. */
function skuPart(value) {
    return String(value)
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toUpperCase()
        .replace(/[^A-Z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '');
}

function setupVariantGenerator() {
    const form = document.getElementById('variantGeneratorForm');
    const previewBtn = document.getElementById('genPreviewBtn');
    const submitBtn = document.getElementById('genSubmitBtn');
    const preview = document.getElementById('genPreview');
    const feedback = document.getElementById('genFeedback');
    const prefixInput = document.getElementById('genPrefix');
    if (!form || !previewBtn || !submitBtn || !preview || !feedback) {
        return;
    }

    // Combinaisons validees par la derniere previsualisation. La generation ne
    // travaille que sur cette liste : impossible de generer autre chose que ce
    // qui a ete affiche a l'ecran.
    let plannedCombos = [];

    const invalidate = () => {
        plannedCombos = [];
        submitBtn.disabled = true;
    };

    form.addEventListener('input', invalidate);
    form.addEventListener('change', invalidate);

    // Le prefixe se pre-remplit avec le SKU du produit, mais reste modifiable.
    form.elements.gen_product_id?.addEventListener('change', (event) => {
        const product = state.lookups.products.find((p) => String(p.id) === String(event.target.value));
        if (prefixInput && product) {
            prefixInput.value = String(product.sku ?? '');
        }
    });

    previewBtn.addEventListener('click', async () => {
        feedback.className = 'feedback';
        feedback.textContent = '';
        preview.innerHTML = '';
        invalidate();

        const productId = Number(form.elements.gen_product_id?.value ?? 0);
        if (!productId) {
            feedback.textContent = 'Choisis un produit.';
            feedback.classList.add('is-error');
            return;
        }

        const prefix = skuPart(prefixInput?.value ?? '');
        if (prefix === '') {
            feedback.textContent = 'Le prefixe des SKU est obligatoire.';
            feedback.classList.add('is-error');
            return;
        }

        // Dimensions du produit cartesien, dans l'ordre d'apparition dans le SKU.
        const dimensions = [];
        const sizes = parseVariantList(form.elements.gen_sizes?.value);
        const colors = parseVariantList(form.elements.gen_colors?.value);
        const vintages = parseVariantList(form.elements.gen_vintages?.value);
        const volumes = parseVariantList(form.elements.gen_volumes?.value);

        if (sizes.length > 0) {
            dimensions.push({ key: 'size', values: sizes });
        }
        if (colors.length > 0) {
            dimensions.push({ key: 'color', values: colors });
        }
        if (vintages.length > 0) {
            if (vintages.some((v) => !/^\d{4}$/.test(v))) {
                feedback.textContent = 'Les millesimes doivent etre des annees a 4 chiffres (ex: 2019).';
                feedback.classList.add('is-error');
                return;
            }
            dimensions.push({ key: 'vintage', values: vintages });
        }
        if (volumes.length > 0) {
            if (volumes.some((v) => !/^\d{1,5}$/.test(v))) {
                feedback.textContent = 'Les contenances doivent etre des nombres entiers de cl (ex: 75).';
                feedback.classList.add('is-error');
                return;
            }
            dimensions.push({ key: 'volume_cl', values: volumes });
        }

        // Dimensions libres : aucune validation de format, c'est le principe -
        // "60 cm", "1 m", "3/4 pouce" et "sur mesure" sont tous acceptes.
        for (const [field, key] of [['gen_widths', 'width'], ['gen_heights', 'height'], ['gen_depths', 'depth'], ['gen_weights', 'weight']]) {
            const values = parseVariantList(form.elements[field]?.value);
            if (values.length > 0) {
                dimensions.push({ key, values });
            }
        }

        // Materiel : egalement libre, aucune validation de format.
        for (const [field, key] of [['gen_puissances', 'puissance'], ['gen_marques', 'marque'], ['gen_types', 'type'], ['gen_vitesses', 'vitesse'], ['gen_tensions', 'tension'], ['gen_formes', 'forme']]) {
            const values = parseVariantList(form.elements[field]?.value);
            if (values.length > 0) {
                dimensions.push({ key, values });
            }
        }

        if (dimensions.length === 0) {
            feedback.textContent = 'Renseigne au moins une liste de valeurs.';
            feedback.classList.add('is-error');
            return;
        }

        // Produit cartesien de toutes les dimensions renseignees.
        let combos = [{}];
        for (const dimension of dimensions) {
            const next = [];
            for (const combo of combos) {
                for (const value of dimension.values) {
                    next.push({ ...combo, [dimension.key]: value });
                }
            }
            combos = next;
        }

        if (combos.length > VARIANT_GENERATOR_WARN_THRESHOLD) {
            const proceed = window.confirm(`${combos.length} combinaisons vont etre creees en une seule fois (une requete par variante) - cela peut prendre plusieurs minutes. Continuer ?`);
            if (!proceed) {
                feedback.textContent = 'Generation annulee.';
                return;
            }
        }

        // SKU deja utilises par ce produit : on les marque "existe deja" pour
        // pouvoir relancer un lot elargi sans creer de doublon.
        let existingSkus = new Set();
        try {
            const response = await apiRequest(`/product-variants?product_id=${productId}&per_page=5000`);
            existingSkus = new Set(normalizeRows(response).map((row) => String(row.sku ?? '').toUpperCase()));
        } catch (error) {
            feedback.textContent = `Impossible de lire les variantes existantes : ${error.message}`;
            feedback.classList.add('is-error');
            return;
        }

        const price = String(form.elements.gen_price?.value ?? '').trim();
        const rows = combos.map((combo) => {
            const parts = dimensions.map((dimension) => skuPart(combo[dimension.key]));
            const sku = [prefix, ...parts].join('-');
            return {
                product_id: productId,
                sku,
                size: combo.size ?? '',
                color: combo.color ?? '',
                vintage: combo.vintage ?? '',
                volume_cl: combo.volume_cl ?? '',
                width: combo.width ?? '',
                height: combo.height ?? '',
                depth: combo.depth ?? '',
                weight: combo.weight ?? '',
                puissance: combo.puissance ?? '',
                marque: combo.marque ?? '',
                type: combo.type ?? '',
                vitesse: combo.vitesse ?? '',
                tension: combo.tension ?? '',
                forme: combo.forme ?? '',
                unit_price: price,
                is_active: 1,
                exists: existingSkus.has(sku.toUpperCase()),
            };
        });

        plannedCombos = rows.filter((row) => !row.exists);
        submitBtn.disabled = plannedCombos.length === 0;

        const hasClothing = dimensions.some((d) => d.key === 'size' || d.key === 'color');
        const hasBottle = dimensions.some((d) => d.key === 'vintage' || d.key === 'volume_cl');
        const hasDimension = dimensions.some((d) => ['width', 'height', 'depth', 'weight'].includes(d.key));
        const hasTechnical = dimensions.some((d) => ['puissance', 'marque', 'type', 'vitesse', 'tension', 'forme'].includes(d.key));

        preview.innerHTML = `
            <div class="table-wrap">
                <table class="data-table">
                    <thead><tr>
                        <th>SKU genere</th>
                        ${hasClothing ? '<th>Taille</th><th>Couleur</th>' : ''}
                        ${hasBottle ? '<th>Millesime</th><th>Contenance</th>' : ''}
                        ${hasDimension ? '<th>Largeur</th><th>Hauteur</th><th>Profondeur</th><th>Poids</th>' : ''}
                        ${hasTechnical ? '<th>Puissance</th><th>Marque</th><th>Type</th><th>Vitesse</th><th>Tension</th><th>Forme</th>' : ''}
                        <th>Etat</th>
                    </tr></thead>
                    <tbody>
                        ${rows.map((row) => `
                            <tr>
                                <td>${sanitize(row.sku)}</td>
                                ${hasClothing ? `<td>${sanitize(row.size || '-')}</td><td>${sanitize(row.color || '-')}</td>` : ''}
                                ${hasBottle ? `<td>${sanitize(row.vintage || '-')}</td><td>${sanitize(row.volume_cl ? row.volume_cl + ' cl' : '-')}</td>` : ''}
                                ${hasDimension ? `<td>${sanitize(row.width || '-')}</td><td>${sanitize(row.height || '-')}</td><td>${sanitize(row.depth || '-')}</td><td>${sanitize(row.weight || '-')}</td>` : ''}
                                ${hasTechnical ? `<td>${sanitize(row.puissance || '-')}</td><td>${sanitize(row.marque || '-')}</td><td>${sanitize(row.type || '-')}</td><td>${sanitize(row.vitesse || '-')}</td><td>${sanitize(row.tension || '-')}</td><td>${sanitize(row.forme || '-')}</td>` : ''}
                                <td>${row.exists ? 'Existe deja - ignoree' : 'A creer'}</td>
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            </div>
        `;

        const skipped = rows.length - plannedCombos.length;
        feedback.textContent = plannedCombos.length === 0
            ? `Les ${rows.length} combinaisons existent deja, rien a generer.`
            : `${plannedCombos.length} variante(s) a creer${skipped > 0 ? `, ${skipped} deja existante(s) ignoree(s)` : ''}. Verifie la liste puis clique sur Generer.`;
        feedback.classList.add(plannedCombos.length === 0 ? 'is-error' : 'is-success');
    });

    form.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (plannedCombos.length === 0) {
            return;
        }

        const productId = plannedCombos[0].product_id;
        const total = plannedCombos.length;
        submitBtn.disabled = true;
        previewBtn.disabled = true;
        feedback.className = 'feedback';

        const failures = [];
        let created = 0;

        for (const [index, combo] of plannedCombos.entries()) {
            feedback.textContent = `Creation en cours... ${index + 1} / ${total}`;
            try {
                await apiRequest('/product-variants', {
                    method: 'POST',
                    body: {
                        product_id: combo.product_id,
                        sku: combo.sku,
                        size: combo.size,
                        color: combo.color,
                        vintage: combo.vintage,
                        volume_cl: combo.volume_cl,
                        width: combo.width,
                        height: combo.height,
                        depth: combo.depth,
                        weight: combo.weight,
                        puissance: combo.puissance,
                        marque: combo.marque,
                        type: combo.type,
                        vitesse: combo.vitesse,
                        tension: combo.tension,
                        forme: combo.forme,
                        unit_price: combo.unit_price,
                        is_active: 1,
                    },
                });
                created += 1;
            } catch (error) {
                failures.push(`${combo.sku} : ${error.message}`);
            }
        }

        // Un produit qui recoit des variantes doit etre marque comme tel, sinon
        // le selecteur de variante n'apparaitra pas dans les mouvements de stock.
        let flagged = false;
        const product = state.lookups.products.find((p) => String(p.id) === String(productId));
        if (created > 0 && product && Number(product.has_variants) !== 1) {
            try {
                await apiRequest(`/products/${productId}`, { method: 'PUT', body: { has_variants: '1' } });
                flagged = true;
            } catch (_) {
                failures.push("Le produit n'a pas pu etre marque comme \"a des variantes\" : fais-le manuellement sur sa fiche.");
            }
        }

        const parts = [`${created} variante(s) creee(s) sur ${total}.`];
        if (flagged) {
            parts.push('Le produit a ete marque comme "a des variantes".');
        }
        if (failures.length > 0) {
            parts.push(`${failures.length} echec(s).`);
        }

        lastVariantGenerationReport = {
            message: parts.join(' '),
            isError: failures.length > 0,
            html: failures.length > 0
                ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>Echecs</th></tr></thead><tbody>${failures.map((f) => `<tr><td>${sanitize(f)}</td></tr>`).join('')}</tbody></table></div>`
                : '',
        };

        await refreshLookups();
        state.pendingVariantProductId = productId;
        await renderCrud('product-variants');
    });
}

/**
 * Avertit quand le produit qu'on s'apprete a compter n'a pas de stock dans
 * l'entrepot de la session d'inventaire, alors qu'il en a ailleurs.
 *
 * C'est le cas ou l'utilisateur s'est trompe d'entrepot en creant la session :
 * l'attendu affiche 0, l'ecart vaut toute la quantite saisie, et la
 * finalisation cree ce stock dans le mauvais entrepot sans toucher au bon.
 * Rien dans l'ecran ne le signalait.
 */
/**
 * Remplit le panneau "Reste a compter" d'une session d'inventaire globale.
 *
 * Volontairement en lecture seule : cliquer sur "Compter" ne fait que
 * pre-selectionner l'article dans le formulaire de saisie. Aucun comptage
 * n'est cree tant que l'utilisateur n'a pas saisi une quantite - un article
 * non compte doit rester non ajuste, sans quoi la finalisation mettrait son
 * stock a zero.
 */
async function loadInventoryRemaining(sessionId) {
    const panel = document.getElementById('inventoryRemainingPanel');
    const list = document.getElementById('inventoryRemainingList');
    const counter = document.getElementById('inventoryRemainingCounter');
    if (!panel || !list) {
        return;
    }

    let data;
    try {
        const response = await apiRequest(`/inventories/${sessionId}/remaining`);
        data = response?.data;
    } catch (_) {
        // Aide a la saisie : en cas d'echec on masque le panneau, la session
        // reste parfaitement utilisable sans lui.
        return;
    }

    if (!data?.applicable) {
        return;
    }

    panel.classList.remove('hidden');
    const total = Number(data.total ?? 0);
    const counted = Number(data.counted ?? 0);
    if (counter) {
        counter.textContent = `${counted} / ${total} article(s) compte(s)`;
    }

    const items = Array.isArray(data.items) ? data.items : [];
    if (items.length === 0) {
        list.innerHTML = total === 0
            ? '<p class="muted">Aucun article en stock dans cet entrepot.</p>'
            : '<p class="feedback is-success">Tous les articles en stock de cet entrepot ont ete comptes.</p>';
        return;
    }

    list.innerHTML = `
        <div class="table-wrap">
            <table class="data-table">
                <thead><tr><th>SKU</th><th>Produit</th><th>Variante</th><th>Stock attendu</th><th>Action</th></tr></thead>
                <tbody>
                    ${items.map((item) => `
                        <tr>
                            <td>${sanitize(item.sku)}</td>
                            <td>${sanitize(item.product_name)}</td>
                            <td>${item.variant_id ? sanitize(variantDescriptor({ ...item, sku: item.variant_sku })) : '-'}</td>
                            <td>${Number(item.expected_qty)}</td>
                            <td><button type="button" class="btn btn-soft" data-action="count-remaining"
                                    data-product-id="${Number(item.product_id)}"
                                    data-variant-id="${item.variant_id ? Number(item.variant_id) : ''}">Compter</button></td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        </div>
    `;

    list.addEventListener('click', async (event) => {
        const button = event.target.closest('[data-action="count-remaining"]');
        if (!button) {
            return;
        }

        const productSelect = document.getElementById('inventoryCountForm')?.elements.product_id;
        if (!productSelect) {
            return;
        }

        productSelect.value = String(button.dataset.productId);
        // dispatchEvent plutot qu'un appel direct : c'est le meme chemin que
        // lorsque l'utilisateur choisit le produit a la main (chargement des
        // variantes, avertissement d'entrepot).
        productSelect.dispatchEvent(new Event('change'));

        const variantId = button.dataset.variantId;
        if (variantId) {
            // Le chargement des variantes est asynchrone : on attend que
            // l'option existe avant de la selectionner.
            const variantSelect = document.getElementById('inventoryVariantSelect');
            for (let attempt = 0; attempt < 20 && variantSelect; attempt += 1) {
                if (variantSelect.querySelector(`option[value="${variantId}"]`)) {
                    variantSelect.value = variantId;
                    break;
                }
                await new Promise((resolve) => setTimeout(resolve, 100));
            }
        }

        document.getElementById('inventoryCountForm')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
        document.getElementById('inventoryCountForm')?.elements.counted_qty?.focus();
    });
}

async function warnIfStockedElsewhere(productId, session) {
    const hint = document.getElementById('inventoryStockHint');
    if (!hint) {
        return;
    }

    hint.className = 'full feedback hidden';
    hint.textContent = '';
    if (!productId) {
        return;
    }

    let stockRows = [];
    try {
        const response = await apiRequest(`/products/${productId}`);
        stockRows = Array.isArray(response?.data?.stock_by_warehouse) ? response.data.stock_by_warehouse : [];
    } catch (_) {
        // Simple aide a la saisie : si l'appel echoue, on n'empeche rien.
        return;
    }

    const sessionWarehouseId = Number(session.warehouse_id);
    const here = stockRows
        .filter((row) => Number(row.warehouse_id) === sessionWarehouseId)
        .reduce((total, row) => total + Number(row.quantity ?? 0), 0);

    if (here > 0) {
        return;
    }

    const elsewhere = stockRows.filter((row) => Number(row.warehouse_id) !== sessionWarehouseId && Number(row.quantity ?? 0) > 0);
    if (elsewhere.length === 0) {
        return;
    }

    const detail = elsewhere
        .map((row) => `${sanitize(row.warehouse_name ?? row.warehouse_code ?? '?')} (${Number(row.quantity)})`)
        .join(', ');

    hint.className = 'full feedback is-error';
    hint.innerHTML = `Attention : ce produit n'a aucun stock dans <strong>${sanitize(session.warehouse_name)}</strong>,
        l'entrepot de cette session, mais il en a ailleurs : ${detail}.
        L'ecart portera donc sur la totalite de la quantite saisie, et la finalisation creera ce stock
        dans ${sanitize(session.warehouse_name)} sans toucher a l'autre entrepot.
        Verifie que la session porte bien sur le bon entrepot.`;
}

/**
 * Resume "ou est ce produit", en tete de l'onglet Stock d'une fiche produit.
 *
 * Le tableau detaille ligne par ligne, mais la question courante - dans quelle
 * allee vais-je le chercher - merite une reponse en une phrase, avant le
 * tableau. Les lignes a quantite nulle sont ecartees : un emplacement vide
 * n'est pas un endroit ou aller.
 */
function renderProductLocationSummary(stockRows) {
    const rows = (Array.isArray(stockRows) ? stockRows : []).filter((row) => Number(row.quantity) !== 0);

    if (rows.length === 0) {
        return '<p class="feedback">Ce produit n\'a de stock dans aucun entrepot.</p>';
    }

    // Regroupement par entrepot, puis liste des emplacements de chacun.
    const byWarehouse = new Map();
    for (const row of rows) {
        const name = row.warehouse_name ?? row.warehouse_code ?? '?';
        if (!byWarehouse.has(name)) {
            byWarehouse.set(name, { total: 0, places: [] });
        }
        const entry = byWarehouse.get(name);
        entry.total += Number(row.quantity);
        entry.places.push({
            label: row.location_code
                ? `${row.location_code}${row.zone_code ? ` (zone ${row.zone_code})` : ''}`
                : 'non range',
            quantity: Number(row.quantity),
            located: Boolean(row.location_code),
        });
    }

    const blocs = [...byWarehouse.entries()].map(([name, entry]) => {
        const places = entry.places
            .map((place) => `<strong>${sanitize(place.label)}</strong> : ${place.quantity}`)
            .join(' &nbsp;|&nbsp; ');
        return `<p><strong>${sanitize(name)}</strong> \u2014 total ${entry.total}<br><span class="muted">${places}</span></p>`;
    });

    return `<div class="panel-inline">${blocs.join('')}</div>`;
}

function renderPaginationBar(meta, rowCount) {
    // L'API renvoie toujours page / per_page / total / last_page dans `meta`.
    // Si un endpoint n'en fournit pas, on n'affiche simplement pas de barre
    // plutot que d'inventer des valeurs.
    if (!meta || typeof meta.total !== 'number') {
        return '';
    }

    const page = Number(meta.page ?? 1);
    const lastPage = Math.max(1, Number(meta.last_page ?? 1));
    const total = Number(meta.total ?? 0);
    const from = total === 0 ? 0 : (page - 1) * Number(meta.per_page ?? state.crudPerPage) + 1;
    const to = from === 0 ? 0 : from + rowCount - 1;

    const perPageOptions = [25, 50, 100]
        .map((size) => `<option value="${size}" ${size === state.crudPerPage ? 'selected' : ''}>${size} par page</option>`)
        .join('');

    return `
        <div class="pagination-bar">
            <span class="muted">
                ${total === 0 ? 'Aucun resultat' : `${from} - ${to} sur ${total} resultat${total > 1 ? 's' : ''}`}
                ${lastPage > 1 ? ` (page ${page} sur ${lastPage})` : ''}
            </span>
            <span class="pagination-actions">
                <select id="crudPerPage">${perPageOptions}</select>
                <button type="button" class="btn btn-soft" id="crudPrevPage" ${page <= 1 ? 'disabled' : ''}>Precedent</button>
                <button type="button" class="btn btn-soft" id="crudNextPage" ${page >= lastPage ? 'disabled' : ''}>Suivant</button>
            </span>
        </div>
    `;
}

function setupPagination(module, meta, rerender = null) {
    // `rerender` : les ecrans qui ne passent pas par renderCrud (demandes et
    // commandes d'achat) fournissent leur propre fonction de rendu. Par
    // defaut on retombe sur renderCrud, le cas de tous les referentiels.
    const refresh = rerender ?? (() => renderCrud(module));
    const lastPage = Math.max(1, Number(meta?.last_page ?? 1));
    const page = Number(meta?.page ?? 1);

    document.getElementById('crudPrevPage')?.addEventListener('click', async () => {
        if (page <= 1) {
            return;
        }
        state.crudPages[module] = page - 1;
        await refresh();
    });

    document.getElementById('crudNextPage')?.addEventListener('click', async () => {
        if (page >= lastPage) {
            return;
        }
        state.crudPages[module] = page + 1;
        await refresh();
    });

    document.getElementById('crudPerPage')?.addEventListener('change', async (event) => {
        // Changer la taille de page invalide le numero de page courant : on
        // repart de la premiere, seule position dont le sens est garanti.
        state.crudPerPage = Number(event.target.value) || 25;
        state.crudPages[module] = 1;
        await refresh();
    });
}

/**
 * Bouton de bascule "en cours" / "passees" des deux ecrans d'achat, avec le
 * nombre d'elements de l'autre vue pour que l'utilisateur sache ce qu'il y
 * trouvera avant de cliquer.
 */
function renderPurchaseScopeToggle(module, meta) {
    const scope = state.purchaseScopes[module] ?? 'open';
    const isRequests = module === 'purchase-requests';
    const archivedTotal = Number(meta?.archived_total ?? 0);
    const openTotal = Number(meta?.open_total ?? 0);

    const label = scope === 'open'
        ? (isRequests
            ? `Voir les demandes passees (${archivedTotal})`
            : `Voir les commandes passees (${archivedTotal})`)
        : (isRequests
            ? `Revenir aux demandes en cours (${openTotal})`
            : `Revenir aux commandes en cours (${openTotal})`);

    return `<button type="button" class="btn btn-soft" id="purchaseScopeToggle">${label}</button>`;
}

function setupPurchaseScopeToggle(module, rerender) {
    document.getElementById('purchaseScopeToggle')?.addEventListener('click', async () => {
        const scope = state.purchaseScopes[module] ?? 'open';
        state.purchaseScopes[module] = scope === 'open' ? 'archived' : 'open';
        // Changer de vue change le nombre de pages : la page courante n'a
        // plus de sens, on repart de la premiere.
        state.crudPages[module] = 1;
        await rerender();
    });
}

/**
 * Colonnes reellement affichees pour un module.
 *
 * Une colonne `secondary` n'apparait que si l'utilisateur a demande la vue
 * complete. Par defaut le tableau tient dans la largeur de l'ecran, ce qui
 * compte davantage que de tout montrer : une barre de defilement horizontale
 * cache la moitie des colonnes sans le dire.
 */
function visibleColumns(config, module) {
    // Ecran Produits avec une selection personnalisee de colonnes (reglage
    // product_list_columns, Parametres) : elle remplace entierement la
    // logique essentielles/toutes ci-dessous, ordre du tableau `columns`
    // conserve (celui choisi a la conception, pas celui de la coche).
    if (module === 'products' && Array.isArray(state.productListColumns)) {
        return config.columns.filter((column) => state.productListColumns.includes(column.key));
    }

    if (state.allColumns[module]) {
        return config.columns;
    }

    return config.columns.filter((column) => !column.secondary);
}

function renderCrudTable(config, rows, canWrite, module = '') {
    // Tableau principal avec actions selon les droits.
    const columns = visibleColumns(config, module);
    const headerCells = columns.map((column) => `<th>${column.label}</th>`).join('');

    const rowCells = rows.map((row) => {
        const cells = columns.map((column) => {
            const value = row[column.key];
            const display = column.format ? column.format(value, row) : sanitize(localizeValue(value, column.key));
            return `<td>${display}</td>`;
        }).join('');

        let actions = '';
        if (canWrite) {
            actions += `<button data-action="edit" data-id="${row.id}" class="btn btn-soft">Editer</button>`;
            if (module === 'users') {
                actions += `<button data-action="reset-password" data-id="${row.id}" class="btn btn-soft">Reinitialiser mdp</button>`;
            }
            actions += `<button data-action="delete" data-id="${row.id}" class="btn btn-danger">Supprimer</button>`;
        }
        if (module === 'products') {
            actions = `<button data-action="view" data-id="${row.id}" class="btn btn-primary">Fiche</button>` + actions;
        }
        if (module === 'customers') {
            actions = `<button data-action="history" data-id="${row.id}" class="btn btn-primary">Historique</button>` + actions;
        }

        const actionCell = actions !== '' ? `<td class="actions">${actions}</td>` : '';

        return `<tr>${cells}${actionCell}</tr>`;
    }).join('');

    const hasActionColumn = canWrite || module === 'products' || module === 'customers';

    return `
        <div class="table-wrap">
            <table class="data-table">
                <thead><tr>${headerCells}${hasActionColumn ? '<th>Actions</th>' : ''}</tr></thead>
                <tbody>${rowCells || `<tr><td colspan="${config.columns.length + (hasActionColumn ? 1 : 0)}">Aucune donnee</td></tr>`}</tbody>
            </table>
        </div>
    `;
}

/**
 * Pre-remplit la TVA d'un produit avec la taxe par defaut de sa categorie.
 *
 * Le reglage "Taxe defaut" existait sur la categorie mais n'etait applique
 * nulle part : on le saisissait, aucun produit n'en heritait. Le serveur
 * l'applique desormais a la creation (ProductRepository) et a l'import CSV ;
 * ici on le rend VISIBLE au moment de la saisie, pour que l'utilisateur voie
 * le taux propose et puisse le changer avant d'enregistrer - plutot que de
 * decouvrir apres coup une TVA qu'il n'a pas choisie.
 *
 * La valeur deja saisie n'est jamais ecrasee : le pre-remplissage ne joue que
 * si le champ TVA est vide.
 */
function setupCategoryDefaultTax(module, form) {
    if (module !== 'products') {
        return;
    }

    const categorySelect = form.elements.namedItem('category_id');
    const taxSelect = form.elements.namedItem('tax_id');
    if (!categorySelect || !taxSelect) {
        return;
    }

    categorySelect.addEventListener('change', () => {
        if (String(taxSelect.value ?? '') !== '') {
            return;
        }

        const category = (state.lookups.categories ?? [])
            .find((row) => String(row.id) === String(categorySelect.value));
        const defaultTaxId = category?.default_tax_id;
        if (!defaultTaxId) {
            return;
        }

        // Uniquement si ce taux existe encore dans la liste (une taxe
        // supprimee depuis laisserait sinon le champ sur une valeur fantome).
        const exists = [...taxSelect.options].some((option) => String(option.value) === String(defaultTaxId));
        if (exists) {
            taxSelect.value = String(defaultTaxId);
        }
    });
}

/**
 * Rend un formulaire compatible douchette.
 *
 * Une douchette se comporte comme un clavier : elle "tape" le code puis
 * envoie Entree. Or, dans un formulaire HTML, Entree dans un champ texte
 * declenche l'envoi du formulaire (soumission implicite). Scanner un code
 * barre dans une fiche produit a moitie remplie l'enregistrait donc
 * prematurement - ou affichait une erreur de champ obligatoire, sans que
 * l'utilisateur comprenne ce qui venait de se passer.
 *
 * Entree passe desormais au champ suivant, comportement habituel d'une
 * saisie au kilometre : on scanne, le curseur avance. L'enregistrement reste
 * un clic explicite sur "Enregistrer".
 */
function setupScannerFriendlyForm(form) {
    form.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter') {
            return;
        }

        const target = event.target;
        // Un textarea a besoin d'Entree pour aller a la ligne, et le bouton
        // Enregistrer doit rester actionnable au clavier.
        if (!(target instanceof HTMLInputElement) || target.type === 'submit') {
            return;
        }

        event.preventDefault();

        const focusable = [...form.querySelectorAll('input, select, textarea, button')]
            .filter((element) => !element.disabled && element.type !== 'hidden');
        const next = focusable[focusable.indexOf(target) + 1];
        next?.focus();
        if (next instanceof HTMLInputElement) {
            next.select();
        }
    });
}

// Palette proposee par defaut pour les tags. Douze teintes franches et
// distinctes les unes des autres : un utilisateur choisit une couleur en un
// clic, sans avoir a connaitre la notation hexadecimale. Le selecteur de
// couleur du navigateur reste disponible a cote pour une teinte precise.
const COLOR_PRESETS = [
    { value: '#ef4444', label: 'Rouge' },
    { value: '#f97316', label: 'Orange' },
    { value: '#f59e0b', label: 'Ambre' },
    { value: '#eab308', label: 'Jaune' },
    { value: '#22c55e', label: 'Vert' },
    { value: '#10b981', label: 'Emeraude' },
    { value: '#06b6d4', label: 'Cyan' },
    { value: '#3b82f6', label: 'Bleu' },
    { value: '#6366f1', label: 'Indigo' },
    { value: '#a855f7', label: 'Violet' },
    { value: '#ec4899', label: 'Rose' },
    { value: '#64748b', label: 'Gris' },
];

const DEFAULT_TAG_COLOR = '#6366f1';

/** '#abc' / 'ABCDEF' / valeur libre -> '#aabbcc', ou null si inexploitable. */
function normalizeHexColor(value) {
    const raw = String(value ?? '').trim();
    const match = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(raw);
    if (!match) {
        return null;
    }

    const hex = match[1].length === 3
        ? match[1].split('').map((char) => char + char).join('')
        : match[1];

    return '#' + hex.toLowerCase();
}

/**
 * Noir ou blanc, selon ce qui reste lisible sur la couleur donnee.
 *
 * Le badge etait toujours en texte blanc : sur un jaune ou un cyan clair, le
 * libelle devenait illisible. Formule de luminance relative (WCAG).
 */
function readableTextColor(hexColor) {
    const hex = normalizeHexColor(hexColor) ?? DEFAULT_TAG_COLOR;
    const channel = (start) => {
        const value = parseInt(hex.slice(start, start + 2), 16) / 255;
        return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
    };
    const luminance = 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);

    return luminance > 0.45 ? '#111827' : '#ffffff';
}

function colorField(key, label, value) {
    const current = normalizeHexColor(value) ?? DEFAULT_TAG_COLOR;
    const swatches = COLOR_PRESETS.map((preset) => `
        <button type="button" class="color-swatch${preset.value === current ? ' is-selected' : ''}"
                data-color-swatch="${key}" data-color="${preset.value}"
                style="background:${preset.value}" title="${preset.label}" aria-label="${preset.label}"></button>
    `).join('');

    return `
        <label class="full"><span>${label}</span>
            <span class="color-field">
                <input type="color" name="${key}" value="${current}" data-color-input="${key}">
                <span class="color-swatches">${swatches}</span>
                <code data-color-value="${key}">${current}</code>
            </span>
        </label>
    `;
}

/**
 * Rend cliquable la palette d'un champ couleur.
 *
 * Le champ <input type="color"> reste la source de verite (c'est lui qui
 * porte le name et part dans le formulaire) ; les pastilles ne font que lui
 * donner une valeur, et le code hexadecimal affiche a cote suit.
 */
/**
 * Rappelle, sous le champ Profil, ce que le profil choisi autorise.
 *
 * Choisir un profil dans une liste de codes sans savoir ce qu'il ouvre ou
 * ferme, c'est donner des droits au jugé - le detail complet reste dans le
 * tableau "Profils et droits" de l'ecran.
 */
function setupRoleHint(form) {
    const select = form.elements.namedItem('role');
    const hint = form.querySelector('#roleHint');
    if (!select || !hint) {
        return;
    }

    const sync = () => {
        const profile = ROLE_MATRIX[String(select.value ?? '').toUpperCase()];
        hint.textContent = profile
            ? profile.summary
            : (select.value === '' ? '' : "Profil inconnu de l'application : consultation seule, aucun enregistrement.");
    };

    select.addEventListener('change', sync);
    sync();
}

/**
 * Remplit la liste "Stock initial - emplacement" avec les emplacements de
 * l'entrepot choisi juste au-dessus.
 *
 * Sans ce lien, la liste aurait propose les emplacements de TOUS les
 * entrepots - et laisse ranger un article dans une allee qui n'existe pas la
 * ou il arrive (le serveur refuse, mais autant ne pas le proposer).
 */
function setupInitialStockLocation(module, form) {
    if (module !== 'products') {
        return;
    }

    const warehouseSelect = form.elements.namedItem('initial_warehouse_id');
    const locationSelect = form.elements.namedItem('initial_location_id');
    if (!warehouseSelect || !locationSelect) {
        return;
    }

    const sync = () => fillLocationOptions(locationSelect, warehouseSelect.value ?? '');
    warehouseSelect.addEventListener('change', sync);
    sync();
}

function setupColorFields(form) {
    form.querySelectorAll('[data-color-input]').forEach((input) => {
        const key = input.getAttribute('data-color-input');
        const output = form.querySelector(`[data-color-value="${key}"]`);
        const swatches = [...form.querySelectorAll(`[data-color-swatch="${key}"]`)];

        const sync = () => {
            const current = normalizeHexColor(input.value) ?? DEFAULT_TAG_COLOR;
            if (output) {
                output.textContent = current;
            }
            swatches.forEach((swatch) => {
                swatch.classList.toggle('is-selected', swatch.getAttribute('data-color') === current);
            });
        };

        swatches.forEach((swatch) => {
            swatch.addEventListener('click', () => {
                input.value = swatch.getAttribute('data-color');
                sync();
            });
        });

        input.addEventListener('input', sync);
        sync();
    });
}

function buildFormFields(fields, item = null, editing = false) {
    // Les champs createOnly n'ont de sens qu'a la creation (ex: stock initial).
    return fields.filter((field) => !(field.createOnly && editing)).map((field) => {
        // field.defaultValue ne s'applique qu'a la creation : en edition, la
        // valeur enregistree du produit prime toujours sur le reglage global.
        const fallback = !item && field.defaultValue !== undefined ? String(field.defaultValue) : '';
        const value = item && item[field.key] !== undefined && item[field.key] !== null ? String(item[field.key]) : fallback;
        const required = field.required || (field.requiredOnCreate && !editing);

        if (field.type === 'textarea') {
            return `<label class="full"><span>${field.label}</span><textarea name="${field.key}" ${required ? 'required' : ''}>${sanitize(value)}</textarea></label>`;
        }

        if (field.type === 'color') {
            return colorField(field.key, field.label, value);
        }

        if (field.type === 'select') {
            // Les options statiques (field.options) sont au format {value,label} ;
            // les options issues des lookups (field.optionsFrom) sont au format {id,...}.
            const defaultOptionValue = field.options ? 'value' : 'id';
            return selectField(
                field.key,
                field.label,
                resolveOptions(field),
                field.optionValue ?? defaultOptionValue,
                field.optionLabel ?? 'label',
                required,
                value,
                field.localizeOptions ?? null,
                // L'aide doit etre A L'INTERIEUR du <label> : placee apres, la
                // grille du formulaire en faisait une cellule a part, affichee
                // sous un tout autre champ.
                //
                // field.hint etait ignore ici : seul le cas special "role"
                // affichait une aide sur un <select> (elle-meme remplie a part,
                // voir roleHint). Un champ select "normal" avec un field.hint
                // (ex: has_variants) n'affichait donc jamais son indice, alors
                // que le meme mecanisme fonctionne pour les autres types de
                // champs (voir plus bas, `const hint = field.hint ...`).
                field.key === 'role'
                    ? '<small class="field-hint" id="roleHint"></small>'
                    : (field.hint ? `<small class="field-hint">${field.hint}</small>` : '')
            );
        }

        if (field.type === 'multiselect') {
            // Pour une relation many-to-many (ex: tags d'un produit), l'objet
            // renvoye par l'API expose la liste complete des entites liees
            // (ex: item.tags = [{id,name,color}, ...]) sous une cle differente
            // de celle utilisee pour l'envoi du formulaire (ex: tag_ids).
            // field.valueFrom permet de faire le lien entre les deux.
            const relatedKey = field.valueFrom ?? field.key;
            const selected = item && Array.isArray(item[relatedKey])
                ? item[relatedKey].map((entry) => String(entry.id ?? entry))
                : [];
            return multiSelectField(field.key, field.label, resolveOptions(field), field.optionValue ?? 'id', field.optionLabel ?? 'label', selected);
        }

        const hint = field.hint ? `<small class="field-hint">${field.hint}</small>` : '';

        return `<label><span>${field.label}</span><input type="${field.type}" name="${field.key}" value="${sanitize(value)}" ${field.step ? `step="${field.step}"` : ''} ${required ? 'required' : ''}>${hint}</label>`;
    }).join('');
}

function collectFormPayload(fields, form, editing) {
    const payload = {};

    for (const field of fields) {
        const input = form.elements[field.key];
        if (!input) {
            continue;
        }

        if (field.type === 'multiselect') {
            const selectedOptions = Array.from(input.selectedOptions ?? []);
            payload[field.key] = selectedOptions.map((opt) => Number(opt.value));
            continue;
        }

        let value = String(input.value ?? '').trim();

        if (field.type === 'number') {
            value = value === '' ? '' : Number(value);
        }

        if (field.type === 'select' && ['category_id', 'supplier_id', 'unit_id', 'brand_id', 'tax_id', 'role_id', 'warehouse_id', 'product_id', 'is_active', 'is_default', 'zone_id', 'location_id', 'parent_id', 'default_tax_id'].includes(field.key)) {
            if (field.key === 'is_active' || field.key === 'is_default') {
                value = Number(value || 0);
            } else if (value !== '') {
                value = Number(value);
            } else {
                value = null;
            }
        }

        if (editing && field.key === 'password' && value === '') {
            continue;
        }

        payload[field.key] = value;
    }

    return payload;
}

function formActions() {
    return `<div class="full form-actions"><button type="submit" class="btn btn-primary">Enregistrer</button><button type="button" data-action="cancel" class="btn btn-soft">Annuler</button></div>`;
}

function normalizeRows(response) {
    if (!response) {
        return [];
    }

    if (Array.isArray(response)) {
        return response;
    }

    if (Array.isArray(response.data)) {
        return response.data;
    }

    if (response.data && Array.isArray(response.data.data)) {
        return response.data.data;
    }

    return [];
}

function resolveOptions(field) {
    if (field.options) {
        return field.options;
    }

    return (state.lookups?.[field.optionsFrom] ?? []);
}

function selectField(name, label, options, optionValue, optionLabel, required = false, selectedValue = '', localize = null, hint = '') {
    const opts = options.map((option) => {
        const value = String(option[optionValue]);
        const raw = option[optionLabel] ?? option.label ?? option.code ?? value;
        const text = sanitize(localize === 'role' ? roleLabel(raw) : raw);
        const selected = selectedValue !== '' && value === String(selectedValue) ? 'selected' : '';
        return `<option value="${sanitize(value)}" ${selected}>${text}</option>`;
    }).join('');

    return `
        <label>
            <span>${label}</span>
            <select name="${name}" ${required ? 'required' : ''}>
                <option value="">Choisir</option>
                ${opts}
            </select>
            ${hint}
        </label>
    `;
}

function multiSelectField(name, label, options, optionValue, optionLabel, selectedValues = []) {
    const opts = options.map((option) => {
        const value = String(option[optionValue]);
        const text = sanitize(option[optionLabel] ?? option.label ?? value);
        const selected = selectedValues.includes(value) ? 'selected' : '';
        return `<option value="${sanitize(value)}" ${selected}>${text}</option>`;
    }).join('');

    return `
        <label class="full">
            <span>${label}</span>
            <select name="${name}" multiple size="4">
                ${opts}
            </select>
            <small class="field-hint">Ctrl/Cmd + clic pour selectionner plusieurs tags.</small>
        </label>
    `;
}

function renderSimpleTable(rows, columns) {
    // Petit tableau reutilisable pour toutes les sections.
    const headers = columns.map(([, label]) => `<th>${label}</th>`).join('');

    const body = rows.map((row) => {
        const cells = columns.map(([key, , formatter]) => {
            const value = row[key];
            const display = formatter ? formatter(value, row) : sanitize(localizeValue(value, key));
            return `<td>${display}</td>`;
        }).join('');

        return `<tr>${cells}</tr>`;
    }).join('');

    return `
        <div class="table-wrap">
            <table class="data-table">
                <thead><tr>${headers}</tr></thead>
                <tbody>${body || `<tr><td colspan="${columns.length}">Aucune donnee</td></tr>`}</tbody>
            </table>
        </div>
    `;
}

async function refreshLookups() {
    const lookupResponse = await apiRequest('/lookups/options');
    state.lookups = lookupResponse.data;
}

// Definition partagee des attributs de variante filtrables (ecrans Variantes
// et Mouvements) - meme colonnes que le generateur en lot / ProductVariantRepository::ATTRIBUTE_COLUMNS
// cote backend. `flag` dit quel reglage (Parametres) active ce menu.
const VARIANT_ATTRIBUTE_DEFS = [
    { key: 'size', label: 'Taille / Pointure', flag: 'clothingVariantsEnabled' },
    { key: 'color', label: 'Couleur', flag: 'clothingVariantsEnabled' },
    { key: 'vintage', label: 'Millesime', flag: 'bottleVariantsEnabled' },
    { key: 'volume_cl', label: 'Contenance (cl)', flag: 'bottleVariantsEnabled' },
    { key: 'width', label: 'Largeur', flag: 'dimensionVariantsEnabled' },
    { key: 'height', label: 'Hauteur', flag: 'dimensionVariantsEnabled' },
    { key: 'depth', label: 'Profondeur', flag: 'dimensionVariantsEnabled' },
    { key: 'weight', label: 'Poids', flag: 'dimensionVariantsEnabled' },
    { key: 'puissance', label: 'Puissance', flag: 'technicalVariantsEnabled' },
    { key: 'marque', label: 'Marque', flag: 'technicalVariantsEnabled' },
    { key: 'type', label: 'Type', flag: 'technicalVariantsEnabled' },
    { key: 'vitesse', label: 'Vitesse', flag: 'technicalVariantsEnabled' },
    { key: 'tension', label: 'Tension', flag: 'technicalVariantsEnabled' },
    { key: 'forme', label: 'Forme', flag: 'technicalVariantsEnabled' },
];

async function refreshVariantAttributeValues() {
    // Petit appel dedie (pas dans /lookups/options : ce ne sont pas des
    // referentiels a ID mais des valeurs de texte libre distinctes par
    // colonne) - voir ProductVariantRepository::attributeValues().
    const response = await apiRequest('/product-variant-attribute-values');
    state.variantAttributeValues = response.data;
}

/**
 * Construit un menu deroulant par attribut actif (Taille, Couleur, Marque...),
 * un seul choix par menu mais combinables entre eux - utilise a la fois par
 * l'ecran Variantes (filtre de la grille) et l'ecran Mouvements (filtre de
 * l'historique). `idPrefix` distingue les deux jeux d'ID dans le DOM.
 */
function renderVariantAttributeFilters(idPrefix, currentFilters) {
    return VARIANT_ATTRIBUTE_DEFS
        .filter((def) => state[def.flag])
        .map((def) => {
            const values = state.variantAttributeValues?.[def.key] ?? [];
            if (values.length === 0) {
                return '';
            }
            const current = currentFilters[def.key] ?? '';
            const options = values.map((value) => `<option value="${sanitize(value)}" ${String(value) === String(current) ? 'selected' : ''}>${sanitize(value)}</option>`).join('');
            return `<select id="${idPrefix}${def.key}Filter" data-attr-filter="${def.key}"><option value="">${sanitize(def.label)} (tous)</option>${options}</select>`;
        })
        .join('');
}

/** Ecoute les changements des menus construits par renderVariantAttributeFilters(). */
function attachVariantAttributeFilterListeners(idPrefix, currentFilters, onChange) {
    VARIANT_ATTRIBUTE_DEFS.forEach((def) => {
        document.getElementById(`${idPrefix}${def.key}Filter`)?.addEventListener('change', async (event) => {
            currentFilters[def.key] = event.target.value;
            await onChange();
        });
    });
}

/**
 * Variante client (sans appel API) des deux fonctions ci-dessus, pour filtrer
 * une liste de variantes DEJA CHARGEE - utilisee par le formulaire "Nouveau
 * mouvement de stock" (et la fiche produit, onglet Stock) pour retrouver plus
 * vite un article parmi les variantes d'UN produit deja recuperees en un
 * appel. Ne propose un menu que pour un attribut ou au moins 2 valeurs
 * distinctes existent parmi CES variantes (inutile de filtrer sur un
 * attribut constant, ou absent, pour CE produit - contrairement aux ecrans
 * Variantes/Mouvements qui listent plusieurs produits a la fois, ici on ne
 * regarde qu'un seul produit : un menu a une seule valeur possible ne
 * filtrerait jamais rien).
 */
function computeAttributeOptionsFromVariants(variants) {
    const result = {};
    VARIANT_ATTRIBUTE_DEFS.forEach((def) => {
        if (!state[def.flag]) {
            return;
        }
        const values = Array.from(new Set(
            variants.map((v) => v[def.key]).filter((v) => v !== null && v !== undefined && String(v) !== '')
        )).sort((a, b) => String(a).localeCompare(String(b), 'fr', { numeric: true }));
        if (values.length > 1) {
            result[def.key] = values;
        }
    });
    return result;
}

function filterVariantsByAttributes(variants, filterValues) {
    return variants.filter((v) => Object.entries(filterValues).every(
        ([key, value]) => value === '' || value === undefined || String(v[key] ?? '') === String(value)
    ));
}

/**
 * Construit et cable les menus de filtre rapide (client) dans `container`, a
 * partir des attributs presents dans `variants`. `onChange` est appele avec
 * les valeurs de filtre a chaque changement.
 */
function renderQuickVariantAttributeFilters(container, variants, filterValues, onChange) {
    if (!container) {
        return;
    }
    const optionsByAttr = computeAttributeOptionsFromVariants(variants);
    const defs = VARIANT_ATTRIBUTE_DEFS.filter((def) => optionsByAttr[def.key]);
    if (defs.length === 0) {
        container.innerHTML = '';
        container.classList.add('hidden');
        return;
    }
    container.classList.remove('hidden');
    container.innerHTML = defs.map((def) => {
        const current = filterValues[def.key] ?? '';
        const options = optionsByAttr[def.key].map((value) => `<option value="${sanitize(value)}" ${String(value) === String(current) ? 'selected' : ''}>${sanitize(value)}</option>`).join('');
        return `<select data-quick-attr-filter="${def.key}"><option value="">${sanitize(def.label)} (tous)</option>${options}</select>`;
    }).join('');
    container.querySelectorAll('[data-quick-attr-filter]').forEach((select) => {
        select.addEventListener('change', (event) => {
            const key = event.target.dataset.quickAttrFilter;
            filterValues[key] = event.target.value;
            onChange();
        });
    });
}

function toQueryString(params) {
    const entries = Object.entries(params).filter(([, value]) => value !== '' && value !== null && value !== undefined);
    if (entries.length === 0) {
        return '';
    }

    const searchParams = new URLSearchParams();
    for (const [key, value] of entries) {
        searchParams.set(key, String(value));
    }

    return `?${searchParams.toString()}`;
}

function renderTagBadges(tags) {
    if (!Array.isArray(tags) || tags.length === 0) {
        return '<span class="muted">-</span>';
    }

    return tags.map((tag) => {
        // Une couleur inexploitable (ancienne saisie libre du type "rouge",
        // champ vide) retombe sur une teinte neutre plutot que de casser le
        // rendu du badge.
        const color = normalizeHexColor(tag.color) ?? '#64748b';
        return `<span class="tag-badge" style="background:${color};color:${readableTextColor(color)}">${sanitize(tag.name)}</span>`;
    }).join(' ');
}

function variantDescriptor(v) {
    // Libelle d'une variante, quel que soit son "type" (vetement:
    // taille/couleur, bouteille: millesime/contenance, ou materiel:
    // largeur/hauteur/profondeur/poids) - v peut venir soit d'un objet
    // variante complet (size/color/vintage/volume_cl/width/height/depth/
    // weight), soit d'une ligne jointe (variant_size/variant_color/
    // variant_vintage/variant_volume_cl/variant_width/...), les deux formats
    // sont acceptes.
    const size = v.size ?? v.variant_size;
    const color = v.color ?? v.variant_color;
    const vintage = v.vintage ?? v.variant_vintage;
    const volumeCl = v.volume_cl ?? v.variant_volume_cl;
    const width = v.width ?? v.variant_width;
    const height = v.height ?? v.variant_height;
    const depth = v.depth ?? v.variant_depth;
    const weight = v.weight ?? v.variant_weight;
    const puissance = v.puissance ?? v.variant_puissance;
    const marque = v.marque ?? v.variant_marque;
    const type = v.type ?? v.variant_type;
    const vitesse = v.vitesse ?? v.variant_vitesse;
    const tension = v.tension ?? v.variant_tension;
    const forme = v.forme ?? v.variant_forme;
    const sku = v.sku ?? v.variant_sku;

    const clothing = [size, color].filter(Boolean);
    if (clothing.length > 0) {
        return clothing.join(' / ');
    }

    const bottle = [];
    if (vintage) {
        bottle.push(`Millesime ${vintage}`);
    }
    if (volumeCl) {
        bottle.push(`${volumeCl}cl`);
    }
    if (bottle.length > 0) {
        return bottle.join(' / ');
    }

    // Dimensions libres : "L 120 cm / H 200 cm / P 60 cm / Poids 12,5 kg". La
    // valeur est affichee telle qu'elle a ete saisie, unite comprise. Meme
    // libelle que cote backend (StockService::refreshProductAlert).
    const dimensions = [];
    if (width) {
        dimensions.push(`L ${width}`);
    }
    if (height) {
        dimensions.push(`H ${height}`);
    }
    if (depth) {
        dimensions.push(`P ${depth}`);
    }
    if (weight) {
        dimensions.push(`Poids ${weight}`);
    }
    if (dimensions.length > 0) {
        return dimensions.join(' / ');
    }

    // Materiel (electrique/mecanique) : "Puissance 1200 W / Marque Bosch /
    // Type ... / Vitesse 3000 tr/min / Tension 230 V / Forme ...". Meme
    // libelle que cote backend (StockService::refreshProductAlert).
    const technical = [];
    if (puissance) {
        technical.push(`Puissance ${puissance}`);
    }
    if (marque) {
        technical.push(`Marque ${marque}`);
    }
    if (type) {
        technical.push(`Type ${type}`);
    }
    if (vitesse) {
        technical.push(`Vitesse ${vitesse}`);
    }
    if (tension) {
        technical.push(`Tension ${tension}`);
    }
    if (forme) {
        technical.push(`Forme ${forme}`);
    }
    if (technical.length > 0) {
        return technical.join(' / ');
    }

    return sku || '-';
}

/**
 * Colonne "Variantes" (detail) de l'ecran Produits : une ligne par variante
 * active, meme libelle que variantDescriptor() partout ailleurs. `variants`
 * vient de ProductRepository::attachVariants() - absent ou vide pour un
 * produit sans variante.
 */
function renderVariantsSummary(variants) {
    if (!Array.isArray(variants) || variants.length === 0) {
        return '<span class="muted">-</span>';
    }

    return variants.map((v) => sanitize(variantDescriptor(v))).join('<br>');
}

function sanitize(value) {
    if (value === null || value === undefined) {
        return '';
    }

    return String(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
}

function formatMoney(value) {
    const amount = Number(value ?? 0);
    return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(amount);
}

/**
 * Demande a l'utilisateur de CHOISIR un entrepot dans une liste deroulante.
 *
 * Remplace les window.prompt() qui reclamaient l'identifiant numerique de
 * l'entrepot : personne ne connait par coeur l'id d'un entrepot, et une
 * faute de frappe envoyait l'article au mauvais endroit sans aucun controle.
 *
 * @returns {Promise<number|null>} l'id choisi, ou null si annulation.
 */
/**
 * Pose une question a choix multiples, formulee dans les termes du metier.
 *
 * Sert la ou une action a une consequence que le code ne peut pas deviner
 * (typiquement : supprimer un numero de serie doit-il retirer l'article du
 * stock ?). Chaque choix affiche sa consequence concrete, pour que
 * l'utilisateur decide en connaissance de cause plutot que de decouvrir
 * l'effet plus tard.
 *
 * @returns {Promise<string|null>} la valeur choisie, ou null si annulation.
 */
// Au-dela de ce nombre d'options, une liste deroulante recoit un champ de
// filtrage. En dessous, le defilement suffit et un champ en plus serait du
// bruit.
const SEARCHABLE_SELECT_THRESHOLD = 12;

// Doit rester synchronise avec FileStorageService::ALLOWED_TYPES (backend) :
// avant cet ajout, rien sur les ecrans "Media" et "Pieces jointes" de la
// fiche produit n'indiquait quels fichiers etaient acceptes - un .txt (par
// exemple) etait refuse sans qu'on sache pourquoi ni quoi essayer a la
// place. Le selecteur de fichiers filtre desormais directement dessus, et
// un texte d'aide rappelle la liste et la taille maximale.
const UPLOAD_ACCEPT_ATTR = '.jpg,.jpeg,.png,.gif,.webp,.pdf,.csv,.doc,.docx,.xls,.xlsx';
const UPLOAD_HINT_TEXT = 'Formats acceptes : images (jpg, png, gif, webp), PDF, Word (doc, docx), Excel (xls, xlsx), CSV. Taille maximale : 15 Mo. Les fichiers .txt ne sont pas acceptes.';

/** Minuscules sans accents, pour un filtrage qui ignore la casse et les accents. */
function searchNormalize(value) {
    return String(value ?? '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase();
}

/**
 * Ajoute un champ de filtrage au-dessus d'une liste deroulante trop longue.
 *
 * Une balise <select> native ne permet de taper que deux ou trois caracteres :
 * le navigateur cherche depuis le DEBUT du libelle et remet son tampon a zero
 * apres une seconde. Avec 144 produits, retrouver "Clavier mecanique" en
 * tapant "clav" est impossible - c'est la limite du composant natif, pas un
 * defaut de configuration.
 *
 * Le filtrage porte sur n'importe quelle partie du libelle (donc aussi le
 * SKU), ignore accents et casse. On reconstruit la liste des options plutot
 * que de jouer sur `option.hidden`, dont le support est inegal selon les
 * navigateurs. Le <select> reste un <select> : les formulaires continuent de
 * lire `.value` sans rien changer.
 */
/**
 * Remplit une liste d'emplacements avec ceux d'un entrepot donne.
 *
 * Les emplacements appartiennent a un entrepot (`warehouse_locations
 * .warehouse_id`) : proposer ceux de tous les entrepots n'aurait aucun sens
 * et permettrait de ranger un article dans une allee qui n'existe pas la ou
 * il se trouve.
 */
function computeVariantAvailability(stockByWarehouse, warehouseId, locationId) {
    // Stock disponible par variante pour un entrepot (et, si precise, un
    // emplacement) donne - utilise pour le mode "deplacer plusieurs
    // variantes a la fois" (Mouvements et fiche produit > Stock), qui a
    // besoin de connaitre la quantite exacte disponible a l'endroit choisi
    // avant de deplacer automatiquement le stock complet de chaque variante
    // cochee. Sans emplacement precise, on additionne toutes les lignes de
    // cet entrepot (meme semantique que source_location_id vide sur un
    // mouvement classique).
    const map = new Map();
    if (!Array.isArray(stockByWarehouse) || !warehouseId) {
        return map;
    }
    stockByWarehouse.forEach((row) => {
        if (row.variant_id === null || row.variant_id === undefined) {
            return;
        }
        if (String(row.warehouse_id) !== String(warehouseId)) {
            return;
        }
        if (locationId && String(row.location_id ?? '') !== String(locationId)) {
            return;
        }
        const key = String(row.variant_id);
        map.set(key, (map.get(key) ?? 0) + Number(row.quantity ?? 0));
    });
    return map;
}

function fillLocationOptions(select, warehouseId, selectedValue = '') {
    if (!select) {
        return;
    }

    const locations = (state.lookups?.warehouse_locations ?? [])
        .filter((location) => String(location.warehouse_id) === String(warehouseId))
        .filter((location) => Number(location.is_active ?? 1) === 1);

    if (!warehouseId) {
        select.innerHTML = '<option value="">Choisis d\'abord un entrepot</option>';
        select.disabled = true;
        return;
    }

    select.disabled = false;

    // Message explicite plutot qu'une liste vide : un entrepot sans
    // emplacement n'est pas une anomalie, mais l'utilisateur doit savoir ou
    // aller en creer plutot que de croire a un dysfonctionnement. Le cas le
    // plus trompeur est celui de l'utilisateur qui n'a cree que des ZONES :
    // elles n'apparaissent nulle part a la saisie, puisque c'est
    // l'emplacement qui porte le stock. Le message le dit.
    if (locations.length === 0) {
        const zoneCount = (state.lookups?.warehouse_zones ?? [])
            .filter((zone) => String(zone.warehouse_id) === String(warehouseId)).length;
        select.innerHTML = zoneCount > 0
            ? `<option value="">Aucun emplacement (${zoneCount} zone(s) definie(s)) - une zone ne se choisit pas ici, cree un emplacement par zone dans Logistique &gt; Emplacements</option>`
            : '<option value="">Aucun emplacement dans cet entrepot - a creer dans Logistique &gt; Emplacements</option>';
        return;
    }

    const optionFor = (location) => {
        const label = location.description
            ? `${location.code} - ${location.description}`
            : location.code;
        return `<option value="${Number(location.id)}" ${String(location.id) === String(selectedValue) ? 'selected' : ''}>${sanitize(label)}</option>`;
    };

    // Regroupement par zone : le nom de la zone apparait comme intitule de
    // groupe. Sans lui, la liste n'affichait que des codes d'emplacement
    // (C1, C2...) et les zones semblaient absentes de l'application.
    const zones = state.lookups?.warehouse_zones ?? [];
    const zoneNameById = new Map(zones.map((zone) => [String(zone.id), zone.name ?? zone.code]));

    const grouped = new Map();
    for (const location of locations) {
        const key = location.zone_id ? String(location.zone_id) : '';
        if (!grouped.has(key)) {
            grouped.set(key, []);
        }
        grouped.get(key).push(location);
    }

    const groups = [...grouped.entries()]
        .map(([zoneId, rows]) => ({
            label: zoneId === '' ? 'Hors zone' : (zoneNameById.get(zoneId) ?? 'Zone ' + zoneId),
            rows,
            orphan: zoneId === '',
        }))
        // Les emplacements sans zone en dernier, le reste par nom de zone.
        .sort((a, b) => (a.orphan === b.orphan ? a.label.localeCompare(b.label, 'fr') : (a.orphan ? 1 : -1)));

    select.innerHTML = '<option value="">Non precise</option>' + groups
        .map((group) => `<optgroup label="${sanitize(group.label)}">${group.rows.map(optionFor).join('')}</optgroup>`)
        .join('');
}

function makeSelectSearchable(select) {
    if (!select || select.dataset.searchable === '1' || select.multiple) {
        return;
    }

    // L'intitule du groupe (ex: le nom de la zone d'un emplacement) fait
    // partie de ce qu'on cherche : taper "reception" doit remonter les
    // emplacements de la zone Reception. Comme le filtrage reconstruit une
    // liste a plat, le nom du groupe est aussi rappele dans le libelle
    // affiche - sinon on ne saurait plus de quelle zone vient chaque ligne.
    const options = Array.from(select.options).map((option) => {
        const group = option.parentElement instanceof HTMLOptGroupElement ? option.parentElement.label : '';
        const text = option.textContent ?? '';
        return {
            value: option.value,
            label: group !== '' && option.value !== '' ? `${text} - ${group}` : text,
            normalized: searchNormalize(group !== '' ? `${text} ${group}` : text),
        };
    });

    if (options.length <= SEARCHABLE_SELECT_THRESHOLD) {
        return;
    }

    select.dataset.searchable = '1';

    const input = document.createElement('input');
    input.type = 'search';
    input.className = 'select-search';
    input.placeholder = `Filtrer (${options.length} entrees)...`;
    input.autocomplete = 'off';
    select.parentNode?.insertBefore(input, select);

    // Entree dans le champ de filtre : on ne soumet pas le formulaire, on
    // laisse simplement le focus passer a la liste.
    input.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
            event.preventDefault();
            select.focus();
        }
    });

    input.addEventListener('input', () => {
        const query = searchNormalize(input.value);
        const previous = select.value;

        const matches = options.filter((option) => option.value === '' || option.normalized.includes(query));
        select.innerHTML = matches
            .map((option) => `<option value="${sanitize(option.value)}">${sanitize(option.label)}</option>`)
            .join('');

        const realMatches = matches.filter((option) => option.value !== '');

        // Un seul resultat : on le selectionne, c'est ce que l'utilisateur
        // cherchait. Sinon on restaure sa selection precedente si elle fait
        // toujours partie des resultats, pour ne jamais la perdre en cours de
        // frappe.
        if (query !== '' && realMatches.length === 1) {
            select.value = realMatches[0].value;
        } else if (matches.some((option) => option.value === previous)) {
            select.value = previous;
        }

        // select.value = ... ne declenche PAS l'evenement 'change' (contrairement
        // a une selection au clavier/souris) : tous les champs qui reagissent au
        // choix du produit (ex: liste des variantes sur l'ecran Numeros de serie,
        // Mouvements, Demandes d'achat...) restaient donc muets quand on passait
        // par le filtre au lieu de choisir directement dans la liste. On simule
        // l'evenement nous-memes, seulement quand la valeur a reellement change.
        if (select.value !== previous) {
            select.dispatchEvent(new Event('change', { bubbles: true }));
        }
    });
}

/** Applique le filtrage a toutes les listes deroulantes longues d'un conteneur. */
function enhanceSelects(root) {
    root?.querySelectorAll('select:not([data-searchable])').forEach(makeSelectSearchable);
}

function askChoice(title, question, choices) {
    return new Promise((resolve) => {
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `
            <div class="modal-box" role="dialog" aria-modal="true">
                <h3>${sanitize(title)}</h3>
                <div class="modal-body">
                    <p>${sanitize(question)}</p>
                    <div class="choice-list">
                        ${choices.map((choice) => `
                            <button type="button" class="btn btn-soft choice-btn" data-choice="${sanitize(choice.value)}">
                                <strong>${sanitize(choice.label)}</strong>
                                <small>${sanitize(choice.hint ?? '')}</small>
                            </button>
                        `).join('')}
                    </div>
                    <div class="form-actions">
                        <button type="button" class="btn btn-soft" id="askChoiceCancel">Annuler</button>
                    </div>
                </div>
            </div>
        `;
        document.body.appendChild(overlay);

        const done = (value) => {
            overlay.remove();
            document.removeEventListener('keydown', onKey);
            resolve(value);
        };
        const onKey = (event) => {
            if (event.key === 'Escape') {
                done(null);
            }
        };

        document.addEventListener('keydown', onKey);
        overlay.addEventListener('click', (event) => {
            if (event.target === overlay) {
                done(null);
            }
        });
        overlay.querySelector('#askChoiceCancel').addEventListener('click', () => done(null));
        overlay.querySelectorAll('.choice-btn').forEach((button) => {
            button.addEventListener('click', () => done(button.dataset.choice));
        });
    });
}

/**
 * Retourne { warehouseId, locationId } (locationId peut etre null), ou null
 * si l'utilisateur annule.
 *
 * L'unique appelant (remettre en stock un numero de serie) attendait deja
 * cette forme d'objet - mais cette fonction ne resolvait jusque-la qu'un
 * simple nombre (l'id d'entrepot). `destination.warehouseId` valait donc
 * toujours `undefined`, silencieusement absent du JSON envoye ; le serveur
 * le traitait comme 0, un entrepot qui n'existe pas - d'ou le message
 * "Reference invalide" (violation de cle etrangere) au moment d'enregistrer.
 * On ajoute ici le choix de l'emplacement (comme partout ailleurs dans
 * l'appli) et on renvoie enfin la forme que l'appelant a toujours attendue.
 */
function askWarehouse(question) {
    return new Promise((resolve) => {
        const warehouses = state.lookups?.warehouses ?? [];
        if (warehouses.length === 0) {
            window.alert('Aucun entrepot n\'est configure.');
            resolve(null);
            return;
        }

        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.innerHTML = `
            <div class="modal-box" role="dialog" aria-modal="true">
                <h3>${sanitize(question)}</h3>
                <div class="modal-body">
                    <label>
                        <span>Entrepot</span>
                        <select id="askWarehouseSelect">
                            ${warehouses.map((w) => `<option value="${Number(w.id)}">${sanitize(w.name ?? w.code ?? w.id)}</option>`).join('')}
                        </select>
                    </label>
                    <label>
                        <span>Emplacement (optionnel)</span>
                        <select id="askWarehouseLocationSelect" disabled>
                            <option value="">Chargement...</option>
                        </select>
                    </label>
                    <div class="form-actions">
                        <button type="button" class="btn btn-primary" id="askWarehouseOk">Valider</button>
                        <button type="button" class="btn btn-soft" id="askWarehouseCancel">Annuler</button>
                    </div>
                </div>
            </div>
        `;
        document.body.appendChild(overlay);

        const warehouseSelect = overlay.querySelector('#askWarehouseSelect');
        const locationSelect = overlay.querySelector('#askWarehouseLocationSelect');
        const syncLocations = () => fillLocationOptions(locationSelect, warehouseSelect.value ?? '');
        warehouseSelect.addEventListener('change', syncLocations);
        syncLocations();

        const done = (value) => {
            overlay.remove();
            document.removeEventListener('keydown', onKey);
            resolve(value);
        };
        const onKey = (event) => {
            if (event.key === 'Escape') {
                done(null);
            }
        };

        document.addEventListener('keydown', onKey);
        overlay.addEventListener('click', (event) => {
            if (event.target === overlay) {
                done(null);
            }
        });
        overlay.querySelector('#askWarehouseCancel').addEventListener('click', () => done(null));
        overlay.querySelector('#askWarehouseOk').addEventListener('click', () => {
            const warehouseId = Number(warehouseSelect.value);
            if (!Number.isFinite(warehouseId) || warehouseId <= 0) {
                done(null);
                return;
            }
            const locationId = locationSelect.value ? Number(locationSelect.value) : null;
            done({ warehouseId, locationId });
        });
    });
}

/**
 * Popup generique pour afficher un detail (contenu d'une demande/commande
 * d'achat...) sans quitter la liste. bodyHtml doit deja etre construit de
 * facon sure par l'appelant (sanitize() sur toute donnee utilisateur), comme
 * pour les formatters de renderSimpleTable.
 */
function showModal(title, bodyHtml) {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.innerHTML = `
        <div class="modal-box" role="dialog" aria-modal="true">
            <button type="button" class="modal-close" aria-label="Fermer">&times;</button>
            <h3>${sanitize(title)}</h3>
            <div class="modal-body">${bodyHtml}</div>
        </div>
    `;
    document.body.appendChild(overlay);

    const close = () => {
        overlay.remove();
        document.removeEventListener('keydown', onEscape);
    };
    const onEscape = (event) => {
        if (event.key === 'Escape') {
            close();
        }
    };

    overlay.addEventListener('click', (event) => {
        if (event.target === overlay) {
            close();
        }
    });
    overlay.querySelector('.modal-close').addEventListener('click', close);
    document.addEventListener('keydown', onEscape);
}

// Colonnes dont la valeur est une donnee saisie par l'utilisateur (SKU, code,
// nom...) et non un statut technique : on ne les traduit jamais, sans quoi une
// unite dont le code est "IN" (pouce) s'afficherait "Entree".
const RAW_VALUE_KEYS = new Set([
    'sku', 'product_sku', 'code', 'barcode', 'name', 'product_name', 'full_name',
    'contact_name', 'email', 'phone', 'address', 'description', 'reference',
    'unit_code', 'warehouse_code', 'destination_warehouse_code', 'serial_number',
    'setting_key', 'setting_value', 'descriptor', 'variant_sku', 'note', 'notes',
    'category_name', 'brand_name', 'supplier_name', 'customer_name', 'size', 'color',
    // Dimensions de variante : texte libre saisi par l'utilisateur ("2 m",
    // "3/4 pouce"), a n'interpreter sous aucun pretexte.
    'width', 'height', 'depth', 'weight',
]);

const VALUE_LABELS = {
    // Statuts generiques
    ACTIVE: 'Actif',
    INACTIVE: 'Inactif',
    PENDING: 'En attente',
    PARTIAL: 'Partielle',
    RECEIVED: 'Recue',
    CANCELLED: 'Annulee',
    DRAFT: 'Brouillon',
    SUBMITTED: 'Soumise',
    APPROVED: 'Approuvee',
    REJECTED: 'Rejetee',
    CONVERTED: 'Convertie',
    COMPLETED: 'Terminee',
    IN_PROGRESS: 'En cours',
    VALIDATED: 'Validee',
    OPEN: 'Ouverte',
    ACKNOWLEDGED: 'Accusee',
    RESOLVED: 'Resolue',
    WARNING: 'Avertissement',
    CRITICAL: 'Critique',
    INFO: 'Information',
    // Types de mouvement de stock
    IN: 'Entree',
    OUT: 'Sortie',
    ADJUSTMENT: 'Ajustement',
    TRANSFER: 'Transfert',
    // Statut d'un numero de serie (OUT partage deja le libelle "Sortie" ci-dessus)
    IN_STOCK: 'En stock',
    // Motifs de mouvement generes automatiquement par l'application (colonne
    // "Motif" de l'historique des mouvements) - avant cet ajout, ces codes
    // techniques restaient affiches tels quels, en anglais, alors que tout
    // le reste de l'ecran est traduit. Le champ "Code motif" restant du
    // texte libre (l'utilisateur peut y saisir ce qu'il veut), seuls les
    // codes que l'application genere elle-meme peuvent etre traduits avec
    // certitude.
    INITIAL_STOCK: 'Stock initial',
    INVENTORY: 'Regularisation inventaire',
    PO_RECEIPT: 'Reception commande achat',
    DELIVERY: 'Livraison client',
    DELIVERY_CANCEL: 'Annulation livraison',
    SERIAL_IN: 'Entree numero de serie',
    SERIAL_OUT: 'Sortie numero de serie',
    SERIAL_RETURN: 'Retour en stock (numero de serie)',
    SERIAL_DELETED: 'Suppression numero de serie',
    // Motifs frequemment saisis a la main (anciennes habitudes/import) :
    // traduits aussi, par coherence avec le reste de l'ecran.
    PURCHASE: 'Achat',
    SALE: 'Vente',
    // Types d'inventaire
    GLOBAL: 'Global',
    CYCLE: 'Tournant',
    // Types d'alerte
    LOW_STOCK: 'Stock bas',
    OUT_OF_STOCK: 'Rupture',
    OVERSTOCK: 'Surstock',
    PO_DELAY: 'Retard commande',
    // Etats de tache d'import
    RUNNING: 'En cours',
    DONE: 'Terminee',
    FAILED: 'Echouee',
    // Types de piece jointe
    IMAGE: 'Image',
    DOCUMENT: 'Document',
    // Profils utilisateur (memes libelles que ROLE_MATRIX, qui fait foi)
    SUPER_ADMIN: 'Super administrateur',
    ADMIN: 'Administrateur',
    MANAGER: 'Responsable',
    STOREKEEPER: 'Magasinier',
    BUYER: 'Acheteur',
    EMPLOYEE: 'Employe',
    VIEWER: 'Lecture seule',
};

function localizeValue(value, key = null) {
    // Traduction simple des statuts techniques vers des libelles lisibles.
    // `key` (nom de la colonne) permet d'ecarter les colonnes de donnees libres.
    if (key !== null && RAW_VALUE_KEYS.has(key)) {
        return value;
    }

    return VALUE_LABELS[String(value ?? '')] ?? value;
}
