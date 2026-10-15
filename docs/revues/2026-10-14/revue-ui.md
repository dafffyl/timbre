# Revue UI/UX — Timbre (état après PR #30/#31)

Périmètre : `App/` (SwiftUI), `App/DesignSystem/`, `KeyboardExtension/`, Info.plist, projet Xcode, assets. Revue en lecture seule (aucun fichier du dépôt modifié ; `git status` propre).
Vérification visuelle : build Debug simulateur (iPhone 17 Pro, iOS 27) dans le scratchpad, captures `simctl` de l'écran d'accueil en taille de texte par défaut et en `accessibility-extra-extra-extra-large` (`home.png`, `home-ax.png`). Les autres écrans demandent des taps : ils sont évalués sur le code.
Contrastes calculés selon la formule WCAG 2.x à partir des valeurs de `Theme.swift`.

Effort : S = moins d'une demi-journée, M = 1 à 2 jours, L = plus de 2 jours.

---

## Top 10

| # | Constat | Fichier:ligne | Effort |
|---|---|---|---|
| 1 | **Une réunion peut être perdue définitivement.** Si la transcription échoue (clé API absente, diarisation en erreur) ou si l'utilisateur quitte l'écran pendant le traitement (retour, fermeture de la feuille, ce qui annule la `.task`), le fichier audio est supprimé. Il n'existe ni bouton « Réessayer » ni sauvegarde. | `App/MeetingTranscriptView.swift:81-86`, `:37-52` | M |
| 2 | **L'enregistrement de réunion n'est pas protégé.** Un swipe vers le bas sur la feuille ou le bouton retour de la navigation pendant l'enregistrement détruit le `MeetingRecordingController` (`@State`). Aucune confirmation, perte silencieuse. Un seul tap sur le bouton arrête aussi la réunion, sans confirmation. | `App/MeetingRecordingView.swift:9, 81-89` ; `App/DiarizationSetupView.swift:136-139` | S |
| 3 | **Il n'y a aucun onboarding.** Rien ne guide l'ajout du clavier, l'activation de l'Accès complet, la saisie de la clé Groq ou une première dictée de test. L'accueil affiche « Prêt — En attente d'une demande du clavier » même si rien n'est configuré. | `App/ContentView.swift:78-134` | M |
| 4 | **Dynamic Type n'est pas pris en charge dans l'app.** Toutes les polices ont une taille fixe (`.system(size:)`). Confirmé par capture : en taille AX5, seule l'icône SF Symbol grossit, aucun texte ne bouge. | `App/DesignSystem/Theme.swift:51-69` (+ `MeetingRecordingView.swift:23`) | M |
| 5 | **Le contraste du bouton principal est insuffisant.** Le texte blanc sur le dégradé obtient 2,98:1 côté violet et 2,15:1 côté corail ; sur `timbreDanger` il obtient 2,78:1. Le seuil AA est de 4,5:1 (3:1 pour le grand texte). Même problème pour le bouton « Start » du clavier. | `App/DesignSystem/Components.swift:68-76` ; `KeyboardExtension/KeyboardView.swift:146-149` | S |
| 6 | **VoiceOver est inutilisable au clavier et faible dans l'app.** Les touches lettres et Supprimer sont des `Text`/`Image` avec un `DragGesture`, donc non activables par VoiceOver. Les boutons iconographiques (✕, ✓, maj, retour, clavier suivant, bouton d'enregistrement) n'ont pas de libellé. Le dépôt ne contient aucun modificateur `accessibility*`. | `KeyboardView.swift:249-259, 403-416, 170-175, 385-397, 461` ; `MeetingRecordingView.swift:81-113` | M |
| 7 | **Le clavier s'appelle « KeyboardExtension » dans Réglages et dans le sélecteur de claviers**, et il est déclaré `en-US` alors que la disposition est AZERTY française. C'est le premier contact avec le produit pendant l'activation. | `Timbre.xcodeproj/project.pbxproj:692, 721` ; `KeyboardExtension/Info.plist` (`PrimaryLanguage`) | S |
| 8 | **Aucune localisation n'est en place.** Il n'y a pas de String Catalog ; `developmentRegion = en` alors que tout est en français ; les titres et messages calculés sont des `String` (donc non extractibles) ; « Start » est en anglais au milieu d'une interface française ; la langue de transcription est codée en dur à `"fr"`. | `project.pbxproj:300` ; `KeyboardView.swift:142` ; `ContentView.swift:118-134` ; `DictationController.swift:204, 242` | L |
| 9 | **Le feedback autour de l'enregistrement de réunion est pauvre.** L'arrêt automatique à 4 h est silencieux (`stop()` sans navigation, la vue retombe sur « Toucher pour démarrer » et l'URL est perdue). L'app n'a aucune haptique. Rien n'indique que l'enregistrement continue en arrière-plan ni que la limite est de 4 h. | `App/MeetingRecordingController.swift:96-98` ; `MeetingRecordingView.swift:40-44` | S |
| 10 | **Les réglages ne s'intègrent pas au thème et leur feedback est trompeur.** `AccentColor` est vide, donc « Fermer », les boutons d'alerte, `ShareLink` et le retour s'affichent en bleu système. « Enregistré » s'affiche même quand la clé est vide, ne disparaît jamais, et un échec Keychain n'affiche rien. | `App/Assets.xcassets/AccentColor.colorset/Contents.json` ; `App/SettingsView.swift:48-56, 90-107` | S |

---

## 1. Parcours

### 1.1 Onboarding, activation du clavier, Accès complet

- **ON-1 — Il n'y a pas de parcours de première configuration** (`ContentView.swift:16-63`).
  - Impact : sur une app dont l'usage principal (le clavier) se configure hors de l'app, en 5 écrans de Réglages, c'est le premier point d'abandon.
  - Correctif : ajouter une carte « Configuration » qui remplace la status card tant que la configuration n'est pas complète, sous forme de checklist :
    1. Ajouter le clavier : bouton `UIApplication.openSettingsURLString` avec le chemin écrit en toutes lettres.
    2. Autoriser l'Accès complet : le clavier écrit au premier lancement un drapeau `hasFullAccess` dans l'App Group, que l'app lit.
    3. Coller la clé Groq : lien vers console.groq.com.
    4. Faire une dictée test : un `TextField` dans l'app.
  - Effort : M.
- **ON-2 — Le message Accès complet du clavier est une ligne `caption2` en corail, sans chemin ni action** (`KeyboardView.swift:155-158`).
  - Impact : l'utilisateur ne sait pas où aller, et le micro disparaît sans explication.
  - Correctif : garder un bouton micro visible mais grisé. Au tap, afficher un encart : « Réglages › Général › Clavier › Claviers › Timbre › Accès complet », avec un lien qui ouvre l'app sur l'étape de checklist (l'ouverture d'URL sans Accès complet reste à vérifier sur device ; en repli, texte seul). Expliquer en une phrase pourquoi c'est nécessaire (réseau et partage avec l'app, aucune frappe envoyée).
  - Effort : S.
