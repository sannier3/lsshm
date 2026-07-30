#Requires -Version 5.1
<#
.SYNOPSIS
    LSSHM - Local SSH Manager (Windows / PowerShell)

.DESCRIPTION
    Local OpenSSH management on Windows: SSH server, incoming access,
    outgoing keys and remote hosts. Menu-driven CLI, no external
    dependency. Same concepts and menus as the Bash/Linux version.

    The interface language is selectable (English, French, Spanish) and is
    stored in the configuration file. It defaults to the detected system
    language, falling back to English.

.NOTES
    Version aligned with the repository VERSION file.
    Windows OpenSSH paths:
      %ProgramData%\ssh\sshd_config
      %ProgramData%\ssh\administrators_authorized_keys
      %USERPROFILE%\.ssh\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Constants and state
# =============================================================================

$script:LSSHM_VERSION = '0.4.0'
$script:LSSHM_NAME = 'LSSHM'
$script:LSSHM_LONG_NAME = 'LSSHM - Local SSH Manager'
$script:LSSHM_REPO_RAW = if ($env:LSSHM_REPO_RAW) { $env:LSSHM_REPO_RAW } else { 'https://raw.githubusercontent.com/sannier3/lsshm/preview' }
$script:LSSHM_ASSUME_YES = $false
$script:LSSHM_TARGET_USER = $null
$script:LSSHM_LANG = 'en'
$script:LSSHM_LANG_OVERRIDE = ''

# =============================================================================
# Internationalization (message catalogs + language selection)
# =============================================================================
# Source strings are written in English (the msgid). Translations live in
# per-language hashtables keyed by the English msgid. A missing translation
# falls back to English. Format strings use .NET placeholders ({0}, {1}, ...).

$script:LSSHM_LANGS = @('en', 'fr', 'es')

$script:LSSHM_MSG_fr = @{
    # Prompts / common
    'Press Enter to continue'                = 'Appuyez sur Entree pour continuer'
    'Choice'                                 = 'Choix'
    'Invalid choice.'                        = 'Choix invalide.'
    'Cancelled.'                             = 'Annule.'
    'No change.'                             = 'Aucun changement.'
    'yes'                                    = 'oui'
    'no'                                     = 'non'
    'not set'                                = 'non defini'
    'present'                                = 'presente'
    'absent'                                 = 'absente'
    'unknown'                                = 'inconnue'
    'forbidden'                              = 'interdit'
    'key only'                               = 'cle uniquement'
    'key or password'                        = 'cle ou mot de passe'
    'forced commands only'                   = 'commandes imposees'
    'active'                                 = 'actif'
    'inactive'                               = 'inactif'
    # Language
    'Language set to: {0}'                   = 'Langue definie sur : {0}'
    'Change the language'                    = 'Changer la langue'
    # Privileges
    'This operation requires PowerShell as administrator.' = 'Cette operation necessite PowerShell en administrateur.'
    'Relaunch: Start-Process powershell -Verb RunAs'       = 'Relancez : Start-Process powershell -Verb RunAs'
    'Elevation required'                     = 'Elevation requise'
    # Status panel
    'SSH server status: {0}'                 = 'Etat du serveur SSH : {0}'
    'Port: {0}'                              = 'Port : {0}'
    'Root / admin access: {0}'               = 'Acces root / admin : {0}'
    'Password authentication: {0}'           = 'Authentification par mot de passe : {0}'
    'Administrator keys (administrators_authorized_keys): {0}' = 'Cles administrateurs (administrators_authorized_keys) : {0}'
    'Private keys of user {0}: {1}'          = 'Cles privees de l''utilisateur {0} : {1}'
    'Registered remote hosts: {0}'           = 'Machines distantes enregistrees : {0}'
    # Server status
    'OpenSSH Server is not installed (sshd.exe not found).' = 'OpenSSH Server n''est pas installe (sshd.exe introuvable).'
    'Auto-start          : {0}'              = 'Demarrage auto      : {0}'
    'Port                : {0}'              = 'Port                : {0}'
    'Admin access        : {0}'              = 'Acces admin         : {0}'
    'Password auth       : {0}'              = 'Auth. mot de passe  : {0}'
    'Key auth            : {0}'              = 'Auth. par cle       : {0}'
    'Config              : {0}'              = 'Config              : {0}'
    # Server install / actions
    'OpenSSH Server already present: {0}'    = 'OpenSSH Server deja present : {0}'
    'Installing OpenSSH.Server (optional Windows feature)...' = 'Installation de OpenSSH.Server (fonctionnalite facultative Windows)...'
    'OpenSSH Server installed.'              = 'OpenSSH Server installe.'
    'Installation failed. Try: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0' = 'Installation echouee. Essayez : Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0'
    'SSH service started.'                   = 'Service SSH demarre.'
    'SSH service stopped.'                   = 'Service SSH arrete.'
    'SSH service restarted.'                 = 'Service SSH redemarre.'
    'Automatic startup: {0}'                 = 'Demarrage automatique : {0}'
    'sshd not found.'                        = 'sshd introuvable.'
    'Configuration valid (sshd -t).'         = 'Configuration valide (sshd -t).'
    'Invalid configuration.'                 = 'Configuration invalide.'
    'No server configuration to back up.'    = 'Aucune configuration serveur a sauvegarder.'
    'Backup created: {0}'                    = 'Sauvegarde creee : {0}'
    'File not found: {0}'                    = 'Fichier introuvable : {0}'
    'Invalid configuration: restore a backup if needed.' = 'Configuration invalide : restaurez une sauvegarde si besoin.'
    'Directive applied: {0} {1}'             = 'Directive appliquee : {0} {1}'
    # Root login menu
    'Administrator / root SSH login'         = 'Connexion SSH administrateur / root'
    '  1. Forbid entirely'                   = '  1. Interdire totalement'
    '  2. Allow with a key only'             = '  2. Autoriser uniquement avec une cle'
    '  3. Allow with a key or a password'    = '  3. Autoriser avec une cle ou un mot de passe'
    '  4. Allow only for forced commands'    = '  4. Autoriser uniquement pour des commandes imposees'
    'Apply this sensitive change?'           = 'Appliquer ce changement sensible ?'
    # Access
    'File: {0}'                              = 'Fichier : {0}'
    'No authorized key.'                     = 'Aucune cle autorisee.'
    'Paste the public key (one line) or a .pub path' = 'Collez la cle publique (une ligne) ou chemin .pub'
    'Key added to {0}'                       = 'Cle ajoutee dans {0}'
    '.ssh not found.'                        = '.ssh introuvable.'
    '.ssh permissions repaired (Windows ACL).' = 'Permissions .ssh reparees (ACL Windows).'
    # Local keys
    'Directory: {0}'                         = 'Repertoire : {0}'
    'No key pair detected.'                  = 'Aucune paire de cles detectee.'
    '   Public   : {0}'                      = '   Publique : {0}'
    '   Private  : {0}'                      = '   Privee   : {0}'
    '   Fingerprint: {0}'                    = '   Empreinte: {0}'
    'Choose a key'                           = 'Choisir une cle'
    'Private key not found: {0}'             = 'Cle privee introuvable : {0}'
    'Key not found: {0}'                     = 'Cle introuvable : {0}'
    '{0} (number)'                           = '{0} (numero)'
    'Invalid choice: {0}'                    = 'Choix invalide : {0}'
    'Number out of range (1-{0}).'           = 'Numero hors plage (1-{0}).'
    'Private key missing for {0}.'           = 'Cle privee absente pour {0}.'
    'Key type (ed25519/rsa)'                 = 'Type de cle (ed25519/rsa)'
    'File name'                              = 'Nom du fichier'
    'Comment'                                = 'Commentaire'
    'Key generated: {0}'                     = 'Cle generee : {0}'
    'Generation failed.'                     = 'Echec de la generation.'
    'Key to inspect'                         = 'Cle a inspecter'
    'Key to export'                          = 'Cle a exporter'
    'Public key not found: {0}'              = 'Cle publique introuvable : {0}'
    'Public key ({0}):'                      = 'Cle publique ({0}) :'
    'Key to delete'                          = 'Cle a supprimer'
    'Deleting the key pair:'                 = 'Suppression de la paire de cles :'
    'A backup will be created. Confirm deletion?' = 'Une sauvegarde sera creee. Confirmer la suppression ?'
    'Key pair deleted (backup kept).'        = 'Paire de cles supprimee (sauvegarde conservee).'
    # ssh-agent
    'No ssh-agent detected. On Windows: Get-Service ssh-agent ; Start-Service ssh-agent' = 'Aucun ssh-agent detecte. Sous Windows : Get-Service ssh-agent ; Start-Service ssh-agent'
    'Key to add to ssh-agent'                = 'Cle a ajouter a ssh-agent'
    'Key added to ssh-agent.'                = 'Cle ajoutee a ssh-agent.'
    'Failed.'                                = 'Echec.'
    'Remove all keys from the agent?'        = 'Retirer toutes les cles de l''agent ?'
    'All keys removed.'                      = 'Toutes les cles retirees.'
    'Key to remove from ssh-agent'           = 'Cle a retirer de ssh-agent'
    'Key removed from ssh-agent.'            = 'Cle retiree de ssh-agent.'
    # Hosts
    'No remote host in ~/.ssh/config.'       = 'Aucune machine distante dans ~/.ssh/config.'
    'Remote hosts ({0}):'                    = 'Machines distantes ({0}) :'
    'Host alias'                             = 'Nom (alias)'
    'Name required.'                         = 'Nom requis.'
    'A host ''{0}'' already exists.'         = 'Un hote ''{0}'' existe deja.'
    'Address (HostName)'                     = 'Adresse (HostName)'
    'User'                                   = 'Utilisateur'
    'Port'                                   = 'Port'
    'Key file'                               = 'Fichier de cle'
    'Host ''{0}'' added.'                    = 'Hote ''{0}'' ajoute.'
    'Host name to delete'                    = 'Nom de l''hote a supprimer'
    'Host not found: {0}'                    = 'Hote introuvable : {0}'
    'Delete host ''{0}''?'                   = 'Supprimer l''hote ''{0}'' ?'
    'Host ''{0}'' deleted.'                  = 'Hote ''{0}'' supprime.'
    'Host name to test'                      = 'Nom de l''hote a tester'
    'Resolving {0}...'                       = 'Resolution de {0}...'
    'DNS resolution succeeded.'              = 'Resolution DNS reussie.'
    'DNS resolution uncertain.'              = 'Resolution DNS incertaine.'
    'Testing port {0}...'                    = 'Test du port {0}...'
    'Port {0} open.'                         = 'Port {0} ouvert.'
    'Port {0} unreachable.'                  = 'Port {0} injoignable.'
    'SSH authentication test (BatchMode)...' = 'Test authentification SSH (BatchMode)...'
    'Authentication succeeded.'              = 'Authentification reussie.'
    'Automatic authentication failed.'       = 'Authentification non automatique.'
    'Host name'                              = 'Nom de l''hote'
    # Doctor
    'LSSHM diagnostics (doctor)'             = 'Diagnostic LSSHM (doctor)'
    'OS           : {0}'                     = 'OS           : {0}'
    'User         : {0}'                     = 'Utilisateur  : {0}'
    'Administrator: {0}'                     = 'Administrateur: {0}'
    'sshd         : {0}'                     = 'sshd         : {0}'
    'Service      : {0}'                     = 'Service      : {0}'
    'not detected'                           = 'non detecte'
    'SSH tools:'                             = 'Outils SSH :'
    'LSSHM paths:'                           = 'Chemins LSSHM :'
    # Audit
    'Local SSH security audit (Windows)'     = 'Audit de securite SSH local (Windows)'
    'OpenSSH Server not installed.'          = 'OpenSSH Server non installe.'
    'PermitRootLogin = no.'                  = 'PermitRootLogin = no.'
    'PermitRootLogin = key only.'            = 'PermitRootLogin = cle uniquement.'
    'PermitRootLogin = yes (admin password possible).' = 'PermitRootLogin = yes (mot de passe admin possible).'
    'PermitRootLogin = {0}'                  = 'PermitRootLogin = {0}'
    'Password authentication disabled.'      = 'Authentification par mot de passe desactivee.'
    'Password authentication enabled.'       = 'Authentification par mot de passe activee.'
    'PasswordAuthentication = {0}'           = 'PasswordAuthentication = {0}'
    '.ssh present for the current user.'     = '.ssh present pour l''utilisateur courant.'
    'No .ssh directory.'                     = 'Aucun repertoire .ssh.'
    'sshd service active.'                   = 'Service sshd actif.'
    'sshd service inactive or absent.'       = 'Service sshd inactif ou absent.'
    'Summary: {0} OK, {1} warnings, {2} failures' = 'Resume : {0} OK, {1} avertissements, {2} echecs'
    # Logs
    'Connections and logs'                   = 'Connexions et journaux'
    '  1. Sessions / sshd processes'         = '  1. Sessions / processus sshd'
    '  2. OpenSSH events (Event Log)'        = '  2. Evenements OpenSSH (Journal des evenements)'
    '  3. Back'                              = '  3. Retour'
    'OpenSSH/Operational log unavailable: {0}' = 'Journal OpenSSH/Operational indisponible : {0}'
    # Backup menu
    'Backup and restore'                     = 'Sauvegarde et restauration'
    '  1. Back up sshd_config'               = '  1. Sauvegarder sshd_config'
    '  2. Back up user authorized_keys'      = '  2. Sauvegarder authorized_keys utilisateur'
    '  3. List backups'                      = '  3. Lister les sauvegardes'
    '  4. Back'                              = '  4. Retour'
    'Backup: {0}'                            = 'Sauvegarde : {0}'
    'authorized_keys not found.'             = 'authorized_keys introuvable.'
    # Settings menu
    'LSSHM settings (Windows)'               = 'Parametres de LSSHM (Windows)'
    'Config : {0}'                           = 'Config : {0}'
    'Data   : {0}'                           = 'Data   : {0}'
    'Language : {0}'                         = 'Langue : {0}'
    '  1. Show diagnostics (doctor)'         = '  1. Afficher le diagnostic (doctor)'
    '  2. Install LSSHM into the user profile' = '  2. Installer LSSHM dans le profil utilisateur'
    '  3. Change the language'               = '  3. Changer la langue'
    # Install
    'Downloading lsshm.ps1...'               = 'Telechargement de lsshm.ps1...'
    'Added to the user PATH: {0}'            = 'Ajoute au PATH utilisateur : {0}'
    'Installed:'                             = 'Installe :'
    'Installation complete.'                 = 'Installation terminee.'
    'Run: lsshm.ps1'                         = 'Lancez : lsshm.ps1'
    # Server menu
    'Local SSH server (Windows OpenSSH)'     = 'Serveur SSH local (Windows OpenSSH)'
    '  1. Install OpenSSH Server'            = '  1. Installer OpenSSH Server'
    '  2. Start the service'                 = '  2. Demarrer le service'
    '  3. Stop the service'                  = '  3. Arreter le service'
    '  4. Restart the service'              = '  4. Redemarrer le service'
    '  5. Enable at boot'                    = '  5. Activer au demarrage'
    '  6. Disable at boot'                   = '  6. Desactiver au demarrage'
    '  7. Change the port'                   = '  7. Changer le port'
    '  8. Address family (AddressFamily)'    = '  8. Famille d''adresses (AddressFamily)'
    '  9. Listen addresses (ListenAddress)'  = '  9. Adresses d''ecoute (ListenAddress)'
    ' 10. Windows Firewall (allow OpenSSH)'  = ' 10. Pare-feu Windows (autoriser OpenSSH)'
    ' 11. Manage PermitRootLogin / admin access' = ' 11. Gerer PermitRootLogin / acces admin'
    ' 12. Password authentication'           = ' 12. Authentification par mot de passe'
    ' 13. Key authentication'                = ' 13. Authentification par cle'
    ' 14. Test the configuration (sshd -t)'  = ' 14. Tester la configuration (sshd -t)'
    ' 15. Show the effective configuration (sshd -T)' = ' 15. Afficher la configuration effective (sshd -T)'
    ' 16. Back'                              = ' 16. Retour'
    'Change the port'                        = 'Changer le port'
    'Address family (AddressFamily)'         = 'Famille d''adresses (AddressFamily)'
    'Listen addresses (ListenAddress)'       = 'Adresses d''ecoute (ListenAddress)'
    'New SSH port'                           = 'Nouveau port SSH'
    'Invalid port.'                          = 'Port invalide.'
    'Check your firewall before changing the port.' = 'Verifiez votre pare-feu avant de changer le port.'
    'SSH address family (AddressFamily)'     = 'Famille d''adresses SSH (AddressFamily)'
    'Current: {0}'                           = 'Actuel : {0}'
    '  1. any   (IPv4 + IPv6, OpenSSH default)' = '  1. any   (IPv4 + IPv6, defaut OpenSSH)'
    '  2. inet  (IPv4 only)'                  = '  2. inet  (IPv4 uniquement)'
    '  3. inet6 (IPv6 only)'                 = '  3. inet6 (IPv6 uniquement)'
    'SSH listen addresses (ListenAddress)'   = 'Adresses d''ecoute SSH (ListenAddress)'
    'Examples: 0.0.0.0   ::   192.168.1.10   0.0.0.0 ::' = 'Exemples : 0.0.0.0   ::   192.168.1.10   0.0.0.0 ::'
    'Empty input restores OpenSSH defaults (all interfaces).' = 'Une saisie vide restaure les defauts OpenSSH (toutes les interfaces).'
    'Listen addresses (space-separated)'     = 'Adresses d''ecoute (separees par des espaces)'
    'Directive removed: {0}'                 = 'Directive retiree : {0}'
    'Directive applied: {0} ({1})'           = 'Directive appliquee : {0} ({1})'
    'Address family      : {0}'              = 'Famille d''adresses  : {0}'
    'Listen addresses    : {0}'              = 'Adresses d''ecoute   : {0}'
    'Firewall            : {0}'              = 'Pare-feu             : {0}'
    'allowed (port {0})'                     = 'autorise (port {0})'
    'not allowed / no matching rule'         = 'non autorise / aucune regle correspondante'
    'Windows Firewall — OpenSSH'             = 'Pare-feu Windows — OpenSSH'
    'Status: {0}'                            = 'Etat : {0}'
    '  1. Allow OpenSSH through the firewall' = '  1. Autoriser OpenSSH dans le pare-feu'
    '  2. Disable OpenSSH firewall rules'    = '  2. Desactiver les regles pare-feu OpenSSH'
    'Allow OpenSSH through Windows Firewall?' = 'Autoriser OpenSSH dans le pare-feu Windows ?'
    'OpenSSH is allowed through Windows Firewall.' = 'OpenSSH est autorise dans le pare-feu Windows.'
    'Created firewall rule for OpenSSH on port {0}.' = 'Regle pare-feu creee pour OpenSSH sur le port {0}.'
    'Firewall rule updated for port {0}.'    = 'Regle pare-feu mise a jour pour le port {0}.'
    'Enabled firewall rule: {0}'             = 'Regle pare-feu activee : {0}'
    'Disabled firewall rule: {0}'            = 'Regle pare-feu desactivee : {0}'
    'LSSHM firewall rule disabled.'          = 'Regle pare-feu LSSHM desactivee.'
    'No OpenSSH firewall rule found to disable.' = 'Aucune regle pare-feu OpenSSH a desactiver.'
    'Unable to create firewall rule: {0}'    = 'Impossible de creer la regle pare-feu : {0}'
    'Unable to update firewall rule: {0}'    = 'Impossible de mettre a jour la regle pare-feu : {0}'
    'Unable to disable LSSHM firewall rule: {0}' = 'Impossible de desactiver la regle pare-feu LSSHM : {0}'
    'Allow PasswordAuthentication?'          = 'Autoriser PasswordAuthentication ?'
    'Allow PubkeyAuthentication?'            = 'Autoriser PubkeyAuthentication ?'
    'Disabling keys may lock you out. Continue?' = 'Desactiver les cles peut vous verrouiller. Continuer ?'
    # Access menu
    'Access to this machine (keys allowed HERE)' = 'Acces a cette machine (cles autorisees ICI)'
    '  1. List user keys (~/.ssh/authorized_keys)' = '  1. Lister les cles utilisateur (~/.ssh/authorized_keys)'
    '  2. List administrator keys (administrators_authorized_keys)' = '  2. Lister les cles administrateurs (administrators_authorized_keys)'
    '  3. Add a user key'                    = '  3. Ajouter une cle utilisateur'
    '  4. Add an administrator key'          = '  4. Ajouter une cle administrateur'
    '  5. Repair .ssh permissions'           = '  5. Reparer les permissions .ssh'
    '  6. Back'                              = '  6. Retour'
    # Keys menu
    'My SSH keys (to connect ELSEWHERE)'     = 'Mes cles SSH (pour se connecter AILLEURS)'
    '  1. List key pairs'                    = '  1. Lister les paires de cles'
    '  2. Generate a new key (ED25519 by default)' = '  2. Generer une nouvelle cle (ED25519 par defaut)'
    '  3. Inspect a key'                     = '  3. Inspecter une cle'
    '  4. Show / export a public key'        = '  4. Afficher / exporter une cle publique'
    '  5. Delete a key pair'                 = '  5. Supprimer une paire de cles'
    '  6. ssh-agent: list'                   = '  6. ssh-agent : lister'
    '  7. ssh-agent: add a key'              = '  7. ssh-agent : ajouter une cle'
    '  8. ssh-agent: remove a key'           = '  8. ssh-agent : retirer une cle'
    '  9. Back'                              = '  9. Retour'
    # Hosts menu
    'Remote hosts (~/.ssh/config) - optional' = 'Machines distantes (~/.ssh/config) - facultatif'
    '  1. List hosts'                        = '  1. Lister les machines'
    '  2. Add a host'                        = '  2. Ajouter une machine'
    '  3. Delete a host'                     = '  3. Supprimer une machine'
    '  4. Test a host'                       = '  4. Tester une machine'
    '  5. Connect'                           = '  5. Se connecter'
    '  6. known_hosts: list'                 = '  6. known_hosts : lister'
    '  7. known_hosts: remove a fingerprint' = '  7. known_hosts : supprimer une empreinte'
    '  8. Update / accept a host key'        = '  8. Mettre a jour / accepter une cle d''hote'
    'Remote host identification has changed (known_hosts conflict).' = 'L''identification de l''hote distant a change (conflit known_hosts).'
    'This can happen after a reinstall, or indicate a MITM risk.' = 'Cela peut arriver apres une reinstallation, ou indiquer un risque MITM.'
    'Remove the old host key for {0} from known_hosts?' = 'Supprimer l''ancienne cle d''hote de {0} dans known_hosts ?'
    'Fetch and accept the new host key now?' = 'Recuperer et accepter la nouvelle cle d''hote maintenant ?'
    'New host key(s) for {0} added to known_hosts.' = 'Nouvelle(s) cle(s) d''hote pour {0} ajoutee(s) a known_hosts.'
    'Unable to fetch host keys from {0}.'    = 'Impossible de recuperer les cles d''hote de {0}.'
    'Re-run the host test after updating known_hosts.' = 'Relancez le test de l''hote apres la mise a jour de known_hosts.'
    'Connecting to {0}...'                   = 'Connexion a {0}...'
    'No known_hosts file.'                   = 'Aucun fichier known_hosts.'
    'Known fingerprints ({0}):'              = 'Empreintes connues ({0}) :'
    'Host to remove from known_hosts'        = 'Hote a supprimer de known_hosts'
    'Fingerprint of {0} removed.'            = 'Empreinte de {0} supprimee.'
    'Removal failed for {0}.'                = 'Echec de la suppression pour {0}.'
    'Host to scan'                           = 'Hote a scanner'
    'ssh-keyscan not found.'                 = 'ssh-keyscan introuvable.'
    'Announced fingerprints:'                = 'Empreintes annoncees :'
    'Automatic authentication failed (missing key or password required).' = 'Authentification non automatique (cle manquante ou mot de passe requis).'
    # Main menu
    '1. Manage the local SSH server'         = '1. Gerer le serveur SSH local'
    '2. Manage access to this machine'       = '2. Gerer les acces a cette machine'
    '3. Manage my SSH keys'                  = '3. Gerer mes cles SSH'
    '4. Manage remote hosts'                 = '4. Gerer les machines distantes'
    '5. View connections and logs'          = '5. Consulter les connexions et journaux'
    '6. Run a security audit'                = '6. Effectuer un audit de securite'
    '7. Back up or restore'                  = '7. Sauvegarder ou restaurer'
    '8. LSSHM settings'                      = '8. Parametres de LSSHM'
    '9. Quit'                                = '9. Quitter'
    # Dispatch errors
    'Unknown server subcommand: {0}'         = 'Sous-commande server inconnue : {0}'
    'Unknown access subcommand: {0}'         = 'Sous-commande access inconnue : {0}'
    'Unknown key subcommand: {0}'            = 'Sous-commande key inconnue : {0}'
    'Unknown host subcommand: {0}'           = 'Sous-commande host inconnue : {0}'
    'Unknown command: {0}'                   = 'Commande inconnue : {0}'
    # Usage / help
    'Usage:'                                 = 'Utilisation :'
    'CLI menu'                               = 'Menu CLI'
    'Local SSH status'                       = 'Etat SSH local'
    'Diagnostics'                            = 'Diagnostic'
    'Security audit'                         = 'Audit de securite'
    'Install into the user profile'          = 'Installer dans le profil utilisateur'
    'sshd service status'                    = 'Etat du service sshd'
    'List local keys'                        = 'Lister les cles locales'
    'List hosts in ~/.ssh/config'            = 'Lister les hotes de ~/.ssh/config'
    'This help'                              = 'Cette aide'
    'Options:'                               = 'Options :'
    'Assume yes (non-interactive)'           = 'Repondre oui automatiquement (non interactif)'
    'Target user (display)'                  = 'Utilisateur cible (affichage)'
    'Interface language (en, fr, es)'        = 'Langue de l''interface (en, fr, es)'
}

