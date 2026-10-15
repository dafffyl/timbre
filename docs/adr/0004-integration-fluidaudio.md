# ADR-0004 — Intégration FluidAudio et provisionnement des modèles

**Statut** : Proposé — 2026-09-29. Même principe que ADR-0003 : ce document
vient avant le code dans la même branche, et rien n'est mergé avant lecture.

## Contexte

Suite de ADR-0003 : l'algorithme d'alignement et le chunking existent,
purs et testés. Reste à brancher le vrai moteur de diarisation (FluidAudio)
derrière l'abstraction `DiarizationProvider`, comme `GroqProvider` le fait
pour `TranscriptionProvider`.

Avant d'écrire une ligne de code d'intégration, j'ai fait tourner FluidAudio
pour de vrai sur ce Mac (le package supporte macOS, pas besoin d'un iPhone
pour ce test précis) — même réflexe que les spikes de Phase 0 : vérifier
plutôt que supposer. Ça a changé la donne.

## Ce que j'ai mesuré, pas supposé

En rejouant l'appel exact déjà validé dans `TimbreDiarizationSpike`
(`OfflineDiarizerManager` + `OfflineDiarizerConfig`, FluidAudio 0.15.6, même
`Package.resolved` que le spike) :

| Constat | Valeur | Source |
|---|---|---|
| `prepareModels()` à froid (1er lancement, ce Mac) | 16,15 s (téléchargement + compilation CoreML) | mesuré |
| `prepareModels()` à chaud (2e lancement, process relancé) | 0,12 s | mesuré |
| Poids du cache modèles sur disque | 482 Mo | mesuré (`du -sh`) |
| `process()` sur l'enregistrement de test (67,5 s) | 1,59 s à froid, 0,49 s à chaud | mesuré, cohérent avec S0.4 (1,35 s) |

**Deux points nouveaux par rapport à C4 (ADR-0001), qui n'avait mesuré tout
ça que sur une seule session iPhone** :

1. **Les modèles ne sont pas embarqués dans le package — ils se
   téléchargent au premier `prepareModels()`.** Le mécanisme local par
   défaut a donc une dépendance réseau cachée à son tout premier usage,
   jamais mentionnée jusqu'ici.
2. **Le cache survit à un relancement du process, pas seulement à la
   session.** Sur ce Mac, un second lancement (nouveau process, pas la même
   session) retrouve les modèles déjà compilés en cache disque
   (`Application Support`, pas `Caches` — non purgé automatiquement par le
   système). 🔶 **Pas encore confirmé sur iPhone** avec un vrai cycle
   kill/relance de l'app — à vérifier en marchant, mais si ça se confirme,
   le coût de 22,76 s mesuré en S0.4 serait payé une fois par installation,
   pas une fois par session comme la formulation actuelle de C4 le laisse
   entendre.
3. **482 Mo est gros** — jamais mesuré ni discuté avant ce test. Ça change
   le compromis : la diarisation "locale" a un coût réseau et de stockage
   non négligeable à son premier usage, à assumer explicitement dans le
   produit plutôt qu'à découvrir en usage réel.

## Décision reçue

Sur la question posée directement ("comment gérer le téléchargement
initial ?") : **Wi-Fi obligatoire + consentement explicite**. Pas de
téléchargement sur cellulaire, jamais sans un accord explicite de
l'utilisateur au préalable.

## Modèle de domaine

```
DiarizationProvider          — protocole, même schéma que TranscriptionProvider
FluidAudioDiarizationProvider — implémentation concrète (actor), wrap OfflineDiarizerManager

NetworkConnectionType        — .wifi / .cellular / .other / .unavailable
NetworkStatusProvider        — protocole pour interroger le type de connexion courant

ModelProvisioningState       — .ready / .needsConsent / .needsWiFi / .failed
ModelProvisioningStateStore  — protocole pour lire/écrire consentement + succès passé
ModelProvisioningCoordinator — orchestre la logique ci-dessous (actor)
```

**Correction en écrivant l'UI** : un état `.downloading` était prévu ici à
l'origine, retiré avant l'implémentation. `ensureModelsReady()` est un seul
appel bloquant qui ne rend la main qu'au résultat final (`.ready`/`.failed`)
— il n'y a pas d'état intermédiaire que le coordinateur pourrait réellement
produire, et `OfflineDiarizerManager.prepareModels()` (vérifié dans le
source de FluidAudio) n'accepte pas de callback de progression. L'attente
(~16s au premier téléchargement) est signalée par un simple indicateur "en
cours" côté vue, pas par un état du domaine.

## Logique de `ModelProvisioningCoordinator`

```
ensureModelsReady() :
  si hasCompletedProvisioningBefore → tenter prepareModels() directement
  sinon si !hasConsentedToDownload → .needsConsent
  sinon si connexion courante != wifi → .needsWiFi
  sinon → tenter prepareModels()

tenter prepareModels() :
  succès → mémoriser hasCompletedProvisioningBefore = true, retourner .ready
  échec → .failed(message)

grantConsent() : mémoriser le consentement, puis rejouer ensureModelsReady()
```

### Cas limites

**1. Modèles déjà provisionnés avec succès une fois** — court-circuite tout
le reste (pas de nouvelle vérification Wi-Fi/consentement à chaque
diarisation, juste au tout premier succès). 🔶 **Limite assumée** : ce
qu'on sait, c'est "on a nous-mêmes déjà réussi une fois sur cet appareil" —
pas "FluidAudio a réellement encore les fichiers en cache" (ex. si
l'utilisateur libère de l'espace disque entre-temps). Une détection plus
précise supposerait une API FluidAudio pour vérifier l'état du cache sans
déclencher de téléchargement — pas trouvée en testant l'API existante,
possible qu'elle existe ailleurs dans le package et n'a pas été cherchée
plus loin pour cet incrément. Si ce cas se présente en usage réel (modèles
supprimés hors de notre contrôle), `prepareModels()` re-téléchargera de
lui-même sans notre gate — pas d'échec silencieux, juste un aller-retour
réseau inattendu la fois suivante.

**2. Consentement donné mais pas sur Wi-Fi au moment de l'appel** —
`.needsWiFi`, jamais de dérogation automatique. L'utilisateur devra relancer
une fois sur Wi-Fi ; pas de file d'attente "télécharge dès que le Wi-Fi
revient" dans cet incrément (ajouterait un vrai mécanisme de arrière-plan
pour un gain incertain — à reconsidérer si ça s'avère frustrant à l'usage).

