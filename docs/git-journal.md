# Journal Git/GitHub — support de révision

Chaque notion rencontrée, avec le cas concret où elle a servi dans Timbre.
Organisé par notion, pas par ordre chronologique.

## `git init`

Transforme un dossier en dépôt Git — crée `.git/`, purement local, rien n'est
envoyé nulle part. **Cas concret** : premier commit de Timbre, dans
`/Users/dafffyl/CLAUDE`.

## `.gitignore` — se méfier des templates génériques

Un template Swift/Xcode standard ignore souvent un dossier `Packages/`
(ancien comportement Xcode pour les dépendances SPM résolues). **Cas
concret** : dans Timbre, `Packages/` est le dossier qui contiendra le vrai
code source (TimbreCore, TimbreAudio…) — copier le template bêtement aurait
rendu tout ce code invisible pour Git. Toujours relire un `.gitignore`
importé ligne par ligne dans le contexte du projet réel.

## Identité Git (`user.name` / `user.email`)

`--global` = défaut pour tous les repos sur la machine ; sans `--global` =
un seul repo. **Cas concret** : aucune identité n'était configurée sur cette
machine, donc réglée en `--global`. Email choisi : l'adresse **noreply**
GitHub (`ID+login@users.noreply.github.com`) plutôt que l'adresse réelle —
un commit est public et permanent (même après suppression du repo, si
quelqu'un l'a cloné entre-temps), donc l'adresse réelle y reste visible pour
toujours si on la commite.

## `gh auth login` (device code) et `gh auth setup-git`

`gh auth login` authentifie le CLI `gh` (API GitHub) via un code à usage
unique saisi sur `github.com/login/device` — nécessaire car le CLI ne peut
pas ouvrir de fenêtre de connexion depuis un terminal distant. Mais `git
push`/`pull` (protocole Git pur, pas l'API GitHub) ne sait pas exploiter ces
identifiants tout seul : `gh auth setup-git` fait le pont en configurant Git
pour utiliser le token `gh` comme identifiant HTTPS. **Cas concret** :
`git push` a échoué avec "could not read Username" juste après un
`gh auth login` pourtant réussi — les deux authentifications sont
distinctes.

## Conventional Commits + lien avec le versioning sémantique

Préfixes (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `perf:`)
lisibles par des outils qui calculent le numéro de version suivant
automatiquement : `fix:` → PATCH, `feat:` → MINOR, `BREAKING CHANGE:` dans le
corps → MAJOR. **Cas concret** : premier commit du repo en `chore:`
(scaffolding pur, aucun comportement), les comptes-rendus de spikes en
`docs:`.

## `gh repo create --source=. --push`

Crée le repo GitHub, configure `origin`, et pousse `main` — en une commande
au lieu de créer sur github.com puis `git remote add` + `git push -u`
séparément. **Cas concret** : création de `dafffyl/timbre` juste après le
premier commit local.

## Secret scanning, push protection, Dependabot

Sur un repo public, secret scanning + push protection sont **actifs par
défaut** (rien à activer). Dependabot security updates nécessite d'abord
d'activer les alertes de vulnérabilité (`vulnerability-alerts`), puis les
corrections automatiques (`automated-security-fixes`) — deux appels API
distincts, le second échoue si le premier n'a pas été fait avant. **Cas
concret** : vérifié et activé juste après la création du repo Timbre.

## Protection de branche

Empêche le push direct sur `main` — tout passe par une PR. `enforce_admins:
true` : même le propriétaire du repo ne peut pas contourner la règle.
`required_approving_review_count: 0` : PR obligatoire, mais pas d'approbation
d'un second relecteur exigée (utile en solo — personne d'autre à qui
demander). **Cas concret** : configurée juste avant la première branche de
spike, pour être forcé à passer par une PR dès le premier essai.

## GitHub Flow et PR même en solo

Une PR n'est pas un mécanisme social (demander un avis) mais un **point de
contrôle** : voir le diff complet dans une interface faite pour ça, laisser
tourner la CI avant la fusion (pas après), garder un historique lisible et
daté. **Cas concret** : chaque spike (S0.1 à S0.4) et l'ADR-0001 sont passés
par une branche + PR + merge, jamais un push direct sur `main` (impossible de
toute façon, cf. protection de branche).

## Stratégies de merge : merge commit / squash / rebase

- **Merge commit** : garde tous les commits de la branche + un commit de
  fusion à deux parents.
- **Squash** : regroupe tous les commits de la branche en un seul, propre,
  sur `main`.
- **Rebase** : rejoue les commits un par un sur `main`, sans commit de
  fusion, historique linéaire mais hachages réécrits.

**Cas concret** : squash choisi pour toutes les PR de Timbre — cohérent avec
les Conventional Commits (un commit = un message de synthèse par PR), pas de
bruit de commits intermédiaires sur `main`.

## Resynchroniser après un merge distant

Un merge fait sur GitHub (bouton "Merge") ne met pas à jour la branche locale
`main` automatiquement. **Cas concret** : après chaque squash-merge, réflexe
`git checkout main && git pull` avant de continuer — sinon `main` en local
reste en retard sur `origin/main`.

## Supprimer une branche après un squash-merge

Après un squash-merge, `main` contient le même contenu que la branche
fusionnée mais sous un **nouveau hash de commit** (le squash recrée un
commit, il ne réutilise pas ceux de la branche). `git branch -d` compare en
général le contenu, pas seulement les hashs, donc ça a systématiquement
fonctionné sans forcer avec `-D` dans Timbre. Un message d'avertissement du
type *"deleting branch that has been merged to origin/X but not yet merged
to HEAD"** peut apparaître même quand la suppression réussit et que le
contenu est bien sur `main` — c'est un faux positif de l'heuristique de Git,
pas un signal d'alerte réel dans ce cas. Toujours suivi de
`git push origin --delete <branche>` pour nettoyer côté GitHub aussi (pas
automatique).

## Le piège de l'auto-staging Xcode

Xcode ajoute automatiquement à l'index Git (`git add` silencieux) tout
nouveau fichier créé dans un projet suivi par Git — y compris les projets
jetables des spikes, qu'on ne veut jamais commiter. **Cas concret** : réflexe
systématique à chaque spike, `git status` avant tout commit, puis
`git restore --staged <dossier>/` pour désindexer ce qui ne doit pas partir.
Résolu définitivement pour les dossiers connus en les ajoutant au
`.gitignore` (`TimbreSpike/`, `TimbreDiarizationSpike/`).

## ADR (Architecture Decision Record)

Un fichier numéroté par décision structurante : contexte, options
envisagées, décision, conséquences — une page max. Sert de référence écrite
pour ne pas avoir à retrouver une conversation ou un raisonnement passé.
**Cas concret** : `docs/adr/0001-architecture-clavier-telecommande.md`,
premier ADR du projet, fige les contraintes C1-C5 issues de la Phase 0.

## Erreur vécue : coder avant de créer la branche

Après le merge de S0.1, resté sur `main` sans créer de nouvelle branche avant
de commencer le code de S0.3 — repéré au `git status` avant le premier
commit (fichiers untracked alors qu'on aurait dû être sur une branche
dédiée). **Réparation** : `git restore --staged` puis `git checkout -b` créée
a posteriori mais **avant** le premier commit — aucune conséquence, la
protection de branche aurait de toute façon bloqué un push direct sur `main`
si on avait continué sans corriger.
