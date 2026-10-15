# ADR-0005 — Pipeline complet de transcription de réunion

**Statut** : Proposé — 2026-09-30. Même principe que ADR-0003/0004 : ce
document vient avant le code dans la même branche.

## Contexte

Toutes les briques existent séparément et sont testées (ADR-0003 :
`SpeakerAlignment`, `AudioChunker`, `TranscriptStitcher` ; ADR-0004 :
`FluidAudioDiarizationProvider`, provisionnement des modèles). Il manque
l'enregistrement lui-même et l'orchestration qui relie tout ça. Décision
reçue : commencer par l'enregistrement live (pas l'import de fichier).

Deux points ont été vérifiés en faisant tourner du vrai code sur ce Mac
avant d'écrire ce document, même réflexe que pour FluidAudio (ADR-0004) :

1. **`AVAssetExportSession` async** — l'API que j'avais en tête au départ
   (`outputURL`/`outputFileType` en propriétés + callback) est **dépréciée**
   sur ce SDK, avec des avertissements explicites redirigeant vers
   `export(to:as:) async throws`. Testé avec le fichier réel du spike
   (`reunion.wav`, 67,54s) : `export.timeRange = CMTimeRange(...)` puis
   `try await export.export(to: outputURL, as: .m4a)` découpe correctement
   une tranche de 10s en 10,0s exportées, ~32 Ko. Retenue directement,
   l'ancienne API n'a pas été utilisée.
2. **`BackgroundRecorder` est réutilisable tel quel pour l'enregistrement de
   réunion** — son nom et ses commentaires sont écrits pour la dictée, mais
   `start()`/`stop()`/`currentLevel` ne dépendent d'aucun état spécifique à
   la dictée (le filet de sécurité de durée vit dans `DictationController`,
   pas dans `BackgroundRecorder` lui-même). Une seconde instance
   indépendante, avec son propre contrôleur et son propre filet de sécurité
   (beaucoup plus long), suffit — pas de duplication du code AVAudioEngine
   déjà écrit et débogué (conversion Float32, réglages AAC, calcul RMS).

## Décision structurante : la diarisation ne se découpe jamais

