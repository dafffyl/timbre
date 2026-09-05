# Ajouter un provider de transcription

Objectif : un nouveau provider doit tenir dans **un seul fichier**, sans
toucher au reste de l'app. `GroqProvider.swift` en est l'exemple de référence.

## Étapes

1. **Un fichier** dans `Packages/TimbreTranscription/Sources/TimbreTranscription/`
   (ex. `DeepgramProvider.swift`).

2. **Conformer au protocole** `TranscriptionProvider` :
   ```swift
   public struct MonProvider: TranscriptionProvider {
       public let identifier = ProviderIdentifier(rawValue: "mon-provider")
       public let capabilities = ProviderCapabilities(
           supportsNativeDiarization: false,
           supportsStreaming: false,
           wordTimestamps: true,
           maxFileSizeBytes: nil
       )

       public func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
           // ...
       }
   }
   ```

3. **Erreurs typées** : réutiliser les cas de `TranscriptionError` existants
   (`.missingAPIKey`, `.network`, `.server`, `.rateLimited`, `.decoding`…)
   plutôt que d'en inventer de nouveaux — l'appelant (l'app, le clavier) ne
   doit gérer qu'un seul type d'erreur, peu importe le provider.

4. **Retry réseau** : envelopper l'appel dans `withRetry(shouldRetry:operation:)`
   si le provider fait du réseau. Voir `GroqProvider.isRetryable` pour
   l'exemple de mapping (quelles erreurs méritent un retry, lesquelles non).

5. **Tests** : un `URLProtocol` factice (voir `MockURLProtocol` dans les
   tests de `TimbreTranscription`) pour ne jamais faire de vrai appel réseau
   en test unitaire. Vérifier au minimum :
   - le provider ne contacte jamais le réseau si une précondition échoue
     (clé manquante, fichier trop gros) ;
   - le décodage d'une réponse réussie ;
   - le mapping d'un code d'erreur HTTP vers le bon cas de `TranscriptionError`.

6. **Sélection dans l'app** : pas encore de registre ni d'écran de choix de
   provider — `GroqProvider` est actuellement câblé en dur dans `ContentView`
   (seul provider existant, cf. YAGNI). Quand un second provider sera
   ajouté, prévoir :
   - un registre simple (`[ProviderIdentifier: any TranscriptionProvider]`
     ou équivalent) plutôt que du câblage en dur ;
   - un sélecteur dans `SettingsView` pour choisir le provider actif.

## Ce qui ne doit jamais changer ailleurs dans le code

Le protocole `TranscriptionProvider` est le seul point de contact entre
l'app et un provider. Si ajouter un provider oblige à modifier
`ContentView`, `DictationViewModel`, ou tout autre code en dehors de
`TimbreTranscription` (au-delà du câblage temporaire mentionné au point 6),
c'est le signe que l'abstraction a une fuite — à corriger avant d'ajouter le
provider, pas après.
