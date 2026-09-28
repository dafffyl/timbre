# ADR-0003 — Algorithme d'alignement mots ↔ locuteurs, et chunking des longs enregistrements

**Statut** : Proposé — 2026-09-29. Rédigé de façon asynchrone (préparation de
nuit) : le code qui suit dans la même branche applique ce qui est décrit
ici, mais **rien n'est mergé** tant que les points signalés "🔶 à trancher"
n'ont pas été validés. Conformément à la consigne reçue, cette explication
vient avant le code, pas après.

## Contexte

Phase 4 : la transcription de réunion avec diarisation, le cœur du projet
(cf. `CLAUDE.md` — le timbre est ce qui distingue deux voix, principe que la
diarisation exploite). Deux briques indépendantes mais nécessaires
ensemble :

1. **L'alignement** : Groq (`TranscriptionWord`, horodatage mot par mot) et
   FluidAudio (segments locuteur horodatés) sont deux sources indépendantes
   — rien ne les relie nativement (C4, ADR-0001 : Groq ne diarise pas). Il
   faut un algorithme qui décide, pour chaque mot transcrit, à quel locuteur
   l'attribuer.
2. **Le chunking** : une réunion dépasse largement la limite de 25 Mo de
   Groq (ADR-0001, C4). Il faut découper l'audio, transcrire chaque morceau
   séparément, puis recoller les résultats en une seule timeline cohérente
   avant de les donner à l'alignement.

Cet incrément couvre **uniquement** ces deux algorithmes, en modules purs
(zéro I/O, testables sur fixtures), sans intégrer FluidAudio ni construire
d'UI — conformément à la consigne reçue.

## Modèle de domaine

```
SpeakerID           — identifiant opaque de locuteur (même schéma que
                       ProviderIdentifier dans TimbreTranscription)
SpeakerSegment       — { speaker: SpeakerID, start: TimeInterval, end: TimeInterval }
AttributedWord       — { word: TranscriptionWord, speaker: SpeakerID? }
                       (speaker nil = mot non attribuable, voir plus bas)

AudioChunkPlan       — { start: TimeInterval, end: TimeInterval }
```

`TranscriptionWord`/`TranscriptionResult` existent déjà dans
`TimbreTranscription` — réutilisés tels quels plutôt que dupliqués (ce sont
déjà des DTO indépendants de tout provider concret).

## 🔶 À trancher — répartition entre packages

