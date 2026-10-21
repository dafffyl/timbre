# ADR-0009 — Rapport IA : plusieurs fournisseurs et catégories d'instructions

**Statut** : Proposé — 2026-10-22. Complète l'ADR-0006 (rapport de réunion),
qui fixait Groq comme seul fournisseur. Même principe : ce document vient
avant le code, dans la même branche.

## Contexte

Le premier test sur iPhone a renvoyé « Erreur Groq (404) ». Cause : Groq a
arrêté `llama-3.3-70b-versatile` et `llama-3.1-8b-instant` le 2026-08-16
(page de dépréciations Groq) ; un identifiant de modèle retiré répond 404.
Deux leçons : (1) coder en dur un identifiant de modèle est fragile — il faut
pouvoir lister ce que le service propose ; (2) dépendre d'un seul
fournisseur impose son calendrier. Besoin exprimé : choisir le fournisseur
du rapport, et créer des catégories d'instructions selon le type de réunion
ou de rapport voulu.

## Décisions

1. **Services** : Groq, OpenAI, Claude (Anthropic), Baseten et un point
   d'accès **personnalisé**. Groq, OpenAI, Baseten et le personnalisé parlent
   le même format (`POST {base}/chat/completions`, `Authorization: Bearer`) ;
   Claude a le sien (`POST /v1/messages`, `x-api-key`, consigne système
   séparée). Deux clients (`OpenAICompatibleChatClient`,
   `AnthropicChatClient`) derrière un protocole `ChatCompletionClient` ; le
   découpage des transcripts longs et les prompts restent dans
   `ChatMeetingSummaryProvider`, indépendants du service.
2. **Choix global** : un seul service + un modèle pour tous les rapports
   (Réglages), pas par catégorie ni par rapport.
3. **Une clé par service**, chacune dans le Keychain (service Keychain
   distinct par fournisseur). La clé Groq reste celle de la dictée. Aucune
   clé dans `UserDefaults`.
4. **Liste de modèles en ligne** (`GET {base}/models`) : l'utilisateur
   choisit parmi les modèles réellement disponibles ; les identifiants ne
   sont plus devinés. Les modèles qui ne font pas de chat (voix, embeddings,
   modération…) sont filtrés par mots-clés — approximatif, l'utilisateur
   peut saisir un identifiant à la main. Quand aucune valeur sûre n'est
   connue (OpenAI, Baseten, personnalisé) le modèle par défaut est vide : on
   demande plutôt que de deviner un identifiant qui finirait en 404.
5. **HTTPS obligatoire** pour le point d'accès personnalisé, sans exception
   ATS : pas de serveur local en `http` (Ollama sur le Mac) dans cette
   version.
6. **Catégorie = nom + format + instructions.** Le *format* est un cas fixe
   (`ReportFormat` : compte rendu structuré, résumé court, libre) qui
   ajoute une consigne de forme au prompt ; les *instructions* sont du texte
   libre qui la complète. Catégories fournies : « Compte rendu » (structuré)
   et « Résumé court ». Création, édition, suppression par l'utilisateur ;
   au moins une catégorie reste toujours. Stockage : `UserDefaults` (JSON),
   non sensible.
7. **Un seul rapport par réunion**, remplacé à la régénération (inchangé). Le
   rapport garde le nom de la catégorie et le service/modèle utilisés
   (champs optionnels : décodage tolérant des anciens rapports).
8. **Sélection** à la main au moment de générer (dernière catégorie utilisée
   par défaut) ; pas de suggestion automatique par le LLM.
9. **Température** : 0,3 pour Groq (valeur historique), omise ailleurs —
   certains modèles OpenAI refusent toute valeur autre que la leur.

## Conséquences

- Le texte du transcript part vers le service choisi : l'écran de réglages
  le dit et nomme le service. Changer de service change qui reçoit les
  transcripts.
- Les messages d'erreur nomment le service ; un **404** devient « modèle
  introuvable : choisis-en un autre » (cas vécu).
- Le nettoyage de dictée (`GroqTextCleanupProvider`, `llama-3.1-8b-instant`)
  a le même défaut et n'est **pas** traité ici (hors périmètre) : à corriger
  à part.
- Les listes de modèles dépendent d'un appel réseau et de la clé : sans clé
  ou hors ligne, repli sur les suggestions du préréglage.
