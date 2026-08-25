# S0.2 — Micro dans l'extension (vérification de C1)

**Date** : 2026-08-25
**Statut** : ✅ Confirmé — C1 est vraie, avec un mécanisme plus strict que prévu.

## Question posée

C1 affirme qu'une extension clavier iOS ne peut pas accéder au microphone, même
avec Full Access accordé. Ce spike visait à le vérifier réellement sur un
appareil physique, avec la version d'iOS actuelle, plutôt que de le tenir pour
acquis.

## Environnement de test

- **Appareil** : iPhone 12 Pro, physique (pas de simulateur)
- **iOS** : 26.6
- **Xcode** : 26.2 (17C52)
- **Projet** : `TimbreSpike` — app hôte SwiftUI minimale + target `KeyboardSpike`
  (Custom Keyboard Extension), projet jetable, non conservé dans l'historique
  final du repo (issu de cette branche `spike/micro-extension`)

## Méthode

1. Target `KeyboardSpike` créée via le template Xcode standard
   *Custom Keyboard Extension*.
2. `Info.plist` de l'extension modifié pour :
   - `RequestsOpenAccess = true` (Full Access), afin de tester exactement le
     cas décrit par C1 — pas une extension sans Full Access.
   - Ajout de `NSMicrophoneUsageDescription`, pour éliminer par avance une
     cause d'échec non liée à C1 (chaîne de description manquante).
3. Code de test dans `KeyboardViewController` : un bouton déclenche
   `AVAudioApplication.requestRecordPermission`, puis en cas d'autorisation
   tente `AVAudioSession.setCategory(.record)` + `.setActive(true)`, puis
   instancie un `AVAudioEngine`, installe un tap sur `inputNode` et appelle
   `engine.start()`. Chaque étape est encadrée par un `do/catch` qui affiche
   le résultat à l'écran et logue via `OSLog`.
4. Test exécuté en conditions réelles : clavier `KeyboardSpike` activé dans
   Réglages, Full Access accordé, invoqué depuis l'app Notes via la touche
   globe.
5. Résultat vérifié **après réinstallation complète de l'app** (suppression +
   reinstall, pas juste un re-build incrémental), pour écarter tout effet de
   cache d'enregistrement d'extension côté iOS.

## Résultat

Le processus de l'extension est **tué par le système** (`SIGABRT`, rapport de
crash iOS de type 309) au moment de l'appel à
`AVAudioApplication.requestRecordPermission` — **avant même** d'atteindre le
code `AVAudioSession`/`AVAudioEngine`. Ce n'est pas une erreur Swift
attrapable : le `do/catch` du code de test n'est jamais exécuté, l'app hôte
(Notes) est simplement rebasculée sur le clavier système par iOS.

Rapport de crash (extrait) :

```
Exception Type:  EXC_CRASH (SIGABRT)
Termination Reason: TCC 0

This app has crashed because it attempted to access privacy-sensitive data
without a usage description. The app's Info.plist must contain an
NSMicrophoneUsageDescription key with a string value explaining to the user
how the app uses this data.

Thread 6 Crashed:
0   libsystem_kernel.dylib    __abort_with_payload + 8
1   libsystem_kernel.dylib    abort_with_payload_wrapper_internal + 103
2   libsystem_kernel.dylib    abort_with_payload + 15
3   TCC                       __TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__ + 171
4   TCC                       ___tcc_server_send_request_authorization_block_invoke_3 + 123
5   TCC                       __tccd_send_message_block_invoke + 623
6   libxpc.dylib              _xpc_connection_reply_callout + 119
...
```

Le message affiché ("Info.plist doit contenir `NSMicrophoneUsageDescription`")
est **trompeur** : cette clé était bien présente dans le `Info.plist` de
l'extension, vérifiée avant et après une réinstallation complète (pour écarter
un problème de cache). Le message générique de TCC est réutilisé alors que la
cause réelle est différente : `tccd` (le daemon de permissions) refuse
catégoriquement d'autoriser une requête microphone dont l'origine est un
processus d'extension clavier (`com.apple.keyboard-service`), et fait
avorter le processus plutôt que de renvoyer un refus applicatif normal.

## Conclusion

**C1 est confirmée**, avec un mécanisme plus strict que ce que les termes
« refuse l'accès » suggéraient : ce n'est pas une permission qui échoue
proprement (auquel cas le code aurait pu intercepter l'erreur et dégrader
l'interface), c'est **le processus entier de l'extension qui est terminé par
le système** dès la tentative de demande d'autorisation micro — avant tout
code applicatif utile. Aucun contournement côté code n'est possible : il ne
s'agit pas d'une erreur qu'on peut attraper et gérer, mais d'un arrêt forcé
imposé au niveau du daemon de confidentialité système.

## Implication pour l'architecture

Confirme sans ambiguïté que l'architecture "clavier = télécommande" (App
Group + Darwin notifications, micro et réseau uniquement côté app conteneur)
n'est pas une simple précaution : c'est la seule architecture qui puisse
fonctionner. Aucun budget de développement ne doit être alloué à une
tentative alternative d'accès micro direct depuis l'extension.