$script:LSSHM_MSG_es = @{
    'Press Enter to continue'                = 'Pulse Intro para continuar'
    'Choice'                                 = 'Eleccion'
    'Invalid choice.'                        = 'Eleccion no valida.'
    'Cancelled.'                             = 'Cancelado.'
    'No change.'                             = 'Sin cambios.'
    'yes'                                    = 'si'
    'no'                                     = 'no'
    'not set'                                = 'sin definir'
    'present'                                = 'presente'
    'absent'                                 = 'ausente'
    'unknown'                                = 'desconocida'
    'forbidden'                              = 'prohibido'
    'key only'                               = 'solo clave'
    'key or password'                        = 'clave o contrasena'
    'forced commands only'                   = 'solo comandos forzados'
    'active'                                 = 'activo'
    'inactive'                               = 'inactivo'
    'Language set to: {0}'                   = 'Idioma establecido en: {0}'
    'Change the language'                    = 'Cambiar el idioma'
    'This operation requires PowerShell as administrator.' = 'Esta operacion requiere PowerShell como administrador.'
    'Relaunch: Start-Process powershell -Verb RunAs'       = 'Reinicie: Start-Process powershell -Verb RunAs'
    'Elevation required'                     = 'Se requiere elevacion'
    'SSH server status: {0}'                 = 'Estado del servidor SSH: {0}'
    'Port: {0}'                              = 'Puerto: {0}'
    'Root / admin access: {0}'               = 'Acceso root / admin: {0}'
    'Password authentication: {0}'           = 'Autenticacion por contrasena: {0}'
    'Administrator keys (administrators_authorized_keys): {0}' = 'Claves de administrador (administrators_authorized_keys): {0}'
    'Private keys of user {0}: {1}'          = 'Claves privadas del usuario {0}: {1}'
    'Registered remote hosts: {0}'           = 'Maquinas remotas registradas: {0}'
    'OpenSSH Server is not installed (sshd.exe not found).' = 'OpenSSH Server no esta instalado (sshd.exe no encontrado).'
    'Auto-start          : {0}'              = 'Inicio automatico   : {0}'
    'Port                : {0}'              = 'Puerto              : {0}'
    'Admin access        : {0}'              = 'Acceso admin        : {0}'
    'Password auth       : {0}'              = 'Auth. contrasena    : {0}'
    'Key auth            : {0}'              = 'Auth. por clave     : {0}'
    'Config              : {0}'              = 'Config              : {0}'
    'OpenSSH Server already present: {0}'    = 'OpenSSH Server ya presente: {0}'
    'Installing OpenSSH.Server (optional Windows feature)...' = 'Instalando OpenSSH.Server (caracteristica opcional de Windows)...'
    'OpenSSH Server installed.'              = 'OpenSSH Server instalado.'
    'Installation failed. Try: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0' = 'Instalacion fallida. Pruebe: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0'
    'SSH service started.'                   = 'Servicio SSH iniciado.'
    'SSH service stopped.'                   = 'Servicio SSH detenido.'
    'SSH service restarted.'                 = 'Servicio SSH reiniciado.'
    'Automatic startup: {0}'                 = 'Inicio automatico: {0}'
    'sshd not found.'                        = 'sshd no encontrado.'
    'Configuration valid (sshd -t).'         = 'Configuracion valida (sshd -t).'
    'Invalid configuration.'                 = 'Configuracion no valida.'
    'No server configuration to back up.'    = 'No hay configuracion de servidor para respaldar.'
    'Backup created: {0}'                    = 'Respaldo creado: {0}'
    'File not found: {0}'                    = 'Archivo no encontrado: {0}'
    'Invalid configuration: restore a backup if needed.' = 'Configuracion no valida: restaure un respaldo si es necesario.'
    'Directive applied: {0} {1}'             = 'Directiva aplicada: {0} {1}'
    'Administrator / root SSH login'         = 'Inicio de sesion SSH de administrador / root'
    '  1. Forbid entirely'                   = '  1. Prohibir por completo'
    '  2. Allow with a key only'             = '  2. Permitir solo con una clave'
    '  3. Allow with a key or a password'    = '  3. Permitir con clave o contrasena'
    '  4. Allow only for forced commands'    = '  4. Permitir solo para comandos forzados'
    'Apply this sensitive change?'           = 'Aplicar este cambio sensible?'
    'File: {0}'                              = 'Archivo: {0}'
    'No authorized key.'                     = 'Ninguna clave autorizada.'
    'Paste the public key (one line) or a .pub path' = 'Pegue la clave publica (una linea) o una ruta .pub'
    'Key added to {0}'                       = 'Clave anadida a {0}'
    '.ssh not found.'                        = '.ssh no encontrado.'
    '.ssh permissions repaired (Windows ACL).' = 'Permisos de .ssh reparados (ACL de Windows).'
    'Directory: {0}'                         = 'Directorio: {0}'
    'No key pair detected.'                  = 'No se detecto ningun par de claves.'
    '   Public   : {0}'                      = '   Publica  : {0}'
    '   Private  : {0}'                      = '   Privada  : {0}'
    '   Fingerprint: {0}'                    = '   Huella   : {0}'
    'Choose a key'                           = 'Elegir una clave'
    'Private key not found: {0}'             = 'Clave privada no encontrada: {0}'
    'Key not found: {0}'                     = 'Clave no encontrada: {0}'
    '{0} (number)'                           = '{0} (numero)'
    'Invalid choice: {0}'                    = 'Eleccion no valida: {0}'
    'Number out of range (1-{0}).'           = 'Numero fuera de rango (1-{0}).'
    'Private key missing for {0}.'           = 'Falta la clave privada para {0}.'
    'Key type (ed25519/rsa)'                 = 'Tipo de clave (ed25519/rsa)'
    'File name'                              = 'Nombre de archivo'
    'Comment'                                = 'Comentario'
    'Key generated: {0}'                     = 'Clave generada: {0}'
    'Generation failed.'                     = 'Fallo la generacion.'
    'Key to inspect'                         = 'Clave a inspeccionar'
    'Key to export'                          = 'Clave a exportar'
    'Public key not found: {0}'              = 'Clave publica no encontrada: {0}'
    'Public key ({0}):'                      = 'Clave publica ({0}):'
    'Key to delete'                          = 'Clave a eliminar'
    'Deleting the key pair:'                 = 'Eliminando el par de claves:'
    'A backup will be created. Confirm deletion?' = 'Se creara un respaldo. Confirmar la eliminacion?'
    'Key pair deleted (backup kept).'        = 'Par de claves eliminado (respaldo conservado).'
    'No ssh-agent detected. On Windows: Get-Service ssh-agent ; Start-Service ssh-agent' = 'No se detecto ssh-agent. En Windows: Get-Service ssh-agent ; Start-Service ssh-agent'
    'Key to add to ssh-agent'                = 'Clave a anadir a ssh-agent'
    'Key added to ssh-agent.'                = 'Clave anadida a ssh-agent.'
    'Failed.'                                = 'Fallo.'
    'Remove all keys from the agent?'        = 'Quitar todas las claves del agente?'
    'All keys removed.'                      = 'Todas las claves eliminadas.'
    'Key to remove from ssh-agent'           = 'Clave a quitar de ssh-agent'
    'Key removed from ssh-agent.'            = 'Clave quitada de ssh-agent.'
    'No remote host in ~/.ssh/config.'       = 'Ninguna maquina remota en ~/.ssh/config.'
    'Remote hosts ({0}):'                    = 'Maquinas remotas ({0}):'
    'Host alias'                             = 'Nombre (alias)'
    'Name required.'                         = 'Nombre requerido.'
    'A host ''{0}'' already exists.'         = 'Ya existe un host ''{0}''.'
    'Address (HostName)'                     = 'Direccion (HostName)'
    'User'                                   = 'Usuario'
    'Port'                                   = 'Puerto'
    'Key file'                               = 'Archivo de clave'
    'Host ''{0}'' added.'                    = 'Host ''{0}'' anadido.'
    'Host name to delete'                    = 'Nombre del host a eliminar'
    'Host not found: {0}'                    = 'Host no encontrado: {0}'
    'Delete host ''{0}''?'                   = 'Eliminar el host ''{0}''?'
    'Host ''{0}'' deleted.'                  = 'Host ''{0}'' eliminado.'
    'Host name to test'                      = 'Nombre del host a probar'
    'Resolving {0}...'                       = 'Resolviendo {0}...'
    'DNS resolution succeeded.'              = 'Resolucion DNS correcta.'
    'DNS resolution uncertain.'              = 'Resolucion DNS incierta.'
    'Testing port {0}...'                    = 'Probando el puerto {0}...'
    'Port {0} open.'                         = 'Puerto {0} abierto.'
    'Port {0} unreachable.'                  = 'Puerto {0} inaccesible.'
    'SSH authentication test (BatchMode)...' = 'Prueba de autenticacion SSH (BatchMode)...'
    'Authentication succeeded.'              = 'Autenticacion correcta.'
    'Automatic authentication failed.'       = 'Autenticacion automatica fallida.'
    'Host name'                              = 'Nombre del host'
    'LSSHM diagnostics (doctor)'             = 'Diagnostico de LSSHM (doctor)'
    'OS           : {0}'                     = 'SO           : {0}'
    'User         : {0}'                     = 'Usuario      : {0}'
    'Administrator: {0}'                     = 'Administrador: {0}'
    'sshd         : {0}'                     = 'sshd         : {0}'
    'Service      : {0}'                     = 'Servicio     : {0}'
    'not detected'                           = 'no detectado'
    'SSH tools:'                             = 'Herramientas SSH:'
    'LSSHM paths:'                           = 'Rutas de LSSHM:'
    'Local SSH security audit (Windows)'     = 'Auditoria de seguridad SSH local (Windows)'
    'OpenSSH Server not installed.'          = 'OpenSSH Server no instalado.'
    'PermitRootLogin = no.'                  = 'PermitRootLogin = no.'
    'PermitRootLogin = key only.'            = 'PermitRootLogin = solo clave.'
    'PermitRootLogin = yes (admin password possible).' = 'PermitRootLogin = yes (contrasena de admin posible).'
    'PermitRootLogin = {0}'                  = 'PermitRootLogin = {0}'
    'Password authentication disabled.'      = 'Autenticacion por contrasena desactivada.'
    'Password authentication enabled.'       = 'Autenticacion por contrasena activada.'
    'PasswordAuthentication = {0}'           = 'PasswordAuthentication = {0}'
    '.ssh present for the current user.'     = '.ssh presente para el usuario actual.'
    'No .ssh directory.'                     = 'Ningun directorio .ssh.'
    'sshd service active.'                   = 'Servicio sshd activo.'
    'sshd service inactive or absent.'       = 'Servicio sshd inactivo o ausente.'
    'Summary: {0} OK, {1} warnings, {2} failures' = 'Resumen: {0} OK, {1} advertencias, {2} fallos'
    'Connections and logs'                   = 'Conexiones y registros'
    '  1. Sessions / sshd processes'         = '  1. Sesiones / procesos sshd'
    '  2. OpenSSH events (Event Log)'        = '  2. Eventos OpenSSH (Visor de eventos)'
    '  3. Back'                              = '  3. Volver'
    'OpenSSH/Operational log unavailable: {0}' = 'Registro OpenSSH/Operational no disponible: {0}'
    'Backup and restore'                     = 'Respaldo y restauracion'
    '  1. Back up sshd_config'               = '  1. Respaldar sshd_config'
    '  2. Back up user authorized_keys'      = '  2. Respaldar authorized_keys de usuario'
    '  3. List backups'                      = '  3. Listar respaldos'
    '  4. Back'                              = '  4. Volver'
    'Backup: {0}'                            = 'Respaldo: {0}'
    'authorized_keys not found.'             = 'authorized_keys no encontrado.'
    'LSSHM settings (Windows)'               = 'Configuracion de LSSHM (Windows)'
    'Config : {0}'                           = 'Config : {0}'
    'Data   : {0}'                           = 'Data   : {0}'
    'Language : {0}'                         = 'Idioma : {0}'
    '  1. Show diagnostics (doctor)'         = '  1. Mostrar el diagnostico (doctor)'
    '  2. Install LSSHM into the user profile' = '  2. Instalar LSSHM en el perfil de usuario'
    '  3. Change the language'               = '  3. Cambiar el idioma'
    'Downloading lsshm.ps1...'               = 'Descargando lsshm.ps1...'
    'Added to the user PATH: {0}'            = 'Anadido al PATH de usuario: {0}'
    'Installed:'                             = 'Instalado:'
    'Installation complete.'                 = 'Instalacion completada.'
    'Run: lsshm.ps1'                         = 'Ejecute: lsshm.ps1'
    'Local SSH server (Windows OpenSSH)'     = 'Servidor SSH local (Windows OpenSSH)'
    '  1. Install OpenSSH Server'            = '  1. Instalar OpenSSH Server'
    '  2. Start the service'                 = '  2. Iniciar el servicio'
    '  3. Stop the service'                  = '  3. Detener el servicio'
    '  4. Restart the service'              = '  4. Reiniciar el servicio'
    '  5. Enable at boot'                    = '  5. Activar al inicio'
    '  6. Disable at boot'                   = '  6. Desactivar al inicio'
    '  7. Change the port'                   = '  7. Cambiar el puerto'
    '  8. Address family (AddressFamily)'    = '  8. Familia de direcciones (AddressFamily)'
    '  9. Listen addresses (ListenAddress)'  = '  9. Direcciones de escucha (ListenAddress)'
    ' 10. Windows Firewall (allow OpenSSH)'  = ' 10. Firewall de Windows (permitir OpenSSH)'
    ' 11. Manage PermitRootLogin / admin access' = ' 11. Gestionar PermitRootLogin / acceso admin'
    ' 12. Password authentication'           = ' 12. Autenticacion por contrasena'
    ' 13. Key authentication'                = ' 13. Autenticacion por clave'
    ' 14. Test the configuration (sshd -t)'  = ' 14. Probar la configuracion (sshd -t)'
    ' 15. Show the effective configuration (sshd -T)' = ' 15. Mostrar la configuracion efectiva (sshd -T)'
    ' 16. Back'                              = ' 16. Volver'
    'Change the port'                        = 'Cambiar el puerto'
    'Address family (AddressFamily)'         = 'Familia de direcciones (AddressFamily)'
    'Listen addresses (ListenAddress)'       = 'Direcciones de escucha (ListenAddress)'
    'New SSH port'                           = 'Nuevo puerto SSH'
    'Invalid port.'                          = 'Puerto no valido.'
    'Check your firewall before changing the port.' = 'Verifique su firewall antes de cambiar el puerto.'
    'SSH address family (AddressFamily)'     = 'Familia de direcciones SSH (AddressFamily)'
    'Current: {0}'                           = 'Actual: {0}'
    '  1. any   (IPv4 + IPv6, OpenSSH default)' = '  1. any   (IPv4 + IPv6, predeterminado OpenSSH)'
    '  2. inet  (IPv4 only)'                  = '  2. inet  (solo IPv4)'
    '  3. inet6 (IPv6 only)'                 = '  3. inet6 (solo IPv6)'
    'SSH listen addresses (ListenAddress)'   = 'Direcciones de escucha SSH (ListenAddress)'
    'Examples: 0.0.0.0   ::   192.168.1.10   0.0.0.0 ::' = 'Ejemplos: 0.0.0.0   ::   192.168.1.10   0.0.0.0 ::'
    'Empty input restores OpenSSH defaults (all interfaces).' = 'Una entrada vacia restaura los valores predeterminados de OpenSSH (todas las interfaces).'
    'Listen addresses (space-separated)'     = 'Direcciones de escucha (separadas por espacios)'
    'Directive removed: {0}'                 = 'Directiva eliminada: {0}'
    'Directive applied: {0} ({1})'           = 'Directiva aplicada: {0} ({1})'
    'Address family      : {0}'              = 'Familia de direcciones: {0}'
    'Listen addresses    : {0}'              = 'Direcciones de escucha: {0}'
    'Firewall            : {0}'              = 'Firewall             : {0}'
    'allowed (port {0})'                     = 'permitido (puerto {0})'
    'not allowed / no matching rule'         = 'no permitido / ninguna regla coincidente'
    'Windows Firewall — OpenSSH'             = 'Firewall de Windows — OpenSSH'
    'Status: {0}'                            = 'Estado: {0}'
    '  1. Allow OpenSSH through the firewall' = '  1. Permitir OpenSSH en el firewall'
    '  2. Disable OpenSSH firewall rules'    = '  2. Desactivar las reglas de firewall OpenSSH'
    'Allow OpenSSH through Windows Firewall?' = 'Permitir OpenSSH en el firewall de Windows?'
    'OpenSSH is allowed through Windows Firewall.' = 'OpenSSH esta permitido en el firewall de Windows.'
    'Created firewall rule for OpenSSH on port {0}.' = 'Regla de firewall creada para OpenSSH en el puerto {0}.'
    'Firewall rule updated for port {0}.'    = 'Regla de firewall actualizada para el puerto {0}.'
    'Enabled firewall rule: {0}'             = 'Regla de firewall activada: {0}'
    'Disabled firewall rule: {0}'            = 'Regla de firewall desactivada: {0}'
    'LSSHM firewall rule disabled.'          = 'Regla de firewall LSSHM desactivada.'
    'No OpenSSH firewall rule found to disable.' = 'No hay regla de firewall OpenSSH para desactivar.'
    'Unable to create firewall rule: {0}'    = 'No se pudo crear la regla de firewall: {0}'
    'Unable to update firewall rule: {0}'    = 'No se pudo actualizar la regla de firewall: {0}'
    'Unable to disable LSSHM firewall rule: {0}' = 'No se pudo desactivar la regla de firewall LSSHM: {0}'
    'Allow PasswordAuthentication?'          = 'Permitir PasswordAuthentication?'
    'Allow PubkeyAuthentication?'            = 'Permitir PubkeyAuthentication?'
    'Disabling keys may lock you out. Continue?' = 'Desactivar las claves puede bloquearle. Continuar?'
    'Access to this machine (keys allowed HERE)' = 'Acceso a esta maquina (claves permitidas AQUI)'
    '  1. List user keys (~/.ssh/authorized_keys)' = '  1. Listar claves de usuario (~/.ssh/authorized_keys)'
    '  2. List administrator keys (administrators_authorized_keys)' = '  2. Listar claves de administrador (administrators_authorized_keys)'
    '  3. Add a user key'                    = '  3. Anadir una clave de usuario'
    '  4. Add an administrator key'          = '  4. Anadir una clave de administrador'
    '  5. Repair .ssh permissions'           = '  5. Reparar los permisos de .ssh'
    '  6. Back'                              = '  6. Volver'
    'My SSH keys (to connect ELSEWHERE)'     = 'Mis claves SSH (para conectarse EN OTRO LUGAR)'
    '  1. List key pairs'                    = '  1. Listar los pares de claves'
    '  2. Generate a new key (ED25519 by default)' = '  2. Generar una nueva clave (ED25519 por defecto)'
    '  3. Inspect a key'                     = '  3. Inspeccionar una clave'
    '  4. Show / export a public key'        = '  4. Mostrar / exportar una clave publica'
    '  5. Delete a key pair'                 = '  5. Eliminar un par de claves'
    '  6. ssh-agent: list'                   = '  6. ssh-agent: listar'
    '  7. ssh-agent: add a key'              = '  7. ssh-agent: anadir una clave'
    '  8. ssh-agent: remove a key'           = '  8. ssh-agent: quitar una clave'
    '  9. Back'                              = '  9. Volver'
    'Remote hosts (~/.ssh/config) - optional' = 'Maquinas remotas (~/.ssh/config) - opcional'
    '  1. List hosts'                        = '  1. Listar las maquinas'
    '  2. Add a host'                        = '  2. Anadir una maquina'
    '  3. Delete a host'                     = '  3. Eliminar una maquina'
    '  4. Test a host'                       = '  4. Probar una maquina'
    '  5. Connect'                           = '  5. Conectarse'
    '  6. known_hosts: list'                 = '  6. known_hosts: listar'
    '  7. known_hosts: remove a fingerprint' = '  7. known_hosts: eliminar una huella'
    '  8. Update / accept a host key'        = '  8. Actualizar / aceptar una clave de host'
    'Remote host identification has changed (known_hosts conflict).' = 'La identificacion del host remoto ha cambiado (conflicto known_hosts).'
    'This can happen after a reinstall, or indicate a MITM risk.' = 'Puede ocurrir tras una reinstalacion, o indicar un riesgo MITM.'
    'Remove the old host key for {0} from known_hosts?' = 'Eliminar la clave de host antigua de {0} en known_hosts?'
    'Fetch and accept the new host key now?' = 'Obtener y aceptar ahora la nueva clave de host?'
    'New host key(s) for {0} added to known_hosts.' = 'Nueva(s) clave(s) de host para {0} anadida(s) a known_hosts.'
    'Unable to fetch host keys from {0}.'    = 'No se pudieron obtener las claves de host de {0}.'
    'Re-run the host test after updating known_hosts.' = 'Vuelva a probar el host tras actualizar known_hosts.'
    'Connecting to {0}...'                   = 'Conectando a {0}...'
    'No known_hosts file.'                   = 'No hay archivo known_hosts.'
    'Known fingerprints ({0}):'              = 'Huellas conocidas ({0}):'
    'Host to remove from known_hosts'        = 'Host a eliminar de known_hosts'
    'Fingerprint of {0} removed.'            = 'Huella de {0} eliminada.'
    'Removal failed for {0}.'                = 'Fallo la eliminacion para {0}.'
    'Host to scan'                           = 'Host a escanear'
    'ssh-keyscan not found.'                 = 'ssh-keyscan no encontrado.'
    'Announced fingerprints:'                = 'Huellas anunciadas:'
    'Automatic authentication failed (missing key or password required).' = 'Autenticacion no automatica (falta clave o se requiere contrasena).'
    '1. Manage the local SSH server'         = '1. Gestionar el servidor SSH local'
    '2. Manage access to this machine'       = '2. Gestionar el acceso a esta maquina'
    '3. Manage my SSH keys'                  = '3. Gestionar mis claves SSH'
    '4. Manage remote hosts'                 = '4. Gestionar las maquinas remotas'
    '5. View connections and logs'          = '5. Consultar las conexiones y registros'
    '6. Run a security audit'                = '6. Ejecutar una auditoria de seguridad'
    '7. Back up or restore'                  = '7. Respaldar o restaurar'
    '8. LSSHM settings'                      = '8. Configuracion de LSSHM'
    '9. Quit'                                = '9. Salir'
    'Unknown server subcommand: {0}'         = 'Subcomando server desconocido: {0}'
    'Unknown access subcommand: {0}'         = 'Subcomando access desconocido: {0}'
    'Unknown key subcommand: {0}'            = 'Subcomando key desconocido: {0}'
    'Unknown host subcommand: {0}'           = 'Subcomando host desconocido: {0}'
    'Unknown command: {0}'                   = 'Comando desconocido: {0}'
    # Usage / help
    'Usage:'                                 = 'Uso:'
    'CLI menu'                               = 'Menu CLI'
    'Local SSH status'                       = 'Estado SSH local'
    'Diagnostics'                            = 'Diagnostico'
    'Security audit'                         = 'Auditoria de seguridad'
    'Install into the user profile'          = 'Instalar en el perfil de usuario'
    'sshd service status'                    = 'Estado del servicio sshd'
    'List local keys'                        = 'Listar las claves locales'
    'List hosts in ~/.ssh/config'            = 'Listar los hosts de ~/.ssh/config'
    'This help'                              = 'Esta ayuda'
    'Options:'                               = 'Opciones:'
    'Assume yes (non-interactive)'           = 'Responder si automaticamente (no interactivo)'
    'Target user (display)'                  = 'Usuario objetivo (visualizacion)'
    'Interface language (en, fr, es)'        = 'Idioma de la interfaz (en, fr, es)'
}

