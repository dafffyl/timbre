# Revue de code — Timbre (main @ c623f67, 14/10/2026)

Périmètre : CLAUDE.md, docs/adr/0001-0005, `App/`, `KeyboardExtension/`, `Packages/` (TimbreCore, TimbreSecurity, TimbreTranscription, TimbreDiarization), tests, CI, `project.pbxproj`, PR #22.
Mode lecture seule : aucun fichier du dépôt modifié, aucun build ni `swift test` lancé localement (la CI de `main` est verte sur les 3 derniers runs).
Gravité : **critique** (perte de données / crash plausible en usage normal), **majeur** (bug réel ou risque fort, à corriger avant usage intensif), **mineur** (qualité, dette, cas rares).

---

## Top 10 (par priorité)

| # | Gravité | Constat | Emplacement |
|---|---|---|---|
| 1 | critique | Quitter l'écran de transcription (ou une suspension de l'app) détruit définitivement l'audio de la réunion et peut enregistrer un transcript rempli de marqueurs | `App/MeetingTranscriptView.swift:81-95`, `App/MeetingTranscriptionController.swift:95-109` |
| 2 | critique | `BackgroundRecorder.start()` n'est pas idempotent : 2e `installTap` → exception ObjC → crash (course cold-wake / Darwin pendant la fenêtre de grâce, ou échec partiel de `start`) | `App/BackgroundRecorder.swift:62-98`, `App/DictationController.swift:60-103` |
| 3 | majeur | L'échec réseau de la dictée N ferme le fichier de la dictée N+1 en cours (`markFailed` → `beginGrace`) → clavier bloqué en « enregistrement » | `App/DictationController.swift:176-223, 269-278` |
| 4 | majeur | Mises à jour perdues sur le canal App Group : l'app réécrit tout le JSON 10×/s et peut écraser `stopRequested` ou le `clear()` d'annulation du clavier | `App/DictationController.swift:141-163`, `KeyboardExtension/DictationViewModel.swift:167-184`, `Packages/TimbreSecurity/.../DictationChannel.swift:22-34` |
| 5 | majeur | Le pipeline réunion crée son propre `FluidAudioDiarizationProvider` : rechargement des modèles (~23 s) à chaque réunion, double empreinte mémoire, et contournement du garde-fou Wi-Fi/consentement (FluidAudio télécharge implicitement si le cache manque) | `App/MeetingTranscriptionController.swift:48`, `App/DiarizationEnvironment.swift:22-26` |
| 6 | majeur | Le marqueur `[transcription indisponible]` est filtré par `TranscriptStitcher` pour tout chunk autre que le premier → le trou redevient silencieux | `App/MeetingTranscriptionController.swift:119-121`, `Packages/TimbreTranscription/.../TranscriptStitcher.swift:51-55` |
| 7 | majeur | Changement de route audio (AirPods, Bluetooth, CarPlay) non géré : `AVAudioEngineConfigurationChange` arrête le moteur sans signal ; la dictée ne branche même pas `onUnrecoverableInterruption` | `App/BackgroundRecorder.swift:108-147`, `App/DictationController.swift:96` |
| 8 | majeur | Réunion : revenir en arrière pendant l'enregistrement laisse le micro actif indéfiniment ; le plafond de 4 h jette l'URL du fichier (`_ = stop()`) | `App/MeetingRecordingView.swift:81-89`, `App/MeetingRecordingController.swift:92-99` |
| 9 | majeur | `FileMeetingHistoryStore` : un décodage raté renvoie `[]`, puis `save()` écrase TOUT l'historique avec une seule réunion | `App/FileMeetingHistoryStore.swift:29-55` |
| 10 | majeur | Clé invalide/révoquée (401/403) en réunion → chaque chunk devient un marqueur au lieu d'un échec clair ; et l'export `AVAssetExportPresetAppleM4A` ré-encode, donc la taille des chunks (calculée pour 32 kbps) n'est pas maîtrisée | `App/MeetingTranscriptionController.swift:104-109, 126-138` |

---

## 1. Critiques

