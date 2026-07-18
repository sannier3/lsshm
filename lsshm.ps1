#Requires -Version 5.1
<#
.SYNOPSIS
    LSSHM - Local SSH Manager (Windows / PowerShell)

.DESCRIPTION
    Gestion locale OpenSSH sous Windows : serveur SSH, acces entrants,
    cles sortantes et machines distantes. Interface CLI a menus, sans
    dependance externe. Meme concepts et menus que la version Bash Linux.

.NOTES
    Version alignee sur VERSION du depot.
    Chemins Windows OpenSSH :
      %ProgramData%\ssh\sshd_config
      %ProgramData%\ssh\administrators_authorized_keys
      %USERPROFILE%\.ssh\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Constantes et etat
# =============================================================================

$script:LSSHM_VERSION = '0.2.0'
$script:LSSHM_NAME = 'LSSHM'
$script:LSSHM_LONG_NAME = 'LSSHM - Local SSH Manager'
$script:LSSHM_REPO_RAW = if ($env:LSSHM_REPO_RAW) { $env:LSSHM_REPO_RAW } else { 'https://raw.githubusercontent.com/sannier3/lsshm/main' }
$script:LSSHM_ASSUME_YES = $false
$script:LSSHM_TARGET_USER = $null

function Initialize-LsshmPaths {
    $script:LSSHM_HOME = $env:USERPROFILE
    if (-not $script:LSSHM_HOME) { $script:LSSHM_HOME = $HOME }

    $localApp = $env:LOCALAPPDATA
    if (-not $localApp) { $localApp = Join-Path $script:LSSHM_HOME 'AppData\Local' }

    $script:LSSHM_CONFIG_DIR = Join-Path $localApp 'lsshm'
    $script:LSSHM_DATA_DIR = Join-Path $localApp 'lsshm\data'
    $script:LSSHM_STATE_DIR = Join-Path $localApp 'lsshm\state'
    $script:LSSHM_CACHE_DIR = Join-Path $localApp 'lsshm\cache'
    $script:LSSHM_BACKUP_DIR = Join-Path $script:LSSHM_STATE_DIR 'backups'
    $script:LSSHM_CONFIG_FILE = Join-Path $script:LSSHM_CONFIG_DIR 'config.json'
    $script:LSSHM_INSTALL_TARGET = Join-Path $script:LSSHM_DATA_DIR 'lsshm.ps1'
    $script:LSSHM_BIN_DIR = Join-Path $script:LSSHM_HOME '.local\bin'
    $script:LSSHM_BIN_LINK = Join-Path $script:LSSHM_BIN_DIR 'lsshm.ps1'

    $script:LSSHM_SSH_DIR = Join-Path $script:LSSHM_HOME '.ssh'
    $script:LSSHM_SSH_CONFIG = Join-Path $script:LSSHM_SSH_DIR 'config'
    $script:LSSHM_KNOWN_HOSTS = Join-Path $script:LSSHM_SSH_DIR 'known_hosts'
    $script:LSSHM_AUTHORIZED_KEYS = Join-Path $script:LSSHM_SSH_DIR 'authorized_keys'

    $programData = $env:ProgramData
    if (-not $programData) { $programData = 'C:\ProgramData' }
    $script:LSSHM_SSHD_CONFIG = Join-Path $programData 'ssh\sshd_config'
    $script:LSSHM_ADMIN_KEYS = Join-Path $programData 'ssh\administrators_authorized_keys'
    $script:LSSHM_SSH_SERVICE = 'sshd'
}

function Ensure-LsshmDirs {
    foreach ($d in @(
            $script:LSSHM_CONFIG_DIR,
            $script:LSSHM_DATA_DIR,
            $script:LSSHM_STATE_DIR,
            $script:LSSHM_CACHE_DIR,
            $script:LSSHM_BACKUP_DIR
        )) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}

# =============================================================================
# Affichage / prompts
# =============================================================================

function Write-LsshmInfo { param([string]$Message) Write-Host $Message }
function Write-LsshmOk { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-LsshmWarn { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-LsshmError { param([string]$Message) Write-Host $Message -ForegroundColor Red }

function Write-LsshmHeader {
    Write-Host $script:LSSHM_LONG_NAME -ForegroundColor Cyan
    Write-Host ("v{0}" -f $script:LSSHM_VERSION) -ForegroundColor DarkGray
    Write-Host ''
}

function Test-LsshmInteractive {
    if ($script:LSSHM_ASSUME_YES) { return $false }
    try { return [Environment]::UserInteractive } catch { return $true }
}

function Read-LsshmPrompt {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default = ''
    )
    if (-not (Test-LsshmInteractive)) {
        return $Default
    }
    $suffix = if ($Default) { " [$Default]" } else { '' }
    $answer = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Confirm-Lsshm {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [switch]$DefaultYes
    )
    if ($script:LSSHM_ASSUME_YES) { return $true }
    if (-not (Test-LsshmInteractive)) { return [bool]$DefaultYes }
    $hint = if ($DefaultYes) { '[O/n]' } else { '[o/N]' }
    $answer = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { return [bool]$DefaultYes }
    switch -Regex ($answer.Trim().ToLowerInvariant()) {
        '^(o|oui|y|yes)$' { return $true }
        default { return $false }
    }
}

function Pause-Lsshm {
    if (-not (Test-LsshmInteractive)) { return }
    Read-Host 'Appuyez sur Entree pour continuer' | Out-Null
}

function Test-LsshmAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$id
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Assert-LsshmAdmin {
    if (-not (Test-LsshmAdmin)) {
        Write-LsshmError 'Cette operation necessite PowerShell en administrateur.'
        Write-LsshmInfo 'Relancez : Start-Process powershell -Verb RunAs'
        throw 'Elevation requise'
    }
}

# =============================================================================
# Detection plateforme / OpenSSH
# =============================================================================

function Get-LsshmSshdPath {
    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'),
        (Join-Path $env:ProgramFiles 'OpenSSH\sshd.exe'),
        'C:\Windows\System32\OpenSSH\sshd.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $cmd = Get-Command sshd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Test-LsshmServerInstalled {
    return [bool](Get-LsshmSshdPath)
}

function Get-LsshmService {
    Get-Service -Name $script:LSSHM_SSH_SERVICE -ErrorAction SilentlyContinue
}

function Test-LsshmServerActive {
    $svc = Get-LsshmService
    return ($svc -and $svc.Status -eq 'Running')
}

function Get-LsshmConfigValue {
    param([Parameter(Mandatory)][string]$Key)
    $keyLower = $Key.ToLowerInvariant()

    # Prefer sshd -T when available and elevated enough
    $sshd = Get-LsshmSshdPath
    if ($sshd) {
        try {
            $dump = & $sshd -T 2>$null
            if ($LASTEXITCODE -eq 0 -and $dump) {
                foreach ($line in $dump) {
                    if ($line -match '^\s*(\S+)\s+(.+)$') {
                        if ($Matches[1].ToLowerInvariant() -eq $keyLower) {
                            return $Matches[2].Trim()
                        }
                    }
                }
            }
        } catch { }
    }

    if (-not (Test-Path -LiteralPath $script:LSSHM_SSHD_CONFIG)) { return $null }
    foreach ($line in Get-Content -LiteralPath $script:LSSHM_SSHD_CONFIG -ErrorAction SilentlyContinue) {
        $trim = $line.Trim()
        if ($trim -match '^\s*#' -or $trim -eq '') { continue }
        if ($trim -match '^\s*(\S+)\s+(.+)$') {
            if ($Matches[1].ToLowerInvariant() -eq $keyLower) {
                return $Matches[2].Trim()
            }
        }
    }
    return $null
}

function Get-LsshmRootLoginLabel {
    param([string]$Value)
    switch -Regex ($Value) {
        '^no$' { return 'interdit' }
        '^(prohibit-password|without-password)$' { return 'cle uniquement' }
        '^yes$' { return 'cle ou mot de passe' }
        '^forced-commands-only$' { return 'commandes imposees' }
        default { if ($Value) { return $Value } else { return 'non defini' } }
    }
}

function Get-LsshmYesNoLabel {
    param([string]$Value)
    switch -Regex ($Value) {
        '^(yes|true|on|1)$' { return 'oui' }
        '^(no|false|off|0)$' { return 'non' }
        default { if ($Value) { return $Value } else { return 'non defini' } }
    }
}

function Get-LsshmKeyCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
            Where-Object { $_ -and $_ -notmatch '^\s*#' }).Count
}

