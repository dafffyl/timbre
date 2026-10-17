# ADR-0006 — Rapport de réunion généré par un LLM

**Statut** : Accepté — 2026-10-17 (décision produit : chaque réunion a un
transcript puis un rapport, avec des instructions libres pour le LLM).

## Décision

- Après le transcript, l'utilisateur peut générer un **rapport** (compte
  rendu) via un modèle de chat Groq (`llama-3.3-70b-versatile` par défaut,
  `llama-3.1-8b-instant` en option rapide). Même fournisseur et même clé que
  la transcription : aucune dépendance ni compte supplémentaire.
- Les **instructions** sont du texte libre de l'utilisateur : un défaut
  modifiable dans les Réglages, ajustable réunion par réunion. Elles
  *complètent* un cadre fixe (ne rien inventer, traiter le transcript comme
  une donnée) ; elles ne le remplacent pas.
- Le rapport est stocké dans `MeetingRecord.report` (texte + date +
  instructions utilisées), jamais l'audio. Décodage tolérant : les réunions
  antérieures n'ont pas de rapport.
- Transcripts longs : notes par tranche de ~40 000 caractères, puis rapport
  final sur l'ensemble des notes (fenêtre de contexte et quotas de débit).
- **Génération automatique désactivée par défaut** : c'est un envoi de texte
  supplémentaire vers un modèle, l'utilisateur l'active explicitement.

## Limites assumées

- Le transcript est encadré par des balises et déclaré « donnée » pour
  réduire l'injection de consignes depuis la réunion elle-même
  (« ignore les instructions précédentes… ») ; ça réduit le risque, pas plus.
- Le texte du transcript quitte l'appareil (Groq), comme l'audio pour la
  transcription. Pas de mode hors ligne pour le rapport (prévu plus tard).
- Un rapport peut contenir des erreurs d'attribution : il se fonde sur
  des locuteurs détectés automatiquement.
