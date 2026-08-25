# Timbre

Timbre est une application iOS open source qui combine deux fonctionnalités :

1. **Un clavier système de dictée** — accessible via la touche globe dans
   n'importe quelle app, qui transcrit la voix en texte et l'insère dans le
   champ actif.
2. **Un transcripteur de réunions avec diarisation** — import ou enregistrement
   d'une réunion, transcription horodatée avec identification des
   interlocuteurs (Locuteur 1, 2, 3…).

## D'où vient le nom

En acoustique, le **timbre** est ce qui permet de distinguer deux voix
émettant la même note — c'est le principe physique qu'exploite la
diarisation. Le nom décrit le mécanisme au cœur de l'app, pas son usage.

## État du projet

🚧 **Phase 0 — spikes de validation.** Avant de construire l'architecture,
quatre inconnues techniques doivent être levées (mémoire disponible pour une
extension clavier, faisabilité de la diarisation locale, latence du canal
clavier ↔ app, accès micro depuis une extension). Le détail est dans
[`docs/spikes/`](docs/spikes/) au fur et à mesure de leur résolution.

Rien n'est encore buildable — ce README sera étoffé (build, contribution,
architecture) à mesure que le projet avance.

## Licence

[MIT](LICENSE)