### C1 — Perte de la réunion à la sortie de l'écran de transcription
- **Où** : `App/MeetingTranscriptView.swift:81-95` ; `App/MeetingTranscriptionController.swift:95-109`.
- **Problème** : le pipeline tourne dans `.task`, annulé dès que la vue disparaît (retour arrière, fermeture de la sheet). L'annulation se propage à `URLSession` → `TranscriptionError.network("cancelled")` (`GroqProvider.swift:95-96`), interceptée par le `catch` générique de la ligne 106, donc chaque chunk restant devient un « marqueur » au lieu d'arrêter la boucle. Ensuite `try? FileManager.default.removeItem(at: audioURL)` (l.86) supprime **toujours** l'audio, et si l'état est `.done`, le record (plein de marqueurs) part dans l'historique. Même résultat si l'app passe en arrière-plan pendant un long traitement : plus de session audio active, donc suspension, requêtes en échec, puis audio supprimé.
- **Correctif** :
  1. Gérer l'annulation explicitement dans la boucle : `try Task.checkCancellation()` en tête d'itération, et `catch is CancellationError` / `URLError.cancelled` → relancer, ne pas marquer de chunk.
  2. Ne supprimer l'audio qu'après un `.done` **sans** chunk manquant et une sauvegarde réussie. Sinon, le déplacer dans `Application Support/pending/` et proposer « Réessayer » depuis l'historique.
  3. Détacher le pipeline de la vue : contrôleur possédé par un objet de niveau app (comme `DictationController.shared`), et `BGContinuedProcessingTask` (iOS 26) ou au minimum `UIApplication.beginBackgroundTask` pour survivre au passage en arrière-plan.

### C2 — Double `installTap` → crash
- **Où** : `App/BackgroundRecorder.swift:91` (installTap sans `removeTap` préalable), `App/DictationController.swift:60-63, 89-102`.
- **Scénario** : le clavier poste la notification Darwin puis, 150 ms plus tard, ouvre `timbre://dictate` si la requête est encore `.pending` (`KeyboardViewController.swift:152-161`). Si le handler Darwin est un peu en retard (hop `Task { @MainActor }`, main thread occupé), l'URL arrive aussi. `startFromColdWake` lit `.pending` et lance `beginRecording(resuming: false)` → `Task { await permission; recorder.start() }`. Pendant ce `await`, `handleWakeSignal` reprend l'enregistrement. Puis `recorder.start()` appelle `installTap` sur un bus qui en a déjà un, ce qui lève une NSException et fait crasher l'app. Autre cas : si `engine.start()` lève après `installTap` (l.98), le tap reste installé et la tentative suivante crashe.
- **Correctif** :
  - Dans `start()` : `guard !isEngineRunning else { try openNewFile(); return }`, puis `engine.inputNode.removeTap(onBus: 0)` avant `installTap`, et un `do/catch` qui défait tout en cas d'échec (`removeTap`, `setActive(false)`).
  - Dans `beginRecording`, après le `await`, re-vérifier que la requête est toujours `.pending` et que `state != .recording`. Prendre le chemin `resumeRecording()` si le moteur tourne déjà.

---

## 2. Majeurs — correction / concurrence

### M1 — Un échec de la dictée N casse la dictée N+1 (top 3)
- **Où** : `App/DictationController.swift:192-222` (Task de transcription) et `269-278` (`markFailed`).
- **Problème** : la fenêtre de grâce est faite pour enchaîner les dictées. Si la dictée 2 démarre pendant que la 1 est encore en `.transcribing`, et que la 1 échoue, `markFailed(requestID: 1)` appelle `beginGrace()` sans condition. `recorder.beginGracePeriod()` met alors `audioFileBox`/`recordedURL` à `nil` : le fichier de la dictée 2 est fermé. Au stop, `stopRecordingAndTranscribe` tombe dans le `guard` (l.181) et ne réécrit jamais le statut. Le clavier reste en `.recording`, qui n'a pas de timeout. `state = .done/.failed` de la dictée 1 écrase aussi l'état UI de la 2.
- **Correctif** : garder `currentRequestID`. `markFailed` et la fin de Task ne touchent au recorder et à `state` que si `requestID == currentRequestID`. Seuls `cancel`/`stop` de la requête courante appellent `beginGrace()`.

### M2 — Canal App Group en read-modify-write multi-écrivains (top 4)
- **Où** : `DictationController.swift:141-163` (lit, modifie `audioLevel`, réécrit tout le blob toutes les 100 ms) ; `DictationViewModel.swift:167-173` (`stopRequested = true`), `178-184` (`clear()`).
- **Problème** : deux processus écrivent la même clé `dictationRequest`. Le cache `UserDefaults` inter-processus (via cfprefsd) peut avoir du retard, donc l'app peut relire une copie sans `stopRequested` et la réécrire, ce qui annule le stop. Pareil pour l'annulation : le `clear()` du clavier peut être suivi d'un `write` de l'app qui ressuscite la requête. Symptôme : un appui sur ✓ ignoré de temps en temps.
- **Correctif** : un seul écrivain par clé. Par exemple `dictation.request` (clavier : id, `stopRequested`, `cancelled`) et `dictation.status.<id>` (app : statut, niveau, résultat, erreur). Ou utiliser une notification Darwin dédiée (`fr.dafffyl.timbre.stop`) comme signal, avec le fichier uniquement comme état. Ajouter un test `DictationChannel` avec deux suites simulées.

