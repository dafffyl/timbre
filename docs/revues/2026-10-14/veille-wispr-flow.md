# Veille concurrentielle : Wispr Flow vs Timbre

*Rédigé le 2026-10-14. Sources web consultées le même jour. Le dépôt Timbre a été lu en lecture seule (`main` @ c623f67, PR #31).*

## 0. Nom et domaine

- Produit : **Wispr Flow**, édité par la société **Wispr** (et non « Whisper Flow »). Domaine officiel : **wisprflow.ai**. Doc : docs.wisprflow.ai. « whisperflow.ai » n'est pas le site officiel.
- Contexte : levée de 280 M$ pour une valorisation de 2 Md$, annoncée en août 2026 ([PYMNTS](https://www.pymnts.com/news/investment-tracker/2026/wispr-flow-raises-280-million-and-debuts-voice-ai-model/), [VKTR](https://www.vktr.com/ai-platforms/wispr-hits-2b-valuation-launches-canto-voice-model/)). Le rythme de livraison est soutenu : release notes publiées chaque semaine.

## 1. Wispr Flow : état au 14 octobre 2026

### 1.1 Moteur et cloud
- **Canto**, le premier modèle de reconnaissance vocale maison (environ 2 milliards de paramètres), a été déployé pour tous les utilisateurs le **17/09/2026** ([whats-new](https://wisprflow.ai/whats-new), [canto](https://wisprflow.ai/canto)). Wispr annonce le WER le plus bas face à Google, OpenAI, AssemblyAI et Deepgram, mais sur son propre jeu de test anglais (environ 10 h de dictées réelles). Ce chiffre n'a pas été vérifié par un tiers. Le modèle n'a ni API publique ni poids publiés, et un successeur dix fois plus gros est en entraînement.
- Le traitement est **100 % cloud, sans aucun mode hors ligne**. La doc officielle le dit explicitement ([limitations](https://docs.wisprflow.ai/articles/4048537120-what-to-expect-from-flow-accuracy-and-known-limitations)). Selon des sources tierces, l'audio part chez Baseten, et le formatage passe par OpenAI, Anthropic ou Cerebras, avec un stockage AWS us-east-1 ([embertype](https://embertype.com/blog/the-day-wispr-flow-banned-a-user/)).
- Performances : -27 % de mémoire et -14 % de latence médiane sur Mac et Windows (post X du 07/10/2026). Le 09/07/2026, Wispr annonçait 99,9 % d'uptime et -30 % de latence depuis janvier.
- Langues : plus de 100 en dictée, avec une seule langue détectée par dictée (pas de bascule au sein d'une phrase). Wispr recommande de choisir la langue manuellement plutôt que la détection automatique ([multi-langues](https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages)). Depuis septembre et octobre 2026, une invite « Speaking a different language? » apparaît sur desktop.

### 1.2 iPhone (clavier iOS)
- **Version 1.77 du 01/10/2026**, iOS 18.3 minimum, 191 Mo, note de 4,8/5 sur 17 000 avis ([App Store](https://apps.apple.com/us/app/wispr-flow-ai-voice-keyboard/id6497229487)). Les notes de version de l'App Store sont génériques depuis la 1.72.
- **Architecture identique à celle de Timbre** : clavier tiers, Accès complet obligatoire, micro tenu par l'app conteneur. Le fonctionnement repose sur des « Flow sessions » : l'app ouvre le micro pendant une fenêtre de 5 min, 15 min, 1 h ou sans limite, puis revient dans l'app hôte ([setup](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone), [field guide](https://github.com/vkorost/wispr-flow-field-guide/blob/main/book/chapters/05-iphone.md)).
- **Retour automatique dans l'app hôte (switchback)** :
  - La v1.63 du 02/07/2026 annonce un « auto-switchback sur toutes les versions iOS supportées, plus d'apps ».
  - La doc [Adapting to iOS 26.4](https://docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4) admet pourtant que le retour peut échouer. L'écran « Flow is on » demande alors de glisser manuellement le long du bord inférieur, et iOS 26.4 déploie ce changement progressivement.
  - **Conclusion : Wispr rencontre la même contrainte C5 que Timbre.** Il la contourne de façon partielle, apparemment par une liste d'apps connues (URL schemes, sans doute). Ce contournement reste fragile.
- Une dictée dure au plus 5 minutes sur iOS. Le résultat est inséré quand on tape ✓, et un X annule. Il faut garder le clavier affiché jusqu'à la fin du traitement, sinon le résultat part dans l'historique.
- Fonctions propres à iOS :
  - Styles : depuis iOS 26.4, l'ajustement par app ne fonctionne plus sur iPhone. Il reste un style par défaut (Formal, Casual, very casual, Excited) et un **Quick Style Switcher** sur le clavier (v1.46).
  - **Action Button**, 6 raccourcis Siri (iOS 18.3+), widgets du Centre de contrôle, **Live Activity** dans la Dynamic Island, dictée rapide vers Notes ou vers le presse-papiers (v1.52, avril 2026).
  - Notes (« Scratchpad » sur desktop) synchronisées avec le desktop (v1.59).
  - v1.62 (17/06/2026) : notification en cas de dictée interrompue, **réessai en un tap**, chronomètre en direct, retour arrière « intelligent ».
  - Champs numériques, téléphone et email : iOS bascule sur le clavier système.
  - Batterie : environ 5 %/h aujourd'hui, contre environ 40 %/h dans les anciennes versions ([field guide](https://github.com/vkorost/wispr-flow-field-guide/blob/main/book/chapters/05-iphone.md)).
- Pas de Notetaker sur mobile : Mac et Windows seulement, le mobile est « sur la roadmap » ([pricing](https://wisprflow.ai/pricing)).

### 1.3 Mac (desktop)
- Dictée par raccourci, maintenu ou en mains libres, collée via le presse-papiers, avec la Flow Bar déplaçable. Une dictée peut durer 20 minutes depuis le 31/03/2026.
- **Auto Cleanup** sur 4 niveaux (24/04/2026) : retrait des hésitations, prise en compte des corrections en cours de phrase (« backtrack »), listes, ponctuation dictée. Le 24/06/2026, un modèle de formatage unique a été déployé.
- **Styles** par app (anglais uniquement, desktop) ([features](https://wisprflow.ai/features)).
- **Context awareness** : lecture de l'arbre d'accessibilité de l'app active, activée par défaut. Un OCR d'écran est disponible en option.
- **Command Mode** (expérimental, desktop) : on sélectionne du texte et on donne une instruction vocale (réécrire, répondre, chercher) ([doc](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode)).
- **Transforms** (bêta, 01/05/2026) : réécriture IA du texte sélectionné par raccourci, avec les transforms « Polish » et « Prompt Engineer » et des prompts personnalisés ([doc](https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta)).
- **Scratchpad** (bêta) : bloc-notes riche à onglets.
- Développeurs : sensibilité à la syntaxe (camelCase, CLI), tagging de fichiers dans Cursor et Windsurf.
- Historique avec **réécoute audio sur 14 jours** (05/08/2026), onglet Insights, choix du micro (virtuel ou routage, 21/08/2026), alerte « micro muet » (09/10/2026).
- **Notetaker** (Mac le 05/08/2026, Windows le 15/09/2026) :
  - Enregistrement de réunion sans bot (audio système et micro), transcript, résumé, recherche transversale entre réunions.
  - Noms des locuteurs **inférés** depuis le calendrier et le contexte, et non par une vraie diarisation acoustique pure ([tldv](https://tldv.io/blog/wispr-flow-notetaker-review/)). Détection des locuteurs pour Teams et Meet (09/10/2026).
  - **Serveur MCP** (Claude, ChatGPT, Gemini) qui donne accès aux notes et transcripts, mais pas aux dictées.
  - Import depuis Otter et Granola avec les noms de locuteurs, 22 langues avec détection automatique, traduction des transcripts en bêta (06/10/2026).

### 1.4 Cloud, synchro, personnalisation
- **Dictionnaire** : ajout manuel, apprentissage automatique à partir des corrections de l'utilisateur, et influence directe sur la reconnaissance avec Canto ([doc](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary)).
- **Snippets** : une phrase-clé dictée est remplacée par un texte long (en texte riche depuis le 29/07/2026). Dictionnaire et snippets peuvent être partagés à l'échelle d'une équipe, d'une organisation ou d'un département (04/09/2026).
- **Cloud Sync** (17/06/2026) : séparé de **Privacy Mode**, qui ne contrôle que l'entraînement des modèles. Une rétention nulle demande Privacy Mode activé **et** Cloud Sync désactivé ([data-controls](https://wisprflow.ai/data-controls), [Voibe](https://www.getvoibe.com/resources/is-wispr-flow-safe/)). Dictionnaire et snippets sont synchronisés dans tous les cas. Stockage local au choix : conservé, supprimé après 24 h ou jamais stocké (24/04/2026).
- Conformité : SOC 2 Type II et ISO 27001 affichés, BAA HIPAA sur tous les plans. Une source tierce (Voibe) signale toutefois que les anciens certificats venaient de l'écosystème Delve (scandale de mars 2026) et qu'un SOC 2 **Type I** A-LIGN a été obtenu en avril 2026. Depuis le 02/10/2026, l'entraînement est désactivé pour tous les membres Growth et Enterprise.

### 1.5 Tarifs ([pricing](https://wisprflow.ai/pricing), consulté le 14/10/2026)
| Plan | Prix | Limite |
|---|---|---|
| Free | 0 $ | 2 000 mots/semaine sur desktop, **1 000 mots/semaine sur iPhone**, Notetaker limité |
| Pro | 15 $/mois ou 12 $/mois en annuel (App Store : 143,99 $/an, 4,49 $/semaine, étudiants -50 %) | illimité |
| Growth | 23 $/mois ou 18 $/mois en annuel | SSO SAML, HIPAA à l'échelle de l'organisation, contrôle de l'entraînement, Notetaker illimité |
| Enterprise | sur devis | SCIM, MDM, audit logs |

### 1.6 Plaintes et limites relevées
- **Fiabilité** : plusieurs jours d'indisponibilité fin mai et juin 2026. Wispr a publié un post-mortem et effectué un rollback de précision les 04 et 10/06/2026. Voibe, un concurrent donc une source partiale, compte plus de 75 incidents en 6 mois ([Voibe outages](https://www.getvoibe.com/resources/is-wispr-flow-reliable/), [Medium](https://medium.com/@ryanshrott/wispr-flow-went-down-for-two-hours-that-is-not-a-small-problem-028c5643ad98)). **Sans réseau, plus de dictée.**
- **Confidentialité** :
  - Un utilisateur a été banni après avoir révélé l'envoi de captures d'écran de l'app active (2025).
  - Un rapport forensique d'avril 2026 sur le Mac v1.4.752 relève une event tap système, une base locale de 694 Mo et des uploads horaires qui continuaient avec le partage désactivé.
  - Des statistiques de mots tirées des dictées ont été publiées sur LinkedIn (10/08/2026).
  - Sources : [Voibe](https://www.getvoibe.com/resources/is-wispr-flow-safe/) (article mis à jour le 13/10/2026), [ModelPiper](https://modelpiper.com/blog/wispr-flow-privacy-incident).
- **Avis** : Trustpilot autour de 2,7/5, contre 4,8/5 sur l'App Store. Plaintes iOS : latence sur réseau faible, frictions liées à l'aller-retour vers l'app, conflit avec la dictée native.
- **Fonctions** : les styles sont en anglais seulement. Une seule langue par dictée. Command Mode et Transforms sont absents sur iOS. Notetaker est absent sur mobile.

## 2. Timbre : ce qui existe aujourd'hui

D'après les fichiers README, CLAUDE.md, `docs/adr/0001` à `0005` et le code de `main`.

- **Clavier de dictée** :
  - Clavier AZERTY complet, à parité avec le clavier système (#19).
  - Le clavier sert de « télécommande ». Le micro est tenu par l'app via un enregistrement en arrière-plan (ADR-0002).
  - Canal entre clavier et app : App Group et notifications Darwin.
  - Onde audio en direct, reprise à chaud, invite claire quand l'Accès complet manque (C3).
  - Limite de 180 s par dictée (`DictationController.maxRecordingDuration`).
  - Contraintes : budget mémoire du clavier de 77 Mo au maximum, cible 35 à 40 Mo (C2). Retour automatique dans l'app hôte impossible par API publique (C5).
- **Transcription** :
  - Groq `whisper-large-v3`, derrière une abstraction `TranscriptionProvider` qui permet de changer de fournisseur.
  - L'utilisateur fournit **sa propre clé API**, stockée dans le Keychain.
  - **Langue codée en dur `"fr"`** (DictationController l.204, MeetingTranscriptionController l.101).
  - Vocabulaire personnalisé transmis à Whisper comme `prompt` (#17), avec audio compressé.
  - Nettoyage LLM optionnel (`llama-3.1-8b-instant`), désactivé par défaut (#18).
- **Réunions** :
  - Enregistrement live en arrière-plan.
  - **Diarisation locale FluidAudio sur l'appareil** : environ 4 % de confusion entre locuteurs, traitement à 0,02x le temps réel, modèles de 500 Mo téléchargés au premier usage.
  - Transcription Groq par chunks de 25 Mo en parallèle, puis alignement des mots sur les locuteurs (ADR-0003 et 0005).
  - Dégradation chunk par chunk : un chunk en échec ne fait pas échouer toute la réunion (#29).
  - Historique (#27), renommage des locuteurs (#28), export via la feuille de partage (#25), reprise après une interruption audio (#31).
  - Transcription non-streaming : elle démarre seulement à la fin de l'enregistrement.
- **Absent aujourd'hui** :
  - Import de fichier audio : l'ADR-0005 a choisi de commencer par le live.
  - Historique des dictées, réessai, styles, snippets, résumé, multi-langue.
  - Shortcuts, Action Button, Live Activity.
  - Mode hors ligne : il serait possible, mais n'est pas implémenté.
  - Synchro, desktop.

## 3. Matrice comparative

Légende : ✅ présent, 🟡 partiel, ❌ absent.

| Domaine | Wispr Flow (oct. 2026) | Timbre (main) |
|---|---|---|
| Clavier iOS tiers + Accès complet | ✅ | ✅ |
| Micro tenu par l'app conteneur (sessions) | ✅ sessions de 5 min à illimitée | ✅ enregistrement en arrière-plan (ADR-0002) |
| Retour automatique dans l'app hôte | 🟡 liste d'apps, cassé ou progressif sous iOS 26.4 | ❌ assumé (C5) |
| Clavier de saisie complet | 🟡 (bascule sur le clavier système pour certains champs) | ✅ AZERTY complet, à parité |
| Moteur STT | Canto, propriétaire, cloud | Whisper large-v3 via Groq, fournisseur interchangeable |
| Hors ligne | ❌ | ❌ (possible avec un modèle local dans l'app) |
| Langues | 100+, une par dictée, choix manuel ou auto | 🟡 français seulement, codé en dur |
| Nettoyage, ponctuation, retrait des hésitations | ✅ 4 niveaux, backtrack | 🟡 optionnel, expérimental |
| Styles / tons | 🟡 sur iOS : défaut + Quick Switcher, en anglais | ❌ |
| Dictionnaire | ✅ manuel + appris des corrections + influence sur la reconnaissance | 🟡 prompt Whisper manuel |
| Snippets | ✅ (texte riche, partage d'équipe) | ❌ |
| Commande vocale / réécriture | ✅ desktop (Command Mode, Transforms) ; ❌ iOS | ❌ |
| Historique des dictées + réessai | ✅ (réessai en un tap, réécoute 14 j sur desktop) | ❌ (réunions seulement) |
| Action Button / Shortcuts / Live Activity | ✅ | ❌ |
| Notes rapides | ✅ synchronisées avec le desktop | ❌ |
| Durée max d'une dictée | 5 min sur iOS, 20 min sur desktop | 3 min |
| Transcription de réunion sur iPhone | ❌ (Mac et Windows seulement) | ✅ |
| Diarisation | 🟡 noms inférés (calendrier, contexte), traitement cloud | ✅ **acoustique, sur l'appareil** |
| Renommage des locuteurs | ✅ correction en un clic | ✅ |
| Résumé, actions, recherche entre réunions | ✅ | ❌ |
| Import de réunions (fichiers, Otter, Granola) | ✅ | ❌ |
| MCP / intégrations LLM | ✅ (Notetaker) | ❌ |
| Export | ✅ | ✅ feuille de partage (texte) |
| Synchro multi-appareils / desktop | ✅ | ❌ |
| Confidentialité | Cloud, toggles Privacy Mode / Cloud Sync, historique d'incidents | Clé de l'utilisateur, aucun serveur Timbre, aucun contenu loggé, diarisation locale, open source MIT |
| Modèle économique | Freemium (1 000 mots/semaine sur iPhone), Pro à 12-15 $ | Gratuit (open source), l'utilisateur paie Groq à l'usage (environ quelques centimes par heure) |

## 4. Ce qui différencie Timbre (à protéger et à mettre en avant)

1. **La transcription de réunion avec diarisation sur iPhone.** Wispr ne la propose pas sur mobile : Notetaker est desktop seulement, et la mobilité est « sur la roadmap ». C'est la fenêtre d'opportunité principale, mais elle peut se refermer vite vu le rythme de livraison de Wispr.
2. **Une diarisation acoustique locale**, plutôt que des noms inférés depuis le calendrier : elle fonctionne pour une réunion en présentiel, sans invitation, avec un seul téléphone posé sur la table.
3. **La confidentialité par construction** : pas de serveur intermédiaire, une clé API personnelle, du code auditable. C'est un argument fort face aux incidents publics de Wispr.
4. **Un fournisseur interchangeable** : l'utilisateur n'est pas captif d'un modèle propriétaire. Cela ouvre la porte à un mode hors ligne, ce que Wispr ne peut pas offrir.
5. **Un vrai clavier complet** (AZERTY, à parité avec le système), en plus du micro.
6. **Une limite de coût prévisible** : pas de plafond de mots, pas d'abonnement.

## 5. Fonctionnalités à ajouter, par ordre de priorité

Effort : S ≈ moins de 2 jours, M ≈ 1 semaine, L ≈ plusieurs semaines. Les dépendances iOS renvoient aux contraintes C1 à C5 de CLAUDE.md.

### P0 : combler les écarts qui coûtent le plus d'usage, pour un effort faible

| # | Fonction | Valeur | Effort | Risques et dépendances iOS |
|---|---|---|---|---|
| 1 | **Choix de la langue** (réglage, puis option « auto » sans `language`) | Débloque tout utilisateur non francophone ou bilingue. Le `"fr"` codé en dur est le plus gros trou par rapport aux « 100+ langues » de Wispr. | S | Aucune limite de clavier. Le prompt de nettoyage s'adapte déjà via `languageHint`. En mode auto, Whisper se trompe parfois sur les courtes dictées : garder un choix manuel par défaut (c'est aussi la recommandation de Wispr). Ajouter un sélecteur rapide sur le clavier, ce qui se limite à un enum dans l'App Group (léger pour C2). |
| 2 | **Historique des dictées + réessai** (audio conservé N jours dans le conteneur de l'app) | Évite de perdre une dictée quand le réseau tombe ou que l'utilisateur quitte le clavier : c'est la plainte n°1 sur ce type de produit. Wispr l'a ajouté en v1.62. | M | Stockage dans l'app, **pas dans le clavier** (C2). Le clavier lit seulement le dernier texte via l'App Group, ce qui demande l'Accès complet (C3). Purge automatique et invariant « aucun contenu loggé » à respecter. Réutilise `FileMeetingHistoryStore`. |
| 3 | **Bouton « coller la dernière transcription »** sur le clavier + fallback presse-papiers | Récupère un résultat arrivé après le retour dans l'app hôte (C5) | S | `UIPasteboard` depuis l'extension demande l'Accès complet. Rester attentif à la bannière de confidentialité du presse-papiers d'iOS. |
| 4 | **Durée max de dictée configurable** (3 min, puis 5 à 10 min) | Parité avec Wispr (5 min sur iOS) | S | Limite de 25 Mo chez Groq : réutiliser `AudioChunker` et le stitcher au-delà. Garde-fou batterie. |

### P1 : renforcer ce qui différencie Timbre (réunions)

| # | Fonction | Valeur | Effort | Risques et dépendances iOS |
|---|---|---|---|---|
| 5 | **Import d'un fichier audio ou vidéo** de réunion (Fichiers, mémos vocaux, feuille de partage) | Usage très fréquent (enregistrements Zoom ou dictaphone). Le pipeline ADR-0005 l'accepte déjà en entrée. | M | `fileImporter` + `AVAssetExportSession` vers m4a. Gros fichiers : chunking déjà prêt. Mémoire de l'app non contrainte (hors C2). Une share extension serait un L à part, avec sa propre limite mémoire d'environ 120 Mo : rester sur un import dans l'app. |
| 6 | **Résumé + décisions + actions** de réunion (LLM Groq, réutilise `TextCleanupProvider`) | Le cœur de l'argumentaire de Notetaker. Rend la diarisation directement exploitable. | M | Contexte du modèle : les longues réunions demandent un map-reduce par blocs. Coût Groq. Les hallucinations doivent rester identifiables : citer les tours de parole. |
| 7 | **Export enrichi** : Markdown, SRT/VTT, horodatage, noms des locuteurs | Intégration dans Notion, Obsidian ou un compte rendu | S | Aucun. `TranscriptFormatter` existe déjà. |
| 8 | **Recherche plein texte dans l'historique des réunions** | Équivalent de la « recherche entre réunions » de Wispr | S-M | Index local simple au début. Core Spotlight en option (attention à la confidentialité : opt-in). |
| 9 | **Reconnaissance des voix connues entre réunions** (embeddings de locuteurs enregistrés, nom réattribué automatiquement) | Supprime le renommage manuel. Spécifique à une diarisation acoustique, donc **impossible à copier pour Wispr avec son approche calendrier**. | L | FluidAudio expose des embeddings. Il faut un seuil de similarité et une gestion des faux positifs. Ce sont des **données biométriques** (RGPD art. 9) : opt-in explicite, stockage local chiffré, suppression facile. |
| 10 | **Transcription progressive pendant l'enregistrement** (chunks envoyés au fil de l'eau, diarisation toujours globale à la fin) | Réduit l'attente en fin de réunion | M-L | Ne pas casser la règle de l'ADR-0005 (diarisation en un seul passage). Seule la branche Groq passe en flux. Réseau en arrière-plan et risque de suspension de l'app. Coût identique. |
| 11 | **Live Activity / Dynamic Island** pendant l'enregistrement de réunion et de dictée | Rend visible un enregistrement en cours. Corrige aussi le cas du bug #31 (un chronomètre qui tourne alors que le flux est coupé). | M | ActivityKit dans l'app (pas dans le clavier). Doit refléter l'état réel du flux audio, pas l'horloge. |

### P2 : confort de dictée (rattraper les fonctions iOS de Wispr)

| # | Fonction | Valeur | Effort | Risques et dépendances iOS |
|---|---|---|---|---|
| 12 | **App Intents** : Shortcuts, Action Button, widget du Centre de contrôle (« Dicter vers le presse-papiers », « Démarrer une réunion ») | Démarrer sans passer par le clavier : contourne en partie C5 | M | Tout se passe côté app (micro autorisé). Contrôle du Centre de contrôle à partir d'iOS 18. Action Button seulement sur iPhone 15 Pro et plus récents. |
| 13 | **Snippets** (phrase-clé remplacée par un texte) | Gain quotidien fort (adresse, signature, lien) | S-M | Remplacement après transcription, **dans l'app**, avant l'écriture dans l'App Group. Le clavier ne fait rien de plus (C2). Matching tolérant aux variations de Whisper (casse, ponctuation). |
| 14 | **Styles / tons** (neutre, pro, décontracté, ou prompt personnalisé), avec un sélecteur sur le clavier | Équivalent du Quick Style Switcher de Wispr. En français, alors que les styles de Wispr sont en anglais seulement. | S-M | Dépend du nettoyage LLM (#18), qui devient plus important. Latence ajoutée par un second appel. Sur iOS, l'app hôte ne peut pas être détectée de façon fiable : Wispr a perdu les styles par app avec iOS 26.4. Proposer un choix manuel uniquement. |
| 15 | **Dictionnaire structuré** (liste de termes plutôt qu'un prompt libre) + remplacements post-transcription (« Don » → « Dawn ») | Fiabilise les noms propres. Approche l'« auto-learn » de Wispr. | M | Le prompt Whisper est limité à environ 224 tokens : prioriser les termes. L'apprentissage automatique à partir des corrections est **difficile sur iOS**, car le clavier ne voit pas les modifications faites dans l'app hôte après insertion (`textDocumentProxy` limité au contexte proche). Un apprentissage partiel reste possible en relisant `documentContextBeforeInput` juste après l'insertion, mais c'est fragile : L si on vise l'automatique. |
| 16 | **Commande vocale de réécriture** (« rends ça plus formel », « traduis en anglais ») sur le texte sélectionné ou précédant le curseur | L'équivalent iOS de Command Mode, **que Wispr n'a pas sur iPhone** | M | `textDocumentProxy.selectedText` (iOS 16+) et `documentContextBeforeInput` sont **partiels** : quelques phrases seulement, et le contenu n'est pas exposé par toutes les apps. Remplacer du texte demande des `deleteBackward` en boucle : risqué sur les longs textes. |
| 17 | **Investiguer le switchback de Wispr** (v1.63, « liste d'apps ») | Réduire la friction C5 pour les apps courantes | S (spike) | Probablement des URL schemes connus des apps hôtes (`whatsapp://`, etc.), ou des API privées. **Risque de rejet par App Review** et comportement cassé par iOS 26.4. À traiter comme un spike, pas une promesse (CLAUDE.md, C5). |

### P3 : paris structurants (à arbitrer)

| # | Fonction | Valeur | Effort | Risques et dépendances iOS |
|---|---|---|---|---|
| 18 | **Mode hors ligne / sur l'appareil** (WhisperKit ou un modèle CoreML de FluidAudio, dans l'**app**) | Différenciateur majeur face à Wispr (100 % cloud, sans réseau = sans dictée). Mode « avion / confidentiel ». | L | Jamais dans le clavier (C2 et l'invariant « zéro ML dans le clavier »). Modèles de plusieurs centaines de Mo, temps de chargement à froid (FluidAudio : environ 23 s), chauffe et batterie, qualité inférieure à large-v3 sur les petits modèles. Le `TranscriptionProvider` existant le permet sans toucher au reste. |
| 19 | **Second fournisseur cloud** (OpenAI, Deepgram, Mistral Voxtral…), avec bascule automatique en cas de panne Groq | Résilience : les pannes sont la plainte n°1 contre Wispr | M | Déjà prévu (`adding-a-provider.md`). Gérer plusieurs clés dans le Keychain. |
| 20 | **Serveur MCP / export vers un LLM** des transcripts | Parité avec Notetaker | L | Pas de serveur sur iOS. Il faudrait un export de fichiers (iCloud Drive, Obsidian) ou un compagnon desktop. Faible priorité tant qu'il n'existe pas de version Mac. |
| 21 | **Synchro iCloud** de l'historique, du vocabulaire et des snippets | Utile en multi-appareils | M | Contredit la politique « pas d'iCloud » pour les **clés**, mais pas pour les contenus. En faire un opt-in explicite. CloudKit avec chiffrement de bout en bout (Advanced Data Protection). |

### À ne pas copier
- **La capture du contexte d'écran ou d'accessibilité** : c'est la source des incidents de confidentialité de Wispr, et elle est impossible depuis un clavier iOS de toute façon.
- **Les compteurs de mots, streaks et notifications d'engagement** : peu de valeur, et en contradiction avec le positionnement de Timbre.
- **Les styles par app sur iOS** : Apple a cassé cette détection avec iOS 26.4.

## 6. Recommandation de séquencement

1. **Sprint court** : #1 langues, #3 coller la dernière transcription, #4 durée, #7 export enrichi. Uniquement des S, avec un fort impact perçu.
2. **Consolider les réunions** : #5 import de fichier, #6 résumé et actions, #2 historique et réessai de dictée.
3. **Creuser l'écart** : #9 reconnaissance des voix connues, #18 mode hors ligne. Ces deux points demandent un ADR chacun : choix structurants à trancher par toi.
4. Mettre en avant dans le README et l'App Store : « diarisation de réunion sur iPhone, locale, sans abonnement, sans serveur tiers autre que le fournisseur STT choisi ».

## Sources principales
- https://wisprflow.ai/whats-new (release notes, consulté le 14/10/2026)
- https://releasebot.io/updates/wispr-flow
- https://wisprflow.ai/pricing
- https://wisprflow.ai/features
- https://wisprflow.ai/canto , https://wisprflow.ai/lab
- https://wisprflow.ai/data-controls , https://wisprflow.ai/privacy
- https://docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4
- https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone
- https://docs.wisprflow.ai/articles/4048537120-what-to-expect-from-flow-accuracy-and-known-limitations
- https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode
- https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta
- https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary
- https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages
- https://apps.apple.com/us/app/wispr-flow-ai-voice-keyboard/id6497229487 (v1.77, 01/10/2026)
- https://github.com/vkorost/wispr-flow-field-guide/blob/main/book/chapters/05-iphone.md (guide communautaire)
- https://tldv.io/blog/wispr-flow-notetaker-review/
- https://www.getvoibe.com/resources/is-wispr-flow-safe/ et https://www.getvoibe.com/resources/is-wispr-flow-reliable/ (concurrent, donc partial)
- https://www.pymnts.com/news/investment-tracker/2026/wispr-flow-raises-280-million-and-debuts-voice-ai-model/
- https://medium.com/@ryanshrott/wispr-flow-went-down-for-two-hours-that-is-not-a-small-problem-028c5643ad98