**Le chunking (limite 25 Mo, ADR-0003) ne s'applique qu'à la transcription
Groq — jamais à la diarisation.** Raison : FluidAudio attribue des
identifiants de locuteur (`S1`, `S2`…) **relatifs à un seul appel**
`process()`. Diariser chunk par chunk donnerait des `S1` incohérents d'un
chunk à l'autre (le `S1` du chunk 2 pourrait être une personne différente du
`S1` du chunk 1) — un problème de ré-identification inter-chunks bien plus
dur que le simple recollage de texte. La diarisation locale n'a de toute
façon pas la contrainte de taille de Groq (traitement local, pas d'upload) :
elle tourne **une seule fois sur le fichier complet**.

Ça donne un pipeline en deux branches qui se rejoignent :

```
Fichier réunion complet
        │
        ├──────────────────────────────┐
        ▼                               ▼
  diarize() une fois              chunker (25 Mo) → exporter chaque
  sur tout le fichier             tranche (AVAssetExportSession) →
        │                          transcrire chaque tranche (Groq)
        │                                       │
        │                          TranscriptStitcher.stitch(...)
        │                                       │
        ▼                                       ▼
  [SpeakerSegment]                       [TranscriptionWord]
        └───────────────┬───────────────────────┘
                         ▼
           SpeakerAlignment.align(words:segments:)
                         ▼
              groupement en tours de parole
                         ▼
                Transcript final affiché
```

Les deux branches (diarisation, chunking+transcription) sont indépendantes
l'une de l'autre — exécutées **concurremment** (`async let`) plutôt que
l'une après l'autre, pour ne pas payer deux fois le temps d'attente sur une
longue réunion.

## Enregistrement (`MeetingRecordingController`)

Nouveau contrôleur, pas une modification de `DictationController` (flux
différent : pas de clavier, pas d'App Group, une seule longue session plutôt
que des allers-retours courts). Réutilise `BackgroundRecorder` par une
nouvelle instance dédiée.

**Filet de sécurité de durée** : 4h (contre 180s pour la dictée) — une vraie
réunion peut durer longtemps, le risque à couvrir ici n'est pas une dictée
qui déraille mais un oubli d'arrêter l'enregistrement.

## Découpage + export (nouveau, dans le contrôleur d'orchestration)

Pour chaque `AudioChunkPlan` produit par `AudioChunker.plan` :
1. `AVAssetExportSession(asset:, presetName: AVAssetExportPresetAppleM4A)`,
   `timeRange` réglé sur le plan.
2. `export(to:as:) async throws` vers un fichier temporaire.
3. Lire les octets, transcrire via `GroqProvider`, supprimer le fichier
   temporaire.

`AudioChunker.maxDuration` utilise le bitrate réel de nos propres
enregistrements (32 kbps, celui de `BackgroundRecorder`) — pas une
estimation, puisqu'on contrôle nous-mêmes tout l'encodage de bout en bout
(pas d'import de fichier externe à ce stade).

### Cas limites

**1. Une transcription de chunk échoue après épuisement des tentatives**
(`RetryPolicy` déjà en place dans `GroqProvider`) — **révisé** : la décision
initiale ("faire échouer toute la réunion") est remplacée par une
dégradation par chunk. Raison du changement : perdre 40 minutes de
traitement sur une longue réunion à cause d'un seul chunk sur six qui a
raté un appel réseau est disproportionné par rapport au coût de dégrader
juste ce chunk-là. Chaque chunk (export **et** transcription) est tenté
indépendamment ; un échec insère un mot-marqueur
(`"[transcription indisponible]"`) à la place du texte de ce chunk plutôt
que d'interrompre le pipeline, et le résultat final signale qu'il est
partiel. Le marqueur, une fois aligné avec les locuteurs comme n'importe
quel mot, reste visible en clair dans le transcript ("Locuteur 2 :
[transcription indisponible]") — pas de trou silencieux qui donnerait
l'impression d'un résultat complet.

**2. La diarisation échoue** (modèles pas prêts — ne devrait pas arriver si
`DiarizationSetupView` a fait son travail avant, mais pas garanti si
l'utilisateur enchaîne sans repasser par cet écran — ou erreur FluidAudio en
cours de route) — **reste** un échec de toute la réunion, contrairement au
cas 1 : la nature du problème diffère (un souci de configuration/environnement
plutôt qu'un aléa réseau ponctuel sur un appel parmi plusieurs). Alternative
envisagée et écartée : dégrader vers un transcript sans locuteurs identifiés.
Écartée parce que ça masquerait un vrai problème (modèles non prêts) derrière
un résultat qui a l'air de fonctionner mais ne fait pas ce que l'utilisateur
attend (distinguer les locuteurs — la raison d'être du produit).

**3. Réunion avec un seul locuteur, ou diarisation qui ne détecte qu'un seul
segment** — fonctionne sans cas particulier : tous les mots s'alignent sur
l'unique segment, un seul tour de parole en sortie.

**4. Aucun mot transcrit du tout** (réunion silencieuse, ou micro
défaillant) — transcript avec zéro tour de parole ; l'écran de résultat doit
afficher un état vide explicite plutôt qu'un écran blanc.

## Regroupement en tours de parole

Nouvelle fonction pure, testable : regrouper une suite de `AttributedWord`
(déjà triée chronologiquement par construction de `SpeakerAlignment.align`)
en tours — chaque tour est une suite maximale de mots consécutifs partageant
le même locuteur (`nil` inclus : une suite de mots non attribués forme aussi
son propre tour, affiché comme tel plutôt que rattaché arbitrairement au
tour précédent ou suivant).

```swift
public struct SpeakerTurn: Sendable, Equatable {
    public let speaker: SpeakerID?
    public let text: String
}

public enum TranscriptFormatter {
    public static func groupIntoTurns(_ words: [AttributedWord]) -> [SpeakerTurn]
}
```

Vit dans `TimbreDiarization` (opère sur `AttributedWord`, déjà là-bas).

## Ce qui n'est toujours pas dans cet incrément

- L'affichage final n'aura pas la refonte visuelle prévue plus tard —
  fonctionnel d'abord, comme le reste.
- Pas de sauvegarde/historique des réunions transcrites — chaque
  transcription vit le temps de l'écran, perdue si on quitte. Un
  raffinement futur évident, pas construit tant que le pipeline de base
  n'a pas été validé sur un vrai enregistrement complet.
- Pas de renommage des locuteurs par l'utilisateur ("S1" → "Sophie") —
  affichage brut des identifiants de FluidAudio pour l'instant.

## Références

`docs/adr/0003-alignement-diarisation-et-chunking.md`,
`docs/adr/0004-integration-fluidaudio.md`