function Get-LsshmText {
    param([Parameter(Mandatory)][string]$Id)
    $table = switch ($script:LSSHM_LANG) {
        'fr' { $script:LSSHM_MSG_fr }
        'es' { $script:LSSHM_MSG_es }
        default { $null }
    }
    if ($table -and $table.ContainsKey($Id) -and $table[$Id]) { return [string]$table[$Id] }
    return $Id
}

# T: translate a msgid. TF: translate then -f format with the given arguments.
function T { param([Parameter(Mandatory)][string]$Id) return (Get-LsshmText $Id) }
function TF {
    param([Parameter(Mandatory)][string]$Id, [Parameter(ValueFromRemainingArguments = $true)][object[]]$FormatArgs)
    $s = Get-LsshmText $Id
    if ($FormatArgs -and $FormatArgs.Count -gt 0) { return ($s -f $FormatArgs) }
    return $s
}

function Get-LsshmLangNativeName {
    param([string]$Code)
    switch ($Code) {
        'en' { 'English' }
        'fr' { 'Francais' }
        'es' { 'Espanol' }
        default { $Code }
    }
}

function Get-LsshmDetectLang {
    try {
        $c = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName.ToLowerInvariant()
    } catch {
        $c = 'en'
    }
    switch ($c) {
        'fr' { 'fr' }
        'es' { 'es' }
        default { 'en' }
    }
}

