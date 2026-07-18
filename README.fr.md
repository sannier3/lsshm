**__Readme Languages__** [![English](https://img.shields.io/badge/lang-English-lightgrey.svg)](README.md) [![Français](https://img.shields.io/badge/lang-Français-blue.svg)](README.fr.md) ![License](https://img.shields.io/badge/License-MIT-success?style=flat-square)

# LSSHM - Local SSH Manager

LSSHM est un outil de gestion OpenSSH **local** : serveur SSH, accès entrants, clés de connexion sortantes et machines distantes. Il fonctionne immédiatement sur la machine où il est installé, **sans aucun hôte distant configuré**.

Interface CLI par défaut (sans dépendance) et interface `dialog` facultative.

> [!WARNING]
> LSSHM est en développement actif (v0.3.0). Une mauvaise configuration SSH peut vous verrouiller hors de la machine. LSSHM vise à limiter ce risque via validation, sauvegardes, confirmations et restauration automatique.

## Positionnement

LSSHM gère quatre domaines distincts, visibles dans tous les menus :

| Partie | Fichiers concernés |
| ------ | ------------------ |
| Serveur SSH local | `/etc/ssh/sshd_config` et inclusions |
| Accès entrants | `~/.ssh/authorized_keys` |
| Clés sortantes | `~/.ssh/id_*`, `ssh-agent` |
| Machines distantes | `~/.ssh/config`, `~/.ssh/known_hosts` |

## Installation

### Linux

Installe LSSHM dans `~/.local` et crée la commande `lsshm` :

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- install
```

Puis lancez :

```bash
export PATH="$HOME/.local/bin:$PATH"   # une fois, dans le terminal actuel
lsshm
```

Les prochaines connexions SSH chargeront le PATH automatiquement (`~/.profile`).

> Pas de `sudo` pour l'installation. Les privilèges root ne sont demandés que pour gérer le serveur SSH ou les fichiers système.

### Windows (PowerShell)

Téléchargez et lancez l'interface CLI PowerShell (mêmes menus et concepts que sous Linux) :

```powershell
irm https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.ps1 -OutFile $env:TEMP\lsshm.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\lsshm.ps1
```

Ou installation dans le profil utilisateur :

```powershell
powershell -ExecutionPolicy Bypass -File $env:TEMP\lsshm.ps1 install
```

La gestion du serveur OpenSSH nécessite PowerShell **en administrateur**. Les clés utilisateur et `~\.ssh\config` n'en ont pas besoin.

## Exécution sans installation

Pour **essayer** LSSHM ou lancer **une commande ponctuelle**, sans rien installer :

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash              # menu
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- status   # état
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- ui       # interface dialog
```

C'est le **même fichier** qu'à l'installation ; le script est juste exécuté directement (retéléchargé à chaque `curl`).

## Utilisation

### Menu interactif

```bash
lsshm
```

Affiche l'état local (serveur, port, root, clés, hôtes) puis le menu principal.

### Interface dialog

```bash
lsshm ui
lsshm --ui          # alias
```

Si `dialog` est absent, LSSHM propose de l'installer ou de basculer sur la CLI.

### Commandes non interactives

```bash
lsshm status
lsshm doctor
lsshm audit
lsshm update
lsshm update rollback
lsshm uninstall
```

#### Serveur SSH local

```bash
lsshm server status|install|start|stop|restart|reload|enable|disable
lsshm server config|test|logs
```

#### Accès entrants (clés autorisées **sur cette machine**)

```bash
lsshm access list [--user root]
lsshm access add [--user jb]
lsshm access remove [--user jb]
lsshm access disable [--user jb]
lsshm access repair [--user jb]
```

#### Clés locales (pour se connecter **ailleurs**)

```bash
lsshm key list|generate
lsshm key inspect ~/.ssh/id_ed25519
lsshm key export ~/.ssh/id_ed25519
lsshm key delete ~/.ssh/id_ed25519
lsshm key agent list|add PATH|remove PATH
```

#### Machines distantes (facultatif)

```bash
lsshm host list|add
lsshm host edit|delete|test|connect|copy-key|revoke-key NOM
```

Options globales : `--user NOM`, `-y`, `--no-color`, `-h`.

### Administrer un autre utilisateur (root / Debian)

En session **root** (console, LXC, ou `sudo`), LSSHM demande quel utilisateur administrer pour les fichiers personnels (`~/.ssh` : clés, `authorized_keys`, `config`). Le serveur SSH système reste géré en root.

Exemples :

```bash
# Menu interactif : choisir l'utilisateur au démarrage
sudo lsshm
# ou directement en root
lsshm

# Sans menu : cibler explicitement
lsshm --user jb access list
lsshm --user jb key generate
```

Vous pouvez aussi changer d’utilisateur dans **Accès**, **Clés** ou **Paramètres**.

## Fonctionnalités v0.3.0

- Détection Debian / dérivés, systemd, LXC
- Installation et gestion du service OpenSSH Server
- Configuration via `/etc/ssh/sshd_config.d/00-lsshm.conf`
- Lecture effective (`sshd -T`) et validation (`sshd -t`)
- Gestion lisible de `PermitRootLogin`, mots de passe, clés publiques, `AllowUsers` / `AllowGroups`
- Restauration automatique pour changements dangereux (port, root, mots de passe…)
- Gestion des `authorized_keys` (liste, ajout, suppression, désactivation, réparation, doublons)
- Génération ED25519/RSA, `ssh-agent`, `~/.ssh/config`, `ssh-copy-id`
- Audit de sécurité, journaux, sauvegarde/restauration
- Mise à jour sécurisée (`bash -n`, SHA-256, remplacement atomique, rollback)

## Développement

Depuis une copie locale du dépôt :

```bash
bash scripts/build.sh
bash lsshm.sh install    # ou : bash install.sh
bash tests/run.sh
```

Structure : modules dans `src/`, fichier unique `lsshm.sh` généré par `scripts/build.sh`.

Voir `CONTRIBUTING.md` et `CHANGELOG.md`.

## Sécurité

LSSHM ne transmet jamais de clé privée. Signalez les vulnérabilités via GitHub (voir `SECURITY.md`), pas en issue publique.

## Licence

MIT — voir `LICENSE`.