### M3 — Provider de diarisation non partagé (top 5)
- **Où** : `App/MeetingTranscriptionController.swift:48` (`= FluidAudioDiarizationProvider()`) vs `App/DiarizationEnvironment.swift:22-26`, dont le commentaire dit justement qu'il doit être unique.
- **Problème** : `OfflineDiarizerManager.prepare()` (FluidAudio 0.15.6, `OfflineDiarizerManager.swift:171-173`) appelle `prepareModels()` si `models == nil`. Chaque réunion recharge donc les modèles CoreML (~23 s, ADR-0004) dans une 2e instance, ce qui double la RAM avec celle du coordinateur. Si le cache a été purgé, le **téléchargement de ~500 Mo** peut partir en cellulaire, sans consentement : cela contourne la décision produit d'ADR-0004.
- **Correctif** : `nonisolated static let diarizationProvider = FluidAudioDiarizationProvider()` dans `DiarizationEnvironment`, injecté à la fois dans `ModelProvisioningCoordinator` et dans `MeetingTranscriptionController`. Ajouter un `ensureModelsReady() == .ready` juste avant `diarize`.

### M4 — Marqueur de chunk manquant supprimé par le stitcher (top 6)
- **Où** : `MeetingTranscriptionController.swift:119-121` (marqueur `start: 0`), `TranscriptStitcher.swift:48-55`.
- **Problème** : pour un chunk d'index > 0, `lowerBound` = milieu du recouvrement = `plan.start + overlap/2` (≈ +5 s). Le marqueur, ramené en global à `plan.start`, vérifie `word.start < lowerBound` et il est filtré. Seul le bandeau ponctuel (`hadMissingChunks`) subsiste : dans l'historique, le trou devient invisible, contrairement à ce que promet ADR-0005.
- **Correctif** : placer le marqueur au milieu de la partie « propre » du chunk, par exemple `start = overlap/2 + ε` (ou `(plan.end - plan.start)/2`). Mieux : rendre `TranscriptStitcher` conscient des chunks en échec (`TranscribedChunk.failed`). Ajouter un test stitcher avec un chunk du milieu en échec.