function Get-LsshmConfiguredLang {
    if ($script:LSSHM_CONFIG_FILE -and (Test-Path -LiteralPath $script:LSSHM_CONFIG_FILE)) {
        try {
            $j = Get-Content -LiteralPath $script:LSSHM_CONFIG_FILE -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($j.PSObject.Properties.Name -contains 'language' -and $j.language) {
                return [string]$j.language
            }
        } catch { }
    }
    return ''
}

function Set-LsshmConfiguredLang {
    param([Parameter(Mandatory)][string]$Lang)
    Ensure-LsshmDirs
    $obj = [ordered]@{}
    if (Test-Path -LiteralPath $script:LSSHM_CONFIG_FILE) {
        try {
            $existing = Get-Content -LiteralPath $script:LSSHM_CONFIG_FILE -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($p in $existing.PSObject.Properties) { $obj[$p.Name] = $p.Value }
        } catch { }
    }
    $obj['language'] = $Lang
    ($obj | ConvertTo-Json) | Set-Content -LiteralPath $script:LSSHM_CONFIG_FILE -Encoding UTF8
}

function Initialize-LsshmLang {
    $want = ''
    if ($script:LSSHM_LANG_OVERRIDE) {
        $want = $script:LSSHM_LANG_OVERRIDE
    } else {
        $cfg = Get-LsshmConfiguredLang
        if ($cfg) { $want = $cfg } else { $want = Get-LsshmDetectLang }
    }
    if ($script:LSSHM_LANGS -contains $want) { $script:LSSHM_LANG = $want } else { $script:LSSHM_LANG = 'en' }
}

function Test-LsshmLangConfigured {
    return [bool](Get-LsshmConfiguredLang)
}

function Select-LsshmLanguage {
    Write-Host ''
    Write-Host 'Language / Langue / Idioma:'
    $i = 0
    foreach ($code in $script:LSSHM_LANGS) {
        $i++
        Write-Host ("  {0}. {1}" -f $i, (Get-LsshmLangNativeName $code))
    }
    $detected = Get-LsshmDetectLang
    $def = '1'
    for ($j = 0; $j -lt $script:LSSHM_LANGS.Count; $j++) {
        if ($script:LSSHM_LANGS[$j] -eq $detected) { $def = [string]($j + 1) }
    }
    $choice = Read-LsshmPrompt 'Choice / Choix / Eleccion' $def
    $picked = $detected
    $n = 0
    if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $script:LSSHM_LANGS.Count) {
        $picked = $script:LSSHM_LANGS[$n - 1]
    } elseif ($script:LSSHM_LANGS -contains $choice) {
        $picked = $choice
    }
    $script:LSSHM_LANG = $picked
    Set-LsshmConfiguredLang $picked
    Write-LsshmOk (TF 'Language set to: {0}' (Get-LsshmLangNativeName $picked))
}

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
# Display / prompts
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

    # Prefer console attachment checks. [Environment]::UserInteractive is often
    # false under OpenSSH Server (remote PowerShell) even when a PTY is
    # allocated and Read-Host works — that used to make the menu auto-quit
    # with the default "9" choice.
    try {
        if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
            return $true
        }
        if ([Console]::IsInputRedirected) {
            return $false
        }
    } catch {
        # Console API unavailable — fall through.
    }

    try {
        return [Environment]::UserInteractive
    } catch {
        return $true
    }
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
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Prompt $hint"
    if ([string]::IsNullOrWhiteSpace($answer)) { return [bool]$DefaultYes }
    switch -Regex ($answer.Trim().ToLowerInvariant()) {
        '^(y|yes|o|oui|s|si)$' { return $true }
        default { return $false }
    }
}

function Pause-Lsshm {
    if (-not (Test-LsshmInteractive)) { return }
    Read-Host (T 'Press Enter to continue') | Out-Null
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
        Write-LsshmError (T 'This operation requires PowerShell as administrator.')
        Write-LsshmInfo (T 'Relaunch: Start-Process powershell -Verb RunAs')
        throw (T 'Elevation required')
    }
}

# =============================================================================
# Platform / OpenSSH detection
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
        '^no$' { return (T 'forbidden') }
        '^(prohibit-password|without-password)$' { return (T 'key only') }
        '^yes$' { return (T 'key or password') }
        '^forced-commands-only$' { return (T 'forced commands only') }
        default { if ($Value) { return $Value } else { return (T 'not set') } }
    }
}