- **ON-3 — L'accueil n'affiche pas l'absence de clé API** (`ContentView.swift:118-134`).
  - Impact : le problème n'apparaît qu'en erreur, en pleine dictée ou à la fin d'une réunion (voir n°1).
  - Correctif : passer la status card en état « Clé API manquante » avec un bouton vers Réglages, et bloquer « Démarrer une réunion » tant que la clé manque.
  - Effort : S.
- **ON-4 — La description d'usage du micro ne parle que du clavier** (`project.pbxproj:541, 576` : « …pour dicter le texte que tu insères dans le clavier »).
  - Impact : quand la première demande de permission arrive depuis « Transcription de réunion », le texte ne correspond pas.
  - Correctif : « Timbre utilise le micro pour tes dictées et pour enregistrer tes réunions. L'audio n'est jamais conservé. »
  - Effort : S.
- **ON-5 — Le slogan d'accueil « Ce qui distingue deux voix sur la même note » est poétique mais n'explique pas ce que fait l'app** (`ContentView.swift:70`).
  - Correctif : le garder, mais ajouter une phrase utile sous la status card en état vierge (« Dicte dans n'importe quelle app avec le clavier Timbre »).
  - Effort : S.

### 1.2 Première dictée (clavier ↔ app)

- **DI-1 — Le bouton « Start » est en anglais et ne dit pas ce qu'il fait** (`KeyboardView.swift:142`).
  - Correctif : utiliser un libellé localisé « Dicter » avec l'icône `mic.fill`, plus cohérente que `waveform` pour démarrer une action.
  - Effort : S.
- **DI-2 — Pendant l'enregistrement, ✕ (annuler) et ✓ (valider) sont collés l'un à l'autre en `.title3`** (`KeyboardView.swift:167-183`). Leur zone de tap fait environ 24 pt, sous le minimum de 44 pt.
  - Impact : un mauvais tap sur ✕ perd la dictée.
  - Correctif : écarter les deux boutons, donner une `contentShape` de 44 pt, transformer ✓ en pastille « Terminer » remplie et laisser ✕ secondaire.
  - Effort : S.
- **DI-3 — Le texte « Ouverture de Timbre… » ne prépare pas au basculement d'app (environ 9 s à froid) ni au retour manuel (C5)** (`KeyboardView.swift:160-164`).
  - Impact : côté app, le sous-titre « Contrôle depuis le clavier — reviens dans ton app » est la seule aide, en `caption` gris.
  - Correctif : sur la première ouverture à froid, afficher dans l'app une carte visible du type « Enregistrement lancé ✓ — Reviens dans ton app (‹ en haut à gauche) ». La flèche système en haut à gauche est le chemin réel ; la nommer explicitement.
  - Effort : S.
- **DI-4 — L'état `.failed(message)` de l'accueil met le message d'erreur complet dans le titre, sans action ni moyen de l'effacer** (`ContentView.swift:124`). Le sous-titre de `.done` (« Contrôle depuis le clavier… ») n'a pas de sens une fois la dictée terminée (`:131`).
  - Correctif : titre court (« Échec de la dictée »), message en sous-titre, bouton contextuel (« Ouvrir Réglages » si la clé ou le micro est en cause). Pour `.done` : « Texte inséré dans ton app ».
  - Effort : S.
- **DI-5 — Le message d'erreur du clavier est sur une seule ligne `caption2`, dans une capsule de la barre du haut, à côté d'un espace réservé de 44 pt** (`KeyboardView.swift:196-209`).
  - Impact : les messages longs (« Clé API Groq manquante — configure-la dans les réglages. ») seront tronqués.
  - Correctif : bandeau sur 2 lignes maximum, sur toute la largeur, au-dessus des touches, avec l'icône ⚠︎ et le bouton « OK ».
  - Effort : S.
- **DI-6 — L'état « Transcription… » du clavier n'a pas de bouton Annuler** (`KeyboardView.swift:191-194`). Seul le délai de 30 s libère l'utilisateur.
  - Correctif : réutiliser `onCancelTap`.
  - Effort : S.

### 1.3 Enregistrement de réunion

- **RE-1 — Le modèle de 500 Mo se télécharge derrière un simple spinner** (`DiarizationSetupView.swift:41-47`).
  - Impact : aucune progression, aucune durée estimée, et l'utilisateur ne sait pas s'il peut fermer la feuille. Le titre reste « Télécharger le modèle de diarisation » pendant tout le téléchargement.
  - Correctif : `ProgressView(value:)` alimentée par le coordinateur, état « Téléchargement… 120/500 Mo », et la mention « Tu peux fermer cet écran » ou au contraire un avertissement explicite.
  - Effort : M.
- **RE-2 — « Diarisation » est un terme de jargon dans l'interface** (`DiarizationSetupView.swift:99`).
  - Correctif : « Préparer la reconnaissance des voix ».
  - Effort : S.
- **RE-3 — Rien ne protège un enregistrement en cours** (voir Top 10 n°2).
  - Correctif :
    - `.interactiveDismissDisabled(controller.state == .recording)` sur la feuille ;
    - `.navigationBarBackButtonHidden(controller.state == .recording)` ;
    - `confirmationDialog` sur l'arrêt (« Terminer la réunion et transcrire ? ») ;
    - éventuellement `UIApplication.shared.isIdleTimerDisabled` pendant l'enregistrement, si l'utilisateur veut garder l'écran allumé (option).
  - Effort : S.
- **RE-4 — L'arrêt automatique à 4 h est silencieux et l'URL est perdue** (`MeetingRecordingController.swift:96-98`).
  - Correctif : passer par le même chemin que `handleUnrecoverableInterruption` (`autoStoppedURL`) et afficher une alerte dédiée.
  - Effort : S.
- **RE-5 — L'alerte d'interruption n'a que le bouton « OK »** (`MeetingRecordingView.swift:69-73`).
  - Correctif : renommer en « Voir la transcription ». « (appel, Siri, alarme...) » utilise trois points ASCII là où le reste du texte emploie « … ».
  - Effort : S.
- **RE-6 — L'écran d'enregistrement est pauvre en repères.** Avant le démarrage, le chronomètre affiche 00:00:00 à 56 pt. Aucun indicateur « REC » ni point rouge n'est visible pendant l'enregistrement. Rien n'indique que l'enregistrement continue écran verrouillé. Rien n'est vérifié avant le démarrage (clé API, Wi-Fi inutile).
  - Correctif : pastille « ● Enregistrement », sous-texte « Continue écran verrouillé · 4 h max », animation de pulsation discrète sur le bouton (désactivée avec Réduire les animations).
  - Effort : S.
- **RE-7 — La mise en page n'est pas défilable** (`MeetingRecordingView.swift:19-48`) : chronomètre de 56 pt, bouton de 88 pt, Spacers.
  - Impact : en paysage iPhone, ou avec un texte de grande taille une fois le Dynamic Type corrigé, le message d'erreur et le bouton risquent d'être rognés.
  - Correctif : `ViewThatFits` ou `ScrollView` plus disposition horizontale en `verticalSizeClass == .compact`.
  - Effort : S.

### 1.4 Transcription d'une réunion

- **TR-1 — La perte de l'audio sur échec ou abandon est le constat le plus grave** (Top 10 n°1, `MeetingTranscriptView.swift:81-86`).
  - Correctif :
    - ne supprimer l'audio qu'après un `.done` sauvegardé ;
    - en cas d'échec, conserver le fichier et afficher « Réessayer » plus « Supprimer l'enregistrement » ;
    - stocker une entrée « en attente » dans l'historique pour reprendre plus tard ;
    - sortir le pipeline de la vue, par exemple dans un contrôleur détenu par l'app, pour qu'il survive à la navigation.
  - Ces changements touchent ADR-0005 (audio jamais conservé), qu'il faudra amender en « conservé jusqu'à transcription réussie ».
  - Effort : M.
- **TR-2 — L'écran de progression se résume à un spinner et à « Transcription (2/5)… »** (`MeetingTranscriptView.swift:99-108`).
  - Correctif : barre de progression déterminée sur les chunks, étapes nommées (1. Voix, 2. Texte, 3. Assemblage), « Garde Timbre ouvert ». Sans le correctif TR-1, ce dernier message est indispensable.
  - Effort : S.
- **TR-3 — L'état d'échec n'a aucune action** (`MeetingTranscriptView.swift:37-52`), pas même « Retour » ou « Ouvrir Réglages » quand la clé manque.
  - Effort : S, avec TR-1.
- **TR-4 — Le titre « Transcript » est un anglicisme** (`MeetingTranscriptView.swift:79`, `MeetingHistoryView.swift:85` « Transcript vide »).
  - Correctif : « Transcription » partout.
  - Effort : S.
- **TR-5 — Une transcription vide n'est pas sauvegardée (`!turns.isEmpty`) mais affiche « Aucune parole détectée. » sans explication ni conseil** (micro trop loin, etc.). Le cas de la parole manquée sur un locuteur éloigné est connu (C4).
  - Correctif : ajouter un conseil (« Pose le téléphone au centre de la table »).
  - Effort : S.

### 1.5 Historique, renommage, export

- **HI-1 — La liste n'a pas de titre de réunion** : la date sert de titre, l'aperçu est la première phrase (`MeetingHistoryView.swift:59-82`). Il manque aussi la durée et le nombre de locuteurs, et il n'y a pas de recherche.
  - Correctif : ajouter un titre éditable (à défaut, la date), une ligne « 42 min · 3 voix », et `.searchable`.
  - Effort : M.
- **HI-2 — La suppression se fait uniquement par balayage, sans confirmation ni annulation, et sans bouton Modifier** (`MeetingHistoryView.swift:42, 88-93`). L'action est irréversible puisqu'il n'y a pas d'audio.
  - Correctif : `confirmationDialog`, ou `EditButton` plus un toast d'annulation.
  - Effort : S.
- **HI-3 — Le renommage n'est pas découvrable.** La seule indication est une icône crayon de 10 pt dans la pastille (`TranscriptRendering.swift:75-79`). L'alerte n'explique pas que le nom s'applique à toute la réunion, et laisser le champ vide revient silencieusement à « Locuteur N ».
  - Correctif :
    - ajouter un bouton toolbar « Locuteurs » qui ouvre une feuille listant chaque voix avec un champ de nom et un extrait ;
    - ajouter un message d'alerte du type « Remplace "Locuteur 2" partout dans cette réunion. Laisse vide pour revenir au nom par défaut. » ;
    - mettre `.textInputAutocapitalization(.words)` sur le champ.
  - Effort : S pour le message d'alerte, M pour la feuille.
- **HI-4 — Les couleurs des locuteurs alternent seulement violet et corail** (`TranscriptRendering.swift:111-114`).
  - Impact : à partir de 3 voix, Locuteur 1 et Locuteur 3 ont la même couleur. La couleur n'est pas indispensable puisque le libellé est présent, mais l'effet visuel « une voix, une couleur » est trompeur.
  - Correctif : ajouter des variantes de luminosité ou un numéro dans la pastille.
  - Effort : S.
- **EX-1 — L'export se limite à un `ShareLink` de texte brut, sans en-tête** (`MeetingHistoryView.swift:121-125`, `TranscriptRendering.swift:136-141`). Il ne contient ni date ni durée, pas de bouton « Copier », et le fichier partagé n'a pas de nom.
  - Correctif :
    - préfixer l'export par « Réunion du 14 oct. 2026, 10:00 » ;
    - utiliser `ShareLink(item:subject:preview:)` ;
    - ajouter une action « Copier » ;
    - proposer plus tard un `.txt`/`.md` nommé via `Transferable`.
  - Effort : S.
- **EX-2 — Ce que contient l'export n'est pas indiqué** (noms personnalisés inclus, marqueurs « [transcription indisponible] » conservés).
  - Effort : S.

### 1.6 Réglages

- **SE-1 — Le feedback d'enregistrement est trompeur** (Top 10 n°10, `SettingsView.swift:48-56, 97-106`).
  - Correctif :
    - fermer la feuille après un enregistrement réussi, ou afficher un toast temporaire ;
    - afficher une erreur explicite si le Keychain échoue ;
    - désactiver « Enregistrer » tant que rien n'a changé ;
    - ajouter une icône d'état sur la clé (« Clé enregistrée ✓ ») plutôt que de pré-remplir le `SecureField` avec la clé réelle ;
    - ajouter idéalement un bouton « Tester la clé ».
  - Effort : S, ou M avec le test de clé.
- **SE-2 — Il manque un lien pour obtenir une clé Groq et une explication de son coût et de la confidentialité** (« l'audio part chez Groq »).
  - Effort : S.
- **SE-3 — Les réglages n'ont pas de section « Clavier »** (état d'installation, rappel de l'Accès complet), ni de section langue, ni de section À propos/Confidentialité.
  - Effort : M.

---

## 2. Système visuel et cohérence

- **VI-1 — `AccentColor` est vide** (Top 10 n°10). Il suffit de le régler sur `timbreViolet` (0.588, 0.518, 1.0) dans l'asset. Effort : S.
- **VI-2 — Le thème du clavier est dupliqué en constantes locales** (`KeyboardView.swift:63-70`). La duplication est justifiée par C2, mais le risque de divergence est réel.
  - Correctif : déplacer les valeurs RGB, sans dépendance SwiftUI lourde, dans `TimbreCore` sous forme de struct de constantes, partagée par les deux cibles.
  - Effort : S.
- **VI-3 — La hiérarchie de l'accueil est inversée.** La status card « Prêt », avec un contenu sans valeur, occupe la 1re position, et la partie basse de l'écran est vide sur un iPhone de 6,3" (voir `home.png`).
  - Correctif : faire de la status card un élément contextuel (configuration, dictée en cours, erreur), absent ou réduit à l'état idle. Ajouter les 2-3 dernières réunions en accès direct.
  - Effort : S.
- **VI-4 — Les rayons et marges sont cohérents** (24 pt pour les cartes, capsules pour les boutons). Bon point de la PR #30.
  - Petite exception : `TimbreMenuRow` empile `.buttonStyle(.plain)` puis `.timbreCard()`, donc l'état pressé n'a aucun retour visuel sur toute la carte. Ajouter un `ButtonStyle` « carte » avec un `scaleEffect` cohérent avec les boutons.
  - Effort : S.
- **VI-5 — Les boutons système des toolbars (« Fermer », « Enregistrer ») utilisent la police système** alors que le reste de l'interface est en `.rounded`.
  - Correctif : `.fontDesign(.rounded)` à la racine (iOS 16.1+).
  - Effort : S.

## 3. Accessibilité

### Dynamic Type

- **AX-1 — Constaté sur capture : les tailles fixes de `Theme.swift` ne suivent pas le réglage.**
  - Correctif :
    - `Font.system(.title2, design: .rounded, weight: .semibold)` et ainsi de suite (styles de texte), ou `@ScaledMetric` pour les tailles de pictos et de cadres (48 pt, 88 pt) ;
    - pour le chronomètre : `.font(.system(.largeTitle, design: .rounded)).monospacedDigit()` plafonné par `.dynamicTypeSize(...DynamicTypeSize.accessibility2)` ;
    - `TimbreMenuRow` doit passer en disposition verticale en taille AX (`ViewThatFits`, ou `dynamicTypeSize.isAccessibilitySize`).
  - Effort : M.
- **AX-2 — Le problème inverse existe au clavier.** Les styles `.title3`/`.subheadline` grossissent avec Dynamic Type (`KeyboardView.swift:145, 251, 333`), alors que le clavier système garde une taille fixe. En AX5, les lettres débordent des touches.
  - Correctif : `.dynamicTypeSize(.large)` ou `...(.xLarge)` à la racine de `KeyboardView`.
  - Effort : S.

### VoiceOver

- **AX-3 — Clavier** (Top 10 n°6).
  - Correctif :
    - sur `letterKey` et `deleteKey` : `.accessibilityElement()`, `.accessibilityLabel(lettre)`, `.accessibilityAddTraits([.isButton, .isKeyboardKey])`, `.accessibilityAction { tapLetter(key) }` ;
    - pour les variantes accentuées : `.accessibilityAction(named:)` ;
    - libellés : maj « Majuscule » avec la valeur « activée/verrouillée », espace « Espace » (le libellé visuel est « Timbre »), retour « Retour », bouton suivant « Clavier suivant » (côté UIKit, `accessibilityLabel`), ✕ « Annuler la dictée », ✓ « Terminer la dictée » ;
    - onde : `.accessibilityHidden(true)` ;
    - chaque changement d'état (enregistrement, transcription, erreur) doit déclencher une annonce `AccessibilityNotification.Announcement`.
  - Effort : M.
- **AX-4 — App.**
  - Bouton d'enregistrement de réunion (`MeetingRecordingView.swift:81-113`) : `.accessibilityLabel(state == .recording ? "Arrêter l'enregistrement" : "Démarrer l'enregistrement")`.
  - Chronomètre : libellé en durée parlée (`Duration.formatted(.units(...))`) et `.updatesFrequently`.
  - Les ondes (`WaveformBars`) et les icônes décoratives (badges, halos) doivent être masquées.
  - Pastille de locuteur : `.accessibilityLabel("Locuteur 1")` plus `.accessibilityHint("Toucher pour renommer")`.
  - Carte de tour de parole : `.accessibilityElement(children: .combine)`.
  - Status card d'accueil : combiner les éléments.
  - Effort : S/M.

### Contraste

- **AX-5 — Contraste des boutons pleins** (Top 10 n°5). Les textes secondaires sont conformes : `timbreTextSecondary` obtient 5,9:1 sur la surface des cartes et 5,4:1 sur les touches.
  - Correctif : soit assombrir les teintes de remplissage des boutons, par exemple violet ~#6A55E8 et corail ~#D9622B (à recalculer, viser au moins 4,5:1 avec le blanc), en gardant les teintes claires actuelles pour le texte et les icônes sur fond sombre ; soit utiliser un texte presque noir (#120F1F) sur le dégradé actuel.
  - Effort : S.

### Réduire les animations et la transparence

- **AX-6 — Ces deux réglages ne sont pas respectés.** Le `scaleEffect`, les ressorts et l'animation de l'onde ignorent `accessibilityReduceMotion`. `.ultraThinMaterial` et les halos flous ignorent `accessibilityReduceTransparency`.
  - Correctif : variantes conditionnelles, avec une surface opaque `timbreSurface` quand la transparence est réduite.
  - Effort : S.

## 4. Mode sombre / clair

- **DM-1 — L'app force le sombre partout** (`.preferredColorScheme(.dark)` répété sur 7 vues). C'est cohérent avec l'identité visuelle et acceptable.
  - Correctif : le déclarer une seule fois à la racine (`TimbreApp`) plutôt que sur chaque vue, ou via `UIUserInterfaceStyle = Dark` dans Info.plist. Effet supplémentaire : les alertes, `ShareLink` et la feuille de partage seront rendus en sombre de façon homogène.
  - Effort : S.
- **DM-2 — Le clavier ignore `textDocumentProxy.keyboardAppearance` et l'apparence système.**
  - Impact : dans une app hôte claire, le bloc noir est très contrasté par rapport au clavier Apple. C'est un choix de marque, mais il faut le décider en connaissance de cause.
  - Correctif : proposer une variante claire, même minimale (fond des touches et texte).
  - Effort : M.

## 5. Haptique

- **HA-1 — L'app n'a aucune haptique.**
  - Correctif : `.sensoryFeedback(.start, trigger:)` et `.stop` sur le bouton de réunion, `.success` à la fin de la transcription, `.error` en cas d'échec, `.impact(.light)` au renommage. Effort : S.
- **HA-2 — Au clavier, `playInputClick()` est un clic sonore, pas une vibration** (`KeyboardViewController.swift:116-118`).
  - Impact : avec le mode silencieux, aucun retour, alors que le clavier Apple vibre si « Retours clavier › Haptique » est activé.
  - Correctif : ajouter `UIImpactFeedbackGenerator(style: .light)` quand `hasFullAccess` est vrai (à valider sur device ; Apple limite l'haptique en extension sans Accès complet). Ajouter aussi une haptique distincte au démarrage et à la fin de la dictée.
  - Effort : S.

## 6. iPad et orientation

- **IP-1 — L'app iPad est l'interface iPhone étirée.** `TARGETED_DEVICE_FAMILY = "1,2"`, mais rien ne limite la largeur : les cartes de l'accueil et les tours de parole s'étendent sur environ 1000 pt, ce qui rend les lignes de transcription très longues.
  - Correctif : `.frame(maxWidth: 640)` centré sur l'accueil et le transcript. À terme, `NavigationSplitView` pour l'historique (liste + détail).
  - Effort : S pour la largeur, M pour le split view.
- **IP-2 — Le clavier iPad utilise la disposition iPhone en pleine largeur.** Il manque la rangée de chiffres et la touche ⌨︎↓ pour masquer le clavier (`dismissKeyboard()`), et les touches deviennent énormes.
  - Correctif : au minimum, ajouter `dismissKeyboard` et plafonner la hauteur des touches.
  - Effort : M.
- **IP-3 — En paysage iPhone, le clavier garde des marges verticales de 12 pt par touche, ce qui le rend trop haut.**
  - Correctif : adapter via `verticalSizeClass`.
  - Effort : S.

## 7. Localisation (FR/EN)

- **LO-1 — L'infrastructure est absente** (Top 10 n°8).
  - Correctif :
    1. Régler `developmentRegion = fr`.
    2. Ajouter `Localizable.xcstrings` à l'app et au clavier.
    3. Convertir les propriétés calculées `String` (`statusTitle`, `title`, `message`, `userMessage(for:)`, `displayLabels`) en `LocalizedStringResource` ou `String(localized:)`.
    4. Utiliser `InfoPlist.xcstrings` pour `NSMicrophoneUsageDescription` et le nom du clavier.
  - Effort : L, en comptant la traduction EN.
- **LO-2 — La langue de transcription est fixée à `"fr"`** (`DictationController.swift:204, 242`, `MeetingTranscriptionController.swift:101`), et la disposition est uniquement AZERTY.
  - Correctif : ajouter un réglage de langue de dictée (Auto/FR/EN) et une disposition QWERTY. Sans cela, une version anglaise de l'interface n'aurait pas de sens.
  - Effort : M.
- **LO-3 — La mise en forme dépend de la langue.**
  - Le format d'export « Locuteur 1 :\n » (espace insécable avant les deux-points) doit être localisé (EN : « Speaker 1: »).
  - Le chronomètre `String(format: "%02d:%02d:%02d")` peut être remplacé par `Duration.formatted(.time(pattern: .hourMinuteSecond))`.
  - Effort : S.
- **LO-4 — Le nom affiché du clavier et sa langue doivent être corrigés** (Top 10 n°7) : `INFOPLIST_KEY_CFBundleDisplayName = Timbre` et `PrimaryLanguage = fr-FR`. Effort : S.

## 8. Micro-copy

Le tutoiement est cohérent partout et les erreurs réseau et clé sont bien formulées. Ajustements proposés :

| Où | Actuel | Proposé |
|---|---|---|
| `KeyboardView.swift:142` | Start | Dicter |
| `KeyboardView.swift:156` | Autorise l'accès complet dans Réglages | Active l'Accès complet pour dicter · Comment ? |
| `ContentView.swift:130` | En attente d'une demande du clavier | Touche « Dicter » sur le clavier Timbre pour commencer |
| `ContentView.swift:131` (.done) | Contrôle depuis le clavier — reviens dans ton app | Texte inséré — tu peux revenir à ton app |
| `DiarizationSetupView.swift:99` | Télécharger le modèle de diarisation | Préparer la reconnaissance des voix |
| `DiarizationSetupView.swift:98` | Prêt | Tout est prêt |
| `MeetingTranscriptView.swift:79` | Transcript | Transcription |
| `MeetingHistoryView.swift:85` | Transcript vide | Transcription vide |
| `MeetingHistoryView.swift:25` | Aucune réunion transcrite pour l'instant. | + bouton « Démarrer une réunion » (état vide actionnable) |
| `MeetingRecordingView.swift:70` | OK | Voir la transcription |
| `MeetingRecordingView.swift:72` | (appel, Siri, alarme...) | (appel, Siri, alarme…) |
| `DictationController.swift:294` | Erreur Groq (code 503). | Le service de transcription est indisponible — réessaie dans un instant. (garder le code en petit) |
| `SettingsView.swift:44` | « …via un second appel IA… Expérimental » | Préciser que le texte est envoyé une seconde fois à Groq |

## 9. États vides, erreur, chargement — synthèse

| Écran | Vide | Chargement | Erreur |
|---|---|---|---|
| Accueil | n/a (status card « Prêt » sans action) | spinner « Transcription en cours… » OK | message dans le titre, pas d'action (DI-4) |
| Setup réunion | « Vérification… » avec message vide (`DiarizationSetupView.swift:107-108`) | spinner sans progression pour 500 Mo (RE-1) | « Réessayer » OK, mais `error.localizedDescription` brut (`ModelProvisioningCoordinator.swift:51`) |
| Enregistrement | OK | n/a | texte rouge, pas de lien vers Réglages pour le micro |
| Transcription | « Aucune parole détectée. » sans conseil (TR-5) | spinner + chunk N/M (TR-2) | aucune action, audio perdu (TR-1) |
| Historique | texte gris non actionnable | chargement synchrone dans l'initialiseur `@State` (bloque à l'ouverture si l'historique est gros) | aucune gestion d'erreur de lecture |
| Clavier | n/a | pilule OK | capsule `caption2` tronquée (DI-5) |

---

## Points forts à conserver

- La vue de transcription est partagée entre le résultat frais et l'historique (une seule implémentation du rendu et du renommage).
- Le design system est centralisé (`Theme.swift`, `Components.swift`) et les composants sont réutilisés de façon cohérente (cartes, capsules, `WaveformBars`).
- Le clavier reproduit fidèlement le comportement du clavier système : double-espace, verrou majuscule, répétition de Supprimer, appui long sur les accents avec glissé continu, clic `playInputClick` qui respecte le réglage utilisateur.
- Les choix système sont honnêtes (C5 assumé, avertissement de chunks manquants, alerte d'interruption).
- La copie est en français soigné, au tutoiement constant.

## Ordre d'attaque suggéré

1. **Lot sécurité des données (S/M)** : n°1, n°2, RE-4.
2. **Lot quick wins visuels (S)** : AccentColor, contraste des boutons, nom et langue du clavier, « Start » → « Dicter », réglages, haptique de l'app.
3. **Lot accessibilité (M)** : Dynamic Type dans l'app, plafond Dynamic Type au clavier, VoiceOver au clavier et dans l'app.
4. **Lot onboarding (M)** : checklist d'activation et dictée test.
5. **Lot localisation (L)** : String Catalog, langue de dictée, QWERTY.
