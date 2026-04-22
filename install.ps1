# ============================================================
#  GESTOCK - Script d installation automatique (Windows)
#  Usage : powershell -ExecutionPolicy Bypass -File .\install.ps1
# ============================================================

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Write-Step($n, $text) { Write-Host "[$n] $text" -ForegroundColor Yellow }
function Write-OK($text)       { Write-Host "  OK  $text" -ForegroundColor Green }
function Write-Err($text)      { Write-Host "  ERR $text" -ForegroundColor Red }

function New-Secret {
    $b = New-Object byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($b)
    return ([BitConverter]::ToString($b) -replace '-','').ToLower()
}

# ── 1. Verifier Docker ──────────────────────────────────────
Write-Step "1/5" "Verification de Docker..."

$dockerCheck = docker --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "Docker introuvable. Telechargez Docker Desktop : https://www.docker.com/products/docker-desktop"
    Read-Host "Appuyez sur Entree pour quitter"; exit 1
}
Write-OK $dockerCheck

$null = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "Docker Desktop n est pas demarre. Lancez-le puis relancez ce script."
    Read-Host "Appuyez sur Entree pour quitter"; exit 1
}
Write-OK "Docker Engine actif"

# ── 2. Verifier docker-compose.yml ─────────────────────────
Write-Step "2/5" "Verification des fichiers..."

if (-not (Test-Path "docker-compose.yml")) {
    Write-Err "Fichier docker-compose.yml introuvable. Executez ce script depuis le dossier du kit."
    Read-Host "Appuyez sur Entree pour quitter"; exit 1
}
Write-OK "docker-compose.yml trouve"

# ── 3. Configurer .env ─────────────────────────────────────
Write-Step "3/5" "Configuration de l environnement..."

if (Test-Path ".env") {
    Write-Host "  Un fichier .env existe deja." -ForegroundColor Gray
    $ow = Read-Host "  Ecraser et reconfigurer ? (o/N)"
    if ($ow -eq "o" -or $ow -eq "O") {
        Remove-Item ".env"
    } else {
        Write-OK ".env conserve"
    }
}

if (-not (Test-Path ".env")) {
    Write-Host ""
    Write-Host "  Renseignez les valeurs (Entree = valeur par defaut entre crochets) :" -ForegroundColor White
    Write-Host ""

    $jwtSecret  = New-Secret
    $jwtRefresh = New-Secret
    $dbAuto     = (New-Secret).Substring(0, 24)
    Write-Host "  Secrets JWT generes automatiquement." -ForegroundColor DarkGray

    $r = Read-Host "  Mot de passe base de donnees [$dbAuto]"
    $dbPwd = if ($r -eq "") { $dbAuto } else { $r }

    $r = Read-Host "  Mot de passe admin initial [Admin@2024!]"
    $adminPwd = if ($r -eq "") { "Admin@2024!" } else { $r }

    $r = Read-Host "  URL acces serveur (http://IP ou https://domaine) [http://localhost]"
    $baseUrl = if ($r -eq "") { "http://localhost" } else { $r.TrimEnd('/') }

    $r = Read-Host "  Port HTTP [80]"
    $port = if ($r -eq "") { "80" } else { $r }

    # CORS_ORIGIN doit inclure le port si different de 80
    $corsOrigin = if ($port -ne "80") { "${baseUrl}:${port}" } else { $baseUrl }

    Write-Host ""
    Write-Host "  SMTP (optionnel - Entree pour ignorer) :" -ForegroundColor White
    $smtpHost = Read-Host "  Serveur SMTP (ex: smtp.office365.com)"
    $smtpPort = "587"
    $smtpUser = ""
    $smtpPass = ""
    $smtpFrom = ""
    if ($smtpHost -ne "") {
        $r = Read-Host "  Port SMTP [587]"
        $smtpPort = if ($r -eq "") { "587" } else { $r }
        $smtpUser = Read-Host "  Utilisateur SMTP"
        $smtpPass = Read-Host "  Mot de passe SMTP"
        $r = Read-Host "  Expediteur (ex: GESTOCK <no-reply@monentreprise.fr>) [$smtpUser]"
        $smtpFrom = if ($r -eq "") { $smtpUser } else { $r }
    }

    Write-Host ""
    Write-Host "  GLPI (optionnel - Entree pour ignorer) :" -ForegroundColor White
    $glpiHost = Read-Host "  Domaine GLPI sans http:// (ex: glpi.monentreprise.fr)"

    $lines = @(
        "# Genere par install.ps1 le $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "",
        "DB_PASSWORD=$dbPwd",
        "",
        "JWT_SECRET=$jwtSecret",
        "JWT_REFRESH_SECRET=$jwtRefresh",
        "",
        "ADMIN_PASSWORD=$adminPwd",
        "",
        "CORS_ORIGIN=$corsOrigin",
        "FRONTEND_PORT=$port",
        "",
        "# SMTP",
        "SMTP_HOST=$smtpHost",
        "SMTP_PORT=$smtpPort",
        "SMTP_SECURE=false",
        "SMTP_USER=$smtpUser",
        "SMTP_PASS=$smtpPass",
        "SMTP_FROM=$smtpFrom",
        "SMTP_REJECT_UNAUTHORIZED=true",
        "",
        "# GLPI",
        "GLPI_HOST=$glpiHost"
    )
    [System.IO.File]::WriteAllLines(".env", $lines, [System.Text.Encoding]::UTF8)
    Write-OK ".env cree"
}