**3. `prepareModels()` échoue après consentement + Wi-Fi confirmés**
(coupure réseau en cours de téléchargement, erreur FluidAudio) —
`.failed(message)`, `hasCompletedProvisioningBefore` reste `false` : la
prochaine tentative repart proprement de `.needsWiFi`/`.needsConsent` selon
l'état, pas bloquée dans un état d'échec permanent.

**4. Type de connexion "autre" (ex. partage de connexion, VPN)** —
🔶 **Décision proposée** : traité comme non-Wi-Fi par défaut (`.needsWiFi`),
la position la plus prudente vu qu'on ne peut pas garantir l'absence de
coût data. Le VPN mérite une mention à part : l'app a déjà eu un faux
positif ce week-end où Proton VPN causait un 403 sur l'API Groq (réseau
filtré/bloqué par le VPN, sans rapport avec la diarisation) — pas le même
mécanisme ici (`NetworkStatusProvider` regarde le type d'interface, pas si
elle fonctionne), mais un rappel que "connecté" ne garantit pas "ça va
marcher".

**5. Grant de consentement alors que `hasCompletedProvisioningBefore` est
déjà vrai** — cas qui ne devrait pas se produire dans le flux normal (l'UI
ne demanderait pas de consentement si déjà prêt), mais `grantConsent()`
reste correct dans ce cas : il rejoue `ensureModelsReady()`, qui
court-circuite immédiatement sur le cas 1.

## Répartition entre packages

`DiarizationProvider`, `FluidAudioDiarizationProvider`,
`NetworkStatusProvider`, `ModelProvisioningCoordinator` et les types
associés vont dans `TimbreDiarization` — aux côtés de `SpeakerAlignment`.

🔶 **Ça révise la description "zéro I/O" de `TimbreDiarization`** dans
`CLAUDE.md`. Précédent direct dans ce même projet : `TimbreTranscription`
mélange déjà des DTO purs (`TranscriptionRequest`) et un provider qui fait
du réseau (`GroqProvider`) dans un seul package, organisé par domaine
(transcription) plutôt que par "pureté". Je propose d'aligner
`TimbreDiarization` sur ce même principe — un package par domaine, la
pureté étant une propriété par fichier/type (`SpeakerAlignment` reste
zéro I/O), pas par package entier — et de corriger la phrase dans
`CLAUDE.md` en conséquence plutôt que de la laisser fausse.

## Ce qui n'est PAS dans cet incrément

- Le dialogue de consentement lui-même (SwiftUI) — ce module expose l'état
  (`ModelProvisioningState`) et une action (`grantConsent()`), l'UI qui les
  affiche/déclenche reste à construire, comme convenu ("l'intégration
  FluidAudio et l'UI viennent après" l'alignement — on est dans
  l'intégration, pas encore dans l'UI).
- L'implémentation concrète de `ModelProvisioningStateStore` côté app
  (`UserDefaults`, même schéma que `DictationPreferences`) — pas de raison
  de l'écrire avant d'avoir un vrai appelant (l'UI) pour la brancher.
- Un test automatisé qui appelle réellement `FluidAudioDiarizationProvider`
  (réseau + téléchargement de 482 Mo en CI, hors de question) — vérifié
  manuellement sur ce Mac comme décrit plus haut, jamais en CI. Même
  logique que "mesures de mémoire/latence/micro : toujours sur appareil
  physique, jamais simulateur" (`CLAUDE.md`) appliquée ici au réseau : un
  fait vérifié à la main, documenté, pas rejoué automatiquement.
- La vérification sur iPhone du point 2 (persistance du cache au
  relancement) — à faire en marchant à la prochaine session sur device.

## Références

`docs/spikes/diarization-quality.md` (S0.4), `TimbreDiarizationSpike/`
(code source de référence), `docs/adr/0003-alignement-diarisation-et-chunking.md`
