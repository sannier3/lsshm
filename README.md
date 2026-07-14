# LSSHM - Local SSH Manager

LSSHM est un outil de gestion OpenSSH **local** : serveur SSH, accès entrants, clés de connexion sortantes et machines distantes. Il fonctionne immédiatement sur la machine où il est installé, **sans aucun hôte distant configuré**.

Interface CLI par défaut (sans dépendance) et interface `dialog` facultative.

> [!WARNING]
> LSSHM est en développement actif (v0.1.0). Une mauvaise configuration SSH peut vous verrouiller hors de la machine. LSSHM vise à limiter ce risque via validation, sauvegardes, confirmations et restauration automatique.

## Positionnement

LSSHM gère quatre domaines distincts, visibles dans tous les menus :

| Partie | Fichiers concernés |
| ------ | ------------------ |
| Serveur SSH local | `/etc/ssh/sshd_config` et inclusions |
| Accès entrants | `~/.ssh/authorized_keys` |
| Clés sortantes | `~/.ssh/id_*`, `ssh-agent` |
| Machines distantes | `~/.ssh/config`, `~/.ssh/known_hosts` |

## Installation

### Depuis le dépôt (recommandé)

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- install
```

Pour examiner le script avant installation :

```bash
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh -o /tmp/lsshm.sh
less /tmp/lsshm.sh
bash /tmp/lsshm.sh install
```

### Depuis une copie locale

```bash
./scripts/build.sh    # assemble lsshm.sh depuis src/
./lsshm.sh install
# ou
./install.sh
```

### Emplacements (XDG)

```text
~/.local/bin/lsshm              -> ~/.local/share/lsshm/lsshm.sh
~/.local/share/lsshm/lsshm.sh
~/.config/lsshm/config
~/.local/state/lsshm/
~/.cache/lsshm/
```

L'installation ne nécessite pas `sudo`. Les privilèges sont demandés uniquement pour les opérations système (service SSH, `/etc/ssh/`, comptes, pare-feu).

### Exécuter sans installer

LSSHM peut être lancé **sans** copie dans `~/.local`. C'est le même fichier `lsshm.sh` (assemblé depuis `src/` par `./scripts/build.sh`) ; seul le chemin d'appel change.

**Depuis GitHub** - un lien, deux usages :

```bash
# Installer (recommandé pour un usage régulier)
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- install

# Exécuter directement, sans installer
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- status
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- doctor
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash              # menu CLI
curl -fsSL https://raw.githubusercontent.com/sannier3/lsshm/main/lsshm.sh | bash -s -- ui       # interface dialog
```

**Depuis une copie locale du dépôt** :

```bash
./scripts/build.sh          # si lsshm.sh n'est pas encore généré
./lsshm.sh                  # menu CLI
./lsshm.sh status
./lsshm.sh doctor
./lsshm.sh server status
```

Le dossier `src/` sert au **développement** ; à l'exécution, tout le code est déjà inclus dans `lsshm.sh`. Inutile de sourcer `src/` à la main.

Sans installation permanente :
- la commande `lsshm` n'est pas ajoutée au PATH ;
- le script est retéléchargé à chaque `curl` (usage ponctuel ou essai) ;
- la configuration (`~/.config/lsshm/`) et l'état (`~/.local/state/lsshm/`) sont quand même créés si besoin.

Pour un usage quotidien, préférez `install` puis `lsshm`.

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

## Fonctionnalités v0.1.0

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

Structure modulaire assemblée en un seul fichier :

```text
src/           modules Bash
scripts/build.sh
tests/         tests unitaires
lsshm.sh       généré (ne pas éditer à la main)
```

```bash
./scripts/build.sh
./tests/run.sh
```

Voir `CONTRIBUTING.md` et `CHANGELOG.md`.

## Sécurité

LSSHM ne transmet jamais de clé privée. Signalez les vulnérabilités via GitHub (voir `SECURITY.md`), pas en issue publique.

## Licence

MIT - voir `LICENSE`.