function Get-LsshmPrivateKeyCount {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) { return 0 }
    return @(Get-ChildItem -LiteralPath $script:LSSHM_SSH_DIR -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'id_*' -and $_.Name -notlike '*.pub' }).Count
}

function Get-LsshmHostCount {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_CONFIG)) { return 0 }
    $n = 0
    foreach ($line in Get-Content -LiteralPath $script:LSSHM_SSH_CONFIG -ErrorAction SilentlyContinue) {
        if ($line -match '^\s*Host\s+(.+)$') {
            foreach ($alias in ($Matches[1] -split '\s+')) {
                if ($alias -and $alias -notmatch '[\*\?]') { $n++ }
            }
        }
    }
    return $n
}

function Show-LsshmStatusPanel {
    $active = if ((Test-LsshmServerInstalled) -and (Test-LsshmServerActive)) { 'actif' } else { 'inactif' }
    $port = Get-LsshmConfigValue 'port'
    if (-not $port) { $port = '22' }
    $root = Get-LsshmRootLoginLabel (Get-LsshmConfigValue 'permitrootlogin')
    $pass = Get-LsshmYesNoLabel (Get-LsshmConfigValue 'passwordauthentication')
    $adminKeys = Get-LsshmKeyCount $script:LSSHM_ADMIN_KEYS
    $userKeys = Get-LsshmPrivateKeyCount
    $hosts = Get-LsshmHostCount
    $user = if ($script:LSSHM_TARGET_USER) { $script:LSSHM_TARGET_USER } else { $env:USERNAME }

    Write-Host "Etat du serveur SSH : $active"
    Write-Host "Port : $port"
    Write-Host "Acces root / admin : $root"
    Write-Host "Authentification par mot de passe : $pass"
    Write-Host "Cles administrateurs (administrators_authorized_keys) : $adminKeys"
    Write-Host "Cles privees de l'utilisateur $user : $userKeys"
    Write-Host "Machines distantes enregistrees : $hosts"
}

# =============================================================================
# Serveur SSH
# =============================================================================

function Show-LsshmServerStatus {
    if (-not (Test-LsshmServerInstalled)) {
        Write-LsshmWarn "OpenSSH Server n'est pas installe (sshd.exe introuvable)."
        return
    }
    $svc = Get-LsshmService
    $active = if (Test-LsshmServerActive) { 'actif' } else { 'inactif' }
    $enabled = if ($svc -and $svc.StartType -eq 'Automatic') { 'oui' } else { 'non' }
    $port = Get-LsshmConfigValue 'port'
    if (-not $port) { $port = '22' }
    Write-Host "Etat du serveur SSH : $active"
    Write-Host "Demarrage auto      : $enabled"
    Write-Host "Port                : $port"
    Write-Host ("Acces admin         : {0}" -f (Get-LsshmRootLoginLabel (Get-LsshmConfigValue 'permitrootlogin')))
    Write-Host ("Auth. mot de passe  : {0}" -f (Get-LsshmYesNoLabel (Get-LsshmConfigValue 'passwordauthentication')))
    Write-Host ("Auth. par cle       : {0}" -f (Get-LsshmYesNoLabel (Get-LsshmConfigValue 'pubkeyauthentication')))
    Write-Host ("Config              : {0}" -f $script:LSSHM_SSHD_CONFIG)
}

function Install-LsshmOpenSshServer {
    Assert-LsshmAdmin
    if (Test-LsshmServerInstalled) {
        Write-LsshmOk ("OpenSSH Server deja present : {0}" -f (Get-LsshmSshdPath))
        return
    }
    Write-LsshmInfo 'Installation de OpenSSH.Server (fonctionnalite facultative Windows)...'
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
    if (Test-LsshmServerInstalled) {
        Write-LsshmOk 'OpenSSH Server installe.'
    } else {
        Write-LsshmError "Installation echouee. Essayez : Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"
    }
}

function Invoke-LsshmServerAction {
    param([ValidateSet('Start', 'Stop', 'Restart')][string]$Action)
    Assert-LsshmAdmin
    switch ($Action) {
        'Start' { Start-Service $script:LSSHM_SSH_SERVICE; Write-LsshmOk 'Service SSH demarre.' }
        'Stop' { Stop-Service $script:LSSHM_SSH_SERVICE -Force; Write-LsshmOk 'Service SSH arrete.' }
        'Restart' { Restart-Service $script:LSSHM_SSH_SERVICE -Force; Write-LsshmOk 'Service SSH redemarre.' }
    }
}