L'architecture (`CLAUDE.md`) place "l'algo d'alignement" dans
`TimbreDiarization`. Mais le chunking/recollage ne concerne pas
spécifiquement la diarisation — un long dictaphone sans aucun locuteur à
identifier aurait le même besoin de découpage à 25 Mo. Proposition : garder
`TimbreDiarization` strictement pour ce qui est spécifique aux locuteurs
(`SpeakerID`, `SpeakerSegment`, `AttributedWord`, l'algorithme
d'alignement), et mettre le chunking/recollage dans `TimbreTranscription`
(à côté de `TranscriptionRequest`/`GroqProvider`, dont c'est le prolongement
naturel). C'est le découpage que j'ai implémenté dans le code qui suit —
mais c'est un choix structurant, pas une évidence : dis-moi si tu préfères
tout regrouper dans `TimbreDiarization` puisque c'est en pratique
Phase 4/réunions qui en a besoin en premier.

## Partie 1 — Algorithme d'alignement

### Principe retenu : overlap maximal

Pour chaque mot, on calcule son chevauchement temporel (en secondes) avec
chaque segment locuteur candidat, et on l'attribue au segment avec le plus
grand chevauchement. C'est l'approche standard en la matière (utilisée par
des outils comme WhisperX) — plus robuste qu'une règle "le mot appartient
au segment qui contient son instant de début", qui piège mal les mots
courts à cheval sur un changement de locuteur.

```
overlap(mot, segment) = max(0, min(mot.end, segment.end) - max(mot.start, segment.start))
```

### Cas limites, un par un

**1. Mot entièrement contenu dans un segment** — trivial, aucune ambiguïté.

**2. Mot à cheval sur une frontière entre deux segments** — ex. segment A
finit à 10,05 s, segment B commence à 10,05 s, le mot va de 10,00 à 10,20 s.
Overlap(A) = 0,05 s, overlap(B) = 0,15 s → attribué à B. C'est exactement le
cas que la règle "overlap maximal" est censée bien gérer, contrairement à
une règle basée sur l'instant de début seul.

**3. Mot dans un trou entre deux segments** (silence détecté par la
diarisation, ou — cas documenté par C4 — parole manquée parce que le
locuteur est trop loin du micro) — aucun overlap positif avec quoi que ce
soit. 🔶 **Décision proposée** : chercher le segment le plus proche
(distance temporelle du mot à ses bords) ; si cette distance est ≤ un
seuil de tolérance (`gapTolerance`, proposé à 1,0 s par défaut), attribuer
à ce segment le plus proche ; au-delà, laisser `speaker = nil`
("non attribué") plutôt que de deviner. Raison de ne PAS attribuer
systématiquement au plus proche, même loin : C4 dit que l'erreur dominante
de la diarisation locale est de la parole *manquée* (un locuteur entier
raté), pas de la mauvaise attribution — deviner à tout prix risquerait de
coller la parole d'un locuteur non détecté sur son voisin le plus proche,
ce qui serait pire qu'une case vide dans le transcript final.

**4. Parole superposée (deux locuteurs qui parlent en même temps)** — si
FluidAudio détecte et donne deux segments qui se chevauchent dans le temps,
un mot peut avoir un overlap positif avec les deux. La règle du overlap
maximal tranche, mais **c'est un plafond de qualité qu'aucun algorithme
d'alignement ne peut dépasser** : Whisper ne transcrit qu'*un* flux de mots
à partir d'un mélange acoustique de deux voix — il ne sépare pas les deux
locuteurs en amont. Le mot mal attribué (à l'un des deux locuteurs, jamais
aux deux) est donc une limite acceptée, pas un bug d'alignement. Point non
vérifié : je ne sais pas si FluidAudio détecte réellement le chevauchement
ou produit des segments toujours disjoints — à vérifier par un test dédié
une fois l'intégration commencée, pas quelque chose que l'algorithme seul
peut résoudre.

**5. Égalité exacte entre deux segments candidats** (overlap identique,
rare avec des horodatages flottants mais possible) — 🔶 **Décision
proposée** : préférer le locuteur du mot précédent immédiatement attribué
(continuité), sinon le segment qui commence en premier (règle de repli
déterministe). Objectif : éviter un battement de locuteur au milieu d'une
phrase sur une égalité qui n'a probablement aucun sens acoustique réel.

**6. Mot à durée nulle ou négative** (`start == end`, ou une incohérence
amont) — la formule d'overlap classique donne toujours 0 pour un
intervalle de largeur nulle, même s'il tombe pile dans un segment (un point
a une mesure nulle par définition). Sans traitement particulier, ces mots
seraient *systématiquement* non attribués, même en plein milieu d'un
segment évident. Traité séparément : pour un mot de durée nulle, le test
devient "est-ce que `segment.start <= mot.start < segment.end`" (contenance
d'un point), pas un calcul de recouvrement.

**7. Aucun segment du tout** (diarisation vide, ou échouée) — tous les mots
`speaker = nil`. Pas un cas d'erreur pour l'algorithme, un résultat valide.

**8. Aucun mot** (chunk silencieux) — liste vide en sortie, trivial.

**9. Segments non triés en entrée** — 🔶 traité défensivement (tri interne
avant tout calcul) plutôt que documenté comme précondition à la charge de
l'appelant : coût négligeable (tri de quelques dizaines de segments par
réunion), et ça supprime une classe entière de bugs d'appel.

**10. Locuteur qui change à chaque mot sur une courte série** (échange
rapide réel, ou artefact d'alignement) — **pas traité dans cet
incrément**. Un lissage (ex. ignorer un mot isolé entouré du même autre
locuteur des deux côtés) est une amélioration de qualité mesurable
seulement sur de vrais enregistrements de réunion — comme le "signal de
qualité audio" déjà repoussé à la Phase 6 dans ADR-0001, je préfère
construire l'algorithme brut d'abord et mesurer avant d'ajouter du
lissage spéculatif.

### Signature proposée

```swift
public enum SpeakerAlignment {
    public static func align(
        words: [TranscriptionWord],
        segments: [SpeakerSegment],
        gapTolerance: TimeInterval = 1.0
    ) -> [AttributedWord]
}
```

## Partie 2 — Chunking et recollage

### Découpage (`AudioChunker`)

Découpe une durée totale en tranches de durée maximale `maxChunkDuration`
(calculée ailleurs à partir de la limite 25 Mo de Groq et du bitrate du
format audio — voir plus bas), avec un recouvrement `overlap` entre
tranches consécutives pour ne jamais couper un mot ou une phrase pile sur
une frontière dure.

**Cas limites** :

- **Durée totale ≤ `maxChunkDuration`** — un seul chunk, pas de
  recouvrement à gérer (cas dégénéré qui doit rester simple, pas un cas
  particulier bricolé après coup).
- **Dernier reste trop court** — si le reste après le dernier chunk plein
  serait plus court que `overlap` lui-même, il n'apporterait presque aucun
  contenu réellement nouveau : absorbé dans le chunk précédent plutôt que
  de créer un chunk final minuscule.
- **`overlap >= maxChunkDuration`** — erreur de configuration de
  l'appelant, pas une donnée runtime à tolérer : `precondition`, pas un
  `throw` typé (cohérent avec la distinction du projet entre erreurs
  runtime typées et erreurs de programmation).

Aide annexe pour dériver `maxChunkDuration` à partir de la contrainte Groq :

```swift
public static func maxDuration(
    forBitrateBitsPerSecond bitrate: Double,
    sizeLimitBytes: Int,
    safetyMargin: Double = 0.9
) -> TimeInterval
```

`safetyMargin` (0,9 par défaut) : l'overhead du conteneur (AAC/MP4, + le
multipart HTTP) fait que la taille réelle du fichier dépasse légèrement le
calcul brut bitrate × durée — même logique de marge de sécurité que le
budget mémoire clavier (35-40 Mo visés pour une limite dure de 77 Mo, C2).
Avec l'AAC 32 kbps mono déjà en place (PR #17) et la limite de 25 Mo de
Groq : ≈ 93 minutes par chunk avant marge — largement suffisant pour la
plupart des réunions en un seul morceau, le chunking ne se déclenchant que
sur les cas vraiment longs.

