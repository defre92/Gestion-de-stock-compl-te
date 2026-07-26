const API_BASE_URL = window.APP_CONFIG.apiBaseUrl.replace(/\/$/, '');
const USER_KEY = 'gs_user';

// Le token de session ne transite plus jamais en JS: il vit dans un cookie
// httpOnly pose par le backend (voir AuthController::login() / AuthCookie),
// ce qui le protege d'un vol par XSS. `credentials: 'include'` suffit a le
// faire circuler sur chaque appel; on ne garde ici en cache local que le
// profil utilisateur (non sensible) pour l'affichage.

function readStorage(key) {
    try {
        return localStorage.getItem(key) ?? sessionStorage.getItem(key);
    } catch (_) {
        return null;
    }
}

function writeStorage(key, value) {
    try {
        localStorage.setItem(key, value);
        return;
    } catch (_) {
    }

    try {
        sessionStorage.setItem(key, value);
    } catch (_) {
    }
}

function removeStorage(key) {
    try {
        localStorage.removeItem(key);
    } catch (_) {
    }

    try {
        sessionStorage.removeItem(key);
    } catch (_) {
    }
}

export function getCachedUser() {
    const raw = readStorage(USER_KEY);
    if (!raw) {
        return null;
    }

    try {
        return JSON.parse(raw);
    } catch (_) {
        return null;
    }
}

export function setAuth(user) {
    writeStorage(USER_KEY, JSON.stringify(user ?? {}));
}

export function clearAuth() {
    removeStorage(USER_KEY);
}

export async function apiRequest(path, options = {}) {
    const { method = 'GET', body } = options;

    const headers = {
        'Content-Type': 'application/json',
    };

    const response = await fetch(`${API_BASE_URL}${path}`, {
        method,
        headers,
        credentials: 'include',
        body: body ? JSON.stringify(body) : undefined,
    });

    if (response.status === 204) {
        return null;
    }

    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
        if (response.status === 401) {
            clearAuth();
            window.location.replace(`${window.APP_CONFIG.frontendBaseUrl}/login.php`);
        }

        throw new Error(toFrenchError(payload.message || 'Erreur API'));
    }

    return payload;
}

export async function uploadRequest(path, formData, options = {}) {
    const { method = 'POST' } = options;

    const response = await fetch(`${API_BASE_URL}${path}`, {
        method,
        credentials: 'include',
        body: formData,
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
        if (response.status === 401) {
            clearAuth();
            window.location.replace(`${window.APP_CONFIG.frontendBaseUrl}/login.php`);
        }
        throw new Error(toFrenchError(payload.message || 'Erreur upload'));
    }

    return payload;
}

export async function fetchAuthenticatedBlob(path) {
    const response = await fetch(`${window.APP_CONFIG.apiBaseUrl}${path}`, {
        method: 'GET',
        credentials: 'include',
    });

    if (!response.ok) {
        if (response.status === 401) {
            clearAuth();
            window.location.replace(`${window.APP_CONFIG.frontendBaseUrl}/login.php`);
        }
        throw new Error('Telechargement impossible');
    }

    return response.blob();
}

function toFrenchError(message) {
    const msg = String(message ?? '').trim();
    const dictionary = {
        'Server error': 'Erreur serveur',
        'Internal server error': 'Erreur interne du serveur',
        'Invalid credentials': 'Identifiants invalides',
        'Unauthorized': 'Session non autorisee',
        'Missing session cookie': 'Session expiree',
        'Inactive account': 'Compte inactif',
        'Route not found': 'Route introuvable',
        'Upload impossible': 'Televersement impossible',
        'Export impossible': 'Export impossible',
    };

    return dictionary[msg] ?? msg;
}