function Set-LsshmServerStartup {
    param([ValidateSet('Automatic', 'Manual', 'Disabled')][string]$Type)
    Assert-LsshmAdmin
    Set-Service -Name $script:LSSHM_SSH_SERVICE -StartupType $Type
    Write-LsshmOk ("Demarrage automatique : {0}" -f $Type)
}

function Test-LsshmServerConfig {
    $sshd = Get-LsshmSshdPath
    if (-not $sshd) {
        Write-LsshmWarn 'sshd introuvable.'
        return $false
    }
    & $sshd -t 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -eq 0) {
        Write-LsshmOk 'Configuration valide (sshd -t).'
        return $true
    }
    Write-LsshmError 'Configuration invalide.'
    return $false
}

function Show-LsshmServerConfigDump {
    $sshd = Get-LsshmSshdPath
    if (-not $sshd) {
        Write-LsshmWarn 'sshd introuvable.'
        return
    }
    & $sshd -T 2>$null | Sort-Object
}

function Backup-LsshmServerConfig {
    Ensure-LsshmDirs
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSHD_CONFIG)) {
        Write-LsshmWarn 'Aucune configuration serveur a sauvegarder.'
        return $null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $script:LSSHM_BACKUP_DIR "$stamp-sshd_config"
    Copy-Item -LiteralPath $script:LSSHM_SSHD_CONFIG -Destination $dest -Force
    Write-LsshmOk "Sauvegarde creee : $dest"
    return $dest
}

function Set-LsshmSshdDirective {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )
    Assert-LsshmAdmin
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSHD_CONFIG)) {
        Write-LsshmError "Fichier introuvable : $($script:LSSHM_SSHD_CONFIG)"
        return $false
    }
    Backup-LsshmServerConfig | Out-Null
    $lines = Get-Content -LiteralPath $script:LSSHM_SSHD_CONFIG
    $found = $false
    $out = foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s+" -and $line -notmatch '^\s*#') {
            if (-not $found) {
                $found = $true
                "$Key $Value"
            }
        } else {
            $line
        }
    }
    if (-not $found) {
        $out = @($out) + @('', "# Managed by LSSHM", "$Key $Value")
    }
    Set-Content -LiteralPath $script:LSSHM_SSHD_CONFIG -Value $out -Encoding UTF8
    if (-not (Test-LsshmServerConfig)) {
        Write-LsshmError 'Configuration invalide : restaurez une sauvegarde si besoin.'
        return $false
    }
    Write-LsshmOk "Directive appliquee : $Key $Value"
    return $true
}

function Set-LsshmRootLoginMenu {
    Write-LsshmHeader
    Write-Host 'Connexion SSH administrateur / root'
    Write-Host ''
    Write-Host '  1. Interdire totalement'
    Write-Host '  2. Autoriser uniquement avec une cle'
    Write-Host '  3. Autoriser avec une cle ou un mot de passe'
    Write-Host '  4. Autoriser uniquement pour des commandes imposees'
    Write-Host ''
    $choice = Read-LsshmPrompt 'Choix' '2'
    $value = switch ($choice) {
        '1' { 'no' }
        '2' { 'prohibit-password' }
        '3' { 'yes' }
        '4' { 'forced-commands-only' }
        default { $null }
    }
    if (-not $value) {
        Write-LsshmInfo 'Aucun changement.'
        return
    }
    if (-not (Confirm-Lsshm 'Appliquer ce changement sensible ?')) { return }
    if (Set-LsshmSshdDirective -Key 'PermitRootLogin' -Value $value) {
        Restart-Service $script:LSSHM_SSH_SERVICE -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Acces entrants
# =============================================================================

function Show-LsshmAccessList {
    param([ValidateSet('User', 'Administrators')][string]$Scope = 'User')
    $path = if ($Scope -eq 'Administrators') { $script:LSSHM_ADMIN_KEYS } else { $script:LSSHM_AUTHORIZED_KEYS }
    Write-Host ("Fichier : {0}" -f $path)
    Write-Host ''
    if (-not (Test-Path -LiteralPath $path)) {
        Write-LsshmInfo 'Aucune cle autorisee.'
        return
    }
    $i = 0
    foreach ($line in Get-Content -LiteralPath $path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $i++
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $tmp -Value $line -Encoding ascii
            $fp = & ssh-keygen -lf $tmp 2>$null
            Write-Host ("{0}. {1}" -f $i, $fp)
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    if ($i -eq 0) { Write-LsshmInfo 'Aucune cle autorisee.' }
}

function Add-LsshmAccessKey {
    param([ValidateSet('User', 'Administrators')][string]$Scope = 'User')
    $path = if ($Scope -eq 'Administrators') { $script:LSSHM_ADMIN_KEYS } else { $script:LSSHM_AUTHORIZED_KEYS }
    if ($Scope -eq 'Administrators') { Assert-LsshmAdmin }

    $keyline = Read-LsshmPrompt 'Collez la cle publique (une ligne) ou chemin .pub'
    if (-not $keyline) { Write-LsshmInfo 'Annule.'; return }
    if (Test-Path -LiteralPath $keyline) {
        $keyline = (Get-Content -LiteralPath $keyline -Raw).Trim()
    }

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR) -and $Scope -eq 'User') {
        New-Item -ItemType Directory -Path $script:LSSHM_SSH_DIR -Force | Out-Null
    }

    Add-Content -LiteralPath $path -Value $keyline -Encoding ascii
    if ($Scope -eq 'User') {
        icacls $script:LSSHM_SSH_DIR /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
        icacls $path /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null
    }
    Write-LsshmOk "Cle ajoutee dans $path"
}

function Repair-LsshmAccessPermissions {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) {
        Write-LsshmWarn ".ssh introuvable."
        return
    }
    icacls $script:LSSHM_SSH_DIR /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null
    if (Test-Path -LiteralPath $script:LSSHM_AUTHORIZED_KEYS) {
        icacls $script:LSSHM_AUTHORIZED_KEYS /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null
    }
    Get-ChildItem -LiteralPath $script:LSSHM_SSH_DIR -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -like '*.pub') {
            icacls $_.FullName /inheritance:r /grant:r "${env:USERNAME}:R" | Out-Null
        } elseif ($_.Name -like 'id_*') {
            icacls $_.FullName /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null
        }
    }
    Write-LsshmOk 'Permissions .ssh reparees (ACL Windows).'
}

