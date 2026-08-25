# S0.3 — Aller-retour clavier → app → clavier

**Date** : 2026-08-26
**Statut** : ✅ Mesuré — cycle complet construit et chronométré, avec une découverte
architecturale importante en cours de route (C5).

## Question posée

Mesurer la latence réelle et évaluer la fluidité perçue du cycle complet :
tap micro dans le clavier → l'app conteneur enregistre → le clavier récupère
le résultat et l'insère. C'est le principal risque UX identifié pour le
projet.

## Environnement de test

- **Appareil** : iPhone 12 Pro, physique
- **iOS** : 26.6
- **Xcode** : 26.2 (17C52)
- **Projet** : `TimbreSpike` (même projet jetable que S0.1/S0.2, non versionné)

## Découverte préalable (avant toute mesure) : C5

Une recherche ciblée avant de construire quoi que ce soit a confirmé, via un
ingénieur Apple DTS sur le forum développeur (juin 2026), qu'**aucune API
publique n'existe pour identifier quelle app hébergeait le clavier, ni pour y
revenir automatiquement** après un aller-retour vers l'app conteneur. C'est un
bug reconnu et ouvert côté Apple (FB22247647), sans calendrier de résolution.
De même, l'enregistrement audio en arrière-plan sans mettre l'app conteneur au
premier plan est confirmé impossible (suspension système après quelques
secondes, même avec le Background Mode Audio actif).

**Conséquence** : le changement d'app manuel par l'utilisateur (revenir dans
Messages/Notes après l'enregistrement) n'est pas un défaut d'implémentation
mais une contrainte de plateforme actuelle — ajoutée à la liste sous le nom
**C5**.

## Deux fausses pistes techniques, résolues en cours de route

### 1. `extensionContext.open()` ne fonctionne pas depuis un clavier

Premier essai : `self.extensionContext?.open(url, completionHandler:)` — l'app
ne s'ouvre pas, `success=false` dans les logs. Après vérification (le schéma
d'URL `timbrespike://` fonctionnait correctement testé depuis Safari), la
cause identifiée : cette méthode de `NSExtensionContext` est documentée par
Apple comme réservée aux **widgets Today**, pas aux extensions clavier.

### 2. La technique qui fonctionne : `EnvironmentValues().openURL()`

L'ancienne technique communautaire (parcourir la responder chain pour trouver
`UIApplication` par sélecteur privé) a été cassée par iOS 18 et est de toute
façon non supportée par Apple. La technique actuelle qui fonctionne (avril
2026) : instancier `EnvironmentValues` directement (hors d'une hiérarchie de
vues SwiftUI) et invoquer son action `openURL` :

```swift
Task { @MainActor in
    let environment = EnvironmentValues()
    environment.openURL(url)
}
```

**Prudence à noter** : ce n'est pas non plus une API officiellement
documentée pour cet usage précis — c'est un comportement observé qui
fonctionne aujourd'hui. Vu que la technique précédente (sélecteur privé) a
cassé sans préavis avec iOS 18, celle-ci doit être considérée comme
potentiellement fragile dans le temps, à surveiller à chaque mise à jour
majeure d'iOS, avec un test de non-régression dédié.

## Méthode de mesure

Trois horodatages écrits dans l'App Group (`group.fr.dafffyl.timbrespike`) :
`recordingRequestedAt` (tap "Enregistrer" dans le clavier), `recordingStartedAt`
(l'app reçoit l'URL et démarre l'enregistrement réel via `AVAudioEngine`),
`transcriptReadyAt` (tap "Terminé" dans l'app). Le clavier, à sa réapparition
(`viewWillAppear`), lit ces horodatages, calcule les trois intervalles, insère
le texte de test via `textDocumentProxy`, et affiche le résultat.

## Résultats

| Essai | Ouverture (tap → app démarre l'enregistrement) | Enregistrement (contrôlé par l'utilisateur) | Retour + insertion (bascule manuelle → détection) |
|---|---|---|---|
| 1 (app pas encore ouverte) | **8,91 s** | 8,77 s | 5,10 s |
| 2 (app déjà ouverte récemment) | **0,11 s** | 1,34 s | 2,50 s |
| 3 (idem) | **0,11 s** | 1,34 s | 1,50 s |

- **Ouverture** : le coût de 8,91 s au premier essai est presque entièrement
  un effet de **lancement à froid** (l'app n'était pas encore en mémoire).
  Une fois l'app "chaude" (récemment utilisée, encore résidente), l'ouverture
  est quasi instantanée (0,11 s), de façon stable sur deux essais consécutifs.
- **Enregistrement** : entièrement contrôlé par l'utilisateur (durée réelle de
  la dictée), pas une latence système — pas pertinent à optimiser.
- **Retour + insertion** : descend avec la pratique (5,10 s → 2,50 s → 1,50 s)
  à mesure que le geste devient familier. Ce chiffre mélange le temps de
  bascule manuelle (humain, incompressible) et notre détection côté clavier
  (`viewWillAppear`, quasi instantanée) — la quasi-totalité de ce délai est
  donc le temps humain de changement d'app, pas un coût technique.

## Conclusion

Le cycle fonctionne bout en bout et la latence *technique* pure est bonne
(0,11 s d'ouverture à chaud, insertion quasi instantanée à la réapparition du
clavier). Le vrai coût, confirmé par la mesure, est **humain et incompressible** :
1 à 2 secondes de bascule manuelle vers l'app d'origine, en plus de
l'interruption elle-même (quitter des yeux l'app qu'on utilisait).

C'est un compromis UX réel, pas un problème de performance à corriger. La
fluidité perçue dépendra surtout de la fréquence à laquelle Timbre reste
"chaud" en mémoire (usage régulier) plutôt que d'optimisations de code.

## Implication pour l'architecture

- Concevoir l'UX en assumant le lancement à froid comme un cas dégradé
  ponctuel (premier usage de la journée), pas le cas nominal — prévoir un
  indicateur de chargement clair pour ce cas précis.
- L'étape de retour manuel vers l'app d'origine doit être explicitement
  assumée dans le design produit (ex. message clair dans Timbre du type
  "Terminé — reviens dans ton app"), pas masquée ni promise comme automatique.
- La technique `EnvironmentValues().openURL()` doit être isolée dans un point
  unique du code (un seul endroit à corriger si iOS casse ce comportement à
  l'avenir, comme cela a été le cas pour la technique précédente en iOS 18) et
  couverte par un test manuel de non-régression à chaque montée de version
  majeure d'iOS.
