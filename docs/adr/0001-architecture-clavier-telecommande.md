# ADR-0001 — Le clavier comme télécommande, et les contraintes qui en découlent

**Statut** : Accepté — 2026-08-26

## Contexte

Timbre repose sur l'hypothèse qu'une extension clavier iOS ne peut pas
accéder au microphone, et doit donc se contenter de déclencher l'app
conteneur (qui, elle, enregistre et parle au réseau) puis d'insérer le
résultat. Avant de bâtir toute l'architecture sur cette hypothèse, la
Phase 0 (4 spikes, voir `docs/spikes/`) l'a vérifiée empiriquement plutôt
que de la tenir pour acquise.

## Options envisagées

- **Accès micro direct depuis l'extension** — écartée : testée en S0.2,
  provoque un `SIGABRT` systématique déclenché par `tccd` dès la demande
  d'autorisation, avant tout code applicatif. Aucun contournement côté code
  n'existe.
- **Clavier = télécommande** (App Group + Darwin notifications, micro/réseau
  exclusivement côté app conteneur) — retenue, seule option viable.

## Décision

L'architecture "clavier-télécommande" est confirmée comme contrainte dure,
pas comme précaution. Les 5 contraintes systèmes suivantes sont actées comme
données d'entrée pour toute la suite du projet :

- **C1** — Le clavier ne peut jamais toucher au micro, même avec Full
  Access. (S0.2)
- **C2** — Budget mémoire clavier : limite dure mesurée à 77 Mo sur iPhone
  12 Pro. **Cible de conception retenue : 35-40 Mo**, marge de sécurité pour
  des appareils plus anciens non testés. (S0.1)
- **C3** — Full Access requis pour réseau/App Group ; dégradation propre
  obligatoire si non accordé (inchangé, non re-testé).
- **C4** — Groq ne diarise pas ; diarisation locale + alignement sur
  timestamps mot (inchangé).
- **C5** *(nouvelle, issue de S0.3)* — Aucune API publique ne permet de
  revenir automatiquement à l'app hôte après un aller-retour clavier → app.
  Bug reconnu par Apple (FB22247647), sans solution ni calendrier.

## Conséquences

- **Budget mémoire** : la règle "zéro dépendance tierce, zéro modèle ML côté
  clavier" n'est pas négociable — 35-40 Mo ne laisse aucune marge pour quoi
  que ce soit de lourd. À vérifier en CI (script d'échec de build si le
  clavier importe autre chose que `TimbreCore`/`TimbreSecurity`).
- **UX du cycle clavier ↔ app** (C5) : le retour manuel vers l'app d'origine
  doit être assumé explicitement dans le design (message clair "reviens dans
  ton app"), jamais présenté comme automatique. Le lancement à froid
  (~9s mesuré) doit avoir un état de chargement visible ; le lancement à
  chaud est quasi instantané (0,11s) et doit être le cas nominal visé.
- **Ouverture de l'app depuis le clavier** : la technique qui fonctionne
  aujourd'hui (`EnvironmentValues().openURL()`, pas `extensionContext.open()`
  qui est réservé aux widgets Today) doit être isolée dans un point unique du
  code, avec un test de non-régression à chaque montée majeure d'iOS —
  l'ancienne technique communautaire a cassé sans préavis en iOS 18.
- **Diarisation locale** : retenue comme chemin par défaut (rapide, fiable
  sur la parole détectée). Le risque produit identifié n'est pas
  algorithmique mais lié à la capture : un locuteur trop loin du micro passe
  sous le seuil de détection de voix plutôt que d'être mal attribué. Un
  signal de qualité audio à l'enregistrement est à prévoir en Phase 6.
- **Chargement des modèles CoreML** (22,76s mesuré) : coût à payer une fois
  par session d'usage, pas par réunion — l'architecture `TimbreDiarization`
  doit garder les modèles chargés tant que l'app reste active.
- Comparaison avec un fallback cloud (Deepgram) reportée à la Phase 5, quand
  `DeepgramProvider` existera réellement dans l'architecture provider.

## Références

`docs/spikes/keyboard-memory.md`, `docs/spikes/micro-extension.md`,
`docs/spikes/keyboard-app-roundtrip.md`, `docs/spikes/diarization-quality.md`
