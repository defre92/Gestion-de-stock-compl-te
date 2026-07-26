import { apiRequest, clearAuth, setAuth } from './http-client.js';

// On ne peut plus lire le cookie httpOnly en JS pour savoir si on est deja
// connecte: on demande directement au backend via /auth/me. Un echec (401)
// est normal ici (pas encore connecte) et ne doit rien afficher.
checkExistingSession();

async function checkExistingSession() {
    try {
        const response = await fetch(`${window.APP_CONFIG.apiBaseUrl}/auth/me`, {
            method: 'GET',
            credentials: 'include',
        });
        if (response.ok) {
            window.location.replace(`${window.APP_CONFIG.frontendBaseUrl}/index.php`);
        }
    } catch (_) {
        // Pas de session active, on reste simplement sur l'ecran de connexion.
    }
}

const form = document.getElementById('loginForm');
const errorBox = document.getElementById('loginError');

form?.addEventListener('submit', async (event) => {
    event.preventDefault();
    errorBox.textContent = '';

    const formData = new FormData(form);
    const payload = {
        email: String(formData.get('email') ?? '').trim(),
        password: String(formData.get('password') ?? ''),
    };

    try {
        const response = await apiRequest('/auth/login', {
            method: 'POST',
            body: payload,
        });

        const user = response?.data?.user ?? response?.user ?? null;
        if (!user) {
            throw new Error('Reponse de connexion invalide');
        }

        // Le token est deja pose en cookie httpOnly par le backend a ce stade;
        // on ne garde en cache local que le profil (affichage uniquement).
        setAuth(user);

        window.location.replace(`${window.APP_CONFIG.frontendBaseUrl}/index.php`);
    } catch (error) {
        clearAuth();
        errorBox.textContent = error.message || 'Connexion impossible';
    }
});