# =============================================================================
# Cles locales
# =============================================================================

function Show-LsshmKeysList {
    Write-Host ("Repertoire : {0}" -f $script:LSSHM_SSH_DIR)
    Write-Host ''
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) {
        Write-LsshmInfo 'Aucun repertoire .ssh.'
        return
    }
    $i = 0
    Get-ChildItem -LiteralPath $script:LSSHM_SSH_DIR -Filter '*.pub' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $i++
        $priv = $_.FullName -replace '\.pub$', ''
        $fp = & ssh-keygen -lf $_.FullName 2>$null
        Write-Host ("{0}. {1}" -f $i, $_.BaseName)
        Write-Host ("   Publique : {0}" -f $_.FullName)
        Write-Host ("   Privee   : {0}" -f $(if (Test-Path -LiteralPath $priv) { "$priv (presente)" } else { 'absente' }))
        Write-Host ("   Empreinte: {0}" -f $fp)
    }
    if ($i -eq 0) { Write-LsshmInfo 'Aucune paire de cles detectee.' }
}

function New-LsshmKey {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) {
        New-Item -ItemType Directory -Path $script:LSSHM_SSH_DIR -Force | Out-Null
    }
    $type = Read-LsshmPrompt 'Type de cle (ed25519/rsa)' 'ed25519'
    if ($type -notin @('ed25519', 'rsa', 'ED25519', 'RSA')) { $type = 'ed25519' }
    $type = $type.ToLowerInvariant()
    $name = Read-LsshmPrompt 'Nom du fichier' ("id_$type")
    $path = Join-Path $script:LSSHM_SSH_DIR $name
    $comment = Read-LsshmPrompt 'Commentaire' ("$env:USERNAME@$env:COMPUTERNAME")
    $args = @('-t', $type, '-f', $path, '-C', $comment)
    if ($type -eq 'rsa') { $args += @('-b', '4096') }
    Write-LsshmInfo ("ssh-keygen {0}" -f ($args -join ' '))
    & ssh-keygen @args
    if ($LASTEXITCODE -eq 0) {
        Write-LsshmOk "Cle generee : $path"
        Get-Content -LiteralPath "$path.pub"
    } else {
        Write-LsshmError 'Echec de la generation.'
    }
}

function Show-LsshmKeyInspect {
    $path = Read-LsshmPrompt 'Chemin de la cle' (Join-Path $script:LSSHM_SSH_DIR 'id_ed25519')
    $pub = if (Test-Path -LiteralPath "$path.pub") { "$path.pub" } else { $path }
    if (-not (Test-Path -LiteralPath $pub)) {
        Write-LsshmError "Fichier introuvable : $pub"
        return
    }
    & ssh-keygen -lf $pub
    & ssh-keygen -lvf $pub
}

function Show-LsshmKeyExport {
    $path = Read-LsshmPrompt 'Chemin de la cle' (Join-Path $script:LSSHM_SSH_DIR 'id_ed25519')
    $pub = if ($path -like '*.pub') { $path } elseif (Test-Path -LiteralPath "$path.pub") { "$path.pub" } else { $null }
    if (-not $pub -or -not (Test-Path -LiteralPath $pub)) {
        Write-LsshmError 'Refus d exporter autre chose qu un fichier .pub.'
        return
    }
    Get-Content -LiteralPath $pub
}

function Remove-LsshmKey {
    $path = Read-LsshmPrompt 'Chemin de la cle a supprimer'
    if (-not $path) { Write-LsshmInfo 'Annule.'; return }
    $priv = $path
    $pub = "$path.pub"
    if ($path -like '*.pub') {
        $priv = $path -replace '\.pub$', ''
        $pub = $path
    }
    if (-not (Confirm-Lsshm 'Confirmer la suppression de la paire de cles ?')) { return }
    Ensure-LsshmDirs
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($f in @($priv, $pub)) {
        if (Test-Path -LiteralPath $f) {
            Copy-Item -LiteralPath $f -Destination (Join-Path $script:LSSHM_BACKUP_DIR "$stamp-$(Split-Path $f -Leaf)") -Force
            Remove-Item -LiteralPath $f -Force
        }
    }
    Write-LsshmOk 'Paire de cles supprimee (sauvegarde conservee).'
}

function Show-LsshmAgentList {
    if (-not $env:SSH_AUTH_SOCK -and -not (Get-Process ssh-agent -ErrorAction SilentlyContinue)) {
        Write-LsshmWarn 'Aucun ssh-agent detecte. Sous Windows : Get-Service ssh-agent ; Start-Service ssh-agent'
    }
    & ssh-add -l 2>&1 | ForEach-Object { Write-Host $_ }
}

# =============================================================================
# Machines distantes
# =============================================================================

function Get-LsshmHostNames {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_CONFIG)) { return @() }
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $script:LSSHM_SSH_CONFIG) {
        if ($line -match '^\s*Host\s+(.+)$') {
            foreach ($alias in ($Matches[1] -split '\s+')) {
                if ($alias -and $alias -notmatch '[\*\?]') { $names.Add($alias) }
            }
        }
    }
    return $names
}

function Get-LsshmHostField {
    param([string]$Name, [string]$Field)
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_CONFIG)) { return $null }
    $in = $false
    $want = $Field.ToLowerInvariant()
    foreach ($line in Get-Content -LiteralPath $script:LSSHM_SSH_CONFIG) {
        if ($line -match '^\s*Host\s+(.+)$') {
            $in = ($Matches[1] -split '\s+') -contains $Name
            continue
        }
        if ($in -and $line -match "^\s*$([regex]::Escape($Field))\s+(.+)$") {
            return $Matches[1].Trim()
        }
        if ($in -and $line -match '^\s*(\S+)\s+(.+)$' -and $Matches[1].ToLowerInvariant() -eq $want) {
            return $Matches[2].Trim()
        }
    }
    return $null
}

function Show-LsshmHostsList {
    $names = @(Get-LsshmHostNames)
    if ($names.Count -eq 0) {
        Write-LsshmInfo 'Aucune machine distante dans ~/.ssh/config.'
        return
    }
    Write-Host ("Machines distantes ({0}) :" -f $script:LSSHM_SSH_CONFIG)
    foreach ($n in $names) {
        $hn = Get-LsshmHostField -Name $n -Field 'HostName'
        Write-Host ("  {0,-20} {1}" -f $n, $hn)
    }
}

