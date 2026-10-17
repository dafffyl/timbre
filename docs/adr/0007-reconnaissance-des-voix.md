# ADR-0007 — Reconnaissance des voix connues

**Statut** : Accepté — 2026-10-17 (décision produit : reconnaître d'une
réunion à l'autre les personnes déjà nommées). Seuils **non calibrés** (voir
Limites).

## Contexte

ADR-0005 notait que les identifiants de locuteur (`S1`, `S2`…) ne sont
cohérents qu'au sein d'une seule diarisation : « pas de mapping global entre
réunions ». La reconnaissance des voix contourne cette limite sans toucher à
ces identifiants : elle compare des **empreintes vocales** (embeddings de
FluidAudio, déjà calculés pendant la diarisation, aucun modèle ni coût en
plus) à celles de personnes que l'utilisateur a nommées.

## Décision

- **Empreinte par locuteur** : moyenne des embeddings de ses segments,
  pondérée par leur durée, normalisée. `DiarizationProvider.diarizeDetailed`
  la renvoie avec les segments (valeur par défaut vide pour un moteur sans
  embeddings).
- **Apprentissage** : quand l'utilisateur nomme un locuteur, son empreinte
  rejoint (moyenne pondérée par la durée de parole, plafonnée à 10 min de
  poids pour qu'un profil reste capable d'évoluer) ou crée le profil de ce
  nom. Pas d'apprentissage sur les reconnaissances automatiques : évite la
  dérive d'un profil par ses propres erreurs.
- **Reconnaissance** : similarité cosinus. Un locuteur n'est nommé que si
  la similarité dépasse un seuil (0,65), s'il est nettement plus proche de
  son meilleur profil que du suivant (marge 0,05), et si chaque profil n'est
  attribué qu'à un seul locuteur. Les noms sont pré-remplis ; l'utilisateur
  corrige d'un tap, comme n'importe quel renommage.
- **Donnée biométrique (RGPD, art. 9)** :
  - désactivée par défaut, **consentement explicite** à l'activation (rappel
    d'informer les participants et d'obtenir leur accord) ;
  - stockage **local uniquement** (jamais envoyé : ni à Groq, ni ailleurs),
    fichiers en `.completeFileProtection`, exclus des sauvegardes, séparés de
    l'historique des réunions (qui s'exporte et se partage) ;
  - suppression d'une voix, de toutes les voix (profils **et** empreintes de
    chaque réunion), et suppression automatique des empreintes d'une réunion
    effacée.

## Limites assumées

- Les seuils sont des valeurs initiales, **pas calibrées** sur un jeu de voix
  réelles ; ils favorisent la prudence (laisser « Locuteur N » plutôt que de
  se tromper). À ajuster à l'usage.
- Une voix au téléphone, enrouée ou très courte (peu de parole) donne une
  empreinte peu fiable.
- Les empreintes de réunion ne sont conservées que si la fonction est active
  au moment de la transcription : nommer a posteriori une réunion
  transcrite fonction désactivée n'enrôle rien.
- Le consentement de l'utilisateur ne vaut pas consentement des personnes
  enregistrées : c'est à l'utilisateur de les informer.
