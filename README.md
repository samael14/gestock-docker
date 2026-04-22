# GESTOCK — Kit de déploiement Docker

> Gestion de stock IT multi-sites · Installation en 5 minutes avec Docker Compose

![image alt](https://github.com/samael14/gestock-docker/blob/main/2026-04-22%2019_07_34-.png)
---

## Prérequis

| Composant | Version minimale |
|---|---|
| Docker | 20.10+ |
| Docker Compose | v2 (plugin intégré) |
| RAM | 2 Go minimum |
| Disque | 5 Go minimum |

---

## Installation rapide (Windows)

```powershell
git clone https://github.com/samael14/gestock-docker.git
cd gestock-docker
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Le script vérifie Docker, génère les secrets automatiquement, configure le `.env` de manière interactive et démarre tous les conteneurs.

---

## Installation manuelle

### 1. Cloner ce dépôt

```bash
git clone https://github.com/samael14/gestock-docker.git
cd gestock-docker
```

### 2. Configurer l'environnement

```bash
cp .env.example .env
nano .env        # ou : notepad .env  (Windows)
```

Remplissez obligatoirement :

| Variable | Description |
|---|---|
| `DB_PASSWORD` | Mot de passe PostgreSQL — choisissez une valeur forte |
| `JWT_SECRET` | Secret JWT (min. 32 caractères) — `openssl rand -hex 32` |
| `JWT_REFRESH_SECRET` | Secret refresh JWT (min. 32 caractères) |
| `ADMIN_PASSWORD` | Mot de passe du compte administrateur initial |
| `CORS_ORIGIN` | URL d'accès (ex : `http://192.168.1.100`) |

> **Exemple de génération de secrets sous Linux/Mac :**
> ```bash
> openssl rand -hex 32
> ```
> **Sous Windows PowerShell :**
> ```powershell
> [System.Web.Security.Membership]::GeneratePassword(32,4)
> ```

### 3. (Optionnel) Se connecter à GitHub Container Registry

Les images sont publiques. La connexion n'est requise que si vous dépassez les limites de pull anonyme.

```bash
docker login ghcr.io -u VOTRE_PSEUDO_GITHUB
# Entrez un Personal Access Token (read:packages) comme mot de passe
```

### 4. Démarrer GESTOCK

```bash
docker compose up -d
```

Docker télécharge automatiquement les images (~300 Mo) et démarre 3 conteneurs :

| Conteneur | Rôle | Port |
|---|---|---|
| `gestock_db` | PostgreSQL 16 | interne uniquement |
| `gestock_api` | API Fastify | interne uniquement |
| `gestock_frontend` | Interface React + Nginx | **80** (configurable) |

### 5. Premier accès

Ouvrez **http://IP-DU-SERVEUR** dans votre navigateur.

Connexion initiale :
- **Identifiant** : `admin`
- **Mot de passe** : valeur de `ADMIN_PASSWORD` dans votre `.env`

> L'application démarre sans aucune donnée. Commencez par créer vos sites via **Paramètres → Sites**.

---

## Mise à jour

```bash
docker compose pull          # Télécharge les nouvelles images
docker compose up -d         # Redémarre avec les nouvelles images
```

Les données PostgreSQL sont conservées dans le volume `gestock_postgres_data`.

---

## Opérations courantes

```bash
# Voir les logs en temps réel
docker compose logs -f

# Voir les logs d'un seul service
docker compose logs -f api
docker compose logs -f frontend

# Redémarrer un service
docker compose restart api

# Arrêter l'application (données conservées)
docker compose down

# Arrêter ET supprimer toutes les données (irréversible)
docker compose down -v
```

---

## Sauvegarde de la base de données

```bash
# Dump PostgreSQL
docker exec gestock_db pg_dump -U gestock gestock_db > backup_$(date +%Y%m%d).sql

# Restauration
docker exec -i gestock_db psql -U gestock gestock_db < backup_20240101.sql
```

---

## Configuration avancée

### Changer le port HTTP

Dans `.env` :
```
FRONTEND_PORT=8080
```
Puis : `docker compose up -d`

### Reverse proxy (HTTPS / nom de domaine)

Pour exposer GESTOCK en HTTPS avec un nom de domaine, placez un reverse proxy (Nginx, Traefik, Caddy) devant le conteneur `gestock_frontend:80`.

Exemple minimal Nginx :
```nginx
server {
    listen 443 ssl;
    server_name gestock.monentreprise.fr;
    location / {
        proxy_pass http://localhost:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Architecture

```
[Navigateur]
     │  HTTP :80
     ▼
[Nginx / Frontend React]
     │  HTTP interne :3001
     ▼
[API Fastify]
     │  TCP interne :5432
     ▼
[PostgreSQL 16]
     │
[Volume Docker persistant]
```

---

## Images Docker

| Image | Registre |
|---|---|
| `ghcr.io/samael14/gestock-frontend:latest` | GitHub Container Registry |
| `ghcr.io/samael14/gestock-api:latest` | GitHub Container Registry |

---

## Support et code source

- Code source (privé) : https://github.com/samael14/GESTOCK
- Problèmes / questions : ouvrir une issue sur ce dépôt

---

## Licence

Propriétaire — Usage interne uniquement.