function Get-LsshmYesNoLabel {
    param([string]$Value)
    switch -Regex ($Value) {
        '^(yes|true|on|1)$' { return (T 'yes') }
        '^(no|false|off|0)$' { return (T 'no') }
        default { if ($Value) { return $Value } else { return (T 'not set') } }
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
    $active = if ((Test-LsshmServerInstalled) -and (Test-LsshmServerActive)) { T 'active' } else { T 'inactive' }
    $port = Get-LsshmConfigValue 'port'
    if (-not $port) { $port = '22' }
    $root = Get-LsshmRootLoginLabel (Get-LsshmConfigValue 'permitrootlogin')
    $pass = Get-LsshmYesNoLabel (Get-LsshmConfigValue 'passwordauthentication')
    $adminKeys = Get-LsshmKeyCount $script:LSSHM_ADMIN_KEYS
    $userKeys = Get-LsshmPrivateKeyCount
    $hosts = Get-LsshmHostCount
    $user = if ($script:LSSHM_TARGET_USER) { $script:LSSHM_TARGET_USER } else { $env:USERNAME }

    Write-Host (TF 'SSH server status: {0}' $active)
    Write-Host (TF 'Port: {0}' $port)
    Write-Host (TF 'Root / admin access: {0}' $root)
    Write-Host (TF 'Password authentication: {0}' $pass)
    Write-Host (TF 'Administrator keys (administrators_authorized_keys): {0}' $adminKeys)
    Write-Host (TF 'Private keys of user {0}: {1}' $user $userKeys)
    Write-Host (TF 'Registered remote hosts: {0}' $hosts)
}

# =============================================================================
# SSH server
# =============================================================================

function Show-LsshmServerStatus {
    if (-not (Test-LsshmServerInstalled)) {
        Write-LsshmWarn (T 'OpenSSH Server is not installed (sshd.exe not found).')
        return
    }
    $svc = Get-LsshmService
    $active = if (Test-LsshmServerActive) { T 'active' } else { T 'inactive' }
    $enabled = if ($svc -and $svc.StartType -eq 'Automatic') { T 'yes' } else { T 'no' }
    $port = Get-LsshmConfigValue 'port'
    if (-not $port) { $port = '22' }
    $family = Get-LsshmConfigValue 'addressfamily'
    if (-not $family) { $family = 'any' }
    $listenVals = @(Get-LsshmConfigValues 'listenaddress')
    $listen = if ($listenVals.Count -gt 0) { $listenVals -join ' ' } else { '0.0.0.0 ::' }
    Write-Host (TF 'SSH server status: {0}' $active)
    Write-Host (TF 'Auto-start          : {0}' $enabled)
    Write-Host (TF 'Port                : {0}' $port)
    Write-Host (TF 'Address family      : {0}' $family)
    Write-Host (TF 'Listen addresses    : {0}' $listen)
    Write-Host (TF 'Firewall            : {0}' (Get-LsshmFirewallStatusText))
    Write-Host (TF 'Admin access        : {0}' (Get-LsshmRootLoginLabel (Get-LsshmConfigValue 'permitrootlogin')))
    Write-Host (TF 'Password auth       : {0}' (Get-LsshmYesNoLabel (Get-LsshmConfigValue 'passwordauthentication')))
    Write-Host (TF 'Key auth            : {0}' (Get-LsshmYesNoLabel (Get-LsshmConfigValue 'pubkeyauthentication')))
    Write-Host (TF 'Config              : {0}' $script:LSSHM_SSHD_CONFIG)
}

function Install-LsshmOpenSshServer {
    Assert-LsshmAdmin
    if (Test-LsshmServerInstalled) {
        Write-LsshmOk (TF 'OpenSSH Server already present: {0}' (Get-LsshmSshdPath))
        return
    }
    Write-LsshmInfo (T 'Installing OpenSSH.Server (optional Windows feature)...')
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
    if (Test-LsshmServerInstalled) {
        Write-LsshmOk (T 'OpenSSH Server installed.')
        if (Confirm-Lsshm (T 'Allow OpenSSH through Windows Firewall?') -DefaultYes) {
            Enable-LsshmFirewallSsh | Out-Null
        }
    } else {
        Write-LsshmError (T 'Installation failed. Try: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0')
    }
}

function Invoke-LsshmServerAction {
    param([ValidateSet('Start', 'Stop', 'Restart')][string]$Action)
    Assert-LsshmAdmin
    switch ($Action) {
        'Start' { Start-Service $script:LSSHM_SSH_SERVICE; Write-LsshmOk (T 'SSH service started.') }
        'Stop' { Stop-Service $script:LSSHM_SSH_SERVICE -Force; Write-LsshmOk (T 'SSH service stopped.') }
        'Restart' { Restart-Service $script:LSSHM_SSH_SERVICE -Force; Write-LsshmOk (T 'SSH service restarted.') }
    }
}

function Set-LsshmServerStartup {
    param([ValidateSet('Automatic', 'Manual', 'Disabled')][string]$Type)
    Assert-LsshmAdmin
    Set-Service -Name $script:LSSHM_SSH_SERVICE -StartupType $Type
    Write-LsshmOk (TF 'Automatic startup: {0}' $Type)
}

function Test-LsshmServerConfig {
    $sshd = Get-LsshmSshdPath
    if (-not $sshd) {
        Write-LsshmWarn (T 'sshd not found.')
        return $false
    }
    & $sshd -t 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -eq 0) {
        Write-LsshmOk (T 'Configuration valid (sshd -t).')
        return $true
    }
    Write-LsshmError (T 'Invalid configuration.')
    return $false
}

function Show-LsshmServerConfigDump {
    $sshd = Get-LsshmSshdPath
    if (-not $sshd) {
        Write-LsshmWarn (T 'sshd not found.')
        return
    }
    & $sshd -T 2>$null | Sort-Object
}

function Backup-LsshmServerConfig {
    Ensure-LsshmDirs
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSHD_CONFIG)) {
        Write-LsshmWarn (T 'No server configuration to back up.')
        return $null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $script:LSSHM_BACKUP_DIR "$stamp-sshd_config"
    Copy-Item -LiteralPath $script:LSSHM_SSHD_CONFIG -Destination $dest -Force
    Write-LsshmOk (TF 'Backup created: {0}' $dest)
    return $dest
}

function Set-LsshmSshdDirective {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )
    Assert-LsshmAdmin
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSHD_CONFIG)) {
        Write-LsshmError (TF 'File not found: {0}' $script:LSSHM_SSHD_CONFIG)
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
        Write-LsshmError (T 'Invalid configuration: restore a backup if needed.')
        return $false
    }
    Write-LsshmOk (TF 'Directive applied: {0} {1}' $Key $Value)
    return $true
}

function Get-LsshmConfigValues {
    param([Parameter(Mandatory)][string]$Key)
    $keyLower = $Key.ToLowerInvariant()
    $values = [System.Collections.Generic.List[string]]::new()

    $sshd = Get-LsshmSshdPath
    if ($sshd) {
        try {
            $dump = & $sshd -T 2>$null
            if ($LASTEXITCODE -eq 0 -and $dump) {
                foreach ($line in $dump) {
                    if ($line -match '^\s*(\S+)\s+(.+)$' -and $Matches[1].ToLowerInvariant() -eq $keyLower) {
                        [void]$values.Add($Matches[2].Trim())
                    }
                }
            }
        } catch { }
    }

    if ($values.Count -eq 0 -and (Test-Path -LiteralPath $script:LSSHM_SSHD_CONFIG)) {
        foreach ($line in Get-Content -LiteralPath $script:LSSHM_SSHD_CONFIG -ErrorAction SilentlyContinue) {
            $trim = $line.Trim()
            if ($trim -match '^\s*#' -or $trim -eq '') { continue }
            if ($trim -match '^\s*(\S+)\s+(.+)$' -and $Matches[1].ToLowerInvariant() -eq $keyLower) {
                [void]$values.Add($Matches[2].Trim())
            }
        }
    }
    return $values.ToArray()
}

function Set-LsshmSshdMultiDirective {
    param(
        [Parameter(Mandatory)][string]$Key,
        [string[]]$Values = @()
    )
    Assert-LsshmAdmin
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSHD_CONFIG)) {
        Write-LsshmError (TF 'File not found: {0}' $script:LSSHM_SSHD_CONFIG)
        return $false
    }
    Backup-LsshmServerConfig | Out-Null
    $lines = Get-Content -LiteralPath $script:LSSHM_SSHD_CONFIG
    $out = foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s+" -and $line -notmatch '^\s*#') {
            # drop existing active lines for this key
        } else {
            $line
        }
    }
    $out = @($out)
    if ($Values.Count -gt 0) {
        $out += ''
        $out += '# Managed by LSSHM'
        foreach ($v in $Values) {
            if ($v) { $out += "$Key $v" }
        }
    }
    Set-Content -LiteralPath $script:LSSHM_SSHD_CONFIG -Value $out -Encoding UTF8
    if (-not (Test-LsshmServerConfig)) {
        Write-LsshmError (T 'Invalid configuration: restore a backup if needed.')
        return $false
    }
    if ($Values.Count -eq 0) {
        Write-LsshmOk (TF 'Directive removed: {0}' $Key)
    } else {
        Write-LsshmOk (TF 'Directive applied: {0} ({1})' $Key ($Values -join ' '))
    }
    return $true
}

function Set-LsshmPortMenu {
    $cur = Get-LsshmConfigValue 'port'
    if (-not $cur) { $cur = '22' }
    $port = Read-LsshmPrompt (T 'New SSH port') $cur
    if ($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535) {
        Write-LsshmError (T 'Invalid port.')
        return
    }
    Write-LsshmWarn (T 'Check your firewall before changing the port.')
    if (-not (Confirm-Lsshm (T 'Apply this sensitive change?'))) { return }
    if (Set-LsshmSshdDirective -Key 'Port' -Value $port) {
        Restart-Service $script:LSSHM_SSH_SERVICE -Force -ErrorAction SilentlyContinue
        # Keep LSSHM firewall rule in sync when present.
        Sync-LsshmFirewallPort -Port $port
    }
}

function Set-LsshmAddressFamilyMenu {
    $cur = Get-LsshmConfigValue 'addressfamily'
    if (-not $cur) { $cur = 'any' }
    Write-LsshmHeader
    Write-Host (T 'SSH address family (AddressFamily)')
    Write-Host (TF 'Current: {0}' $cur)
    Write-Host ''
    Write-Host (T '  1. any   (IPv4 + IPv6, OpenSSH default)')
    Write-Host (T '  2. inet  (IPv4 only)')
    Write-Host (T '  3. inet6 (IPv6 only)')
    Write-Host ''
    $choice = Read-LsshmPrompt (T 'Choice') '1'
    $value = switch ($choice) {
        '1' { 'any' }
        '2' { 'inet' }
        '3' { 'inet6' }
        default { $null }
    }
    if (-not $value) {
        Write-LsshmInfo (T 'No change.')
        return
    }
    if (-not (Confirm-Lsshm (T 'Apply this sensitive change?'))) { return }
    if (Set-LsshmSshdDirective -Key 'AddressFamily' -Value $value) {
        Restart-Service $script:LSSHM_SSH_SERVICE -Force -ErrorAction SilentlyContinue
    }
}

function Set-LsshmListenAddressMenu {
    $curVals = @(Get-LsshmConfigValues 'listenaddress')
    $cur = if ($curVals.Count -gt 0) { $curVals -join ' ' } else { '0.0.0.0 ::' }
    Write-LsshmHeader
    Write-Host (T 'SSH listen addresses (ListenAddress)')
    Write-Host (TF 'Current: {0}' $cur)
    Write-Host ''
    Write-Host (T 'Examples: 0.0.0.0   ::   192.168.1.10   0.0.0.0 ::')
    Write-Host (T 'Empty input restores OpenSSH defaults (all interfaces).')
    Write-Host ''
    $raw = Read-LsshmPrompt (T 'Listen addresses (space-separated)') $cur
    $addrs = @()
    if ($raw) {
        $addrs = @($raw -split '\s+' | Where-Object { $_ })
    }
    if (-not (Confirm-Lsshm (T 'Apply this sensitive change?'))) { return }
    if (Set-LsshmSshdMultiDirective -Key 'ListenAddress' -Values $addrs) {
        Restart-Service $script:LSSHM_SSH_SERVICE -Force -ErrorAction SilentlyContinue
    }
}

function Get-LsshmSshFirewallRules {
    $rules = @()
    try {
        $rules = @(Get-NetFirewallRule -ErrorAction Stop | Where-Object {
            $_.Enabled -ne $null -and (
                $_.DisplayName -match 'OpenSSH|SSH|LSSHM' -or
                $_.Name -match 'OpenSSH|SSH|LSSHM'
            )
        })
    } catch {
        # Fallback for older systems without Get-NetFirewallRule in PATH context
        $rules = @()
    }
    return $rules
}

function Get-LsshmFirewallStatusText {
    $port = Get-LsshmConfigValue 'port'
    if (-not $port) { $port = '22' }
    $rules = @(Get-LsshmSshFirewallRules | Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' })
    if ($rules.Count -gt 0) {
        return (TF 'allowed (port {0})' $port)
    }
    return (T 'not allowed / no matching rule')
}

function Sync-LsshmFirewallPort {
    param([Parameter(Mandatory)][string]$Port)
    Assert-LsshmAdmin
    $name = 'LSSHM-OpenSSH-Server-In-TCP'
    try {
        $existing = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
        if ($existing) {
            Set-NetFirewallRule -Name $name -LocalPort $Port -Enabled True -ErrorAction Stop
            Write-LsshmOk (TF 'Firewall rule updated for port {0}.' $Port)
            return $true
        }
    } catch { }
    return $false
}

function Enable-LsshmFirewallSsh {
    Assert-LsshmAdmin
    $port = Get-LsshmConfigValue 'port'
    if (-not $port) { $port = '22' }

    # Prefer enabling the built-in OpenSSH rule when present (Server and Client).
    $builtIn = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match 'OpenSSH-Server-In-TCP' -or $_.DisplayName -match 'OpenSSH.*Server'
    })
    $enabledAny = $false
    foreach ($r in $builtIn) {
        try {
            Enable-NetFirewallRule -Name $r.Name -ErrorAction Stop
            $enabledAny = $true
            Write-LsshmOk (TF 'Enabled firewall rule: {0}' $r.DisplayName)
        } catch { }
    }

    $name = 'LSSHM-OpenSSH-Server-In-TCP'
    $existing = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
    if (-not $existing) {
        try {
            New-NetFirewallRule `
                -Name $name `
                -DisplayName 'LSSHM OpenSSH Server (TCP inbound)' `
                -Group 'LSSHM' `
                -Enabled True `
                -Direction Inbound `
                -Protocol TCP `
                -Action Allow `
                -LocalPort $port `
                -Profile Any `
                -ErrorAction Stop | Out-Null
            Write-LsshmOk (TF 'Created firewall rule for OpenSSH on port {0}.' $port)
            $enabledAny = $true
        } catch {
            Write-LsshmError (TF 'Unable to create firewall rule: {0}' $_.Exception.Message)
            return $false
        }
    } else {
        try {
            Set-NetFirewallRule -Name $name -LocalPort $port -Enabled True -Action Allow -ErrorAction Stop
            Write-LsshmOk (TF 'Firewall rule updated for port {0}.' $port)
            $enabledAny = $true
        } catch {
            Write-LsshmError (TF 'Unable to update firewall rule: {0}' $_.Exception.Message)
            return $false
        }
    }

    if ($enabledAny) {
        Write-LsshmOk (T 'OpenSSH is allowed through Windows Firewall.')
        return $true
    }
    return $false
}

