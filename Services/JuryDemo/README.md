# MORE — service de la version jury

Service Node **sans dépendance** pour le doublon iPhone de MORE. Il prépare le contexte d'un matin, comprend et révise une réponse avec OpenAI Responses, utilise ElevenLabs pour la voix, puis envoie réellement le texte relu via le compte Gmail Composio configuré. L'app principale n'utilise pas ce service.

Le déroulement est maîtrisé ; la formulation de l'utilisateur et le brouillon restent libres. Le modèle ne choisit jamais le destinataire, le compte, le sujet, un nom d'outil, une URL ou la réussite d'un effet externe.

## Configuration privée

Node 22.9 ou supérieur. Copier `.env.example` dans un fichier privé, remplir les valeurs puis lancer, depuis ce dossier :

```sh
node --env-file=/chemin/prive/more-jury.env server.mjs
```

Ne pas afficher ce fichier dans les logs ou l'enregistrer dans Git.

| Variable | Usage |
| --- | --- |
| `JURY_DEMO_TOKEN` | Secret aléatoire de 32 à 160 caractères URL-safe, également configuré dans le doublon iPhone. |
| `OPENAI_API_KEY`, `OPENAI_MODEL` | Modèle Responses prenant en charge la sortie JSON stricte ; `gpt-4.1-mini` par défaut. |
| `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID` | Voix réellement accessible à ce compte. `ELEVENLABS_MODEL` vaut `eleven_multilingual_v2` par défaut. |
| `COMPOSIO_API_KEY`, `COMPOSIO_GMAIL_ACCOUNT_ID`, `COMPOSIO_USER_ID` | Clé projet et compte Gmail personnel ACTIVE appartenant exactement à cet utilisateur Composio. |
| `COMPOSIO_GMAIL_VERSION` | Version figée des outils ; `20261010_00` par défaut, vérifiée contre leurs métadonnées. |
| `JURY_DEMO_SENDER` | Adresse Gmail attendue, vérifiée avec `GMAIL_GET_PROFILE` au démarrage et avant l'envoi. |
| `JURY_DEMO_RECIPIENT`, `JURY_DEMO_RECIPIENT_NAME` | Une seule adresse réelle autorisée et son nom. Utiliser son propre compte ou un destinataire consentant pour les répétitions. Aucun destinataire n'est fourni dans Git. |
| `JURY_DEMO_SLEEP`, `JURY_DEMO_WEATHER`, `JURY_DEMO_MEETING_TIME`, `JURY_DEMO_CALENDAR_CONFLICT` | Faits préparés. Ni capteur, ni boîte de réception, ni agenda réel ne sont lus par ces champs. |
| `JURY_DEMO_MAIL_SUBJECT` | Sujet préparé. Chaque session y ajoute `[MORE-xxxxxxxx]` pour permettre une réconciliation sans double envoi. |
| `JURY_DEMO_SOCIAL_URL` | URL HTTPS sur `www.instagram.com` ou `www.tiktok.com`. Aucun accès automatique à leur contenu n'est prétendu. |
| `JURY_DEMO_DATA_DIR` | Répertoire privé persistant des sessions, transcriptions textuelles et journaux d'effets ; `./data` par défaut. |
| `HOST`, `PORT` | `127.0.0.1:8791` par défaut. L'iPhone doit utiliser une origine joignable depuis son réseau. |

Le service démarre aussi avec les connexions absentes afin de signaler leur état ; il refuse de créer une fausse session. Pour exposer le service au téléphone, choisir explicitement l'interface réseau et protéger son accès. Garder une connexion HTTPS sur tout réseau non maîtrisé. Ne pas exposer ce serveur personnel directement sur Internet.

## Contrat iPhone

Toutes les routes sauf `/health` exigent `Authorization: Bearer <JURY_DEMO_TOKEN>`. Les POST exigent `Content-Type: application/json` ; les réponses ne sont pas mises en cache.

| Route | Entrée | Résultat |
| --- | --- | --- |
| `GET /health` | — | `{ok,service,configured:{conversation,speech,mail}}` sans identité ni secret. Indique la présence de configuration, pas une preuve d'accès au fournisseur. |
| `POST /v1/jury/session` | `{}` | `201` puis un `Turn` avec une identité de session opaque et le premier court passage. Vérifie d'abord le vrai compte Gmail. |
| `GET /v1/jury/session/{sessionID}` | — | Reprend la même session sans progression ni action externe. Réconcilie un envoi incertain en lecture seule ; ne prétend jamais l'avoir envoyé à nouveau. |
| `POST /v1/jury/turn` | `{sessionID,requestID,text}` | `Turn`. `requestID` est un UUID neuf par nouvelle prise de parole ; le conserver pour une reprise de cette même demande. |
| `DELETE /v1/jury/session/{sessionID}` | — | `Turn` arrêté. Invalide la génération en cours, annule OpenAI et empêche de nouveaux dispatchs. Une action déjà partie ne peut pas être annulée rétroactivement. |
| `POST /v1/jury/speech` | `{text}` | Bytes `audio/mpeg` provenant d'ElevenLabs. Aucun repli silencieux sur une voix système. |

`Turn` :

```json
{
  "sessionID": "opaque UUID",
  "stage": "mail",
  "text": "Le seul passage à lire et afficher maintenant.",
  "completed": false
}
```

`stage` vaut `morning`, `mail`, `draft`, `social`, `complete` ou `stopped`. Une confirmation de mail comprend `receipt: {type: "email", id: "Gmail message ID", status: "sent"}`. Le passage aux réseaux peut comprendre `action: {type: "openURL", url: "https://www.instagram.com/"}`. Une URL ouverte ne certifie ni stories lues ni scroll effectué.

