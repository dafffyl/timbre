# S0.4 — Qualité de la diarisation locale

**Date** : 2026-08-26
**Statut** : ✅ Mesuré — bon signal global, une limite concrète identifiée.

## Question posée

Tester FluidAudio (diarisation locale, CoreML/ANE) sur un enregistrement réel
en français, plusieurs locuteurs, micro de téléphone. Mesurer un DER
approximatif et le temps de traitement, pour juger si le chemin "local par
défaut" (vs fallback cloud) est viable.

## Environnement de test

- **Appareil** : iPhone 12 Pro, physique
- **iOS** : 26.6 / **Xcode** : 26.2 (17C52)
- **Projet** : `TimbreDiarizationSpike` (jetable, non versionné)
- **Bibliothèque** : FluidAudio 0.12.4+ (SPM), pipeline offline
  "Pyannote Community-1"
- **Enregistrement** : 67,5s, 3 locuteurs réels (David, Sophie, Enola),
  micro de téléphone, Sophie éloignée du micro (niveau sonore faible)

## Méthode

`OfflineDiarizerManager` de FluidAudio exécuté sur le fichier converti en WAV
16 kHz mono. Vérité terrain établie a posteriori par écoute manuelle de
l'enregistrement (découpage approximatif des tours de parole par personne).
Comparaison segment par segment (point médian de chaque segment détecté
comparé à la vérité terrain).

## Résultat — performance

- **Chargement des modèles** : 22,76s (coût unique par lancement d'app, pas
  par réunion traitée)
- **Traitement** : 1,35s pour 67,5s d'audio — **ratio 0,02x temps réel**,
  très largement sous la contrainte temps réel
- **13 segments détectés**, répartis sur 3 locuteurs (S1/S2/S3)

## Résultat — qualité

Deux mesures distinctes, à ne pas confondre :

### 1. Discrimination des voix (confusion entre locuteurs détectés)

**Excellente.** Sur les 39s de parole effectivement détectées, un seul
segment (1,48s, le tout premier — "David" 1,19-2,67s) est mal attribué
(classé avec Sophie). Tout le reste s'aligne parfaitement sur une permutation
simple (S1→Sophie, S2→David, S3→Enola) : **taux de confusion ≈ 4%** parmi la
parole détectée.

### 2. DER approximatif global

**≈ 40%** — mais ce chiffre est dominé par de la **parole manquée**, pas par
de la confusion. Sur ~63s de parole réelle (vérité terrain), seulement ~39s
ont été détectées comme parole par le pipeline. L'essentiel du déficit vient
de **Sophie**, dont l'intervention (5-25s), à faible niveau sonore, semble
en grande partie passée sous le seuil de détection de voix (VAD) — traitée
comme du silence plutôt que mal attribuée à quelqu'un d'autre.

| Métrique | Valeur | Interprétation |
|---|---|---|
| Confusion entre locuteurs détectés | ~4% | Le moteur distingue très bien les voix qu'il capte |
| DER approximatif global | ~40% | Dominé par la parole manquée (locuteur loin du micro), pas par la confusion |

## Conclusion

Le mécanisme de diarisation lui-même — celui qui justifie le nom du projet —
fonctionne bien : quand une voix est détectée, elle est presque toujours
attribuée au bon locuteur. Le vrai risque pour l'usage réel n'est pas "le
système confond les gens", c'est **"le système perd purement et simplement
un locuteur trop loin du micro"** — exactement le scénario "téléphone posé
sur la table" que le protocole de test visait à vérifier.

## Limites de la mesure

- Un seul enregistrement, court (67,5s), 3 locuteurs — pas encore testé sur
  une vraie réunion longue avec chevauchements de parole ou plus de
  locuteurs.
- Vérité terrain approximative (découpage manuel à l'oreille, pas de
  transcription seconde par seconde).
- Pas encore de comparaison avec un fallback cloud (Deepgram) — reporté à la
  Phase 5, quand `DeepgramProvider` existera réellement dans l'architecture
  (plutôt que d'introduire un compte et une clé API supplémentaires pour ce
  seul spike jetable).

## Implication pour l'architecture

- La diarisation locale par défaut est **viable** : rapide (très sous le
  temps réel), et fiable sur la parole qu'elle détecte.
- Le risque produit à traiter n'est pas algorithmique mais **UX/capture** :
  prévoir un signal de qualité audio à l'enregistrement (ex. avertir si le
  niveau sonore d'un passage est trop faible), ou recommander explicitement
  à l'utilisateur de centraliser le téléphone entre les locuteurs.
- Le chargement des modèles (22,76s) doit être fait une fois par session
  d'usage, pas à chaque réunion — à anticiper dans l'architecture de
  `TimbreDiarization` (modèles chargés paresseusement puis conservés tant que
  l'app reste active, cohérent avec l'exigence de performance déjà posée).
- Comparaison avec Deepgram reportée à la Phase 5.

## Clôture de la Phase 0

Les 4 spikes (S0.1 mémoire, S0.2 micro, S0.3 aller-retour, S0.4 diarisation)
sont maintenant clos. Voir chaque document pour le détail ; synthèse globale
et arbitrage à faire avant de démarrer la Phase 1.