function Disable-LsshmFirewallSsh {
    Assert-LsshmAdmin
    $name = 'LSSHM-OpenSSH-Server-In-TCP'
    $disabled = $false
    try {
        $r = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
        if ($r) {
            Disable-NetFirewallRule -Name $name -ErrorAction Stop
            Write-LsshmOk (T 'LSSHM firewall rule disabled.')
            $disabled = $true
        }
    } catch {
        Write-LsshmError (TF 'Unable to disable LSSHM firewall rule: {0}' $_.Exception.Message)
    }

    $builtIn = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match 'OpenSSH-Server-In-TCP' -or $_.DisplayName -match 'OpenSSH.*Server'
    })
    foreach ($r in $builtIn) {
        try {
            Disable-NetFirewallRule -Name $r.Name -ErrorAction Stop
            Write-LsshmOk (TF 'Disabled firewall rule: {0}' $r.DisplayName)
            $disabled = $true
        } catch { }
    }

    if (-not $disabled) {
        Write-LsshmWarn (T 'No OpenSSH firewall rule found to disable.')
    }
}

function Show-LsshmFirewallMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host (T 'Windows Firewall — OpenSSH')
        Write-Host ''
        Write-Host (TF 'Status: {0}' (Get-LsshmFirewallStatusText))
        Write-Host ''
        Write-Host (T '  1. Allow OpenSSH through the firewall')
        Write-Host (T '  2. Disable OpenSSH firewall rules')
        Write-Host (T '  3. Back')
        $c = Read-LsshmPrompt (T 'Choice') '3'
        switch ($c) {
            '1' { Enable-LsshmFirewallSsh; Pause-Lsshm }
            '2' { Disable-LsshmFirewallSsh; Pause-Lsshm }
            '3' { return }
            default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
        }
    }
}

function Set-LsshmRootLoginMenu {
    Write-LsshmHeader
    Write-Host (T 'Administrator / root SSH login')
    Write-Host ''
    Write-Host (T '  1. Forbid entirely')
    Write-Host (T '  2. Allow with a key only')
    Write-Host (T '  3. Allow with a key or a password')
    Write-Host (T '  4. Allow only for forced commands')
    Write-Host ''
    $choice = Read-LsshmPrompt (T 'Choice') '2'
    $value = switch ($choice) {
        '1' { 'no' }
        '2' { 'prohibit-password' }
        '3' { 'yes' }
        '4' { 'forced-commands-only' }
        default { $null }
    }
    if (-not $value) {
        Write-LsshmInfo (T 'No change.')
        return
    }
    if (-not (Confirm-Lsshm (T 'Apply this sensitive change?'))) { return }
    if (Set-LsshmSshdDirective -Key 'PermitRootLogin' -Value $value) {
        Restart-Service $script:LSSHM_SSH_SERVICE -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Incoming access
# =============================================================================

function Show-LsshmAccessList {
    param([ValidateSet('User', 'Administrators')][string]$Scope = 'User')
    $path = if ($Scope -eq 'Administrators') { $script:LSSHM_ADMIN_KEYS } else { $script:LSSHM_AUTHORIZED_KEYS }
    Write-Host (TF 'File: {0}' $path)
    Write-Host ''
    if (-not (Test-Path -LiteralPath $path)) {
        Write-LsshmInfo (T 'No authorized key.')
        return
    }
    $i = 0
    foreach ($line in Get-Content -LiteralPath $path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        $i++
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Set-Content -LiteralPath $tmp -Value $line -Encoding ascii
            $fp = Get-LsshmKeyFingerprint -PubPath $tmp
            Write-Host ("{0}. {1}" -f $i, $fp)
        } finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    if ($i -eq 0) { Write-LsshmInfo (T 'No authorized key.') }
}

function Add-LsshmAccessKey {
    param([ValidateSet('User', 'Administrators')][string]$Scope = 'User')
    $path = if ($Scope -eq 'Administrators') { $script:LSSHM_ADMIN_KEYS } else { $script:LSSHM_AUTHORIZED_KEYS }
    if ($Scope -eq 'Administrators') { Assert-LsshmAdmin }

    $keyline = Read-LsshmPrompt (T 'Paste the public key (one line) or a .pub path')
    if (-not $keyline) { Write-LsshmInfo (T 'Cancelled.'); return }
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
    Write-LsshmOk (TF 'Key added to {0}' $path)
}

function Repair-LsshmAccessPermissions {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) {
        Write-LsshmWarn (T '.ssh not found.')
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
    Write-LsshmOk (T '.ssh permissions repaired (Windows ACL).')
}

# =============================================================================
# Local keys
# =============================================================================

function Get-LsshmPubPath {
    param([Parameter(Mandatory)][string]$PrivatePath)
    return ($PrivatePath + '.pub')
}

function Get-LsshmKeyFingerprint {
    param([Parameter(Mandatory)][string]$PubPath)
    if (-not (Test-Path -LiteralPath $PubPath)) { return (T 'unknown') }
    # Avoid terminating on native stderr when $ErrorActionPreference is Stop.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & ssh-keygen -lf $PubPath 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { return [string]$out }
        return (T 'unknown')
    } catch {
        return (T 'unknown')
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-LsshmKeyPairs {
    $list = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) { return @() }
    Get-ChildItem -LiteralPath $script:LSSHM_SSH_DIR -Filter '*.pub' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object {
            $base = $_.FullName
            if ($base.EndsWith('.pub')) {
                $list.Add($base.Substring(0, $base.Length - 4))
            }
        }
    return @($list.ToArray())
}

function Show-LsshmKeysList {
    Write-Host (TF 'Directory: {0}' $script:LSSHM_SSH_DIR)
    Write-Host ''
    $keys = @(Get-LsshmKeyPairs)
    if ($keys.Count -eq 0) {
        Write-LsshmInfo (T 'No key pair detected.')
        return $false
    }
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $priv = [string]$keys[$i]
        $pub = Get-LsshmPubPath -PrivatePath $priv
        $fp = Get-LsshmKeyFingerprint -PubPath $pub
        Write-Host ("{0}. {1}" -f ($i + 1), (Split-Path $priv -Leaf))
        Write-Host (TF '   Public   : {0}' $pub)
        Write-Host (TF '   Private  : {0}' $(if (Test-Path -LiteralPath $priv) { "$priv ($(T 'present'))" } else { T 'absent' }))
        Write-Host (TF '   Fingerprint: {0}' $fp)
    }
    return $true
}

function Select-LsshmKey {
    param(
        [string]$Prompt = 'Choose a key',
        [switch]$RequirePrivate,
        [string]$GivenPath = ''
    )

    if ($GivenPath) {
        $path = $GivenPath
        if ($path -like '*.pub') { $path = $path.Substring(0, $path.Length - 4) }
        $pub = Get-LsshmPubPath -PrivatePath $path
        if ($RequirePrivate -and -not (Test-Path -LiteralPath $path)) {
            Write-LsshmError (TF 'Private key not found: {0}' $path)
            return $null
        }
        if (-not (Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $pub)) {
            Write-LsshmError (TF 'Key not found: {0}' $GivenPath)
            return $null
        }
        return $path
    }

    if (-not (Show-LsshmKeysList)) { return $null }
    Write-Host ''
    $choice = Read-LsshmPrompt (TF '{0} (number)' (T $Prompt))
    if (-not $choice) {
        Write-LsshmInfo (T 'Cancelled.')
        return $null
    }

    $choicePub = Get-LsshmPubPath -PrivatePath $choice
    if ((Test-Path -LiteralPath $choice) -or (Test-Path -LiteralPath $choicePub)) {
        if ($choice -like '*.pub') { $choice = $choice.Substring(0, $choice.Length - 4) }
        return $choice
    }

    $n = 0
    if (-not [int]::TryParse($choice, [ref]$n)) {
        Write-LsshmError (TF 'Invalid choice: {0}' $choice)
        return $null
    }
    $keys = @(Get-LsshmKeyPairs)
    if ($n -lt 1 -or $n -gt $keys.Count) {
        Write-LsshmError (TF 'Number out of range (1-{0}).' $keys.Count)
        return $null
    }
    $path = [string]$keys[$n - 1]
    if ($RequirePrivate -and -not (Test-Path -LiteralPath $path)) {
        Write-LsshmError (TF 'Private key missing for {0}.' (Split-Path $path -Leaf))
        return $null
    }
    return $path
}

function New-LsshmKey {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) {
        New-Item -ItemType Directory -Path $script:LSSHM_SSH_DIR -Force | Out-Null
    }
    $type = Read-LsshmPrompt (T 'Key type (ed25519/rsa)') 'ed25519'
    if ($type -notin @('ed25519', 'rsa', 'ED25519', 'RSA')) { $type = 'ed25519' }
    $type = $type.ToLowerInvariant()
    $name = Read-LsshmPrompt (T 'File name') ("id_$type")
    $path = Join-Path $script:LSSHM_SSH_DIR $name
    $comment = Read-LsshmPrompt (T 'Comment') ("$env:USERNAME@$env:COMPUTERNAME")
    $keygenArgs = @('-t', $type, '-f', $path, '-C', $comment)
    if ($type -eq 'rsa') { $keygenArgs += @('-b', '4096') }
    Write-LsshmInfo ("ssh-keygen {0}" -f ($keygenArgs -join ' '))
    & ssh-keygen @keygenArgs
    if ($LASTEXITCODE -eq 0) {
        Write-LsshmOk (TF 'Key generated: {0}' $path)
        Get-Content -LiteralPath (Get-LsshmPubPath -PrivatePath $path)
    } else {
        Write-LsshmError (T 'Generation failed.')
    }
}

function Show-LsshmKeyInspect {
    param([string]$GivenPath = '')
    $path = Select-LsshmKey -Prompt 'Key to inspect' -GivenPath $GivenPath
    if (-not $path) { return }
    $pub = Get-LsshmPubPath -PrivatePath $path
    if (-not (Test-Path -LiteralPath $pub)) { $pub = $path }
    if (-not (Test-Path -LiteralPath $pub)) {
        Write-LsshmError (TF 'File not found: {0}' $pub)
        return
    }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & ssh-keygen -lf $pub
        & ssh-keygen -lvf $pub
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Show-LsshmKeyExport {
    param([string]$GivenPath = '')
    $path = Select-LsshmKey -Prompt 'Key to export' -GivenPath $GivenPath
    if (-not $path) { return }
    $pub = Get-LsshmPubPath -PrivatePath $path
    if (-not (Test-Path -LiteralPath $pub)) {
        Write-LsshmError (TF 'Public key not found: {0}' $pub)
        return
    }
    Write-LsshmInfo (TF 'Public key ({0}):' $pub)
    Get-Content -LiteralPath $pub
}

function Remove-LsshmKey {
    param([string]$GivenPath = '')
    $path = Select-LsshmKey -Prompt 'Key to delete' -GivenPath $GivenPath
    if (-not $path) { return }
    $priv = $path
    $pub = Get-LsshmPubPath -PrivatePath $path
    Write-LsshmWarn (T 'Deleting the key pair:')
    if (Test-Path -LiteralPath $priv) { Write-Host "  $priv" }
    if (Test-Path -LiteralPath $pub) { Write-Host "  $pub" }
    if (-not (Confirm-Lsshm (T 'A backup will be created. Confirm deletion?'))) { return }
    Ensure-LsshmDirs
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($f in @($priv, $pub)) {
        if (Test-Path -LiteralPath $f) {
            Copy-Item -LiteralPath $f -Destination (Join-Path $script:LSSHM_BACKUP_DIR "$stamp-$(Split-Path $f -Leaf)") -Force
            Remove-Item -LiteralPath $f -Force
        }
    }
    Write-LsshmOk (T 'Key pair deleted (backup kept).')
}

function Show-LsshmAgentList {
    if (-not $env:SSH_AUTH_SOCK -and -not (Get-Process ssh-agent -ErrorAction SilentlyContinue)) {
        Write-LsshmWarn (T 'No ssh-agent detected. On Windows: Get-Service ssh-agent ; Start-Service ssh-agent')
    }
    & ssh-add -l 2>&1 | ForEach-Object { Write-Host $_ }
}

function Add-LsshmAgentKey {
    $path = Select-LsshmKey -Prompt 'Key to add to ssh-agent' -RequirePrivate
    if (-not $path) { return }
    & ssh-add $path
    if ($LASTEXITCODE -eq 0) { Write-LsshmOk (T 'Key added to ssh-agent.') } else { Write-LsshmError (T 'Failed.') }
}

function Remove-LsshmAgentKey {
    if (Confirm-Lsshm (T 'Remove all keys from the agent?')) {
        & ssh-add -D
        Write-LsshmOk (T 'All keys removed.')
        return
    }
    $path = Select-LsshmKey -Prompt 'Key to remove from ssh-agent' -RequirePrivate
    if (-not $path) { return }
    & ssh-add -d $path
    if ($LASTEXITCODE -eq 0) { Write-LsshmOk (T 'Key removed from ssh-agent.') } else { Write-LsshmError (T 'Failed.') }
}

# =============================================================================
# Remote hosts
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
        Write-LsshmInfo (T 'No remote host in ~/.ssh/config.')
        return
    }
    Write-Host (TF 'Remote hosts ({0}):' $script:LSSHM_SSH_CONFIG)
    foreach ($n in $names) {
        $hn = Get-LsshmHostField -Name $n -Field 'HostName'
        Write-Host ("  {0,-20} {1}" -f $n, $hn)
    }
}

function Add-LsshmHost {
    if (-not (Test-Path -LiteralPath $script:LSSHM_SSH_DIR)) {
        New-Item -ItemType Directory -Path $script:LSSHM_SSH_DIR -Force | Out-Null
    }
    $name = Read-LsshmPrompt (T 'Host alias') 'proxmox1'
    if (-not $name) { Write-LsshmError (T 'Name required.'); return }
    if ((Get-LsshmHostNames) -contains $name) {
        Write-LsshmError (TF 'A host ''{0}'' already exists.' $name)
        return
    }
    $hostname = Read-LsshmPrompt (T 'Address (HostName)') '192.168.100.240'
    $user = Read-LsshmPrompt (T 'User') 'root'
    $port = Read-LsshmPrompt (T 'Port') '22'
    $identity = Read-LsshmPrompt (T 'Key file') (Join-Path $script:LSSHM_SSH_DIR 'id_ed25519')
    $block = @"

Host $name
    HostName $hostname
    User $user
    Port $port
    IdentityFile $identity
    IdentitiesOnly yes
"@
    Add-Content -LiteralPath $script:LSSHM_SSH_CONFIG -Value $block -Encoding utf8
    Write-LsshmOk (TF 'Host ''{0}'' added.' $name)
}