### M5 — Changements de route audio et interruptions côté dictée (top 7)
- **Où** : `BackgroundRecorder.swift:108-147` ; `DictationController.swift:96` (jamais de `onUnrecoverableInterruption`).
- **Problème** : brancher ou débrancher des AirPods pendant une réunion émet `AVAudioEngineConfigurationChange`. Le moteur s'arrête, le format d'entrée change (le convertisseur et le tap sont figés sur l'ancien), et `isEngineRunning` reste `true`. C'est le même symptôme que celui corrigé par #31 (enregistrement qui s'arrête en silence), par un autre chemin. Côté dictée, une interruption sans `shouldResume` laisse `isEngineRunning == true` : `handleWakeSignal` « reprend » sur un moteur arrêté, ce qui donne un fichier vide envoyé à Groq.
- **Correctif** : observer `.AVAudioEngineConfigurationChange`, puis `removeTap`, recréer le `converter` avec le nouveau `inputFormat`, `installTap` et `engine.start()`. Mettre `isEngineRunning = false` sur `.began`. Brancher `onUnrecoverableInterruption` dans `DictationController` (→ stop + transcription de l'existant). Ajouter un chien de garde : aucun buffer reçu depuis 2 s pendant `.recording` → état d'alerte visible.

### M6 — Micro qui reste actif / réunion de 4 h perdue (top 8)
- **Où** : `MeetingRecordingView.swift:9` (contrôleur en `@State` d'une vue poussée), `MeetingRecordingController.swift:92-99`.
- **Problème** :
  - (a) Le bouton retour reste disponible pendant l'enregistrement. La vue disparaît mais le tap capture `[self]` du `BackgroundRecorder` en fort (`BackgroundRecorder.swift:91`, cycle moteur → tap → recorder). Le micro tourne donc indéfiniment (indicateur orange, fichier qui grossit, batterie), sans aucune UI pour l'arrêter. Le `Timer` répétitif n'est jamais invalidé non plus.
  - (b) Au-delà de 4 h, `_ = stop()` jette l'URL : la réunion est perdue et un fichier orphelin reste dans `tmp/`.
- **Correctif** : (a) `.navigationBarBackButtonHidden(controller.state == .recording)` + bouton « Arrêter et quitter » avec confirmation ; `onDisappear` → `stop()` ; `deinit`/`isolated deinit` qui invalide le timer. (b) `autoStoppedURL = stop()` (même chemin que l'interruption). (c) Au lancement, balayer `tmp/*.m4a` orphelins (proposer récupération ou suppression).

### M7 — Historique effacé par un décodage raté (top 9)
- **Où** : `App/FileMeetingHistoryStore.swift:29-33, 35-39, 52-55`.
- **Problème** : `try?` sur la lecture et le décodage renvoie `[]`. Le `save` suivant persiste alors `[nouvelle réunion]` et écrase tout. Ça arrive dès qu'un champ non optionnel est ajouté à `MeetingRecord`/`SpeakerTurn`, ou si le fichier est corrompu. Les erreurs d'écriture sont aussi muettes, ce qui contredit la convention « jamais de `try?` silencieux ».
- **Correctif** : API `throws`. Distinguer « fichier absent » (→ `[]`) de « décodage impossible » (→ erreur + copie `meetings.corrupt-<date>.json`, jamais d'écrasement). Ajouter `decodeIfPresent` avec valeurs par défaut pour les nouveaux champs, et un `schemaVersion`. Écrire avec `[.atomic, .completeFileProtectionUnlessOpen]`.

### M8 — Erreurs non transitoires traitées comme des chunks manquants (top 10)
- **Où** : `MeetingTranscriptionController.swift:104-109`.
- **Problème** : seul `missingAPIKey` est fatal. Une clé révoquée (`.server(401/403)`), un modèle retiré (`404`) ou `fileTooLarge` échouent de façon déterministe sur **chaque** chunk. Résultat : une heure de « [transcription indisponible] » sauvegardée comme succès (et l'audio supprimé, cf. C1).
- **Correctif** : ajouter un prédicat `isFatalForWholeMeeting` (`missingAPIKey`, `server` 400-499 sauf 408/429, `fileTooLarge`) qui interrompt et conserve l'audio. Le factoriser avec `GroqProvider.isRetryable`.

### M9 — Taille des chunks non maîtrisée (export ré-encodé)
- **Où** : `MeetingTranscriptionController.swift:41-45, 126-137` ; hypothèse écrite dans ADR-0005 (§ « Découpage + export »).
- **Problème** : `AVAssetExportPresetAppleM4A` **ré-encode** avec les réglages du preset, pas à 32 kbps. `maxDuration` donne ~94 min par chunk (25 Mo × 0,9 / 32 kbps). Si le preset sort par exemple 64-128 kbps, un chunk de 94 min fait 45-90 Mo : `fileTooLarge` (rattrapé en marqueur), donc des réunions longues entièrement non transcrites. S'y ajoutent une perte de génération AAC→AAC et du CPU/batterie pour rien. **À vérifier sur appareil** (taille réelle d'un chunk exporté).
- **Correctif** : `AVAssetExportPresetPassthrough` + `outputFileType = .m4a` (aucun ré-encodage : taille ≈ bitrate source, export quasi instantané). Ou vérifier `chunkData.count` avant l'envoi et redécouper par dichotomie si la limite est dépassée. Ajouter un test d'intégration local (non-CI) qui mesure la taille d'un chunk exporté.

### M10 — Clavier bloqué en `.recording` si l'app meurt
- **Où** : `KeyboardExtension/DictationViewModel.swift:93-97` (aucun timeout sur `.recording`, contrairement à `.pending` et `.transcribing`).
- **Problème** : si l'app est tuée (jetsam, crash C2, M1), le clavier sonde à 10 Hz pour toujours et affiche une onde figée.
- **Correctif** : l'app met à jour un battement (`statusUpdatedAt` ou `heartbeatAt`) à chaque écriture de niveau. Le clavier passe en erreur « Timbre ne répond plus » sans battement depuis plus de 3 s.

### M11 — `NWPathMonitor` : double `resume` possible
- **Où** : `App/NWPathNetworkStatusProvider.swift:16-23`.
- **Problème** : `pathUpdateHandler` peut être appelé plusieurs fois avant que `cancel()` ne prenne effet. Un `CheckedContinuation` repris deux fois provoque un crash.
- **Correctif** : drapeau `OSAllocatedUnfairLock<Bool>` « déjà repris », ou `monitor.currentPath` après un premier callback ; garder une seule instance de moniteur.

### M12 — Projet compilé en Swift 5, pas Swift 6
- **Où** : `Timbre.xcodeproj/project.pbxproj:559, 594` (et tous les targets) `SWIFT_VERSION = 5.0` ; CLAUDE.md:89 affirme « Swift 6, concurrency stricte ».
- **Problème** : en mode Swift 5, la plupart des diagnostics de data race sont des avertissements ou absents. Les `@unchecked Sendable`/`nonisolated(unsafe)` de `BackgroundRecorder` ne sont pas réellement contrôlés, le clavier n'a pas d'isolation par défaut, et `DictationViewModel` (non `@MainActor`) est muté depuis des callbacks `Timer`.
- **Correctif** : passer `SWIFT_VERSION = 6.0` target par target (clavier d'abord, c'est le plus petit), ajouter `@MainActor` à `DictationViewModel` et corriger les diagnostics.

---

## 3. Majeurs — sécurité / confidentialité

### S1 — La clé Groq peut partir dans le trousseau iCloud via l'autofill
- **Où** : `App/SettingsView.swift:20-22` (`.textContentType(.password)`) et `79-85` (pré-remplissage avec la vraie clé).
- **Problème** : `.password` déclenche la proposition « Enregistrer le mot de passe » d'iOS, ce qui pousse la clé dans les mots de passe iCloud, contraire à l'invariant « pas d'iCloud ». Le pré-remplissage garde aussi la clé en clair dans l'état SwiftUI.
- **Correctif** : `.textContentType(nil)` (ou `.oneTimeCode`), `.privacySensitive()`. Ne pas pré-remplir : afficher « Clé enregistrée (…xxxx) » avec les boutons Remplacer et Supprimer. Montrer l'erreur Keychain au lieu de `savedConfirmation = false` muet (l.104-106).

### S2 — `APIKeyStore.save` non atomique
- **Où** : `Packages/TimbreSecurity/Sources/TimbreSecurity/APIKeyStore.swift:31-41`.
- **Problème** : `SecItemDelete` puis `SecItemAdd`. Si l'ajout échoue (`errSecInteractionNotAllowed`, appareil verrouillé…), l'ancienne clé est déjà perdue.
- **Correctif** : `SecItemUpdate`, puis `SecItemAdd` seulement si `errSecItemNotFound`. Ajouter un target de tests TimbreSecurity (service de test dédié).

### S3 — Dernière dictée conservée en clair dans l'App Group
- **Où** : `DictationViewModel.swift:109-115` (`.ready` → `clearPending()` mais pas `channel.clear()`).
- **Problème** : `resultText` reste indéfiniment dans le plist partagé `group.fr.dafffyl.timbre` (sauvegardes incluses), jusqu'à la dictée suivante.
- **Correctif** : `channel.clear()` après l'insertion, et purge côté app à la fin de la fenêtre de grâce.

### S4 — Transcripts de réunion sans protection renforcée et inclus dans les sauvegardes
- **Où** : `App/FileMeetingHistoryStore.swift:23-27, 52-55`.
- **Correctif** : `.completeFileProtectionUnlessOpen` à l'écriture. Décider explicitement (et documenter dans un ADR) si `meetings.json` doit être exclu des sauvegardes (`isExcludedFromBackup`).

### S5 — Fichiers audio temporaires
- **Où** : `BackgroundRecorder.swift:186`, `MeetingTranscriptionController.swift:135`.
- **Problème** : les réunions sont écrites dans `tmp/` sans nettoyage après crash (cf. M6c). La protection par défaut est acceptable (l'enregistrement doit pouvoir continuer écran verrouillé), mais les orphelins doivent être purgés.

### Mineurs sécurité
- `DictationController.swift:198`, `240`, `MeetingTranscriptionController.swift:49` : `{ (try? apiKeyStore.load()) ?? nil }`. Une erreur Keychain (ex. appareil pas encore déverrouillé depuis le boot) devient « clé manquante », ce qui donne un message trompeur. Mapper vers une erreur dédiée (`keychainUnavailable`).
- Le schéma `timbre://` et la notification Darwin `fr.dafffyl.timbre.wake` sont publics : n'importe quelle app peut réveiller Timbre. C'est sans effet tant qu'aucune requête `.pending` n'existe (bon garde-fou), mais il faut valider `url.host == "dictate"` (`ContentView.swift:139`).
- Aucune journalisation (aucun `print`/`Logger`) : conforme à l'invariant, mais zéro diagnostic. Prévoir un `Logger` avec `privacy: .private` pour les états (jamais le texte).

---

## 4. Performance / batterie / mémoire

- **P1 (majeur, UX/batterie)** — `BackgroundRecorder.swift:64`. `.playAndRecord` sans `.mixWithOthers`/`.duckOthers` : chaque dictée **coupe la musique ou le podcast** de l'utilisateur, et la fenêtre de grâce (30 s, `DictationController.swift:45`) garde le micro ouvert (indicateur orange) et l'audio des autres apps coupé. Correctif : `options: [.mixWithOthers]` (ou `.duckOthers` pendant l'enregistrement seulement), et une grâce plus courte ou configurable. Documenter le compromis dans ADR-0002.
- **P2 (mineur)** — `BackgroundRecorder.swift:212-236`. Pendant la grâce, chaque buffer est quand même converti (allocation d'un `AVAudioPCMBuffer` par callback) puis jeté. Correctif : lire d'abord `audioFileBox` et sortir s'il est `nil` (garder le calcul du niveau si nécessaire), et préallouer le buffer de conversion.
- **P3 (mineur)** — `BackgroundRecorder.swift:235`. `try? file?.write` : disque plein ou erreur d'encodeur = enregistrement perdu en silence. Correctif : compteur d'erreurs atomique remonté via `onUnrecoverableInterruption`.
- **P4 (mineur)** — Canal App Group écrit/lu 10×/s des deux côtés avec JSON complet + `UserDefaults(suiteName:)` recréé à chaque appel (`DictationChannel.swift:18-20`). C'est acceptable sur 3 min, mais une clé de niveau dédiée (Float) et une instance `UserDefaults` gardée réduiraient le trafic cfprefsd.
- **P5 (mineur)** — `MeetingTranscriptionController.swift:99` : `Data(contentsOf:)` de jusqu'à 25 Mo sur le MainActor, puis copie dans le multipart (`GroqProvider.swift:153`), soit ~50 Mo de pic et un main thread bloqué pendant la lecture. Correctif : `URLSession.upload(for:fromFile:)` avec un corps multipart écrit sur disque, hors MainActor.
- **P6 (mineur)** — `GroqProvider.swift:142` : `timestamp_granularities[]=word` + `verbose_json` aussi pour la dictée, qui n'utilise que `text`. Ajouter un paramètre `wantsWordTimestamps` (latence et taille de réponse).
- **P7 (mineur)** — `GroqProvider.swift:78-89` : pas de `timeoutInterval` (60 s par défaut × 3 tentatives) alors que le clavier abandonne à 30 s (`DictationViewModel.swift:47`). Aligner : ~15 s par tentative pour la dictée. `RetryPolicy` ignore `retryAfter` (`RetryPolicy.swift:44`). `TranscriptionError.cancelled` n'est jamais produit : mapper `URLError.cancelled`/`CancellationError`.
- **P8 (mineur)** — `SpeakerAlignment.swift:58-67, 102-115` : O(mots × segments), soit ~10⁷ itérations pour 1 h. Acceptable, mais un balayage à deux pointeurs (segments triés) le ramène à O(n+m).
- **P9 (mineur)** — `MeetingHistoryView.swift:13` : `loadAll()` dans l'initialiseur de `@State`, réévalué à chaque reconstruction de la vue parente (lecture disque + décodage). Charger dans `.task`. La liste n'est pas rafraîchie après un renommage dans le détail.

---

## 5. Gestion d'erreurs / UX

- **E1 (mineur)** — `DictationController.swift:280-300` vs `MeetingTranscriptionController.swift:140-154` : deux traductions erreur → message qui divergent déjà. La réunion n'a pas de cas `server` ; la PR #22 n'améliore que la dictée. Factoriser dans `TimbreTranscription` (`TranscriptionError.userMessage`) et tester.
- **E2 (mineur)** — `DictationChannel.swift:22-29` : un `try?` sur le décodage d'un JSON d'une autre version (app mise à jour, clavier encore en mémoire) donne `nil`, que l'app interprète comme une **annulation** (`DictationController.swift:142-146`). Ajouter un champ `version` + `decodeIfPresent`.
- **E3 (mineur)** — `DictationController.swift:165-174` : `cancelRecording` supprime le fichier avant de le fermer (`beginGrace` vient après). C'est sans gravité, mais il faut fermer d'abord.
- **E4 (mineur)** — `SettingsView.swift:97-106` : l'échec Keychain n'est jamais affiché, et il n'y a aucun moyen de supprimer la clé.
- **E5 (mineur)** — `MeetingTranscriptView.swift:90` : une réunion à 0 tour n'est pas sauvegardée, ce qui est correct, mais l'audio est quand même supprimé (cf. C1).
- **E6 (mineur)** — `INFOPLIST_KEY_NSMicrophoneUsageDescription` (`project.pbxproj:541`) ne mentionne que la dictée, pas l'enregistrement de réunions (App Review).

---

## 6. Accessibilité (côté code)

- **A1 (majeur)** — `KeyboardExtension/KeyboardView.swift:249-258` (lettres = `Text` + `DragGesture`) et `403-415` (suppression = `Image` + geste) : pour VoiceOver ce ne sont pas des boutons, donc **le clavier est inutilisable au lecteur d'écran**. Correctif : `.accessibilityElement()`, `.accessibilityLabel(key)`, `.accessibilityAddTraits(.isKeyboardKey)`, `.accessibilityAction { tapLetter(key) }`, et pour la suppression `.accessibilityLabel("Supprimer")` + action.
- **A2 (majeur)** — `App/DesignSystem/Theme.swift:50-69` (+ `MeetingRecordingView.swift:23`) : toutes les polices sont en `.system(size:)` fixe, donc **aucun Dynamic Type** dans toute l'app. Correctif : `Font.system(.title2, design: .rounded, weight: .semibold)`, etc. (styles de texte), ou `@ScaledMetric` pour les tailles custom.
- **A3 (mineur)** — Boutons icône seule sans libellé : enregistrement réunion (`MeetingRecordingView.swift:81-113` : « Démarrer/Arrêter l'enregistrement »), ✗/✓ du clavier (`KeyboardView.swift:170-175` : « Annuler »/« Terminer la dictée »), crayon de renommage (`TranscriptRendering.swift:72-81`). Ajouter `.accessibilityLabel`/`.accessibilityHint`.
- **A4 (mineur)** — `WaveformBars` (`Components.swift:147-167`) et l'onde du clavier sont lues comme une série de rectangles : `.accessibilityHidden(true)`. Le chrono de réunion mérite un `.accessibilityLabel` en durée parlée.
- **A5 (mineur)** — Libellé « Start » en anglais dans un clavier français (`KeyboardView.swift:142`) ; `PrimaryLanguage = en-US` pour un AZERTY français (`KeyboardExtension/Info.plist:13-14`) : mettre `fr-FR` (langue annoncée aux apps hôtes et à la correction).
- **A6 (mineur)** — Animations (`Components.swift:85, 161`) sans prise en compte de `accessibilityReduceMotion`.

---

## 7. Duplication / simplification / dette technique

- **D1** — `requestMicrophonePermission()` dupliquée (`DictationController.swift:118-124`, `MeetingRecordingController.swift:101-107`) : à déplacer dans `BackgroundRecorder` (ou un helper).
- **D2** — Le polling `Timer` 0,1 s + `Task { @MainActor }` est dupliqué dans les deux contrôleurs. Une boucle `Task { while !Task.isCancelled { …; try await Task.sleep(for: .milliseconds(100)) } }` annulable serait plus simple et éviterait les timers jamais invalidés.
- **D3** — `GroqProvider` et `GroqTextCleanupProvider` dupliquent la gestion HTTP (statuts, 429, `isRetryable`). Un petit `GroqHTTPClient` interne suffirait.
- **D4** — Palette dupliquée volontairement dans le clavier (`KeyboardView.swift:63-70`). C'est justifié par C2, mais on pourrait déplacer les constantes de couleur (pas SwiftUI : des tuples RGB) dans `TimbreCore` pour une source unique.
- **D5** — `TimbreSecurity.swift` est un placeholder vide qui n'a plus de raison d'être. Les packages `TimbreAudio`/`TimbreUI` cités dans CLAUDE.md et `check-keyboard-dependencies.sh` n'existent pas : la doc d'architecture est désalignée.
- **D6** — ADR-0005 (« Ce qui n'est toujours pas dans cet incrément ») annonce encore l'absence d'historique et de renommage, livrés depuis (#27, #28). Le commentaire de `DictationRequest.swift:29-32` (« lit à chaque bloc audio ~90 ms ») ne correspond plus au code (timer 100 ms sur le MainActor). `GroqProvider.swift:9-11` dit « schéma pas encore vérifié contre un vrai appel », ce qui est faux depuis l'usage réel.
- **D7** — `check-keyboard-dependencies.sh` ne vérifie que les `import` de packages locaux, pas les `packageProductDependencies`/frameworks liés au target `KeyboardExtension` dans le `pbxproj`, ni les imports tiers (ex. `import FluidAudio` passerait). L'invariant « zéro dépendance tierce » n'est donc pas réellement garanti.
- **D8** — `KeyboardViewController.swift:179-185` : `textWillChange`/`textDidChange` vides (template Xcode). `@IBOutlet` inutile (l.23) : bouton créé en code.
- **D9** — `SWIFT_VERSION = 5.0` (cf. M12). Pas de lint/format (SwiftLint/swift-format) alors que la CI existe.
- **D10** — `TimbreSpike/`, `TimbreDiarizationSpike/` sont présents localement (ignorés par git, OK). Vérifier qu'ils ne sont référencés par aucun scheme partagé.

---

## 8. Couverture de tests — trous

Couvert (69 `@Test`) : chunker, stitcher, retry, `GroqProvider` (via `MockURLProtocol`), nettoyage, alignement, formatter, provisioning, codable. C'est une bonne base pour la partie pure.

Non couvert (par ordre d'importance) :
1. **`MeetingTranscriptionController`** (aucun test, et le target App n'a que le template XCTest `TimbreTests.swift`). C'est là qu'auraient été attrapés C1, M4 et M8. Extraire `transcribeAllChunks` derrière un protocole `ChunkExporter` + `FakeTranscriptionProvider` (qui existe déjà) dans un package testable.
2. **`TranscriptStitcher` avec chunk en échec au milieu** (M4).
3. **`DictationViewModel`** (machine à états du clavier, timeouts) : 100 % logique, testable si `UserDefaults`/`DictationChannel` sont injectés.
4. **`DictationController`** : enchaînement de dictées, échec N pendant N+1 (M1), annulation. Nécessite un protocole `Recorder` (DI, conformément à CLAUDE.md « DI par protocole partout où il y a réseau/disque/horloge » : ici ni le recorder, ni le canal, ni l'horloge ne sont injectés).
5. **`FileMeetingHistoryStore`** (corruption, migration de schéma : M7).
6. **TimbreSecurity** : aucun target de test et absent de la boucle CI (`.github/workflows/ci.yml:25`). Couvrir `APIKeyStore` (save/update/load/delete) et `DictationChannel`.
7. **`TranscriptFormatting`** (labels, export texte) : pur, facile.
8. **Traduction des erreurs** (E1 / PR #22).
9. Les tests de l'app (`TimbreTests`, `TimbreUITests`) ne sont pas lancés en CI : il faudrait `xcodebuild test` sur un simulateur, au moins pour la logique.

---

## 9. PR #22 — « fix: affiche le vrai message d'erreur Groq »

**État GitHub** : `mergeable: MERGEABLE`, `mergeStateStatus: CLEAN`, CI `build` verte… mais exécutée le **29/09** sur une base ancienne (`6dc9e0e`, après #20). Depuis, 10 PR ont été mergées (#23 à #31). `git merge-tree` contre `origin/main` actuel : **aucun conflit**, et `App/DictationController.swift` n'a pas bougé depuis la base. La protection de `main` n'exige ni status check ni branche à jour, d'où le « CLEAN » malgré une CI périmée.

**Revue du diff** (+31/−1, `App/DictationController.swift:293-330` dans la PR) :
- ✅ Utile et ciblé : affiche le message JSON de Groq, cas spécial 401/403.
- **mineur** — Si `rawMessage` est vide ou ne contient que des espaces, `humanReadableDetail` renvoie `""`. La branche 401/403 n'appelle pas `!isEmpty`, d'où « Clé API Groq refusée (code 401) :  — vérifie… ». Correctif : `return decoded.error.message.trimmed.nilIfEmpty` et filtrer le repli brut de la même façon.
- **mineur** — Le repli « texte brut tel quel » peut afficher une page HTML entière (502 Cloudflare, proxy captif) dans la capsule `caption2` du clavier. Correctif : tronquer (~120 caractères) et ignorer le repli si le corps commence par `<`.
- **mineur** — Le 403 de Groq ne signifie pas toujours une clé invalide (restriction d'organisation, région, modèle non autorisé). Le message affirme « Clé API Groq refusée » ; c'est atténué par l'ajout du détail. Formulation suggérée : « Accès refusé par Groq (code 403) : <détail> ».
- **mineur** — `try?` sur le décodage : acceptable ici (repli documenté), cohérent avec l'exception déjà admise pour le nettoyage.
- **mineur** — Aucun test (fonction `private static` dans le target App, sans tests). Le chemin réunion (`MeetingTranscriptionController.userMessage`) ne bénéficie pas du correctif. À terme : déplacer dans `TimbreTranscription` (cf. E1).

**Verdict** : **mergeable** (aucun conflit, risque très faible, pas de régression possible hors du message d'erreur). Avant le merge, recommandé : « Update branch » (ou rebase sur `main`) pour relancer la CI sur la base actuelle, puis corriger le cas du détail vide (2 lignes). Les autres remarques peuvent partir dans une PR de suivi (factorisation + tests). À terme, activer « Require status checks to pass » + « Require branches to be up to date » sur `main`, pour que « CLEAN » veuille vraiment dire « vert sur la base actuelle ».

---

## 10. Ordre de correction suggéré

1. C1 + M8 (ne plus perdre de réunion), puis M6 (micro fantôme / 4 h).
2. C2 + M1 + M5 (robustesse du recorder et de l'enchaînement des dictées).
3. M2 + M10 (protocole du canal : un écrivain par clé + battement).
4. M3 + M4 + M9 (pipeline réunion : provider partagé, marqueur, passthrough).
5. M7, S1, S2 (persistance et clé).
6. A1/A2 (accessibilité), M12 (Swift 6), tests (§8), puis le reste des mineurs.
