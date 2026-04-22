# ══════════════════════════════════════════════════════════════════════════════
#  GESTOCK — Script d'installation automatique (Windows)
#  Usage : Clic-droit → "Exécuter avec PowerShell"
#          ou : powershell -ExecutionPolicy Bypass -File .\install.ps1
# ══════════════════════════════════════════════════════════════════════════════

$ErrorActionPreference = 'Stop'

function Write-Header {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         GESTOCK — Installation               ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step($n, $text) {
    Write-Host "[$n] $text" -ForegroundColor Yellow
}

function Write-OK($text) {
    Write-Host "  ✓ $text" -ForegroundColor Green
}

function Write-Err($text) {
    Write-Host "  ✗ $text" -ForegroundColor Red
}

function Prompt-Value($label, $default = "", $secret = $false) {
    if ($secret) {
        $prompt = "    → $label"
        if ($default) { $prompt += " [laisser vide = $default]" }
        $prompt += " : "
        $val = Read-Host -Prompt $prompt -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($val))
        if ($plain -eq "" -and $default -ne "") { return $default }
        return $plain
    } else {
        $prompt = "    → $label"
        if ($default) { $prompt += " [$default]" }
        $prompt += " : "
        $val = Read-Host -Prompt $prompt
        if ($val -eq "" -and $default -ne "") { return $default }
        return $val
    }
}

function Generate-Secret {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    return ([System.BitConverter]::ToString($bytes) -replace '-','').ToLower()
}

# ── Début ──────────────────────────────────────────────────────────────────────

Write-Header

# ── Étape 1 : Vérifier Docker ─────────────────────────────────────────────────
Write-Step "1/5" "Vérification de Docker..."

try {
    $dockerVer = docker --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    Write-OK "Docker trouvé : $dockerVer"
} catch {
    Write-Err "Docker n'est pas installé ou n'est pas démarré."
    Write-Host "    Téléchargez Docker Desktop : https://www.docker.com/products/docker-desktop" -ForegroundColor Gray
    Write-Host ""
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}

try {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw }
    Write-OK "Docker Engine actif"
} catch {
    Write-Err "Docker Desktop n'est pas démarré. Lancez-le puis relancez ce script."
    Write-Host ""
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}

# ── Étape 2 : Vérifier docker-compose.yml ─────────────────────────────────────
Write-Step "2/5" "Vérification des fichiers..."

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

if (-not (Test-Path "docker-compose.yml")) {
    Write-Err "Fichier docker-compose.yml introuvable dans $scriptDir"
    Write-Host "    Assurez-vous d'exécuter ce script depuis le dossier du kit de déploiement." -ForegroundColor Gray
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}
Write-OK "docker-compose.yml trouvé"

# ── Étape 3 : Configurer le fichier .env ──────────────────────────────────────
Write-Step "3/5" "Configuration de l'environnement..."

if (Test-Path ".env") {
    Write-Host "    Un fichier .env existe déjà." -ForegroundColor Gray
    $overwrite = Read-Host "    → Écraser et reconfigurer ? (o/N)"
    if ($overwrite -ne "o" -and $overwrite -ne "O") {
        Write-OK ".env conservé tel quel"
    } else {
        Remove-Item ".env"
    }
}

if (-not (Test-Path ".env")) {
    Write-Host ""
    Write-Host "  Configuration requise (appuyez sur Entrée pour utiliser la valeur par défaut) :" -ForegroundColor White
    Write-Host ""

    # Générer des secrets automatiquement
    $jwtSecret      = Generate-Secret
    $jwtRefresh     = Generate-Secret
    $dbPasswordAuto = Generate-Secret | Select-String -Pattern '^.{24}' | ForEach-Object { $_.Matches[0].Value }

    Write-Host "    Secrets JWT générés automatiquement ✓" -ForegroundColor DarkGray

    $dbPassword   = Prompt-Value "Mot de passe base de données" $dbPasswordAuto $true
    $adminPwd     = Prompt-Value "Mot de passe admin initial" "Admin@2024!" $true
    $corsOrigin   = Prompt-Value "URL d'accès (IP ou domaine du serveur)" "http://localhost"
    $frontendPort = Prompt-Value "Port HTTP" "80"

    $envContent = @"
# Généré automatiquement par install.ps1 le $(Get-Date -Format 'yyyy-MM-dd HH:mm')

DB_PASSWORD=$dbPassword

JWT_SECRET=$jwtSecret
JWT_REFRESH_SECRET=$jwtRefresh

ADMIN_PASSWORD=$adminPwd

CORS_ORIGIN=$corsOrigin
FRONTEND_PORT=$frontendPort
"@

    [System.IO.File]::WriteAllText("$scriptDir\.env", $envContent, [System.Text.Encoding]::UTF8)
    Write-OK ".env créé"
}

# ── Étape 4 : Télécharger les images ─────────────────────────────────────────
Write-Step "4/5" "Téléchargement des images Docker (peut prendre quelques minutes)..."

docker compose pull
if ($LASTEXITCODE -ne 0) {
    Write-Err "Erreur lors du téléchargement des images."
    Write-Host "    Vérifiez votre connexion internet." -ForegroundColor Gray
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}
Write-OK "Images téléchargées"

# ── Étape 5 : Démarrer les conteneurs ────────────────────────────────────────
Write-Step "5/5" "Démarrage de GESTOCK..."

docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Err "Erreur lors du démarrage des conteneurs."
    Write-Host "    Consultez les logs : docker compose logs" -ForegroundColor Gray
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}

# ── Attendre que l'API soit prête ─────────────────────────────────────────────
Write-Host ""
Write-Host "  Attente du démarrage de la base de données..." -ForegroundColor Gray

$maxWait = 30
$waited  = 0
do {
    Start-Sleep -Seconds 2
    $waited += 2
    $health = docker inspect --format='{{.State.Health.Status}}' gestock_db 2>$null
} while ($health -ne "healthy" -and $waited -lt $maxWait)

if ($health -ne "healthy") {
    Write-Host "  ⚠ La base de données tarde à démarrer. Vérifiez avec : docker compose logs db" -ForegroundColor Yellow
} else {
    Write-OK "Base de données prête"
}

# ── Résumé ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  GESTOCK est démarré !                                   ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

# Lire le port depuis .env
$port = "80"
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^FRONTEND_PORT=(.+)$') { $port = $Matches[1].Trim() }
}
$corsVal = "http://localhost"
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^CORS_ORIGIN=(.+)$') { $corsVal = $Matches[1].Trim() }
}
$url = if ($port -eq "80") { $corsVal } else { "${corsVal}:${port}" }

Write-Host "  Accès         : $url" -ForegroundColor Cyan
Write-Host "  Identifiant   : admin" -ForegroundColor Cyan
Write-Host "  Mot de passe  : (valeur ADMIN_PASSWORD dans .env)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Commandes utiles :" -ForegroundColor Gray
Write-Host "    Logs          : docker compose logs -f" -ForegroundColor Gray
Write-Host "    Arrêter       : docker compose down" -ForegroundColor Gray
Write-Host "    Mettre à jour : docker compose pull && docker compose up -d" -ForegroundColor Gray
Write-Host ""

$open = Read-Host "  Ouvrir dans le navigateur ? (O/n)"
if ($open -ne "n" -and $open -ne "N") {
    Start-Process $url
}

Write-Host ""
