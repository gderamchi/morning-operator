# MORE Démo — passage devant le jury

MORE Démo est un doublon isolé de MORE. Le parcours conserve l’accueil, le paysage et les commandes habituelles : aucun écran ni panneau de présentation supplémentaire.

Avant de commencer, préciser oralement : **« Le sommeil, la météo et le message de départ sont préparés pour ce matin. La rédaction et l’envoi du mail utilisent de vrais services. »** Le message annoncé ne provient pas d’une lecture en direct de l’inbox.

## État vérifié au 16 octobre 2026

- **Services réels :** rédaction libre puis révision avec OpenAI, synthèse ElevenLabs, un seul mail envoyé au compte lui-même et relu avec label SENT, destinataire et contenu exacts. La reprise serveur retrouve le reçu sans nouvel envoi.
- **iPhone :** deux tests d’interface avec données de test passent. Un autre test utilise le vrai audio : neuf secondes en arrière-plan, pause, reprise avec lecture effective, puis arrêt. Il passe en 76,52 s ; résultat local non versionné : `work/jury-demo-final-lifecycle-verified.xcresult`.
- **Dynamic Island :** rendu réel observé par capture et accessibilité. Les commandes restent à valider : le premier harnais mettait l’activité en pause avant d’interroger ses actions et utilisait un ancien libellé d’accessibilité. Il est adapté ; aucun défaut produit n’est établi par cet essai.
- **Logique partagée :** commande Swift réussie après intégration de `main` (`e8312a9`), avec 1 961 tests rapportés dans 226 suites et 7 tests optionnels ignorés ; 36 tests du service réussis. Le graphe audio iOS a changé depuis (`f1878ab`) : le package macOS ne couvre pas ce code conditionnel iOS, dont le nouvel essai téléphone reste en cours.
- **Python :** le contrôle historique sur `463af5f` comptait 33 méthodes réussies et une en échec pour 133 traductions anglaises absentes (104 dans le catalogue principal, 29 dans MorningApple). La PR 207 a corrigé ces catalogues ; les 34 méthodes passent sur le `main` combiné `1fc10f7` et [l’issue 208](https://github.com/gibouu/morning-operator/issues/208) est résolue.
- **Conversion audio numérique :** quatre cas Float32 à 44,1 kHz, mono/stéréo vers 48 kHz mono, passent sur des signaux d’une seconde et de 8,4 secondes : écart de durée nul et fin conservée. Cela ne valide pas la reconnaissance acoustique.
- **Encore non prouvés :** conversation acoustique interactive complète, création réelle d’un rappel, connexion et navigation dans un fil Instagram. L’entrée audio examinée contient uniquement des zéros en Float32 mono 48 kHz, malgré les autorisations accordées et les indicateurs muet désactivés. Le diagnostic et l’essai du nouveau graphe continuent. La démo complète devant jury n’est pas déclarée validée.

## Préparer la répétition

- Installer **MORE Démo**, avec sa configuration privée, à côté de l’app principale.
- Garder le Mac allumé, éveillé et connecté à Internet ; le téléphone et le Mac utilisent le même Wi-Fi, sans isolation entre appareils.
- Depuis la racine du dépôt, lancer `./Services/JuryDemo/run-local.sh`. Le script charge le `.env` privé du service ; ne jamais le projeter ni en afficher le contenu.
- Vérifier l’origine locale configurée dans l’app : le nom Bonjour du Mac et le port doivent être joignables depuis l’iPhone. La variante iOS autorise cette communication locale via sa configuration réseau/ATS.
- Vérifier les accès microphone et reconnaissance vocale, la voix ElevenLabs, le compte Gmail et le destinataire **identique à ce compte** pour cette démo.
- Ouvrir Instagram dans le navigateur intégré, terminer la connexion et vérifier que des Reels sont accessibles avant le passage.
- Préparer Gmail pour retrouver rapidement les éléments envoyés. Chaque nouvelle session peut envoyer un nouveau vrai message ; arrêter les répétitions inutiles.
- Pour montrer un rappel créé, le passage doit précéder **14 h 40 aujourd’hui**, soit vingt minutes avant le rendez-vous préparé de 15 h. Préparer la permission Rappels dans le parcours normal.
- Arrêter la session de répétition avant de commencer le passage du jury.

Le service local sur le port 8791 fonctionne actuellement dans un processus détaché. Cette installation dépend du Mac éveillé et du même réseau local ; elle ne constitue pas un déploiement cloud ni une preuve de fonctionnement loin du Mac.

## Parcours visé de deux à trois minutes

Répéter d’abord les passages vocaux sur le téléphone. Garder les options Rappels et Instagram seulement après leur validation réelle ; les tests du serveur ne suffisent pas à les certifier.

**0:00 — Commencer son matin.** Lancer la routine sur le paysage normal. MORE évoque brièvement le sommeil et la météo préparés, puis propose de regarder le message. Répondre naturellement : « Oui, on regarde. »

**0:20 — Comprendre et répondre.** MORE explique la proposition de point produit à 15 h. Dire : « Oui, réponds que je serai disponible. » OpenAI prépare une réponse que MORE lit ; rien n’est encore envoyé.

**0:40 — Corriger librement.** Dire par exemple : « Fais plus court, et précise que c’est un message de démonstration avec une disponibilité fictive. » Écouter la nouvelle version. Une seule révision suffit à montrer que le dialogue accepte des formulations libres.

**1:00 — Produire un vrai résultat.** Dire « Envoie ». Attendre la confirmation vérifiée, puis ouvrir Gmail et montrer le message dans les éléments envoyés, avec son heure et son contenu. Le destinataire est le compte de démonstration lui-même.

**1:25 — Option Rappels, après validation et si l’heure le permet.** Revenir dans MORE et dire : « Rappelle-moi vingt minutes avant le point produit. » Le parcours prévu prépare un rappel natif à 14 h 40 et n’annonce sa création qu’après confirmation de l’iPhone. Si l’heure est passée ou l’accès refusé, conserver la réponse d’indisponibilité et continuer.

**1:45 — Option Instagram, après connexion et vérification du fil.** Demander de passer aux vidéos. Une fois un vrai Reel chargé dans le navigateur intégré, dire « La suivante » et vérifier le changement. Une page ouverte ou une connexion réussie ne vaut pas navigation vérifiée.

**2:10 — Garder le contrôle.** Montrer l’état dans la Dynamic Island. Après validation des commandes choisies, montrer pause, reprise et arrêt. Le test audio réussi établit ces changements de lecture en arrière-plan ; il ne valide pas encore leur déclenchement par une conversation acoustique.

Le rythme dépend de la conversation et des fournisseurs. Mieux vaut montrer ces quelques effets lisibles que multiplier les étapes ou réciter un texte exact.

## Si quelque chose ne répond pas

- Un envoi incertain se vérifie dans Gmail ; ne pas recommencer une nouvelle session pour le renvoyer. Le service conserve le journal et peut rechercher le résultat sans répéter l’envoi.
- Un rappel incertain se vérifie dans Rappels ; ne pas demander une seconde création pour masquer l’incertitude.
- Une connexion Instagram expirée se prépare à nouveau dans le navigateur ; ne pas prétendre qu’une vidéo a été parcourue si la page n’est pas disponible.
- Une panne du Mac, du réseau ou d’un fournisseur appelle un arrêt clair du passage.

Les détails des services et les limites de leurs preuves figurent dans [le service jury](../Services/JuryDemo/README.md). Actualiser ce statut seulement après observation du résultat correspondant sur le téléphone.
