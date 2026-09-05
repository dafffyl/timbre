# S-extra — Enregistrement réel en arrière-plan (Background Mode Audio)

**Date** : 2026-09-05
**Statut** : ✅ Confirmé — révise une partie de l'ADR-0001 (C5).

## Contexte

En comparant l'expérience de Timbre à celle de Wispr Flow (AI Voice Keyboard),
observation directe sur appareil : leur clavier affiche "Listening" et insère
le texte **sans jamais quitter visiblement l'app hôte** (testé dans Notes).
Ça semblait contredire ce qu'on avait retenu du spike S0.3 — mais cette
affirmation ("l'enregistrement en arrière-plan est impossible") venait d'une
**recherche web** (une question de forum sans réponse), pas d'un test qu'on
avait fait nous-mêmes. Elle n'avait pas le même niveau de preuve que C1
(démontrée par un vrai crash `tccd`). Ce spike corrige ça : on teste
nous-mêmes plutôt que de faire confiance à une source non vérifiée.

## Hypothèse testée

Une app avec la capacité **Background Modes → Audio, AirPlay, and Picture
in Picture**, qui démarre un enregistrement réel (`AVAudioEngine`) *avant*
de passer en arrière-plan, continue-t-elle à capturer du vrai audio une fois
backgroundée ?

## Méthode

Vue de test jetable dans l'app Timbre (`BackgroundRecordingSpikeView`,
retirée après le spike) : bouton "Démarrer l'enregistrement" → configure
`AVAudioSession(.playAndRecord)` → installe un tap sur `AVAudioEngine.inputNode`
qui logue (`OSLog`) et incrémente un compteur à chaque bloc audio reçu.
Séquence : démarrer → rester au premier plan quelques secondes → passer en
arrière-plan → attendre → revenir → arrêter. Vérification via Console.app
(logs kernel/OSLog, même méthode que les spikes précédents) que les blocs
audio continuent d'arriver pendant la fenêtre où l'app était backgroundée.

## Résultat

Sur la fenêtre où l'app était confirmée en arrière-plan (14:44:57 → 14:45:01,
~4s), les logs montrent des blocs audio reçus **sans aucune interruption**,
au même rythme régulier (~90-110ms) qu'au premier plan :

```
14:44:57.292  Bloc audio reçu
14:44:57.353  Bloc audio reçu
...
14:45:01.038  Bloc audio reçu
14:45:01.147  Bloc audio reçu
```

**Confirmé** : un enregistrement démarré avant le passage en arrière-plan
continue à capturer du vrai audio pendant que l'app est backgroundée, grâce
au Background Mode Audio.

**Non testé séparément** (déduit, à vérifier en marchant en Phase 4) : la
capacité du process, dans cet état, à recevoir un signal externe (Darwin
notification depuis le clavier) pour savoir quand s'arrêter. Un process qui
traite des blocs audio toutes les 90ms n'est par définition pas suspendu —
rien n'indique qu'il ne pourrait pas aussi recevoir une notification pendant
ce temps, mais ça reste à confirmer en le construisant.

## Implication pour l'architecture — révision de C5

**C5 reste vraie** (aucune API pour revenir automatiquement à l'app hôte),
mais elle ne bloque plus l'enregistrement lui-même : l'app conteneur n'a pas
besoin de rester visible pour continuer à enregistrer. Ça ouvre une
architecture où :

1. Le clavier ouvre brièvement l'app (toujours nécessaire, C1 : seule l'app a
   le micro) pour démarrer l'enregistrement.
2. L'utilisateur peut revenir presque immédiatement à son app d'origine
   (toujours un aller-retour manuel, C5 inchangée) **pendant que
   l'enregistrement continue réellement** en arrière-plan.
3. Le clavier peut afficher sa propre UI de progression ("Listening", forme
   d'onde) — légitime, puisque dessiner une interface ne viole pas C1, seul
   l'accès au micro est interdit à l'extension.
4. Le clavier peut signaler l'arrêt (bouton dans le clavier plutôt que dans
   l'app) via le canal App Group déjà existant.

Ça réduit drastiquement le temps où l'utilisateur doit rester sur l'écran de
l'app conteneur — de "toute la durée de la dictée" à "un aller-retour quasi
instantané", rapprochant l'expérience de Timbre de celle de Wispr Flow.

## Point de vigilance

Ça doit rester un **enregistrement réel et borné**, déclenché par une action
utilisateur explicite (comme une app de dictaphone) — pas une session audio
maintenue indéfiniment "juste au cas où", qui s'apparenterait à un
contournement du système de suspension plutôt qu'un usage légitime du
Background Mode Audio, et risquerait un rejet en revue App Store.