function Remove-LsshmHost {
    $name = Read-LsshmPrompt (T 'Host name to delete')
    if (-not $name) { return }
    if (-not ((Get-LsshmHostNames) -contains $name)) {
        Write-LsshmError (TF 'Host not found: {0}' $name)
        return
    }
    if (-not (Confirm-Lsshm (TF 'Delete host ''{0}''?' $name))) { return }
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
    Write-LsshmOk (TF 'Host ''{0}'' deleted.' $name)
}

function Remove-LsshmKnownHost {
    param([Parameter(Mandatory)][string]$HostSpec)
    Ensure-LsshmDirs
    if (-not (Test-Path -LiteralPath $script:LSSHM_KNOWN_HOSTS)) {
        Write-LsshmError (T 'No known_hosts file.')
        return $false
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $script:LSSHM_KNOWN_HOSTS -Destination (Join-Path $script:LSSHM_BACKUP_DIR "$stamp-known_hosts") -Force -ErrorAction SilentlyContinue
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & ssh-keygen -R $HostSpec -f $script:LSSHM_KNOWN_HOSTS 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-LsshmOk (TF 'Fingerprint of {0} removed.' $HostSpec)
            # ssh-keygen may leave known_hosts.old
            $old = "$($script:LSSHM_KNOWN_HOSTS).old"
            if (Test-Path -LiteralPath $old) {
                Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
            }
            return $true
        }
    } finally {
        $ErrorActionPreference = $prev
    }
    Write-LsshmError (TF 'Removal failed for {0}.' $HostSpec)
    return $false
}

function Show-LsshmKnownHostsList {
    if (-not (Test-Path -LiteralPath $script:LSSHM_KNOWN_HOSTS)) {
        Write-LsshmInfo (T 'No known_hosts file.')
        return
    }
    Write-LsshmInfo (TF 'Known fingerprints ({0}):' $script:LSSHM_KNOWN_HOSTS)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & ssh-keygen -lf $script:LSSHM_KNOWN_HOSTS 2>&1 | ForEach-Object { Write-Host $_ }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Invoke-LsshmKnownHostRemovePrompt {
    $hostSpec = Read-LsshmPrompt (T 'Host to remove from known_hosts')
    if (-not $hostSpec) {
        Write-LsshmInfo (T 'Cancelled.')
        return
    }
    Remove-LsshmKnownHost -HostSpec $hostSpec | Out-Null
}

function Add-LsshmKnownHostKey {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [string]$Port = '22'
    )
    Ensure-LsshmDirs
    if (-not (Get-Command ssh-keyscan -ErrorAction SilentlyContinue)) {
        Write-LsshmError (T 'ssh-keyscan not found.')
        return $false
    }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & ssh-keyscan -p $Port $HostName 2>$null
    } finally {
        $ErrorActionPreference = $prev
    }
    if (-not $lines) {
        Write-LsshmError (TF 'Unable to fetch host keys from {0}.' $HostName)
        return $false
    }
    if (-not (Test-Path -LiteralPath $script:LSSHM_KNOWN_HOSTS)) {
        New-Item -ItemType File -Path $script:LSSHM_KNOWN_HOSTS -Force | Out-Null
    }
    Add-Content -LiteralPath $script:LSSHM_KNOWN_HOSTS -Value $lines -Encoding ascii
    Write-LsshmOk (TF 'New host key(s) for {0} added to known_hosts.' $HostName)
    Write-LsshmInfo (T 'Announced fingerprints:')
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines | & ssh-keygen -lf - 2>&1 | ForEach-Object { Write-Host ("  {0}" -f $_) }
    } finally {
        $ErrorActionPreference = $prev
    }
    return $true
}

function Repair-LsshmHostKeyConflict {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$HostName,
        [string]$Port = '22'
    )
    Write-LsshmWarn (T 'Remote host identification has changed (known_hosts conflict).')
    Write-LsshmWarn (T 'This can happen after a reinstall, or indicate a MITM risk.')
    if (-not (Confirm-Lsshm (TF 'Remove the old host key for {0} from known_hosts?' $HostName) -DefaultYes)) {
        Write-LsshmInfo (T 'Cancelled.')
        return $false
    }

    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($h in @($HostName, $Name)) {
        if ($h -and -not $targets.Contains($h)) { $targets.Add($h) }
    }
    if ($Port -and $Port -ne '22') {
        $bracket = "[{0}]:{1}" -f $HostName, $Port
        if (-not $targets.Contains($bracket)) { $targets.Add($bracket) }
    }

    $ok = $false
    foreach ($t in $targets) {
        if (Remove-LsshmKnownHost -HostSpec $t) { $ok = $true }
    }

    if ($ok -and (Confirm-Lsshm (T 'Fetch and accept the new host key now?') -DefaultYes)) {
        Add-LsshmKnownHostKey -HostName $HostName -Port $Port | Out-Null
    }
    return $ok
}

function Test-LsshmSshOutputIndicatesHostKeyConflict {
    param([string]$Text)
    if (-not $Text) { return $false }
    return ($Text -match 'REMOTE HOST IDENTIFICATION HAS CHANGED' -or
            $Text -match 'Host key verification failed' -or
            $Text -match 'Offending .+ key in')
}

