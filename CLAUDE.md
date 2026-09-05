# Timbre

## Pitch

Clavier système de dictée (Groq Whisper par défaut, providers interchangeables)
+ transcripteur de réunions avec diarisation locale, en iOS/Swift 6 open source.
Le timbre est ce qui distingue deux voix sur la même note — le principe
acoustique que la diarisation exploite. Le nom décrit le mécanisme, pas l'usage.

## Identifiants

- Bundle ID app : `fr.dafffyl.timbre`
- Bundle ID extension : `fr.dafffyl.timbre.keyboard`
- App Group : `group.fr.dafffyl.timbre`
- Keychain Group : `$(AppIdentifierPrefix)fr.dafffyl.timbre`
- Préfixe packages Swift : `Timbre` (TimbreCore, TimbreAudio, TimbreTranscription,
  TimbreDiarization, TimbreSecurity, TimbreUI)

## Contraintes système (validées Phase 0, ADR-0001)

- **C1** — Le clavier ne peut JAMAIS toucher au micro, même avec Full Access.
  Confirmé S0.2 : `tccd` tue le process (`SIGABRT`) dès la demande
  d'autorisation, avant tout code applicatif. Aucun contournement possible.
- **C2** — Budget mémoire clavier. Limite dure mesurée : **77 Mo** (iPhone 12
  Pro, jetsam `per-process-limit`). **Cible de conception : 35-40 Mo** (marge
  pour appareils plus anciens non testés).
- **C3** — Full Access requis pour réseau + lecture App Group. Sans Full
  Access : clavier alphanumérique fonctionnel + invite claire, jamais de crash.
- **C4** — Groq ne diarise pas (timestamps mot seulement, 25 Mo max/fichier).
  Diarisation locale (FluidAudio) : confusion entre locuteurs détectés ~4%
  (excellent), DER global ~40% dominé par de la parole manquée sur locuteur
  loin du micro (pas un problème d'algorithme). Traitement 0,02x temps réel ;
  chargement des modèles CoreML ~23s, une fois par session, pas par réunion.
- **C5** — Aucune API publique pour revenir automatiquement à l'app hôte après
  un aller-retour clavier → app conteneur (bug Apple reconnu, FB22247647, sans
  solution). Le retour manuel doit être assumé dans l'UI, jamais promis comme
  automatique. Ouverture à chaud quasi instantanée (0,11s), à froid ~9s.
  **Nuance (ADR-0002)** : ça ne bloque que le retour visuel — un enregistrement
  démarré avant le passage en arrière-plan continue réellement (Background
  Mode Audio, confirmé par test), donc l'utilisateur peut revenir à son app
  d'origine pendant que ça enregistre encore.

## Architecture

```
Timbre/
├── App/                    SwiftUI. Seul propriétaire du micro et du réseau.
├── KeyboardExtension/      UIInputViewController, 0 dépendance tierce.
├── Packages/
│   ├── TimbreCore/         Modèles de domaine, DTO, protocoles. Zéro I/O.
│   ├── TimbreTranscription/  Abstraction provider + implémentations.
│   ├── TimbreAudio/        Capture, VAD, encodage, chunking.
│   ├── TimbreDiarization/  Wrapper FluidAudio + algo d'alignement. Zéro I/O.
│   ├── TimbreSecurity/     Keychain, App Group, redaction des logs.
│   └── TimbreUI/           Composants SwiftUI communs. PAS dans le clavier.
```

**Règle de dépendance (doit faire échouer le build si violée)** :
`KeyboardExtension` importe UNIQUEMENT `TimbreCore` et `TimbreSecurity`.

Canal clavier ↔ app : App Group (fichier partagé) + Darwin notifications pour
le signal. Le clavier ne fait jamais de réseau ni d'audio lui-même.

## Commandes

- **Build** (app + clavier) : ouvrir `Timbre.xcodeproj` dans Xcode, scheme
  `Timbre`, ▶️ Run sur un appareil physique (obligatoire, voir invariants).
  En CLI (ce que fait la CI) :
  `xcodebuild build -project Timbre.xcodeproj -scheme Timbre -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- **Tests des packages** : `cd Packages/<Nom> && swift test` (ex.
  `TimbreCore`, `TimbreTranscription`). Nécessite `xcode-select` pointé sur
  la vraie app Xcode, pas les Command Line Tools seules (sinon le framework
  `Testing` est introuvable).
- **Règle de dépendance du clavier** : `./scripts/check-keyboard-dependencies.sh`
- **Lint/format** : pas encore configuré.

⚠️ Après un changement de dossier/déplacement du repo : supprimer les
`.build/` de chaque package avant `swift test` (ils gardent des chemins
absolus en cache).

## Conventions

- **Commits** : Conventional Commits strict (`feat:`, `fix:`, `docs:`,
  `refactor:`, `test:`, `chore:`, `perf:`) — piloté par semver côté outils.
- **Branches** : GitHub Flow. Une branche par fonctionnalité/spike/doc, une PR
  par branche, même en solo. `main` protégée (PR obligatoire, pas de push
  direct, pas de force-push). Préfixes observés : `spike/`, `docs/`, `feat/`.
- **Swift** : Swift 6, concurrency stricte. `async/await` uniquement, pas de
  Combine sauf besoin démontré. `@Observable`, pas `ObservableObject`. Erreurs
  typées, jamais de `try?` silencieux. `@unchecked Sendable` interdit sans
  commentaire justifiant l'invariant. DI par protocole partout où il y a
  réseau/disque/horloge.
- **Tests** : Swift Testing (`@Test`, `#expect`), pas XCTest. `TimbreCore` et
  `TimbreDiarization` sont zéro-I/O : testables sur fixtures JSON pures.

## Invariants à ne jamais casser

- Clavier = télécommande. Jamais d'`AVAudioSession`/`AVAudioEngine` dans
  `KeyboardExtension`.
- `KeyboardExtension` : zéro dépendance tierce, zéro modèle ML.
- Clés API dans le Keychain uniquement (`AfterFirstUnlockThisDeviceOnly`, pas
  d'iCloud). Jamais dans `UserDefaults`, jamais dans le code, jamais loggées.
- Aucun contenu transcrit loggé en Release.
- Mesures de mémoire/latence/micro : toujours sur appareil physique, jamais
  simulateur — le simulateur ment sur ces trois points.
- `main` toujours verte : PR + CI avant merge, pas d'exception.

## Rôle de mentor GitHub

- Avant toute commande git/gh : expliquer ce qu'elle fait, pourquoi ici,
  l'alternative — puis exécuter. Jamais d'enchaînement silencieux.
- Erreur/bêtise git = occasion d'apprendre : expliquer le mécanisme, montrer
  la réparation, ne pas juste réparer.
- Tenir `docs/git-journal.md` à jour à chaque nouvelle notion Git/GitHub
  rencontrée, avec le cas concret où elle a servi.

## Méthode de travail

- Raisonnement à rebours : partir de l'objectif de l'étape, remonter jusqu'à
  la première action.
- Affirmation technique = toujours justifiée. Jamais de fait technique sans
  la raison derrière.
- Expert énergétique/thermo, à l'aise en info sans être développeur pro : pas
  de détail Swift trivial superflu, mais expliquer les mécanismes iOS non
  triviaux.
- Options multiples → présenter les compromis, laisser trancher. Ne jamais
  décider seul sur un choix structurant.
- Si une proposition est mauvaise, le dire franchement, avec les raisons.
- Petits incréments vérifiables : quoi a été fait, comment le vérifier dans
  Xcode, étape suivante.
- Emojis pertinents dans les réponses.
