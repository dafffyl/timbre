# Diarisation sur AMI, micro distant

**Date** : 2026-10-26. Complète `diarization-quality.md` (S0.4, un seul
enregistrement de 67 s) avec un jeu de données public annoté.

## Question

La séparation des voix est jugée mauvaise sur un test réel. Est-ce un
problème de réglage, de repli d'attribution des mots, ou une limite du
modèle ? Banc : `scripts/diarization-bench/`.

## Données

AMI (CC-BY-4.0), réunions de 4 personnes, **micro distant** `Array1-01`
(proxy d'un téléphone posé sur la table) : ES2004a, IS1009a, TS3003a,
EN2002a (jeu de test). Référence : RTTM `AMI-diarization-setup`.

## Résultats

DER (collar 0,25 s) avec la configuration actuelle (défaut) :

| Réunion | DER | Parole manquée | Fausse alarme | Confusion | Locuteurs trouvés |
|---|---|---|---|---|---|
| ES2004a (micro-casque, pour mémoire) | 10,4 % | 7,5 | 1,6 | 1,4 | 4/4 |
| ES2004a | 19,2 % | 15,4 | 2,2 | 1,6 | 4/4 |
| IS1009a | 15,6 % | 10,3 | 2,2 | 3,1 | 4/4 |
| TS3003a | 19,1 % | 13,5 | 0,9 | 4,7 | **2/4** |
| EN2002a | 27,5 % | 23,2 | 0,3 | 4,1 | 5/4 |

- **La parole manquée domine** (comme en S0.4) ; la confusion entre voix
  détectées reste faible (1,6 à 4,7 %).
- **Aucun réglage n'aide** : seuil de regroupement (0,5/0,8), zeroVoteReembed,
  gain adaptatif (AGC : *pire*, 27 % sur ES2004a). `exclusiveSegments=false`
  (segments qui se chevauchent) est meilleur ou égal sur les 4 réunions
  (EN2002a 27,5 → 21,1 %) mais augmente la confusion ; non adopté (l'attribution
  des mots ne s'en trouve presque pas améliorée, +0,5 point).
- **Forcer le nombre de locuteurs** n'aide pas et peut aggraver : TS3003a passe
  de 19,1 à 42,4 % de DER avec `numSpeakers=4`.
- Second moteur FluidAudio (Sortformer) sur l'enregistrement du spike : 47 s de
  parole détectée contre 39 s, mais avec des chevauchements parasites ; pas
  clairement meilleur.

### Attribution des mots (hors chevauchements)

| Réunion | correct | faux | non attribué |
|---|---|---|---|
| ES2004a | 90,7 % | 3,6 % | 5,8 % |
| IS1009a | 93,2 % | 6,2 % | 0,6 % |
| TS3003a | 86,4 % | 7,4 % | 6,1 % |
| EN2002a | 89,3 % | 8,8 % | 1,9 % |

Règles de repli (tolérance 3 s, « toujours le plus proche », encadrement par
le même locuteur) : elles transforment des « non attribué » en erreurs, sans
gain net.

### Essai : réassigner les passages manqués par la voix

Empreinte (`DiarizerManager.extractSpeakerEmbedding`) des zones parlées mais non
détectées, rattachées au locuteur le plus proche : mots corrects
+1,9 / 0 / **−2,5** / +0,4 points selon la réunion. Sans gain fiable ; **abandonné**.

## Mesure de bout en bout (tcpWER), 2026-10-26

Chaîne de Timbre (Whisper large-v3 + diarisation FluidAudio + alignement de
l'app) sur les mêmes 4 réunions, références AMI (jeu de test), outil
`meeteval`. Trois scénarios isolent la source d'erreur :

| Réunion | Whisper seul (cpWER) | + diarisation parfaite | **Chaîne actuelle** (cpWER / tcpWER) | mots réf. |
|---|---|---|---|---|
| ES2004a | 34,1 % | 39,5 % | 43,2 % / 45,9 % | 2 630 |
| IS1009a | 31,0 % | 37,4 % | 37,8 % / 41,3 % | 1 995 |
| TS3003a | 37,3 % | 41,2 % | 42,6 % / 47,8 % | 2 531 |
| EN2002a | 42,0 % | 52,4 % | 53,5 % / 56,1 % | 7 621 |
| **Moyenne pondérée** | **38,3 %** | **46,2 %** | **47,7 % / 50,9 %** | 14 777 |

Lecture :
- **La transcription seule coûte ~38 %** en micro distant : c'est le premier
  poste (biais : le texte de référence contient les « uh/um » que Whisper omet).
- **Attribuer les mots à des locuteurs coûte +8 points même avec une
  diarisation parfaite** : les mots dits pendant un chevauchement ne peuvent
  être donnés qu'à une personne. Limite structurelle d'une chaîne
  « ASR sur le mélange + diarisation ».
- **Notre diarisation réelle n'ajoute que 1,5 point (cpWER) / 2,4 points
  (tcpWER)** à la diarisation parfaite : améliorer le moteur de diarisation a
  un plafond de gain faible.
- Ordre des leviers : qualité de la transcription et de la capture ≫
  chevauchements ≫ moteur de diarisation.

### Comparatif de moteurs : Parakeet TDT v3 (FluidAudio, sur l'appareil) contre Whisper large-v3

Mêmes audio, mêmes références, même diarisation, même alignement ; seule la
transcription change. Moyennes pondérées par les mots de référence (14 777,
ou 14 252 une fois les hésitations retirées).

| Moyenne | Whisper | Parakeet v3 | Écart |
|---|---|---|---|
| ASR seul, cpWER | 38,3 % | 33,3 % | −5,0 |
| Chaîne complète, cpWER | 47,7 % | 42,4 % | −5,3 |
| Chaîne complète, tcpWER | 50,9 % | 45,2 % | −5,7 |
| *Sans hésitations* : ASR seul, cpWER | 36,3 % | 32,2 % | −4,1 |
| *Sans hésitations* : chaîne, cpWER | 46,2 % | 41,5 % | −4,7 |
| *Sans hésitations* : chaîne, tcpWER | 49,5 % | 44,3 % | −5,2 |

- Parakeet est meilleur sur **chacune des 4 réunions**, avec et sans
  hésitations (la référence contient « uh/um » que Parakeet transcrit et
  Whisper omet : retirées des deux côtés, l'avantage passe de ~5 à ~4-5 points).
- Vitesse sur Mac M4 : 7 s pour 14 min d'audio (~120× le temps réel) ; Whisper
  large-v3 (whisper.cpp, Metal) : 103 s pour la même réunion.
- Parakeet donne des jetons horodatés avec confiance ; pas de boucle
  d'hallucination observée (Whisper en a une sans `-mc 0`).
- **Limites** : anglais, AMI, Mac. Rien n'est mesuré en **français réel**, ni
  sur iPhone (vitesse, mémoire, chaleur), ni contre l'API Groq elle-même.
  À confirmer sur l'audio réel avant tout changement de moteur dans l'app.

Piège : `whisper-cli -ml 1 -sow` duplique du texte ; sans `-mc 0`, Whisper boucle
(×2 de mots). Les deux ont d'abord faussé la mesure.

## Mise en garde

Une première mesure comptait les mots dits pendant un chevauchement de parole
(très fréquents dans AMI) : elle donnait ~20 % de mots faux, un artefact. Ne pas
la reprendre.

## Conclusion

Sur ce corpus, la configuration actuelle est proche du mieux que FluidAudio
fait ; ni réglage, ni repli, ni réassignation par voix ne l'améliore de façon
fiable. Le mauvais résultat observé sur un test réel (2 personnes, même pièce,
téléphone posé) n'est **pas expliqué** par ces données : il faut l'audio réel
(`DebugAudioRetention`, PR #49) avec une vérité terrain notée à la main.