Une erreur prend la forme `{error:{code,message}}` avec un statut HTTP 4xx/5xx. Ne pas répéter automatiquement une action à la suite d'un timeout. Un `requestID` réutilisé avec un texte différent est refusé.

Chaque demande dispose d'un budget total de 25 secondes, partagé entre les appels fournisseurs ; un appel individuel est limité à 15 secondes par défaut (`JURY_DEMO_TIMEOUT_MS`, maximum 30 secondes, sans dépasser le budget total). Aucun nouvel appel ne part après expiration du budget.

## Parcours et garanties

1. Un bonjour court annonce explicitement le contexte préparé du sommeil et de la météo, puis demande de regarder le message. Après accord, MORE lit la proposition de point produit de l'après-midi. Aucun enregistrement de l'inbox n'est inventé.
2. « Oui, dis-lui que je serai là » prépare une réponse librement formulée avec OpenAI ; elle est lue et affichée sur l'accueil existant.
3. « Propose plutôt 15 h 30 » ou « Fais plus court » révise le brouillon complet. Aucune réponse n'est envoyée à ce stade.
4. « Envoie » déclenche l'opération réelle. Un « oui » après lecture n'envoie rien ; les ordres composés ou conditionnels appellent une revue séparée. Les formulations simples acceptées comprennent « envoie le mail », « envoie la réponse » et « vas-y, envoie ».
5. Le service vérifie compte, utilisateur Composio, adresse Gmail et révision de connexion, réserve un journal durable, puis utilise uniquement `GMAIL_SEND_EMAIL`. La vérification finale exige le label `SENT`, l'expéditeur et le destinataire exacts, le sujet de cette session et le corps du brouillon.
6. Une coupure, un résultat incomplet ou un échec de vérification donne un état **incertain**, jamais « envoyé ». Un nouvel ordre d'envoi cherche ce même message dans les éléments envoyés et vérifie son contenu. Il ne relance pas le send. Le marqueur de sujet distingue les répétitions du scénario.
7. « Pause », « reprends », « arrête la routine » fonctionnent sans appel au modèle. Pause invalide le contexte d'envoi ; reprise relit le brouillon avant un nouvel ordre explicite. Stop invalide toute réponse tardive.
8. Les réseaux ouvrent la vraie URL configurée dans le navigateur MORE. Le serveur annonce que la navigation reste manuelle. Les rappels restent explicitement indisponibles tant qu'aucune route réelle ne les prend en charge.

**Un seul processus doit servir un même répertoire de données.** Les réservations d'effets utilisent une création atomique de fichier et les écritures sont synchronisées sur disque, mais les sessions actives et leurs interruptions sont coordonnées en mémoire. Ne pas multiplier les workers. Conserver le journal persistant entre redémarrages et ne pas l'effacer pour tenter à nouveau un envoi incertain.

Une session expire après six heures. Les fichiers ne sont pas supprimés automatiquement : les effacer après le jury et après réconciliation des effets. Les effets déjà envoyés ne sont pas annulés par cette suppression. Une nouvelle session permet une nouvelle répétition et donc un nouvel envoi réel.

L'iPhone peut conserver uniquement `sessionID` entre lancements et appeler GET pour reprendre. Une session arrêtée reste lisible, avec son reçu éventuel. Une session inconnue ou expirée renvoie `404` : le client ne doit pas démarrer silencieusement un nouveau matin. DELETE conserve les journaux et les confirmations nécessaires à la réconciliation.

## Confidentialité et preuve

Cette variante distante a été expressément demandée pour la démo. OpenAI reçoit uniquement le texte reconnu, les huit derniers passages utiles, les faits préparés et le brouillon ; `store:false` est demandé, sans prétendre que cela supprime toute rétention du fournisseur. ElevenLabs reçoit le texte à prononcer. Composio/Gmail reçoivent le brouillon lors de son envoi. Le service ne reçoit et ne conserve aucun enregistrement audio, aucune vidéo, aucun token OAuth brut. Les clés fournisseurs ne quittent pas le serveur.

Les sessions et les journaux contiennent du texte privé et sont stockés avec des permissions restreintes. Ils sont ignorés par Git. Le serveur ne journalise pas les corps des requêtes ni les réponses des fournisseurs.

```sh
npm test
```

Les tests locaux simulent les fournisseurs et vérifient le contrat, les erreurs, la revue, l'envoi unique, le redémarrage, la réconciliation, les changements d'identité et l'arrêt pendant un appel tardif. Ils ne prouvent ni un envoi Gmail réel, ni l'accès ElevenLabs, ni la continuité audio iOS ; ces preuves doivent être obtenues séparément sur le téléphone et les comptes autorisés.

Vérification réelle du 16 octobre 2026, côté serveur : une proposition libre à 15 h 30 puis une révision exacte via OpenAI (1,80 s et 1,31 s), un audio ElevenLabs de 166 808 octets (2,17 s), et **un seul** envoi Gmail vers le compte lui-même. Le label SENT, l'expéditeur, le destinataire, le sujet et le corps exact ont été vérifiés en 2,86 s pour l'envoi et sa vérification, sans nouvel essai. Après redémarrage du service, GET a retrouvé la même session et son reçu sans action externe. Les identifiants, adresses et contenus de cette preuve restent dans le journal privé. Cela ne certifie pas encore le parcours vocal sur iPhone ni la navigation sociale.

Contrats fournisseurs consultés : [OpenAI Structured Outputs / Responses](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses), [Composio execute v3.1](https://docs.composio.dev/reference/api-reference/tools/postToolsExecuteByToolSlug), [catalogue Gmail](https://docs.composio.dev/toolkits/gmail), [ElevenLabs text to speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert).
