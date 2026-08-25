# S0.1 — Mémoire clavier

**Date** : 2026-08-25
**Statut** : ✅ Mesuré — seuil de kill trouvé, chiffre précis obtenu via les logs kernel.

## Question posée

C2 estime le budget mémoire d'une extension clavier iOS à ~40-60 Mo avant
kill par le système. Ce spike visait à mesurer le seuil réel sur un appareil
physique, pas à se fier à une estimation générique.

## Environnement de test

- **Appareil** : iPhone 12 Pro, physique
- **iOS** : 26.6
- **Xcode** : 26.2 (17C52)
- **Projet** : `TimbreSpike` / target `KeyboardSpike` (le même projet jetable
  que S0.2, réutilisé — non versionné)

## Méthode

Bouton "Saturer la mémoire" dans l'extension : alloue des blocs de 5 Mo en
boucle (toutes les 0,3s), les retient dans un tableau pour empêcher l'ARC de
les libérer, jusqu'à ce que le système tue le processus. Compteur affiché à
l'écran en temps réel, mesure précise récupérée après coup dans les logs
kernel via Console.app (même méthode que S0.2).

### Faux départ : `Data(count:)` seul ne suffit pas

Premier essai : blocs créés avec `Data(count: chunkSize)`. Résultat : plus de
**3 Go** "alloués" sans qu'iOS ne réagisse — clairement pas une vraie mesure
de mémoire physique.

**Cause** : `Data(count:)` initialise à zéro, et iOS peut représenter des
pages entièrement nulles comme partagées en *copy-on-write* avec la page
zéro système, tant qu'on n'écrit rien dedans. Ça consomme de l'espace
d'adressage virtuel (quasi gratuit) mais pas de mémoire physique résidente —
et jetsam (le mécanisme de kill) surveille le *footprint* réel (pages
"dirty"), pas la réservation virtuelle.

**Correctif** : forcer l'écriture réelle dans chaque bloc avec `memset`
avant de le retenir, pour garantir des pages effectivement résidentes :

```swift
var block = Data(count: chunkSize)
block.withUnsafeMutableBytes { rawBuffer in
    if let base = rawBuffer.baseAddress {
        memset(base, 0xAA, chunkSize)
    }
}
```

Après correction, le kill est survenu à ~70 Mo affichés à l'écran — cohérent
avec l'ordre de grandeur attendu.

**Leçon à retenir pour la suite du projet** : toute mesure future de
consommation mémoire réelle (pas seulement ce spike) doit vérifier que la
mémoire testée est effectivement "dirty", pas juste allouée en virtuel.

## Résultat

Log kernel au moment du kill (`Console.app`, filtré sur `KeyboardSpike`) :

```
kernel  memorystatus: KeyboardSpike [994] exceeded mem limit: ActiveHard 77 MB (fatal)
kernel  memorystatus: killing process 994 [KeyboardSpike] in high band FOREGROUND (100) - memorystatus_available_pages: 113991
kernel  memorystatus: killing_specific_process pid 994 [KeyboardSpike] (per-process-limit 100 12s rf:- type:app) 78850KB - memorystatus_available_pages: 114015
ReportSystemMemory  Process KeyboardSpike [994] killed by jetsam reason per-process-limit
```

- **Limite dure (`ActiveHard`) : 77 Mo**
- **Footprint réel au moment du kill : 78 850 Ko (≈ 77 Mo)** — cohérent, tué
  juste après avoir franchi la limite
- **Bande jetsam : `FOREGROUND`** — le clavier est traité comme un process de
  premier plan tant qu'il est affiché (pas de bande "background" pertinente
  pour une extension clavier, qui n'a pas vraiment d'existence hors écran)
- **Raison du kill : `jetsam` / `per-process-limit`**

## Limites de la mesure

- Chiffre obtenu sur un **seul appareil** (iPhone 12 Pro). `ActiveHard` est
  généralement calculé en fonction de la RAM totale du device — un appareil
  plus ancien ou avec moins de RAM aura probablement une limite plus stricte.
  **77 Mo est une borne haute optimiste, pas une cible universelle.**
- Le process testé était quasiment vide (juste le bouton "Next Keyboard" +
  bouton de test) : les 77 Mo incluent déjà le socle UIKit/Swift/Foundation
  incompressible d'une extension, mais pas encore le vrai code applicatif
  (TimbreCore, TimbreSecurity, l'UI du vrai clavier).

## Conclusion

Le seuil réel (77 Mo, `ActiveHard`, sur iPhone 12 Pro / iOS 26.6) est un peu
plus généreux que l'estimation générique de C2 (40-60 Mo), mais dans le même
ordre de grandeur. Vu l'incertitude par appareil, je recommande de concevoir
le budget mémoire du vrai clavier Timbre avec une marge de sécurité
confortable — viser un plafond de fonctionnement autour de **35-40 Mo**
plutôt que de flirter avec 77 Mo, pour rester dans le vert même sur des
appareils plus anciens non testés ici.

## Implication pour l'architecture

Confirme la règle "zéro dépendance tierce, zéro modèle ML côté clavier" (C2)
: la marge disponible est trop étroite pour absorber quoi que ce soit de
lourd. Renforce aussi l'intérêt de mesurer la mémoire sur un appareil
d'entrée de gamme avant la Phase 8 (durcissement), pour vérifier que la marge
de sécurité choisie tient sur le pire cas, pas seulement sur cet iPhone 12
Pro.
