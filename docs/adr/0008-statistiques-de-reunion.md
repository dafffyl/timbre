# ADR-0008 — Statistiques de réunion et de participants

**Statut** : Proposé — 2026-10-21. Même principe que les ADR précédents : ce
document vient avant le code, dans la même branche. Numéro 0008 (et non 0006)
pour ne pas entrer en collision avec les ADR-0006/0007 des PR #43/#44, encore
ouvertes.

## Contexte

Une réunion transcrite ne garde que ses `turns` (`SpeakerTurn` : locuteur,
texte, `start`/`end` optionnels) et ses `speakerNames` (ADR-0005). C'est
suffisant pour en tirer des statistiques sans rien stocker de plus, sans
réseau, et sans toucher au modèle persisté : tout est **dérivé**, recalculé à
l'ouverture.

## Décisions

1. **Calcul pur dans `TimbreDiarization`** (`MeetingStats.compute(turns:)`),
   zéro I/O, testé sur des tours construits à la main — même régime que
   l'algo d'alignement (ADR-0003). L'interface ne fait que présenter.
2. **Rien n'est persisté.** Une stat enregistrée devient fausse dès qu'on
   change l'algo ou qu'on renomme un locuteur ; recalculer coûte quelques
   millisecondes même pour une réunion de plusieurs heures (un passage
   linéaire sur les tours).
3. **Dégradation sans horodatage.** Les réunions antérieures à l'introduction
   de `start`/`end` n'ont que le texte : on calcule alors seulement ce qui en
   dépend (mots, parts de mots, mots-clés, titres basés sur les mots). Frise,
   rythme, interruptions et délais de réaction sont absents
   (`hasTimings == false`), jamais inventés.
4. **Le temps de parole d'un tour = `end - start`**, pauses internes
   incluses. Les tours ne se chevauchent pas (ils sortent de
   `TranscriptFormatter.groupIntoTurns`, qui attribue chaque mot à un seul
   locuteur) : un vrai chevauchement de voix n'est donc pas observable.
5. **Interruption = heuristique, pas mesure.** Un changement de locuteur avec
   un silence ≤ 0,3 s est compté comme coupure de parole (le nouveau
   locuteur interrompt le précédent). La diarisation (DER ~40 %, voir C4)
   rend la frontière imprécise : l'interface les présente comme *indicatives*.
6. **Équilibre de parole** = entropie de Shannon des parts de parole,
   normalisée par `ln(n)` et ramenée à 0-100. Raison : vaut 100 quand tout
   le monde parle autant, 0 quand une seule personne parle, et reste
   comparable quel que soit le nombre de participants (une simple variance
   ne l'est pas).
7. **Titres ludiques déterministes** : règles et seuils fixes, un titre par
   personne et une personne par titre, attribués dans un ordre de priorité
   fixe, uniquement s'il y a au moins 2 participants. Le package ne renvoie
   qu'un `enum` ; les libellés (fr/en) vivent côté app.
8. **Localisation** : les textes de cette fonctionnalité sont dans un
   catalogue séparé (`App/Stats.xcstrings`, table `Stats`) plutôt que dans
   `Localizable.xcstrings` (PR #45, non mergée). Évite un conflit de fusion
   sur un fichier de 1 600 lignes ; fusionnable plus tard si souhaité.
9. **Deux PR.** (1) Stats de réunion et de participants (cette ADR).
   (2) « Moi au fil du temps » : suivi inter-réunions, qui dépend de la
   reconnaissance des voix (#44) car les `SpeakerID` ne sont pas comparables
   d'une réunion à l'autre (ADR-0005).

## Conséquences

- Aucune migration, aucun nouveau champ dans `MeetingRecord`.
- Les mots-clés reposent sur des listes de mots vides fr/en maintenues à la
  main : approximatif, volontairement simple (pas de NLP).
- Les stats sont aussi précises que la diarisation : un locuteur « fantôme »
  créé par une erreur de diarisation apparaîtra comme participant.