# ── 4. Pull images ─────────────────────────────────────────
Write-Step "4/5" "Telechargement des images Docker..."

docker compose pull
if ($LASTEXITCODE -ne 0) {
    Write-Err "Erreur lors du telechargement des images. Verifiez votre connexion."
    Read-Host "Appuyez sur Entree pour quitter"; exit 1
}
Write-OK "Images telechargees"

# ── 5. Demarrer ────────────────────────────────────────────
Write-Step "5/5" "Demarrage de GESTOCK..."

docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Err "Erreur au demarrage. Consultez : docker compose logs"
    Read-Host "Appuyez sur Entree pour quitter"; exit 1
}

Write-Host "  Attente base de donnees..." -ForegroundColor Gray
$waited = 0
do {
    Start-Sleep -Seconds 2; $waited += 2
    $h = docker inspect --format="{{.State.Health.Status}}" gestock_db 2>$null
} while ($h -ne "healthy" -and $waited -lt 60)

if ($h -ne "healthy") {
    Write-Host "  La base de donnees tarde a demarrer. Verifiez : docker compose logs db" -ForegroundColor Yellow
} else {
    Write-OK "Base de donnees prete"
}

# ── Résumé ─────────────────────────────────────────────────
$envOrigin = "http://localhost"
Get-Content ".env" | ForEach-Object {
    if ($_ -match '^CORS_ORIGIN=(.+)') { $envOrigin = $Matches[1].Trim() }
}
# CORS_ORIGIN contient deja le port si necessaire (ex: http://localhost:9696)
$url = $envOrigin

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  GESTOCK est demarre !" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Acces       : $url" -ForegroundColor Cyan
Write-Host "  Identifiant : admin" -ForegroundColor Cyan
Write-Host "  Mot de passe: (valeur ADMIN_PASSWORD dans .env)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Commandes utiles :" -ForegroundColor Gray
Write-Host "    Logs          : docker compose logs -f" -ForegroundColor Gray
Write-Host "    Arreter       : docker compose down" -ForegroundColor Gray
Write-Host "    Mettre a jour : docker compose pull && docker compose up -d" -ForegroundColor Gray
Write-Host ""

$o = Read-Host "  Ouvrir dans le navigateur ? (O/n)"
if ($o -ne "n" -and $o -ne "N") { Start-Process "cmd" -ArgumentList "/c start $url" }