function Add-LsshmHost {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) {
        New-Item -ItemType Directory -Path $script:LSSHM_SSH_DIR -Force | Out-Null
    }
    $name = Read-LsshmPrompt 'Nom (alias)' 'proxmox1'
    if (-not $name) { Write-LsshmError 'Nom requis.'; return }
    if ((Get-LsshmHostNames) -contains $name) {
        Write-LsshmError "Un hote '$name' existe deja."
        return
    }
    $hostname = Read-LsshmPrompt 'Adresse (HostName)' '192.168.100.240'
    $user = Read-LsshmPrompt 'Utilisateur' 'root'
    $port = Read-LsshmPrompt 'Port' '22'
    $identity = Read-LsshmPrompt 'Fichier de cle' (Join-Path $script:LSSHM_SSH_DIR 'id_ed25519')
    $block = @"

Host $name
    HostName $hostname
    User $user
    Port $port
    IdentityFile $identity
    IdentitiesOnly yes
"@
    Add-Content -LiteralPath $script:LSSHM_SSH_CONFIG -Value $block -Encoding utf8
    Write-LsshmOk "Hote '$name' ajoute."
}

function Remove-LsshmHost {
    $name = Read-LsshmPrompt 'Nom de l hote a supprimer'
    if (-not $name) { return }
    if (-not ((Get-LsshmHostNames) -contains $name)) {
        Write-LsshmError "Hote introuvable : $name"
        return
    }
    if (-not (Confirm-Lsshm "Supprimer l hote '$name' ?")) { return }
    Ensure-LsshmDirs
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $script:LSSHM_SSH_CONFIG -Destination (Join-Path $script:LSSHM_BACKUP_DIR "$stamp-ssh_config") -Force
    $out = [System.Collections.Generic.List[string]]::new()
    $skip = $false
    foreach ($line in Get-Content -LiteralPath $script:LSSHM_SSH_CONFIG) {
        if ($line -match '^\s*Host\s+(.+)$') {
            $skip = ($Matches[1] -split '\s+') -contains $name
            if ($skip) { continue }
        }
        if (-not $skip) { $out.Add($line) }
    }
    Set-Content -LiteralPath $script:LSSHM_SSH_CONFIG -Value $out -Encoding utf8
    Write-LsshmOk "Hote '$name' supprime."
}

function Test-LsshmHost {
    $name = Read-LsshmPrompt 'Nom de l hote a tester'
    if (-not $name) { return }
    $hostName = Get-LsshmHostField -Name $name -Field 'HostName'
    if (-not $hostName) { $hostName = $name }
    $port = Get-LsshmHostField -Name $name -Field 'Port'
    if (-not $port) { $port = '22' }

    Write-LsshmInfo "Resolution de $hostName..."
    try {
        [System.Net.Dns]::GetHostAddresses($hostName) | Out-Null
        Write-LsshmOk 'Resolution DNS reussie.'
    } catch {
        Write-LsshmWarn 'Resolution DNS incertaine.'
    }

    Write-LsshmInfo "Test du port $port..."
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($hostName, [int]$port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(3000, $false)
        if ($ok -and $client.Connected) {
            Write-LsshmOk "Port $port ouvert."
        } else {
            Write-LsshmWarn "Port $port injoignable."
        }
        $client.Close()
    } catch {
        Write-LsshmWarn "Port $port injoignable."
    }

    Write-LsshmInfo 'Test authentification SSH (BatchMode)...'
    & ssh -o BatchMode=yes -o ConnectTimeout=5 $name true 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-LsshmOk 'Authentification reussie.'
    } else {
        Write-LsshmWarn 'Authentification non automatique.'
    }
}

function Connect-LsshmHost {
    $name = Read-LsshmPrompt 'Nom de l hote'
    if (-not $name) { return }
    & ssh $name
}

# =============================================================================
# Audit / doctor / logs / backup / settings
# =============================================================================

function Invoke-LsshmDoctor {
    Write-LsshmHeader
    Write-Host 'Diagnostic LSSHM (doctor)'
    Write-Host ''
    Write-Host ("OS           : {0}" -f [System.Environment]::OSVersion.VersionString)
    Write-Host ("Utilisateur  : {0}" -f $env:USERNAME)
    Write-Host ("Administrateur: {0}" -f $(if (Test-LsshmAdmin) { 'oui' } else { 'non' }))
    Write-Host ("sshd         : {0}" -f $(if (Get-LsshmSshdPath) { Get-LsshmSshdPath } else { 'non detecte' }))
    Write-Host ("Service      : {0}" -f $script:LSSHM_SSH_SERVICE)
    Write-Host ''
    Write-Host 'Outils SSH :'
    foreach ($t in @('ssh', 'sshd', 'ssh-keygen', 'ssh-add', 'ssh-keyscan')) {
        $c = Get-Command $t -ErrorAction SilentlyContinue
        if ($c) { Write-Host ("  [OK]  {0}" -f $t) } else { Write-Host ("  [--]  {0} (absent)" -f $t) }
    }
    Write-Host ''
    Write-Host 'Chemins LSSHM :'
    Write-Host ("  config : {0}" -f $script:LSSHM_CONFIG_DIR)
    Write-Host ("  data   : {0}" -f $script:LSSHM_DATA_DIR)
    Write-Host ("  state  : {0}" -f $script:LSSHM_STATE_DIR)
}

