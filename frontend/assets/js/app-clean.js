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
};

const dashboardCharts = {
    movementTrend: null,
    outgoing: null,
};

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

const crudModules = {
    categories: {
        endpoint: '/categories',
        label: 'categorie',
        fields: [
            { key: 'parent_id', label: 'Categorie parent', type: 'select', optionsFrom: 'categories', optionLabel: 'name' },
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'description', label: 'Description', type: 'textarea' },
            { key: 'default_min_stock', label: 'Seuil mini defaut', type: 'number' },
            { key: 'default_max_stock', label: 'Seuil maxi defaut', type: 'number' },
            { key: 'default_tax_id', label: 'Taxe defaut', type: 'select', optionsFrom: 'taxes', optionLabel: 'name' },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'name', label: 'Nom' },
            { key: 'parent_id', label: 'Parent' },
            { key: 'default_min_stock', label: 'Min' },
            { key: 'default_max_stock', label: 'Max' },
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
            { key: 'color', label: 'Couleur', type: 'text' },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'name', label: 'Nom' },
            { key: 'color', label: 'Couleur' },
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
            { key: 'barcode', label: 'Code barre', type: 'text' },
            { key: 'name', label: 'Nom', type: 'text', required: true },
            { key: 'description', label: 'Description', type: 'textarea' },
            { key: 'category_id', label: 'Categorie', type: 'select', optionsFrom: 'categories', optionLabel: 'name', required: true },
            { key: 'supplier_id', label: 'Fournisseur', type: 'select', optionsFrom: 'suppliers', optionLabel: 'name' },
            { key: 'unit_id', label: 'Unite', type: 'select', optionsFrom: 'units', optionLabel: 'code' },
            { key: 'brand_id', label: 'Marque', type: 'select', optionsFrom: 'brands', optionLabel: 'name' },
            { key: 'pack_size', label: 'Conditionnement', type: 'text' },
            { key: 'weight_kg', label: 'Poids kg', type: 'number', step: '0.001' },
            { key: 'width_cm', label: 'Largeur cm', type: 'number', step: '0.01' },
            { key: 'height_cm', label: 'Hauteur cm', type: 'number', step: '0.01' },
            { key: 'depth_cm', label: 'Profondeur cm', type: 'number', step: '0.01' },
            { key: 'unit_price', label: 'Prix vente', type: 'number', step: '0.01' },
            { key: 'cost_price', label: 'Prix achat', type: 'number', step: '0.01' },
            { key: 'tax_id', label: 'Taxe (TVA)', type: 'select', optionsFrom: 'taxes', optionLabel: 'name' },
            { key: 'reorder_level', label: 'Seuil alerte', type: 'number' },
            { key: 'min_stock', label: 'Stock mini', type: 'number' },
            { key: 'max_stock', label: 'Stock maxi', type: 'number' },
            { key: 'safety_stock', label: 'Stock securite', type: 'number' },
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
            if (state.clothingVariantsEnabled || state.bottleVariantsEnabled) {
                fields.push({ key: 'has_variants', label: `Ce produit a des variantes (${variantsAttributesLabel()})`, type: 'select', options: [
                    { value: '0', label: 'Non' },
                    { value: '1', label: 'Oui - gerer les variantes dans le module dedie' },
                ] });
            }

            fields.push({ key: 'tag_ids', label: 'Tags', type: 'multiselect', optionsFrom: 'tags', optionLabel: 'name', valueFrom: 'tags' });
            return fields;
        },
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'sku', label: 'SKU' },
            { key: 'barcode', label: 'Code barre' },
            { key: 'name', label: 'Nom' },
            { key: 'category_name', label: 'Categorie' },
            { key: 'brand_name', label: 'Marque' },
            { key: 'unit_code', label: 'Unite' },
            { key: 'supplier_name', label: 'Fournisseur' },
            { key: 'stock_total', label: 'Stock' },
            { key: 'unit_price', label: 'Prix', format: (value) => formatMoney(value) },
            { key: 'tax_rate', label: 'TVA', format: (value) => (value !== null && value !== undefined ? `${Number(value)}%` : '-') },
            { key: 'valuation_method', label: 'Valorisation' },
            { key: 'is_active', label: 'Actif', format: (v) => (Number(v) === 1 ? 'Oui' : 'Non') },
            { key: 'has_variants', label: 'Variantes', format: (v) => (Number(v) === 1 ? 'Oui' : 'Non') },
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
                { key: 'barcode', label: 'Code barre', type: 'text' },
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
            { key: 'id', label: 'ID' },
            { key: 'warehouse_id', label: 'Entrepot' },
            { key: 'code', label: 'Code' },
            { key: 'name', label: 'Nom' },
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
            { key: 'id', label: 'ID' },
            { key: 'warehouse_id', label: 'Entrepot' },
            { key: 'zone_id', label: 'Zone' },
            { key: 'code', label: 'Code' },
            { key: 'capacity', label: 'Capacite' },
        ],
    },
    users: {
        endpoint: '/users',
        label: 'utilisateur',
        fields: [
            { key: 'full_name', label: 'Nom complet', type: 'text', required: true },
            { key: 'email', label: 'Email', type: 'email', required: true },
            { key: 'password', label: 'Mot de passe', type: 'password', requiredOnCreate: true },
            { key: 'role', label: 'Profil', type: 'select', optionsFrom: 'roles', optionValue: 'code', optionLabel: 'code', required: true },
            { key: 'is_active', label: 'Actif', type: 'select', options: [
                { value: '1', label: 'Oui' },
                { value: '0', label: 'Non' },
            ] },
        ],
        columns: [
            { key: 'id', label: 'ID' },
            { key: 'full_name', label: 'Nom' },
            { key: 'email', label: 'Email' },
            { key: 'role_code', label: 'Profil' },
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
    const [meResponse, lookupResponse, clothingSettingResponse, bottleSettingResponse, valuationSettingResponse] = await Promise.all([
        apiRequest('/auth/me'),
        apiRequest('/lookups/options'),
        apiRequest('/settings?setting_key=clothing_variants_enabled').catch(() => null),
        apiRequest('/settings?setting_key=bottle_variants_enabled').catch(() => null),
        apiRequest('/settings?setting_key=default_valuation_method').catch(() => null),
    ]);

    state.user = meResponse.data;
    state.lookups = lookupResponse.data;
    const clothingRow = normalizeRows(clothingSettingResponse)[0];
    const bottleRow = normalizeRows(bottleSettingResponse)[0];
    state.clothingVariantsEnabled = String(clothingRow?.setting_value ?? '0') === '1';
    state.bottleVariantsEnabled = String(bottleRow?.setting_value ?? '0') === '1';
    syncValuationSettingState(normalizeRows(valuationSettingResponse)[0]?.setting_value);

    const userPill = document.getElementById('userPill');
    userPill.textContent = `${state.user.full_name} | ${localizeValue(state.user.role)}`;
    userPill.addEventListener('click', () => {
        setActiveNav('account');
        renderModule('account');
    });

    setupNavigation();
    applyNavAccess();
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
    return parts.length === 0 ? 'aucune option activee' : parts.join(' ou ');
}

function syncVariantsSettingState(settingKey, settingValue) {
    const enabled = String(settingValue ?? '0') === '1';
    if (settingKey === 'clothing_variants_enabled') {
        state.clothingVariantsEnabled = enabled;
    } else if (settingKey === 'bottle_variants_enabled') {
        state.bottleVariantsEnabled = enabled;
    }

    // Reaffiche/masque immediatement le lien "Variantes" sans attendre un
    // rechargement complet de la page.
    const hasEitherEnabled = state.clothingVariantsEnabled || state.bottleVariantsEnabled;
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
    // Module optionnel (vetement: taille/couleur, OU bouteille:
    // millesime/contenance) : masque le lien de navigation tant qu'aucune
    // des deux options n'est activee dans Parametres.
    if (!state.clothingVariantsEnabled && !state.bottleVariantsEnabled) {
        document.querySelector('[data-module="product-variants"]')?.remove();
    }
}

function applyNavAccess() {
    const isAdmin = canWrite('users');
    if (isAdmin) {
        return;
    }

    const hiddenModules = ['users', 'settings', 'imports', 'audits'];
    hiddenModules.forEach((module) => {
        const btn = document.querySelector(`[data-module="${module}"]`);
        btn?.remove();
    });
    document.getElementById('demoDataNavLink')?.remove();
    document.getElementById('migrateNavLink')?.remove();
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

function setupGlobalSearch() {
    const input = document.getElementById('globalSearch');
    input?.addEventListener('keydown', async (event) => {
        if (event.key !== 'Enter') {
            return;
        }

        event.preventDefault();
        state.globalQuery = String(input.value ?? '').trim();
        // Nouvelle recherche = nouveau jeu de resultats : rester page 3
        // afficherait une page vide.
        state.crudPages.products = 1;
        setActiveNav('products');
        await renderModule('products');
    });
}

function canWrite(module) {
    const role = String(state.user?.role ?? '').toUpperCase();
    if (role === 'SUPER_ADMIN' || role === 'ADMIN') {
        return true;
    }

    const matrix = {
        BUYER: ['suppliers', 'customers', 'purchase-requests', 'purchase-orders'],
        STOREKEEPER: ['movements', 'product-serials', 'product-variants', 'deliveries', 'inventories', 'alerts'],
        MANAGER: ['movements', 'product-serials', 'product-variants', 'deliveries', 'inventories', 'alerts', 'purchase-requests', 'purchase-orders', 'suppliers'],
    };

    return Boolean(matrix[role]?.includes(module));
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
    state.module = normalized;

    if (updateUrl) {
        syncUrlModule(normalized);
    }

    document.getElementById('pageTitle').textContent = moduleTitles[normalized] ?? normalized;

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
        { label: 'PO en retard', value: data.totals.delayed_po, icon: 'bi-clock-history', theme: 'kpi-violet', target: 'purchase-orders' },
        { label: 'PO ouvertes', value: data.totals.purchase_orders_pending, icon: 'bi-cart-check', theme: 'kpi-cyan', target: 'purchase-orders' },
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

async function renderAudits() {
    // Journal d'audit en lecture seule (qui a fait quoi) - reserve aux admins,
    // deja filtre par le middleware cote backend, on ne fait ici que l'affichage.
    const root = document.getElementById('appContent');

    const filters = state.auditFilters ?? { user_id: '', action: '' };
    state.auditFilters = filters;

    const [usersResponse, auditsResponse] = await Promise.all([
        apiRequest('/users' + toQueryString({ per_page: 200 })),
        apiRequest('/audits' + toQueryString({ ...filters, per_page: 100 })),
    ]);

    const users = normalizeRows(usersResponse);
    const rows = normalizeRows(auditsResponse);
    const actionOptions = ['CREATE', 'UPDATE', 'DELETE', 'RESET_PASSWORD', 'LOGIN', 'LOGOUT'];

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
                        ${actionOptions.map((a) => `<option value="${a}" ${filters.action === a ? 'selected' : ''}>${a}</option>`).join('')}
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
                ['user_name', 'Utilisateur', (value, row) => sanitize(value ?? row.user_email ?? 'Systeme')],
                ['action', 'Action'],
                ['entity_type', 'Entite'],
                ['entity_id', 'ID'],
                ['ip_address', 'IP'],
                ['payload_json', 'Detail', (value) => (value ? `<code>${sanitize(value)}</code>` : '')],
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

    const query = {
        page: state.crudPages[module] ?? 1,
        per_page: state.crudPerPage,
    };
    if (module === 'products' && state.globalQuery !== '') {
        query.q = state.globalQuery;
    }
    if (module === 'products' && state.tagFilter !== '') {
        query.tag_id = state.tagFilter;
    }
    if (module === 'product-variants' && state.pendingVariantProductId) {
        query.product_id = state.pendingVariantProductId;
        state.pendingVariantProductId = null;
        query.page = 1;
        state.crudPages[module] = 1;
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

    const tagFilterOptions = module === 'products'
        ? (state.lookups?.tags ?? []).map((tag) => `<option value="${tag.id}" ${String(tag.id) === String(state.tagFilter) ? 'selected' : ''}>${sanitize(tag.name)}</option>`).join('')
        : '';

    root.innerHTML = `
        <section class="panel">
            <div class="panel-head">
                <h4>Gestion ${config.label}</h4>
                <div class="panel-actions">
                    ${module === 'products' ? `<select id="productTagFilter"><option value="">Tous les tags</option>${tagFilterOptions}</select>` : ''}
                    ${module === 'products' ? '<button class="btn btn-soft" id="clearProductSearch">Effacer filtre</button>' : ''}
                    ${writable ? '<button class="btn btn-primary" id="createBtn">Nouveau</button>' : ''}
                </div>
            </div>

            <form id="crudForm" class="form-grid hidden"></form>
            <div id="crudFeedback" class="feedback"></div>

            ${renderCrudTable(config, rows, writable, module)}
            ${renderPaginationBar(meta, rows.length)}
        </section>
        ${module === 'products' ? '<section class="panel" id="productDetailPane"><h4>Fiche produit</h4><p class="muted">Selectionne un produit pour afficher sa fiche detaillee.</p></section>' : ''}
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

        document.getElementById('clearProductSearch')?.addEventListener('click', async () => {
            state.globalQuery = '';
            state.tagFilter = '';
            state.crudPages.products = 1;
            const input = document.getElementById('globalSearch');
            if (input) {
                input.value = '';
            }
            await renderCrud('products');
        });
    }

    setupPagination(module, meta);

    if (module === 'product-variants' && writable) {
        setupVariantGenerator();
    }

    if (writable) {
        const createBtn = document.getElementById('createBtn');

        createBtn?.addEventListener('click', () => {
            editId = null;
            resetPasswordId = null;
            feedback.textContent = '';
            form.classList.remove('hidden');
            form.innerHTML = buildFormFields(config.fields, null, false) + formActions();
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
            if (viewBtn) {
                const id = Number(viewBtn.dataset.id);
                state.activeProductId = id;
                await renderProductDetail(id);
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
                    if (['clothing_variants_enabled', 'bottle_variants_enabled'].includes(deletedSettingKey)) {
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
                if (module === 'settings' && ['clothing_variants_enabled', 'bottle_variants_enabled'].includes(payload.setting_key)) {
                    syncVariantsSettingState(payload.setting_key, payload.setting_value);
                }
                if (module === 'settings' && payload.setting_key === 'default_valuation_method') {
                    syncValuationSettingState(payload.setting_value);
                }

                // Un produit "a variantes" fraichement cree n'a encore aucune
                // variante : il est inutilisable en mouvement tant qu'on n'est
                // pas passe par le module dedie. On propose donc le raccourci
                // au lieu de laisser l'utilisateur deviner l'etape suivante.
                const createdProductId = module === 'products'
                    && editId === null
                    && String(payload.has_variants ?? '0') === '1'
                    ? Number(saveResponse?.data?.id ?? saveResponse?.id ?? 0) || null
                    : null;

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
        await renderProductDetail(state.activeProductId);
    }
}

async function renderMovements() {
    // Journal des mouvements + creation rapide.
    const root = document.getElementById('appContent');

    const [listResponse] = await Promise.all([
        apiRequest('/stock/movements'),
        refreshLookups(),
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
                    <label><span>Variante</span><select name="variant_id" id="movementVariantSelect"></select></label>
                    <small class="field-hint">Ce produit utilise des variantes : choisis celle concernee par ce mouvement.</small>
                </div>
                ${selectField('warehouse_id', 'Entrepot source', state.lookups.warehouses, 'id', 'name', true)}
                ${selectField('destination_warehouse_id', 'Entrepot destination', state.lookups.warehouses, 'id', 'name', false)}
                <label><span>Type</span><select name="type" required>
                    <option value="IN">Entree</option>
                    <option value="OUT">Sortie</option>
                    <option value="ADJUSTMENT">Ajustement</option>
                    <option value="TRANSFER">Transfert</option>
                </select></label>
                <label><span>Quantite</span><input type="number" name="quantity" min="1" required></label>
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
                <label><span>Code motif</span><input type="text" name="reason_code"></label>
                <label class="full"><span>Note</span><textarea name="notes"></textarea></label>
                <button type="submit" class="btn btn-primary">Enregistrer mouvement</button>
                <p id="movementFeedback" class="feedback"></p>
            </form>
            ` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>

        <section class="panel">
            <h4>Historique mouvements</h4>
            ${renderSimpleTable(rows, [
                ['created_at', 'Date'],
                ['type', 'Type'],
                ['product_name', 'Produit'],
                ['variant_sku', 'Variante', (v, row) => (row.variant_id ? sanitize(variantDescriptor(row)) : '-')],
                ['quantity', 'Quantite'],
                ['balance_after', 'Stock apres'],
                ['warehouse_name', 'Source'],
                ['destination_warehouse_name', 'Destination'],
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
    let availableOutSerialCount = 0;

    const loadVariantOptions = async () => {
        if (!variantWrap || !variantSelect) {
            return;
        }
        const productId = productSelect?.value;
        const product = state.lookups.products.find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;
        variantWrap.classList.toggle('hidden', !hasVariants);
        variantSelect.required = hasVariants;

        if (!hasVariants || !productId) {
            variantSelect.innerHTML = '';
            return;
        }

        variantSelect.innerHTML = '<option value="">Chargement...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=200`);
        const variants = normalizeRows(response);
        variantSelect.innerHTML = variants.length === 0
            ? '<option value="">Aucune variante active pour ce produit</option>'
            : variants.map((v) => {
                const descriptors = variantDescriptor(v);
                return `<option value="${v.id}">${sanitize(descriptors)} (stock: ${v.stock_total ?? 0})</option>`;
            }).join('');
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
        const query = `product_id=${productId}&status=IN_STOCK&per_page=200${warehouseId ? `&warehouse_id=${warehouseId}` : ''}`;
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

    const toggleSerialsWrap = () => {
        const isIn = typeSelect?.value === 'IN';
        const isOut = typeSelect?.value === 'OUT';
        serialsInWrap?.classList.toggle('hidden', !isIn);
        serialsOutWrap?.classList.toggle('hidden', !isOut);
        if (isOut) {
            loadOutSerialOptions();
        }
    };
    toggleSerialsWrap();
    typeSelect?.addEventListener('change', toggleSerialsWrap);
    productSelect?.addEventListener('change', loadOutSerialOptions);
    warehouseSelect?.addEventListener('change', loadOutSerialOptions);
    productSelect?.addEventListener('change', loadVariantOptions);
    loadVariantOptions();

    form?.addEventListener('submit', async (event) => {
        event.preventDefault();
        feedback.textContent = '';
        feedback.classList.remove('is-error');

        const data = new FormData(form);
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
            type,
            quantity,
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
                        body: { product_id: productId, warehouse_id: warehouseId, serial_numbers: serialNumbers },
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
                        await apiRequest(`/product-serials/${serialId}/mark-out`, { method: 'POST', body: {} });
                    } catch (serialError) {
                        failures.push(`#${serialId}: ${serialError.message}`);
                    }
                }
                await renderMovements();
                if (failures.length > 0) {
                    window.alert(`Mouvement enregistre, mais erreur sur certains numeros de serie:\n${failures.join('\n')}`);
                }
                return;
            }

            await renderMovements();
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
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
                ${selectField('warehouse_id', 'Entrepot', state.lookups.warehouses, 'id', 'name', false)}
                <label class="full">
                    <span>Numero(s) de serie (un par ligne, pour enregistrer plusieurs exemplaires recus en une fois)</span>
                    <textarea name="serial_numbers" rows="4" placeholder="SN-00012345&#10;SN-00012346" required></textarea>
                </label>
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
                ['warehouse_name', 'Entrepot'],
                ['status', 'Statut'],
                ['created_at', 'Enregistre le'],
                ...(writable ? [['id', 'Actions', (value, row) => `
                    ${row.status === 'IN_STOCK'
                        ? `<button class="btn btn-soft" data-mark-out="${value}">Marquer sorti</button>`
                        : `<button class="btn btn-soft" data-mark-in="${value}">Remettre en stock</button>`}
                    <button class="btn btn-soft" data-delete-serial="${value}">Supprimer</button>
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
                    <p><strong>${sanitize(found.product_name)}</strong> (${sanitize(found.sku)})</p>
                    <p>Numero de serie: ${sanitize(found.serial_number)}</p>
                    <p>Statut: ${sanitize(found.status)}</p>
                    <p>Entrepot: ${sanitize(found.warehouse_name ?? '-')}</p>
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

        const payload = {
            product_id: Number(data.get('product_id')),
            warehouse_id: warehouseId,
            serial_numbers: serialNumbers,
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
            const warehouseId = window.prompt('Id de l\'entrepot de retour en stock ?');
            if (!warehouseId) {
                return;
            }
            try {
                await apiRequest(`/product-serials/${btn.dataset.markIn}/mark-in-stock`, {
                    method: 'POST',
                    body: { warehouse_id: Number(warehouseId) },
                });
                await renderProductSerials();
            } catch (error) {
                window.alert(error.message);
            }
        });
    });

    root.querySelectorAll('[data-delete-serial]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            if (!window.confirm('Supprimer ce numero de serie ?')) {
                return;
            }
            try {
                await apiRequest(`/product-serials/${btn.dataset.deleteSerial}`, { method: 'DELETE' });
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
                ['delivery_number', 'Numero'],
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
                const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=200`);
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
                const response = await apiRequest(`/product-serials?product_id=${productId}&status=IN_STOCK&per_page=200`);
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
                ['min_stock', 'Min'],
                ['reorder_level', 'Seuil'],
            ])}
        </section>
        <section class="panel">
            <h4>PO en retard</h4>
            ${renderSimpleTable(computed.data.delayed_po ?? [], [
                ['order_number', 'PO'],
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

    const itemsHtml = items.map((item) => {
        const diff = Number(item.difference_qty);
        const diffClass = diff === 0 ? '' : (diff > 0 ? 'is-positive' : 'is-error');
        const diffLabel = diff > 0 ? `+${diff}` : String(diff);
        return `
            <tr>
                <td>${sanitize(item.sku)}</td>
                <td>${sanitize(item.product_name)}</td>
                <td>${item.variant_id ? sanitize(variantDescriptor({ ...item, sku: item.variant_sku })) : '-'}</td>
                <td>${Number(item.expected_qty)}</td>
                <td>${Number(item.counted_qty)}</td>
                <td class="${diffClass}">${diffLabel}</td>
                <td>${sanitize(item.location_code ?? '-')}</td>
                <td>${sanitize(item.counted_by_name ?? '-')}</td>
                <td>${sanitize(item.counted_at)}</td>
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
            <p class="muted">Si un produit est compte plusieurs fois, seul le dernier comptage saisi pour ce produit sera applique a la finalisation.</p>
            <div class="table-wrap">
                <table class="data-table">
                    <thead><tr><th>SKU</th><th>Produit</th><th>Variante</th><th>Attendu</th><th>Compte</th><th>Ecart</th><th>Emplacement</th><th>Compte par</th><th>Date</th></tr></thead>
                    <tbody>${itemsHtml || '<tr><td colspan="9">Aucun comptage saisi pour le moment.</td></tr>'}</tbody>
                </table>
            </div>
        </section>

        ${writable && isEditable ? `
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
                ${selectField('location_id', 'Emplacement', state.lookups.warehouse_locations, 'id', 'code', false)}
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
            const variantsResponse = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=200`);
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

    const response = await apiRequest('/purchase-requests');
    const rows = normalizeRows(response);
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
                <select name="variant_id" id="requestLineVariant" class="hidden"><option value="">-</option></select>
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
            <h4>Demandes achat</h4>
            ${renderSimpleTable(rows, [
                ['request_number', 'Numero'],
                ['status', 'Statut'],
                ['warehouse_name', 'Entrepot'],
                ['requester_name', 'Demandeur'],
                ['requested_at', 'Date'],
                ['id', 'Detail', (value) => `<button type="button" class="btn btn-soft" data-view-request="${value}">Voir le detail</button>`],
            ])}
        </section>
    `;

    const lineForm = document.getElementById('requestLineForm');
    const lineProductSelect = lineForm?.elements.namedItem('product_id');
    const lineVariantSelect = document.getElementById('requestLineVariant');

    const refreshLineVariants = async () => {
        const productId = lineProductSelect?.value;
        const product = (state.lookups.products ?? []).find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;
        lineVariantSelect.classList.toggle('hidden', !hasVariants);
        lineVariantSelect.required = hasVariants;
        lineVariantSelect.innerHTML = '<option value="">-</option>';
        if (!hasVariants || !productId) {
            return;
        }
        lineVariantSelect.innerHTML = '<option value="">Choisir...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=200`);
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

    const listResponse = await apiRequest('/purchase-orders');
    const rows = normalizeRows(listResponse);
    const writable = canWrite('purchase-orders');
    const orderOptions = rows.map((row) => `<option value="${row.id}">${sanitize(row.order_number)} | ${sanitize(row.status)}</option>`).join('');

    const requestsResponse = await apiRequest('/purchase-requests');
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
                <select name="variant_id" id="orderLineVariant" class="hidden"><option value="">-</option></select>
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
                <div id="receiptItemsContainer" class="full"><p class="muted">Choisis une commande pour voir ses lignes restantes.</p></div>
                <button type="submit" class="btn btn-primary">Receptionner les lignes cochees</button>
                <p id="poReceiptFeedback" class="feedback"></p>
            </form>
            ` : '<p class="muted">Acces en lecture seule sur ce module.</p>'}
        </section>

        <section class="panel">
            <h4>Commandes achat</h4>
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
        </section>
    `;

    const lineForm = document.getElementById('orderLineForm');
    const itemsPreview = document.getElementById('orderItemsPreview');
    const orderLineProductSelect = lineForm?.elements.namedItem('product_id');
    const orderLineVariantSelect = document.getElementById('orderLineVariant');

    const refreshOrderLineVariants = async () => {
        const productId = orderLineProductSelect?.value;
        const product = (state.lookups.products ?? []).find((p) => String(p.id) === String(productId));
        const hasVariants = Number(product?.has_variants) === 1;
        orderLineVariantSelect.classList.toggle('hidden', !hasVariants);
        orderLineVariantSelect.required = hasVariants;
        orderLineVariantSelect.innerHTML = '<option value="">-</option>';
        if (!hasVariants || !productId) {
            return;
        }
        orderLineVariantSelect.innerHTML = '<option value="">Choisir...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=200`);
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

    const loadReceiptItems = async (orderId) => {
        if (!orderId) {
            receiptItemsContainer.innerHTML = '<p class="muted">Choisis une commande pour voir ses lignes restantes.</p>';
            return;
        }

        const orderResponse = await apiRequest(`/purchase-orders/${orderId}`);
        const order = orderResponse.data ?? {};
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
                body: { items },
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
    // Exports rapides en CSV pour exploitation externe.
    const root = document.getElementById('appContent');

    root.innerHTML = `
        <section class="panel">
            <h4>Exports CSV</h4>
            <div class="panel-actions">
                <button class="btn btn-primary" data-report="/reports/stock.csv" data-name="stock-report.csv">Export stock</button>
                <button class="btn btn-primary" data-report="/reports/movements.csv" data-name="movements-report.csv">Export mouvements</button>
                <button class="btn btn-primary" data-report="/reports/purchases.csv" data-name="purchases-report.csv">Export achats</button>
            </div>
        </section>
    `;

    root.querySelectorAll('[data-report]').forEach((btn) => {
        btn.addEventListener('click', async () => {
            await downloadCsv(btn.getAttribute('data-report'), btn.getAttribute('data-name') ?? 'report.csv');
        });
    });
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
                <p id="importFeedback" class="feedback"></p>
            </form>
            <p class="muted">Headers recommandes: products(sku,name,category_name,supplier_name,unit_price,cost_price,reorder_level,status,barcode), suppliers(name,contact_name,phone,email,address), customers(code,name,email,phone,address,status), initial-stocks(sku,warehouse_code,quantity).</p>
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

async function renderProductDetail(productId) {
    // Fiche produit multi-onglets (stock, media, pieces jointes, etiquette).
    const pane = document.getElementById('productDetailPane');
    if (!pane) {
        return;
    }

    const [productResponse, movementResponse, attachmentResponse] = await Promise.all([
        apiRequest(`/products/${productId}`),
        apiRequest(`/stock/movements?product_id=${productId}&per_page=20`),
        apiRequest(`/attachments?entity_type=product&entity_id=${productId}`),
    ]);

    const product = productResponse.data;
    const movements = normalizeRows(movementResponse);
    const attachments = normalizeRows(attachmentResponse);
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
            <button class="btn btn-soft" data-tab="media">Media</button>
            <button class="btn btn-soft" data-tab="attachments">Pieces jointes</button>
            <button class="btn btn-soft" data-tab="label">Etiquette</button>
        </div>
        <div class="tab-panel" data-tab-panel="info">
            <div class="cards-grid">
                <article class="metric-card"><p>Categorie</p><h3>${sanitize(product.category_name)}</h3></article>
                <article class="metric-card"><p>Fournisseur</p><h3>${sanitize(product.supplier_name)}</h3></article>
                <article class="metric-card"><p>Stock total</p><h3>${sanitize(product.stock_total)}</h3></article>
                <article class="metric-card"><p>Prix vente</p><h3>${formatMoney(product.unit_price)}</h3></article>
                <article class="metric-card"><p>Prix achat</p><h3>${formatMoney(product.cost_price)}</h3></article>
                <article class="metric-card"><p>Code-barres</p><h3>${sanitize(product.barcode || '-')}</h3></article>
            </div>
            <p class="muted">${sanitize(product.description)}</p>
            <p>${renderTagBadges(product.tags)}</p>
        </div>
        <div class="tab-panel hidden" data-tab-panel="stock">
            ${renderSimpleTable(stockRows, [
                ['warehouse_code', 'Code'],
                ['warehouse_name', 'Entrepot'],
                ['variant_label', 'Variante'],
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
                ${selectField('destination_warehouse_id', 'Entrepot destination', state.lookups.warehouses, 'id', 'name', false)}
                <div class="full ${Number(product.has_variants) === 1 ? '' : 'hidden'}" id="productMoveVariantWrap">
                    <label><span>Variante</span><select name="variant_id" id="productMoveVariantSelect" ${Number(product.has_variants) === 1 ? 'required' : ''}></select></label>
                    <small class="field-hint">Ce produit utilise des variantes : choisis celle concernee par ce mouvement.</small>
                </div>
                <label><span>Type</span><select name="type" required>
                    <option value="IN">Entree</option>
                    <option value="OUT">Sortie</option>
                    <option value="ADJUSTMENT">Ajustement</option>
                    <option value="TRANSFER">Transfert</option>
                </select></label>
                <label><span>Quantite</span><input type="number" min="1" name="quantity" required></label>
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
                <label><span>Motif</span><input type="text" name="reason_code" placeholder="INVENTORY/PO_RECEIPT/etc"></label>
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
                ['destination_warehouse_name', 'Destination'],
                ['customer_name', 'Client'],
                ['reason_code', 'Motif'],
                ['moved_by_name', 'Par'],
            ])}
        </div>
        <div class="tab-panel hidden" data-tab-panel="media">
            ${canManageProduct ? `
            <form id="productMediaUploadForm" class="form-grid">
                <label><span>Type media</span><select name="media_type"><option value="IMAGE">Image</option><option value="DOCUMENT">Document</option></select></label>
                <label><span>Fichier</span><input type="file" name="file" required></label>
                <button type="submit" class="btn btn-primary">Televerser un media</button>
                <p class="feedback" id="mediaUploadFeedback"></p>
            </form>` : '<p class="muted">Pas de droit upload media.</p>'}
            ${renderDownloadTable(media, 'media')}
        </div>
        <div class="tab-panel hidden" data-tab-panel="attachments">
            <form id="attachmentUploadForm" class="form-grid">
                <label><span>Fichier</span><input type="file" name="file" required></label>
                <button type="submit" class="btn btn-primary">Televerser une piece jointe</button>
                <p class="feedback" id="attachmentUploadFeedback"></p>
            </form>
            ${renderDownloadTable(attachments, 'attachment')}
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
    let productMoveAvailableOutSerialCount = 0;

    const loadProductMoveVariantOptions = async () => {
        if (!productMoveVariantSelect || Number(product.has_variants) !== 1) {
            return;
        }
        productMoveVariantSelect.innerHTML = '<option value="">Chargement...</option>';
        const response = await apiRequest(`/product-variants?product_id=${productId}&is_active=1&per_page=200`);
        const variants = normalizeRows(response);
        productMoveVariantSelect.innerHTML = variants.length === 0
            ? '<option value="">Aucune variante active pour ce produit</option>'
            : '<option value="">Choisir...</option>' + variants.map((v) => {
                const descriptors = variantDescriptor(v);
                return `<option value="${v.id}">${sanitize(descriptors)} (stock: ${v.stock_total ?? 0})</option>`;
            }).join('');
    };

    const loadProductMoveOutSerialOptions = async () => {
        if (!productMoveSerialOutList || moveTypeSelect?.value !== 'OUT') {
            return;
        }
        const warehouseId = moveWarehouseSelect?.value;
        productMoveSerialOutList.innerHTML = '<p class="muted">Chargement...</p>';
        const query = `product_id=${productId}&status=IN_STOCK&per_page=200${warehouseId ? `&warehouse_id=${warehouseId}` : ''}`;
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
        const isOut = moveTypeSelect?.value === 'OUT';
        productMoveSerialsInWrap?.classList.toggle('hidden', !isIn);
        productMoveSerialsOutWrap?.classList.toggle('hidden', !isOut);
        if (isOut) {
            loadProductMoveOutSerialOptions();
        }
    };
    toggleProductMoveSerialsWrap();
    moveTypeSelect?.addEventListener('change', toggleProductMoveSerialsWrap);
    moveWarehouseSelect?.addEventListener('change', loadProductMoveOutSerialOptions);
    loadProductMoveVariantOptions();

    moveForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const feedback = document.getElementById('productMoveFeedback');
        feedback.textContent = '';
        feedback.classList.remove('is-error');
        const data = new FormData(moveForm);
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
                        body: { product_id: productId, warehouse_id: warehouseId, serial_numbers: serialNumbers },
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

        try {
            const payload = new FormData();
            payload.append('media_type', String(data.get('media_type') ?? 'IMAGE'));
            payload.append('file', data.get('file'));
            await uploadRequest(`/products/${productId}/media/upload`, payload);
            await renderProductDetail(productId);
        } catch (error) {
            feedback.textContent = error.message;
            feedback.classList.add('is-error');
        }
    });

    const attachmentForm = document.getElementById('attachmentUploadForm');
    attachmentForm?.addEventListener('submit', async (event) => {
        event.preventDefault();
        const feedback = document.getElementById('attachmentUploadFeedback');
        feedback.textContent = '';
        const data = new FormData(attachmentForm);

        try {
            const payload = new FormData();
            payload.append('entity_type', 'product');
            payload.append('entity_id', String(productId));
            payload.append('file', data.get('file'));
            await uploadRequest('/attachments/upload', payload);
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

    await loadLabelPreview(productId);
}

function renderDownloadTable(rows, type) {
    const body = rows.map((row) => `
        <tr>
            <td>${sanitize(row.id)}</td>
            <td>${sanitize(row.file_name)}</td>
            <td>${sanitize(row.mime_type ?? '')}</td>
            <td>${sanitize(row.created_at ?? '')}</td>
            <td class="actions"><button class="btn btn-soft" data-download-type="${type}" data-download-id="${row.id}" data-download-name="${sanitize(row.file_name ?? 'file.bin')}">Telecharger le fichier</button></td>
        </tr>
    `).join('');

    return `
        <div class="table-wrap">
            <table class="data-table">
                <thead><tr><th>ID</th><th>Fichier</th><th>Type</th><th>Date</th><th>Action</th></tr></thead>
                <tbody>${body || '<tr><td colspan="5">Aucune donnee</td></tr>'}</tbody>
            </table>
        </div>
    `;
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

const VARIANT_GENERATOR_MAX = 200;

function renderVariantGenerator() {
    const clothing = state.clothingVariantsEnabled;
    const bottle = state.bottleVariantsEnabled;

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

        if (combos.length > VARIANT_GENERATOR_MAX) {
            feedback.textContent = `${combos.length} combinaisons demandees, maximum ${VARIANT_GENERATOR_MAX} par lot. Reduis les listes et procede en plusieurs fois.`;
            feedback.classList.add('is-error');
            return;
        }

        // SKU deja utilises par ce produit : on les marque "existe deja" pour
        // pouvoir relancer un lot elargi sans creer de doublon.
        let existingSkus = new Set();
        try {
            const response = await apiRequest(`/product-variants?product_id=${productId}&per_page=200`);
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
                unit_price: price,
                is_active: 1,
                exists: existingSkus.has(sku.toUpperCase()),
            };
        });

        plannedCombos = rows.filter((row) => !row.exists);
        submitBtn.disabled = plannedCombos.length === 0;

        const hasClothing = dimensions.some((d) => d.key === 'size' || d.key === 'color');
        const hasBottle = dimensions.some((d) => d.key === 'vintage' || d.key === 'volume_cl');

        preview.innerHTML = `
            <div class="table-wrap">
                <table class="data-table">
                    <thead><tr>
                        <th>SKU genere</th>
                        ${hasClothing ? '<th>Taille</th><th>Couleur</th>' : ''}
                        ${hasBottle ? '<th>Millesime</th><th>Contenance</th>' : ''}
                        <th>Etat</th>
                    </tr></thead>
                    <tbody>
                        ${rows.map((row) => `
                            <tr>
                                <td>${sanitize(row.sku)}</td>
                                ${hasClothing ? `<td>${sanitize(row.size || '-')}</td><td>${sanitize(row.color || '-')}</td>` : ''}
                                ${hasBottle ? `<td>${sanitize(row.vintage || '-')}</td><td>${sanitize(row.volume_cl ? row.volume_cl + ' cl' : '-')}</td>` : ''}
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

function setupPagination(module, meta) {
    const lastPage = Math.max(1, Number(meta?.last_page ?? 1));
    const page = Number(meta?.page ?? 1);

    document.getElementById('crudPrevPage')?.addEventListener('click', async () => {
        if (page <= 1) {
            return;
        }
        state.crudPages[module] = page - 1;
        await renderCrud(module);
    });

    document.getElementById('crudNextPage')?.addEventListener('click', async () => {
        if (page >= lastPage) {
            return;
        }
        state.crudPages[module] = page + 1;
        await renderCrud(module);
    });

    document.getElementById('crudPerPage')?.addEventListener('change', async (event) => {
        // Changer la taille de page invalide le numero de page courant : on
        // repart de la premiere, seule position dont le sens est garanti.
        state.crudPerPage = Number(event.target.value) || 25;
        state.crudPages[module] = 1;
        await renderCrud(module);
    });
}

function renderCrudTable(config, rows, canWrite, module = '') {
    // Tableau principal avec actions selon les droits.
    const headerCells = config.columns.map((column) => `<th>${column.label}</th>`).join('');

    const rowCells = rows.map((row) => {
        const cells = config.columns.map((column) => {
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

        const actionCell = actions !== '' ? `<td class="actions">${actions}</td>` : '';

        return `<tr>${cells}${actionCell}</tr>`;
    }).join('');

    return `
        <div class="table-wrap">
            <table class="data-table">
                <thead><tr>${headerCells}${(canWrite || module === 'products') ? '<th>Actions</th>' : ''}</tr></thead>
                <tbody>${rowCells || `<tr><td colspan="${config.columns.length + ((canWrite || module === 'products') ? 1 : 0)}">Aucune donnee</td></tr>`}</tbody>
            </table>
        </div>
    `;
}

function buildFormFields(fields, item = null, editing = false) {
    return fields.map((field) => {
        // field.defaultValue ne s'applique qu'a la creation : en edition, la
        // valeur enregistree du produit prime toujours sur le reglage global.
        const fallback = !item && field.defaultValue !== undefined ? String(field.defaultValue) : '';
        const value = item && item[field.key] !== undefined && item[field.key] !== null ? String(item[field.key]) : fallback;
        const required = field.required || (field.requiredOnCreate && !editing);

        if (field.type === 'textarea') {
            return `<label class="full"><span>${field.label}</span><textarea name="${field.key}" ${required ? 'required' : ''}>${sanitize(value)}</textarea></label>`;
        }

        if (field.type === 'select') {
            // Les options statiques (field.options) sont au format {value,label} ;
            // les options issues des lookups (field.optionsFrom) sont au format {id,...}.
            const defaultOptionValue = field.options ? 'value' : 'id';
            return selectField(field.key, field.label, resolveOptions(field), field.optionValue ?? defaultOptionValue, field.optionLabel ?? 'label', required, value);
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

        return `<label><span>${field.label}</span><input type="${field.type}" name="${field.key}" value="${sanitize(value)}" ${field.step ? `step="${field.step}"` : ''} ${required ? 'required' : ''}></label>`;
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

function selectField(name, label, options, optionValue, optionLabel, required = false, selectedValue = '') {
    const opts = options.map((option) => {
        const value = String(option[optionValue]);
        const text = sanitize(option[optionLabel] ?? option.label ?? option.code ?? value);
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
        const color = tag.color && String(tag.color).trim() !== '' ? tag.color : '#64748b';
        return `<span class="tag-badge" style="background:${sanitize(color)}">${sanitize(tag.name)}</span>`;
    }).join(' ');
}

function variantDescriptor(v) {
    // Libelle d'une variante, quel que soit son "type" (vetement:
    // taille/couleur, ou bouteille: millesime/contenance) - v peut venir
    // soit d'un objet variante complet (size/color/vintage/volume_cl), soit
    // d'une ligne jointe (variant_size/variant_color/variant_vintage/
    // variant_volume_cl), les deux formats sont acceptes.
    const size = v.size ?? v.variant_size;
    const color = v.color ?? v.variant_color;
    const vintage = v.vintage ?? v.variant_vintage;
    const volumeCl = v.volume_cl ?? v.variant_volume_cl;
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

    return sku || '-';
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
    // Profils utilisateur
    ADMIN: 'Administrateur',
    MANAGER: 'Responsable',
    STOREKEEPER: 'Magasinier',
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
