# ADR-0002 — L'enregistrement survit à l'arrière-plan (révision partielle de C5)

**Statut** : Accepté — 2026-09-05

## Contexte

L'ADR-0001 établissait C5 ("aucun retour automatique à l'app hôte") à
partir d'une recherche web pendant S0.3 qui affirmait aussi que
l'enregistrement audio en arrière-plan était impossible sans app au premier
plan. Cette seconde affirmation venait d'une question de forum sans
réponse — pas d'un test réalisé par nous, contrairement à C1 (démontrée par
un crash `tccd` reproductible). En comparant l'expérience de Timbre à
Wispr Flow (AI Voice Keyboard), leur clavier affiche "Listening" et insère
le texte sans jamais montrer visiblement leur app conteneur — ce qui a
remis en cause cette hypothèse non vérifiée.

## Décision

Testé nous-mêmes (`docs/spikes/background-recording.md`) : avec la capacité
**Background Modes → Audio** et un enregistrement démarré avant le passage
en arrière-plan, la capture audio réelle **continue** pendant que l'app est
backgroundée — confirmé par des logs de blocs audio ininterrompus sur une
fenêtre de 4s en arrière-plan.

**C5 reste vraie** (toujours aucune API pour revenir automatiquement à
l'app hôte) mais elle ne bloque plus que le *retour visuel* de
l'utilisateur, plus l'enregistrement lui-même.

## Conséquences

- Le clavier peut ouvrir l'app conteneur juste assez longtemps pour démarrer
  l'enregistrement, puis l'utilisateur peut revenir à son app d'origine
  **pendant que l'enregistrement continue réellement** en arrière-plan —
  au lieu de devoir rester sur l'écran de l'app le temps de toute la dictée.
- Le clavier peut afficher sa propre UI de progression (légitime : dessiner
  une interface ne viole pas C1, seul l'accès micro est interdit à
  l'extension) et piloter l'arrêt via le canal App Group existant, sans
  jamais rouvrir l'app conteneur.
- **Contrainte non négociable** : ça doit rester un enregistrement réel et
  borné, déclenché par une action utilisateur explicite — pas une session
  audio maintenue indéfiniment pour contourner la suspension, qui
  risquerait un rejet en revue App Store.
- Point non vérifié séparément, à confirmer en marchant lors de la
  construction de la Phase 4 : la capacité du process, une fois en
  arrière-plan, à recevoir un signal (Darwin notification) du clavier pour
  déclencher l'arrêt.

## Références

`docs/spikes/background-recording.md`, `docs/adr/0001-architecture-clavier-telecommande.md`