function Invoke-LsshmAudit {
    Write-LsshmHeader
    Write-Host 'Audit de securite SSH local (Windows)'
    Write-Host ''
    $script:LSSHM_AUDIT_PASS = 0
    $script:LSSHM_AUDIT_WARN = 0
    $script:LSSHM_AUDIT_FAIL = 0

    if (Test-LsshmServerInstalled) {
        $script:LSSHM_AUDIT_PASS++; Write-Host '  [OK]    OpenSSH Server installe.' -ForegroundColor Green
    } else {
        $script:LSSHM_AUDIT_WARN++; Write-Host '  [AVERT] OpenSSH Server non installe.' -ForegroundColor Yellow
    }

    $root = Get-LsshmConfigValue 'permitrootlogin'
    switch -Regex ($root) {
        '^no$' {
            $script:LSSHM_AUDIT_PASS++
            Write-Host '  [OK]    PermitRootLogin = no.' -ForegroundColor Green
        }
        '^(prohibit-password|without-password)$' {
            $script:LSSHM_AUDIT_PASS++
            Write-Host '  [OK]    PermitRootLogin = cle uniquement.' -ForegroundColor Green
        }
        '^yes$' {
            $script:LSSHM_AUDIT_FAIL++
            Write-Host '  [ECHEC] PermitRootLogin = yes (mot de passe admin possible).' -ForegroundColor Red
        }
        default {
            $script:LSSHM_AUDIT_WARN++
            Write-Host ("  [AVERT] PermitRootLogin = {0}" -f $(if ($root) { $root } else { 'non defini' })) -ForegroundColor Yellow
        }
    }

    $passAuth = Get-LsshmConfigValue 'passwordauthentication'
    switch -Regex ($passAuth) {
        '^no$' {
            $script:LSSHM_AUDIT_PASS++
            Write-Host '  [OK]    Authentification par mot de passe desactivee.' -ForegroundColor Green
        }
        '^yes$' {
            $script:LSSHM_AUDIT_WARN++
            Write-Host '  [AVERT] Authentification par mot de passe activee.' -ForegroundColor Yellow
        }
        default {
            $script:LSSHM_AUDIT_WARN++
            Write-Host ("  [AVERT] PasswordAuthentication = {0}" -f $(if ($passAuth) { $passAuth } else { 'non defini' })) -ForegroundColor Yellow
        }
    }

    if (Test-Path -LiteralPath $script:LSSHM_SSH_DIR) {
        $script:LSSHM_AUDIT_PASS++
        Write-Host '  [OK]    .ssh present pour l utilisateur courant.' -ForegroundColor Green
    } else {
        $script:LSSHM_AUDIT_WARN++
        Write-Host '  [AVERT] Aucun repertoire .ssh.' -ForegroundColor Yellow
    }

    if (Test-LsshmServerActive) {
        $script:LSSHM_AUDIT_PASS++
        Write-Host '  [OK]    Service sshd actif.' -ForegroundColor Green
    } else {
        $script:LSSHM_AUDIT_WARN++
        Write-Host '  [AVERT] Service sshd inactif ou absent.' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host ("Resume : {0} OK, {1} avertissements, {2} echecs" -f `
            $script:LSSHM_AUDIT_PASS, $script:LSSHM_AUDIT_WARN, $script:LSSHM_AUDIT_FAIL)
}

function Show-LsshmLogsMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host 'Connexions et journaux'
        Write-Host ''
        Write-Host '  1. Sessions / processus sshd'
        Write-Host '  2. Evenements OpenSSH (Journal des evenements)'
        Write-Host '  3. Retour'
        $c = Read-LsshmPrompt 'Choix' '3'
        switch ($c) {
            '1' {
                Get-Process -Name sshd -ErrorAction SilentlyContinue | Format-Table Id, ProcessName, StartTime -AutoSize
                Get-Service sshd -ErrorAction SilentlyContinue | Format-List *
                Pause-Lsshm
            }
            '2' {
                try {
                    Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 20 -ErrorAction Stop |
                        Format-Table TimeCreated, Id, Message -Wrap
                } catch {
                    Write-LsshmWarn "Journal OpenSSH/Operational indisponible : $($_.Exception.Message)"
                }
                Pause-Lsshm
            }
            '3' { return }
            default { Write-LsshmWarn 'Choix invalide.'; Pause-Lsshm }
        }
    }
}

function Show-LsshmBackupMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host 'Sauvegarde et restauration'
        Write-Host ''
        Write-Host '  1. Sauvegarder sshd_config'
        Write-Host '  2. Sauvegarder authorized_keys utilisateur'
        Write-Host '  3. Lister les sauvegardes'
        Write-Host '  4. Retour'
        $c = Read-LsshmPrompt 'Choix' '4'
        switch ($c) {
            '1' { Backup-LsshmServerConfig; Pause-Lsshm }
            '2' {
                Ensure-LsshmDirs
                if (Test-Path -LiteralPath $script:LSSHM_AUTHORIZED_KEYS) {
                    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $dest = Join-Path $script:LSSHM_BACKUP_DIR "$stamp-authorized_keys"
                    Copy-Item -LiteralPath $script:LSSHM_AUTHORIZED_KEYS -Destination $dest -Force
                    Write-LsshmOk "Sauvegarde : $dest"
                } else {
                    Write-LsshmWarn 'authorized_keys introuvable.'
                }
                Pause-Lsshm
            }
            '3' {
                Ensure-LsshmDirs
                Get-ChildItem -LiteralPath $script:LSSHM_BACKUP_DIR -ErrorAction SilentlyContinue |
                    ForEach-Object { Write-Host ("  {0}" -f $_.Name) }
                Pause-Lsshm
            }
            '4' { return }
            default { Write-LsshmWarn 'Choix invalide.'; Pause-Lsshm }
        }
    }
}

function Show-LsshmSettingsMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host 'Parametres de LSSHM (Windows)'
        Write-Host ''
        Write-Host ("Config : {0}" -f $script:LSSHM_CONFIG_FILE)
        Write-Host ("Data   : {0}" -f $script:LSSHM_DATA_DIR)
        Write-Host ''
        Write-Host '  1. Afficher le diagnostic (doctor)'
        Write-Host '  2. Installer LSSHM dans le profil utilisateur'
        Write-Host '  3. Retour'
        $c = Read-LsshmPrompt 'Choix' '3'
        switch ($c) {
            '1' { Invoke-LsshmDoctor; Pause-Lsshm }
            '2' { Install-LsshmSelf; Pause-Lsshm }
            '3' { return }
            default { Write-LsshmWarn 'Choix invalide.'; Pause-Lsshm }
        }
    }
}

# =============================================================================
# Installation locale Windows
# =============================================================================

function Install-LsshmSelf {
    Ensure-LsshmDirs
    if (-not (Test-Path -LiteralPath $script:LSSHM_BIN_DIR)) {
        New-Item -ItemType Directory -Path $script:LSSHM_BIN_DIR -Force | Out-Null
    }

    $self = $PSCommandPath
    if ($self -and (Test-Path -LiteralPath $self)) {
        Copy-Item -LiteralPath $self -Destination $script:LSSHM_INSTALL_TARGET -Force
    } else {
        Write-LsshmInfo 'Telechargement de lsshm.ps1...'
        $tmp = Join-Path $env:TEMP ("lsshm-{0}.ps1" -f [guid]::NewGuid())
        Invoke-WebRequest -Uri "$($script:LSSHM_REPO_RAW)/lsshm.ps1" -OutFile $tmp -UseBasicParsing
        Copy-Item -LiteralPath $tmp -Destination $script:LSSHM_INSTALL_TARGET -Force
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath $script:LSSHM_INSTALL_TARGET -Destination $script:LSSHM_BIN_LINK -Force

    # User PATH
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$($script:LSSHM_BIN_DIR)*") {
        [Environment]::SetEnvironmentVariable('Path', "$($script:LSSHM_BIN_DIR);$userPath", 'User')
        $env:Path = "$($script:LSSHM_BIN_DIR);$env:Path"
        Write-LsshmOk "Ajoute au PATH utilisateur : $($script:LSSHM_BIN_DIR)"
    }

    Write-LsshmOk "Installe :"
    Write-Host ("  {0}" -f $script:LSSHM_INSTALL_TARGET)
    Write-Host ("  {0}" -f $script:LSSHM_BIN_LINK)
    Write-LsshmInfo 'Dans une nouvelle session : lsshm.ps1   ou   powershell -File lsshm.ps1'
}

# =============================================================================
# Menus CLI
# =============================================================================

function Show-LsshmServerMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host 'Serveur SSH local (Windows OpenSSH)'
        Write-Host ''
        Show-LsshmServerStatus
        Write-Host ''
        Write-Host '  1. Installer OpenSSH Server'
        Write-Host '  2. Demarrer le service'
        Write-Host '  3. Arreter le service'
        Write-Host '  4. Redemarrer le service'
        Write-Host '  5. Activer au demarrage'
        Write-Host '  6. Desactiver au demarrage'
        Write-Host '  7. Gerer PermitRootLogin / acces admin'
        Write-Host '  8. Authentification par mot de passe'
        Write-Host '  9. Authentification par cle'
        Write-Host ' 10. Tester la configuration (sshd -t)'
        Write-Host ' 11. Afficher la configuration effective (sshd -T)'
        Write-Host ' 12. Retour'
        $c = Read-LsshmPrompt 'Choix' '12'
        try {
            switch ($c) {
                '1' { Install-LsshmOpenSshServer; Pause-Lsshm }
                '2' { Invoke-LsshmServerAction Start; Pause-Lsshm }
                '3' { Invoke-LsshmServerAction Stop; Pause-Lsshm }
                '4' { Invoke-LsshmServerAction Restart; Pause-Lsshm }
                '5' { Set-LsshmServerStartup Automatic; Pause-Lsshm }
                '6' { Set-LsshmServerStartup Disabled; Pause-Lsshm }
                '7' { Set-LsshmRootLoginMenu; Pause-Lsshm }
                '8' {
                    if (Confirm-Lsshm 'Autoriser PasswordAuthentication ?' -DefaultYes:$false) {
                        Set-LsshmSshdDirective -Key 'PasswordAuthentication' -Value 'yes' | Out-Null
                    } else {
                        Set-LsshmSshdDirective -Key 'PasswordAuthentication' -Value 'no' | Out-Null
                    }
                    Restart-Service sshd -Force -ErrorAction SilentlyContinue
                    Pause-Lsshm
                }
                '9' {
                    if (Confirm-Lsshm 'Autoriser PubkeyAuthentication ?' -DefaultYes) {
                        Set-LsshmSshdDirective -Key 'PubkeyAuthentication' -Value 'yes' | Out-Null
                    } else {
                        if (Confirm-Lsshm 'Desactiver les cles peut vous verrouiller. Continuer ?') {
                            Set-LsshmSshdDirective -Key 'PubkeyAuthentication' -Value 'no' | Out-Null
                        }
                    }
                    Restart-Service sshd -Force -ErrorAction SilentlyContinue
                    Pause-Lsshm
                }
                '10' { Test-LsshmServerConfig | Out-Null; Pause-Lsshm }
                '11' { Show-LsshmServerConfigDump; Pause-Lsshm }
                '12' { return }
                default { Write-LsshmWarn 'Choix invalide.'; Pause-Lsshm }
            }
        } catch {
            Write-LsshmError $_.Exception.Message
            Pause-Lsshm
        }
    }
}

function Show-LsshmAccessMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host 'Acces a cette machine (cles autorisees ICI)'
        Write-Host ''
        Write-Host '  1. Lister les cles utilisateur (~/.ssh/authorized_keys)'
        Write-Host '  2. Lister les cles administrateurs (administrators_authorized_keys)'
        Write-Host '  3. Ajouter une cle utilisateur'
        Write-Host '  4. Ajouter une cle administrateur'
        Write-Host '  5. Reparer les permissions .ssh'
        Write-Host '  6. Retour'
        $c = Read-LsshmPrompt 'Choix' '6'
        try {
            switch ($c) {
                '1' { Show-LsshmAccessList -Scope User; Pause-Lsshm }
                '2' { Show-LsshmAccessList -Scope Administrators; Pause-Lsshm }
                '3' { Add-LsshmAccessKey -Scope User; Pause-Lsshm }
                '4' { Add-LsshmAccessKey -Scope Administrators; Pause-Lsshm }
                '5' { Repair-LsshmAccessPermissions; Pause-Lsshm }
                '6' { return }
                default { Write-LsshmWarn 'Choix invalide.'; Pause-Lsshm }
            }
        } catch {
            Write-LsshmError $_.Exception.Message
            Pause-Lsshm
        }
    }
}

function Show-LsshmKeysMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host 'Mes cles SSH (pour se connecter AILLEURS)'
        Write-Host ''
        Write-Host '  1. Lister les paires de cles'
        Write-Host '  2. Generer une nouvelle cle (ED25519 par defaut)'
        Write-Host '  3. Inspecter une cle'
        Write-Host '  4. Afficher / exporter une cle publique'
        Write-Host '  5. Supprimer une paire de cles'
        Write-Host '  6. ssh-agent : lister'
        Write-Host '  7. Retour'
        $c = Read-LsshmPrompt 'Choix' '7'
        switch ($c) {
            '1' { Show-LsshmKeysList; Pause-Lsshm }
            '2' { New-LsshmKey; Pause-Lsshm }
            '3' { Show-LsshmKeyInspect; Pause-Lsshm }
            '4' { Show-LsshmKeyExport; Pause-Lsshm }
            '5' { Remove-LsshmKey; Pause-Lsshm }
            '6' { Show-LsshmAgentList; Pause-Lsshm }
            '7' { return }
            default { Write-LsshmWarn 'Choix invalide.'; Pause-Lsshm }
        }
    }
}

function Show-LsshmHostsMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host 'Machines distantes (~/.ssh/config) - facultatif'
        Write-Host ''
        Write-Host '  1. Lister les machines'
        Write-Host '  2. Ajouter une machine'
        Write-Host '  3. Supprimer une machine'
        Write-Host '  4. Tester une machine'
        Write-Host '  5. Se connecter'
        Write-Host '  6. Retour'
        $c = Read-LsshmPrompt 'Choix' '6'
        switch ($c) {
            '1' { Show-LsshmHostsList; Pause-Lsshm }
            '2' { Add-LsshmHost; Pause-Lsshm }
            '3' { Remove-LsshmHost; Pause-Lsshm }
            '4' { Test-LsshmHost; Pause-Lsshm }
            '5' { Connect-LsshmHost }
            '6' { return }
            default { Write-LsshmWarn 'Choix invalide.'; Pause-Lsshm }
        }
    }
}

function Show-LsshmMainMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Show-LsshmStatusPanel
        Write-Host ''
        Write-Host '1. Gerer le serveur SSH local'
        Write-Host '2. Gerer les acces a cette machine'
        Write-Host '3. Gerer mes cles SSH'
        Write-Host '4. Gerer les machines distantes'
        Write-Host '5. Consulter les connexions et journaux'
        Write-Host '6. Effectuer un audit de securite'
        Write-Host '7. Sauvegarder ou restaurer'
        Write-Host '8. Parametres de LSSHM'
        Write-Host '9. Quitter'
        $c = Read-LsshmPrompt 'Choix' '9'
        switch ($c) {
            '1' { Show-LsshmServerMenu }
            '2' { Show-LsshmAccessMenu }
            '3' { Show-LsshmKeysMenu }
            '4' { Show-LsshmHostsMenu }
            '5' { Show-LsshmLogsMenu }
            '6' { Invoke-LsshmAudit; Pause-Lsshm }
            '7' { Show-LsshmBackupMenu }
            '8' { Show-LsshmSettingsMenu }
            { $_ -in @('9', 'q', 'Q') } { return }
            default { Write-LsshmWarn 'Choix invalide.'; Pause-Lsshm }
        }
    }
}

# =============================================================================
# Point d'entree
# =============================================================================

function Show-LsshmUsage {
    @"
$script:LSSHM_LONG_NAME v$script:LSSHM_VERSION (Windows / PowerShell)

Usage :
  lsshm.ps1                     Menu CLI
  lsshm.ps1 status              Etat SSH local
  lsshm.ps1 doctor              Diagnostic
  lsshm.ps1 audit               Audit de securite
  lsshm.ps1 install             Installer dans le profil utilisateur
  lsshm.ps1 server status       Etat du service sshd
  lsshm.ps1 key list            Lister les cles locales
  lsshm.ps1 host list           Lister les hotes ~/.ssh/config
  lsshm.ps1 help                Cette aide

Options :
  -Yes                          Confirmer automatiquement (non interactif)
  -User NOM                     Utilisateur cible (affichage)
"@ | Write-Host
}

function Invoke-LsshmMain {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ArgsRest
    )

    Initialize-LsshmPaths
    Ensure-LsshmDirs

    $cmd = if ($ArgsRest -and $ArgsRest.Count -gt 0) { $ArgsRest[0].ToLowerInvariant() } else { 'menu' }
    $rest = if ($ArgsRest -and $ArgsRest.Count -gt 1) { $ArgsRest[1..($ArgsRest.Count - 1)] } else { @() }

    switch ($cmd) {
        'menu' { Show-LsshmMainMenu }
        'status' { Show-LsshmStatusPanel }
        'doctor' { Invoke-LsshmDoctor }
        'audit' { Invoke-LsshmAudit }
        'install' { Install-LsshmSelf }
        'version' { Write-Host ("{0} v{1}" -f $script:LSSHM_NAME, $script:LSSHM_VERSION) }
        'help' { Show-LsshmUsage }
        'server' {
            $sub = if ($rest.Count -gt 0) { $rest[0].ToLowerInvariant() } else { 'status' }
            switch ($sub) {
                'status' { Show-LsshmServerStatus }
                'install' { Install-LsshmOpenSshServer }
                'start' { Invoke-LsshmServerAction Start }
                'stop' { Invoke-LsshmServerAction Stop }
                'restart' { Invoke-LsshmServerAction Restart }
                'test' { Test-LsshmServerConfig | Out-Null }
                'config' { Show-LsshmServerConfigDump }
                default { Write-LsshmError "Sous-commande server inconnue : $sub"; exit 1 }
            }
        }
        'access' {
            $sub = if ($rest.Count -gt 0) { $rest[0].ToLowerInvariant() } else { 'list' }
            switch ($sub) {
                'list' { Show-LsshmAccessList -Scope User }
                'repair' { Repair-LsshmAccessPermissions }
                default { Write-LsshmError "Sous-commande access inconnue : $sub"; exit 1 }
            }
        }
        'key' {
            $sub = if ($rest.Count -gt 0) { $rest[0].ToLowerInvariant() } else { 'list' }
            switch ($sub) {
                'list' { Show-LsshmKeysList }
                'generate' { New-LsshmKey }
                default { Write-LsshmError "Sous-commande key inconnue : $sub"; exit 1 }
            }
        }
        'host' {
            $sub = if ($rest.Count -gt 0) { $rest[0].ToLowerInvariant() } else { 'list' }
            switch ($sub) {
                'list' { Show-LsshmHostsList }
                'add' { Add-LsshmHost }
                default { Write-LsshmError "Sous-commande host inconnue : $sub"; exit 1 }
            }
        }
        default {
            Write-LsshmError "Commande inconnue : $cmd"
            Show-LsshmUsage
            exit 1
        }
    }
}

# --- parse global switches then dispatch ---
$rawArgs = [System.Collections.Generic.List[string]]::new()
if ($args) {
    for ($i = 0; $i -lt $args.Count; $i++) {
        switch -Regex ($args[$i]) {
            '^-y$|^--yes$|^-Yes$' { $script:LSSHM_ASSUME_YES = $true }
            '^-h$|^--help$|^-Help$' { $rawArgs.Add('help') }
            '^-V$|^--version$|^-Version$' { $rawArgs.Add('version') }
            '^--user$' {
                if ($i + 1 -lt $args.Count) {
                    $script:LSSHM_TARGET_USER = $args[$i + 1]
                    $i++
                }
            }
            default { $rawArgs.Add([string]$args[$i]) }
        }
    }
}

Invoke-LsshmMain -ArgsRest $rawArgs.ToArray()