### Recollage (`TranscriptStitcher`)

Chaque chunk est transcrit indépendamment, avec des horodatages de mots
*locaux* (0 = début du chunk). Recoller consiste à :

1. Décaler chaque mot par l'heure de début globale de son chunk.
2. Dans la zone de recouvrement entre deux chunks consécutifs (transcrite
   deux fois), choisir une seule version.

**Stratégie retenue (simple, volontairement pas la plus fine)** : couper au
milieu de la fenêtre de recouvrement — les mots du chunk N dont le début
global tombe avant ce point médian sont gardés, ceux du chunk N+1 dont le
début global tombe après sont gardés, le reste de chaque côté est
écarté.

**Limite assumée** : si le point de coupure tombe au milieu d'un mot ou
d'une phrase, le recollage peut perdre un mot ou en dupliquer un
légèrement différent (Whisper peut transcrire le même instant un peu
différemment selon le contexte de chaque chunk). Une stratégie plus fine
existe (aligner les deux séquences de mots qui se chevauchent, façon diff
de texte, pour trouver le meilleur point de coupe) mais c'est un
raffinement à construire seulement si la qualité au niveau des coutures
s'avère être un problème réel sur de vrais enregistrements — pas
spéculativement maintenant.

**Non couvert par ce module** : que faire si la transcription d'un chunk
échoue complètement (réseau, après épuisement des tentatives de
`RetryPolicy`). C'est une décision de la couche d'orchestration (Phase
suivante, "intégration FluidAudio et UI") — ce module pur suppose que tous
les chunks ont un résultat.

### Signature proposée

```swift
public enum AudioChunker {
    public static func plan(
        totalDuration: TimeInterval,
        maxChunkDuration: TimeInterval,
        overlap: TimeInterval
    ) -> [AudioChunkPlan]

    public static func maxDuration(
        forBitrateBitsPerSecond bitrate: Double,
        sizeLimitBytes: Int,
        safetyMargin: Double = 0.9
    ) -> TimeInterval
}

public enum TranscriptStitcher {
    public static func stitch(
        chunks: [(plan: AudioChunkPlan, words: [TranscriptionWord])]
    ) -> [TranscriptionWord]
}
```

## Conséquences

- `Packages/TimbreDiarization` créé pour la première fois (`SpeakerID`,
  `SpeakerSegment`, `AttributedWord`, `SpeakerAlignment`), dépend de
  `TimbreTranscription` pour réutiliser `TranscriptionWord`.
- `AudioChunker`/`TranscriptStitcher` ajoutés à `TimbreTranscription`
  (🔶 sous réserve du choix de répartition ci-dessus).
- Aucun des deux nouveaux modules n'est branché dans l'app ni dans
  `Timbre.xcodeproj` — ce sont des packages testables en isolation
  (`swift test`), pas encore consommés. Le branchement (FluidAudio +
  orchestration + UI) est la prochaine étape, après validation de cet ADR.
- `check-keyboard-dependencies.sh` n'a pas besoin de modification :
  `TimbreDiarization` y figure déjà dans la liste des packages interdits au
  clavier.

## Références

`docs/adr/0001-architecture-clavier-telecommande.md` (C4),
`Packages/TimbreTranscription/Sources/TimbreTranscription/TranscriptionResult.swift`