function Test-LsshmHost {
    $name = Read-LsshmPrompt (T 'Host name to test')
    if (-not $name) { return }
    $hostName = Get-LsshmHostField -Name $name -Field 'HostName'
    if (-not $hostName) { $hostName = $name }
    $port = Get-LsshmHostField -Name $name -Field 'Port'
    if (-not $port) { $port = '22' }

    Write-LsshmInfo (TF 'Resolving {0}...' $hostName)
    try {
        [System.Net.Dns]::GetHostAddresses($hostName) | Out-Null
        Write-LsshmOk (T 'DNS resolution succeeded.')
    } catch {
        Write-LsshmWarn (T 'DNS resolution uncertain.')
    }

    Write-LsshmInfo (TF 'Testing port {0}...' $port)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($hostName, [int]$port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(3000, $false)
        if ($ok -and $client.Connected) {
            Write-LsshmOk (TF 'Port {0} open.' $port)
        } else {
            Write-LsshmWarn (TF 'Port {0} unreachable.' $port)
        }
        $client.Close()
    } catch {
        Write-LsshmWarn (TF 'Port {0} unreachable.' $port)
    }

    Write-LsshmInfo (T 'SSH authentication test (BatchMode)...')
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $sshOut = ''
    try {
        $sshOut = (& ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes $name true 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }

    if ($code -eq 0) {
        Write-LsshmOk (T 'Authentication succeeded.')
        return
    }

    if (Test-LsshmSshOutputIndicatesHostKeyConflict -Text $sshOut) {
        Repair-LsshmHostKeyConflict -Name $name -HostName $hostName -Port $port | Out-Null
        Write-LsshmInfo (T 'Re-run the host test after updating known_hosts.')
        return
    }

    Write-LsshmWarn (T 'Automatic authentication failed (missing key or password required).')
}

function Connect-LsshmHost {
    $name = Read-LsshmPrompt (T 'Host name')
    if (-not $name) { return }
    $hostName = Get-LsshmHostField -Name $name -Field 'HostName'
    if (-not $hostName) { $hostName = $name }
    $port = Get-LsshmHostField -Name $name -Field 'Port'
    if (-not $port) { $port = '22' }

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Probe first so we can offer known_hosts repair before an interactive session.
        $probe = (& ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes $name true 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $probeCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }

    if ($probeCode -ne 0 -and (Test-LsshmSshOutputIndicatesHostKeyConflict -Text $probe)) {
        Repair-LsshmHostKeyConflict -Name $name -HostName $hostName -Port $port | Out-Null
    }

    Write-LsshmInfo (TF 'Connecting to {0}...' $name)
    & ssh $name
}

# =============================================================================
# Audit / doctor / logs / backup / settings
# =============================================================================

function Invoke-LsshmDoctor {
    Write-LsshmHeader
    Write-Host (T 'LSSHM diagnostics (doctor)')
    Write-Host ''
    Write-Host (TF 'OS           : {0}' ([System.Environment]::OSVersion.VersionString))
    Write-Host (TF 'User         : {0}' $env:USERNAME)
    Write-Host (TF 'Administrator: {0}' $(if (Test-LsshmAdmin) { T 'yes' } else { T 'no' }))
    Write-Host (TF 'sshd         : {0}' $(if (Get-LsshmSshdPath) { Get-LsshmSshdPath } else { T 'not detected' }))
    Write-Host (TF 'Service      : {0}' $script:LSSHM_SSH_SERVICE)
    Write-Host ''
    Write-Host (T 'SSH tools:')
    foreach ($t in @('ssh', 'sshd', 'ssh-keygen', 'ssh-add', 'ssh-keyscan')) {
        $c = Get-Command $t -ErrorAction SilentlyContinue
        if ($c) { Write-Host ("  [OK]  {0}" -f $t) } else { Write-Host ("  [--]  {0} ({1})" -f $t, (T 'absent')) }
    }
    Write-Host ''
    Write-Host (T 'LSSHM paths:')
    Write-Host ("  config : {0}" -f $script:LSSHM_CONFIG_DIR)
    Write-Host ("  data   : {0}" -f $script:LSSHM_DATA_DIR)
    Write-Host ("  state  : {0}" -f $script:LSSHM_STATE_DIR)
}

function Invoke-LsshmAudit {
    Write-LsshmHeader
    Write-Host (T 'Local SSH security audit (Windows)')
    Write-Host ''
    $script:LSSHM_AUDIT_PASS = 0
    $script:LSSHM_AUDIT_WARN = 0
    $script:LSSHM_AUDIT_FAIL = 0

    if (Test-LsshmServerInstalled) {
        $script:LSSHM_AUDIT_PASS++; Write-Host ("  [OK]    {0}" -f (T 'OpenSSH Server installed.')) -ForegroundColor Green
    } else {
        $script:LSSHM_AUDIT_WARN++; Write-Host ("  [WARN]  {0}" -f (T 'OpenSSH Server not installed.')) -ForegroundColor Yellow
    }

    $root = Get-LsshmConfigValue 'permitrootlogin'
    switch -Regex ($root) {
        '^no$' {
            $script:LSSHM_AUDIT_PASS++
            Write-Host ("  [OK]    {0}" -f (T 'PermitRootLogin = no.')) -ForegroundColor Green
        }
        '^(prohibit-password|without-password)$' {
            $script:LSSHM_AUDIT_PASS++
            Write-Host ("  [OK]    {0}" -f (T 'PermitRootLogin = key only.')) -ForegroundColor Green
        }
        '^yes$' {
            $script:LSSHM_AUDIT_FAIL++
            Write-Host ("  [FAIL]  {0}" -f (T 'PermitRootLogin = yes (admin password possible).')) -ForegroundColor Red
        }
        default {
            $script:LSSHM_AUDIT_WARN++
            Write-Host ("  [WARN]  {0}" -f (TF 'PermitRootLogin = {0}' $(if ($root) { $root } else { T 'not set' }))) -ForegroundColor Yellow
        }
    }

    $passAuth = Get-LsshmConfigValue 'passwordauthentication'
    switch -Regex ($passAuth) {
        '^no$' {
            $script:LSSHM_AUDIT_PASS++
            Write-Host ("  [OK]    {0}" -f (T 'Password authentication disabled.')) -ForegroundColor Green
        }
        '^yes$' {
            $script:LSSHM_AUDIT_WARN++
            Write-Host ("  [WARN]  {0}" -f (T 'Password authentication enabled.')) -ForegroundColor Yellow
        }
        default {
            $script:LSSHM_AUDIT_WARN++
            Write-Host ("  [WARN]  {0}" -f (TF 'PasswordAuthentication = {0}' $(if ($passAuth) { $passAuth } else { T 'not set' }))) -ForegroundColor Yellow
        }
    }

    if (Test-Path -LiteralPath $script:LSSHM_SSH_DIR) {
        $script:LSSHM_AUDIT_PASS++
        Write-Host ("  [OK]    {0}" -f (T '.ssh present for the current user.')) -ForegroundColor Green
    } else {
        $script:LSSHM_AUDIT_WARN++
        Write-Host ("  [WARN]  {0}" -f (T 'No .ssh directory.')) -ForegroundColor Yellow
    }

    if (Test-LsshmServerActive) {
        $script:LSSHM_AUDIT_PASS++
        Write-Host ("  [OK]    {0}" -f (T 'sshd service active.')) -ForegroundColor Green
    } else {
        $script:LSSHM_AUDIT_WARN++
        Write-Host ("  [WARN]  {0}" -f (T 'sshd service inactive or absent.')) -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host (TF 'Summary: {0} OK, {1} warnings, {2} failures' `
            $script:LSSHM_AUDIT_PASS $script:LSSHM_AUDIT_WARN $script:LSSHM_AUDIT_FAIL)
}

function Show-LsshmLogsMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host (T 'Connections and logs')
        Write-Host ''
        Write-Host (T '  1. Sessions / sshd processes')
        Write-Host (T '  2. OpenSSH events (Event Log)')
        Write-Host (T '  3. Back')
        $c = Read-LsshmPrompt (T 'Choice') '3'
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
                    Write-LsshmWarn (TF 'OpenSSH/Operational log unavailable: {0}' $_.Exception.Message)
                }
                Pause-Lsshm
            }
            '3' { return }
            default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
        }
    }
}

function Show-LsshmBackupMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host (T 'Backup and restore')
        Write-Host ''
        Write-Host (T '  1. Back up sshd_config')
        Write-Host (T '  2. Back up user authorized_keys')
        Write-Host (T '  3. List backups')
        Write-Host (T '  4. Back')
        $c = Read-LsshmPrompt (T 'Choice') '4'
        switch ($c) {
            '1' { Backup-LsshmServerConfig; Pause-Lsshm }
            '2' {
                Ensure-LsshmDirs
                if (Test-Path -LiteralPath $script:LSSHM_AUTHORIZED_KEYS) {
                    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $dest = Join-Path $script:LSSHM_BACKUP_DIR "$stamp-authorized_keys"
                    Copy-Item -LiteralPath $script:LSSHM_AUTHORIZED_KEYS -Destination $dest -Force
                    Write-LsshmOk (TF 'Backup: {0}' $dest)
                } else {
                    Write-LsshmWarn (T 'authorized_keys not found.')
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
            default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
        }
    }
}

function Show-LsshmSettingsMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host (T 'LSSHM settings (Windows)')
        Write-Host ''
        Write-Host (TF 'Config : {0}' $script:LSSHM_CONFIG_FILE)
        Write-Host (TF 'Data   : {0}' $script:LSSHM_DATA_DIR)
        Write-Host (TF 'Language : {0}' (Get-LsshmLangNativeName $script:LSSHM_LANG))
        Write-Host ''
        Write-Host (T '  1. Show diagnostics (doctor)')
        Write-Host (T '  2. Install LSSHM into the user profile')
        Write-Host (T '  3. Change the language')
        Write-Host (T '  4. Back')
        $c = Read-LsshmPrompt (T 'Choice') '4'
        switch ($c) {
            '1' { Invoke-LsshmDoctor; Pause-Lsshm }
            '2' { Install-LsshmSelf; Pause-Lsshm }
            '3' { Select-LsshmLanguage; Pause-Lsshm }
            '4' { return }
            default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
        }
    }
}

# =============================================================================
# Local Windows installation
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
        Write-LsshmInfo (T 'Downloading lsshm.ps1...')
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
        Write-LsshmOk (TF 'Added to the user PATH: {0}' $script:LSSHM_BIN_DIR)
    }

    Write-LsshmOk (T 'Installed:')
    Write-Host ("  {0}" -f $script:LSSHM_INSTALL_TARGET)
    Write-Host ("  {0}" -f $script:LSSHM_BIN_LINK)
    Write-LsshmOk (T 'Installation complete.')
    Write-LsshmOk (T 'Run: lsshm.ps1')
}

# =============================================================================
# CLI menus
# =============================================================================

function Show-LsshmServerMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host (T 'Local SSH server (Windows OpenSSH)')
        Write-Host ''
        Show-LsshmServerStatus
        Write-Host ''
        Write-Host (T '  1. Install OpenSSH Server')
        Write-Host (T '  2. Start the service')
        Write-Host (T '  3. Stop the service')
        Write-Host (T '  4. Restart the service')
        Write-Host (T '  5. Enable at boot')
        Write-Host (T '  6. Disable at boot')
        Write-Host (T '  7. Change the port')
        Write-Host (T '  8. Address family (AddressFamily)')
        Write-Host (T '  9. Listen addresses (ListenAddress)')
        Write-Host (T ' 10. Windows Firewall (allow OpenSSH)')
        Write-Host (T ' 11. Manage PermitRootLogin / admin access')
        Write-Host (T ' 12. Password authentication')
        Write-Host (T ' 13. Key authentication')
        Write-Host (T ' 14. Test the configuration (sshd -t)')
        Write-Host (T ' 15. Show the effective configuration (sshd -T)')
        Write-Host (T ' 16. Back')
        $c = Read-LsshmPrompt (T 'Choice') '16'
        try {
            switch ($c) {
                '1' { Install-LsshmOpenSshServer; Pause-Lsshm }
                '2' { Invoke-LsshmServerAction Start; Pause-Lsshm }
                '3' { Invoke-LsshmServerAction Stop; Pause-Lsshm }
                '4' { Invoke-LsshmServerAction Restart; Pause-Lsshm }
                '5' { Set-LsshmServerStartup Automatic; Pause-Lsshm }
                '6' { Set-LsshmServerStartup Disabled; Pause-Lsshm }
                '7' { Set-LsshmPortMenu; Pause-Lsshm }
                '8' { Set-LsshmAddressFamilyMenu; Pause-Lsshm }
                '9' { Set-LsshmListenAddressMenu; Pause-Lsshm }
                '10' { Show-LsshmFirewallMenu }
                '11' { Set-LsshmRootLoginMenu; Pause-Lsshm }
                '12' {
                    if (Confirm-Lsshm (T 'Allow PasswordAuthentication?') -DefaultYes:$false) {
                        Set-LsshmSshdDirective -Key 'PasswordAuthentication' -Value 'yes' | Out-Null
                    } else {
                        Set-LsshmSshdDirective -Key 'PasswordAuthentication' -Value 'no' | Out-Null
                    }
                    Restart-Service sshd -Force -ErrorAction SilentlyContinue
                    Pause-Lsshm
                }
                '13' {
                    if (Confirm-Lsshm (T 'Allow PubkeyAuthentication?') -DefaultYes) {
                        Set-LsshmSshdDirective -Key 'PubkeyAuthentication' -Value 'yes' | Out-Null
                    } else {
                        if (Confirm-Lsshm (T 'Disabling keys may lock you out. Continue?')) {
                            Set-LsshmSshdDirective -Key 'PubkeyAuthentication' -Value 'no' | Out-Null
                        }
                    }
                    Restart-Service sshd -Force -ErrorAction SilentlyContinue
                    Pause-Lsshm
                }
                '14' { Test-LsshmServerConfig | Out-Null; Pause-Lsshm }
                '15' { Show-LsshmServerConfigDump; Pause-Lsshm }
                '16' { return }
                default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
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
        Write-Host (T 'Access to this machine (keys allowed HERE)')
        Write-Host ''
        Write-Host (T '  1. List user keys (~/.ssh/authorized_keys)')
        Write-Host (T '  2. List administrator keys (administrators_authorized_keys)')
        Write-Host (T '  3. Add a user key')
        Write-Host (T '  4. Add an administrator key')
        Write-Host (T '  5. Repair .ssh permissions')
        Write-Host (T '  6. Back')
        $c = Read-LsshmPrompt (T 'Choice') '6'
        try {
            switch ($c) {
                '1' { Show-LsshmAccessList -Scope User; Pause-Lsshm }
                '2' { Show-LsshmAccessList -Scope Administrators; Pause-Lsshm }
                '3' { Add-LsshmAccessKey -Scope User; Pause-Lsshm }
                '4' { Add-LsshmAccessKey -Scope Administrators; Pause-Lsshm }
                '5' { Repair-LsshmAccessPermissions; Pause-Lsshm }
                '6' { return }
                default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
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
        Write-Host (T 'My SSH keys (to connect ELSEWHERE)')
        Write-Host ''
        Write-Host (T '  1. List key pairs')
        Write-Host (T '  2. Generate a new key (ED25519 by default)')
        Write-Host (T '  3. Inspect a key')
        Write-Host (T '  4. Show / export a public key')
        Write-Host (T '  5. Delete a key pair')
        Write-Host (T '  6. ssh-agent: list')
        Write-Host (T '  7. ssh-agent: add a key')
        Write-Host (T '  8. ssh-agent: remove a key')
        Write-Host (T '  9. Back')
        $c = Read-LsshmPrompt (T 'Choice') '9'
        switch ($c) {
            '1' { Show-LsshmKeysList | Out-Null; Pause-Lsshm }
            '2' { New-LsshmKey; Pause-Lsshm }
            '3' { Show-LsshmKeyInspect; Pause-Lsshm }
            '4' { Show-LsshmKeyExport; Pause-Lsshm }
            '5' { Remove-LsshmKey; Pause-Lsshm }
            '6' { Show-LsshmAgentList; Pause-Lsshm }
            '7' { Add-LsshmAgentKey; Pause-Lsshm }
            '8' { Remove-LsshmAgentKey; Pause-Lsshm }
            '9' { return }
            default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
        }
    }
}

function Show-LsshmHostsMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Write-Host (T 'Remote hosts (~/.ssh/config) - optional')
        Write-Host ''
        Write-Host (T '  1. List hosts')
        Write-Host (T '  2. Add a host')
        Write-Host (T '  3. Delete a host')
        Write-Host (T '  4. Test a host')
        Write-Host (T '  5. Connect')
        Write-Host (T '  6. known_hosts: list')
        Write-Host (T '  7. known_hosts: remove a fingerprint')
        Write-Host (T '  8. Update / accept a host key')
        Write-Host (T '  9. Back')
        $c = Read-LsshmPrompt (T 'Choice') '9'
        switch ($c) {
            '1' { Show-LsshmHostsList; Pause-Lsshm }
            '2' { Add-LsshmHost; Pause-Lsshm }
            '3' { Remove-LsshmHost; Pause-Lsshm }
            '4' { Test-LsshmHost; Pause-Lsshm }
            '5' { Connect-LsshmHost }
            '6' { Show-LsshmKnownHostsList; Pause-Lsshm }
            '7' { Invoke-LsshmKnownHostRemovePrompt; Pause-Lsshm }
            '8' {
                $h = Read-LsshmPrompt (T 'Host to scan')
                if ($h) {
                    $p = Read-LsshmPrompt (T 'Port') '22'
                    if (-not $p) { $p = '22' }
                    # Remove old keys first when updating.
                    Remove-LsshmKnownHost -HostSpec $h | Out-Null
                    if ($p -ne '22') {
                        Remove-LsshmKnownHost -HostSpec ("[{0}]:{1}" -f $h, $p) | Out-Null
                    }
                    Add-LsshmKnownHostKey -HostName $h -Port $p | Out-Null
                }
                Pause-Lsshm
            }
            '9' { return }
            default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
        }
    }
}

function Show-LsshmMainMenu {
    while ($true) {
        Clear-Host
        Write-LsshmHeader
        Show-LsshmStatusPanel
        Write-Host ''
        Write-Host (T '1. Manage the local SSH server')
        Write-Host (T '2. Manage access to this machine')
        Write-Host (T '3. Manage my SSH keys')
        Write-Host (T '4. Manage remote hosts')
        Write-Host (T '5. View connections and logs')
        Write-Host (T '6. Run a security audit')
        Write-Host (T '7. Back up or restore')
        Write-Host (T '8. LSSHM settings')
        Write-Host (T '9. Quit')
        $c = Read-LsshmPrompt (T 'Choice') '9'
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
            default { Write-LsshmWarn (T 'Invalid choice.'); Pause-Lsshm }
        }
    }
}

# =============================================================================
# Entry point
# =============================================================================

function Show-LsshmUsage {
    Write-Host ("{0} v{1} (Windows / PowerShell)" -f $script:LSSHM_LONG_NAME, $script:LSSHM_VERSION)
    Write-Host ''
    Write-Host (T 'Usage:')
    Write-Host ("  lsshm.ps1                     {0}" -f (T 'CLI menu'))
    Write-Host ("  lsshm.ps1 status              {0}" -f (T 'Local SSH status'))
    Write-Host ("  lsshm.ps1 doctor              {0}" -f (T 'Diagnostics'))
    Write-Host ("  lsshm.ps1 audit               {0}" -f (T 'Security audit'))
    Write-Host ("  lsshm.ps1 install             {0}" -f (T 'Install into the user profile'))
    Write-Host ("  lsshm.ps1 server status       {0}" -f (T 'sshd service status'))
    Write-Host ("  lsshm.ps1 key list            {0}" -f (T 'List local keys'))
    Write-Host ("  lsshm.ps1 host list           {0}" -f (T 'List hosts in ~/.ssh/config'))
    Write-Host ("  lsshm.ps1 help                {0}" -f (T 'This help'))
    Write-Host ''
    Write-Host (T 'Options:')
    Write-Host ("  -Yes                          {0}" -f (T 'Assume yes (non-interactive)'))
    Write-Host ("  -User NAME                    {0}" -f (T 'Target user (display)'))
    Write-Host ("  -Lang CODE                    {0}" -f (T 'Interface language (en, fr, es)'))
}

function Invoke-LsshmMain {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ArgsRest
    )

    Initialize-LsshmPaths
    Ensure-LsshmDirs
    Initialize-LsshmLang

    $cmd = if ($ArgsRest -and $ArgsRest.Count -gt 0) { $ArgsRest[0].ToLowerInvariant() } else { 'menu' }
    $rest = if ($ArgsRest -and $ArgsRest.Count -gt 1) { $ArgsRest[1..($ArgsRest.Count - 1)] } else { @() }

    # First interactive run without a stored language: offer to choose one.
    # Skip when -Lang already forced a language for this invocation.
    if ($cmd -in @('menu', 'install') `
        -and (Test-LsshmInteractive) `
        -and -not (Test-LsshmLangConfigured) `
        -and -not $script:LSSHM_LANG_OVERRIDE) {
        Select-LsshmLanguage
    }

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
                default { Write-LsshmError (TF 'Unknown server subcommand: {0}' $sub); exit 1 }
            }
        }
        'access' {
            $sub = if ($rest.Count -gt 0) { $rest[0].ToLowerInvariant() } else { 'list' }
            switch ($sub) {
                'list' { Show-LsshmAccessList -Scope User }
                'repair' { Repair-LsshmAccessPermissions }
                default { Write-LsshmError (TF 'Unknown access subcommand: {0}' $sub); exit 1 }
            }
        }
        'key' {
            $sub = if ($rest.Count -gt 0) { $rest[0].ToLowerInvariant() } else { 'list' }
            switch ($sub) {
                'list' { Show-LsshmKeysList }
                'generate' { New-LsshmKey }
                default { Write-LsshmError (TF 'Unknown key subcommand: {0}' $sub); exit 1 }
            }
        }
        'host' {
            $sub = if ($rest.Count -gt 0) { $rest[0].ToLowerInvariant() } else { 'list' }
            switch ($sub) {
                'list' { Show-LsshmHostsList }
                'add' { Add-LsshmHost }
                default { Write-LsshmError (TF 'Unknown host subcommand: {0}' $sub); exit 1 }
            }
        }
        default {
            Write-LsshmError (TF 'Unknown command: {0}' $cmd)
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
            '^--lang$|^--language$|^-Lang$' {
                if ($i + 1 -lt $args.Count) {
                    $script:LSSHM_LANG_OVERRIDE = [string]$args[$i + 1]
                    $i++
                }
            }
            default { $rawArgs.Add([string]$args[$i]) }
        }
    }
}

Invoke-LsshmMain -ArgsRest $rawArgs.ToArray()
