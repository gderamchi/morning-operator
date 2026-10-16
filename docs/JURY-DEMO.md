# MORE Démo — passage devant le jury

MORE Démo est un doublon isolé de MORE. Le parcours conserve l’accueil, le paysage et les commandes habituelles : aucun écran ni panneau de présentation supplémentaire.

Avant de commencer, préciser oralement : **« Le sommeil, la météo et le message de départ sont préparés pour ce matin. La conversation et les actions que nous allons demander sont réelles. »** Le message annoncé ne provient pas d’une lecture en direct de l’inbox.

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

Cette installation dépend du Mac et du réseau local. Elle ne constitue pas un déploiement cloud ni une preuve de fonctionnement loin du Mac.

## Parcours de deux à trois minutes

**0:00 — Commencer son matin.** Lancer la routine sur le paysage normal. MORE évoque brièvement le sommeil et la météo préparés, puis propose de regarder le message. Répondre naturellement : « Oui, on regarde. »

**0:20 — Comprendre et répondre.** MORE explique la proposition de point produit à 15 h. Dire : « Oui, réponds que je serai disponible. » OpenAI prépare une réponse que MORE lit ; rien n’est encore envoyé.

**0:40 — Corriger librement.** Dire par exemple : « Fais plus court, et précise que c’est un message de démonstration avec une disponibilité fictive. » Écouter la nouvelle version. Une seule révision suffit à montrer que le dialogue accepte des formulations libres.

**1:00 — Produire un vrai résultat.** Dire « Envoie ». Attendre la confirmation vérifiée, puis ouvrir Gmail et montrer le message dans les éléments envoyés, avec son heure et son contenu. Le destinataire est le compte de démonstration lui-même.

**1:25 — Ajouter un rappel, si l’heure le permet.** Revenir dans MORE et dire : « Rappelle-moi vingt minutes avant le point produit. » MORE prépare un rappel natif à 14 h 40 ; il annonce sa création seulement après confirmation de l’iPhone. Si l’heure est passée ou l’accès refusé, conserver la réponse d’indisponibilité et continuer.

**1:45 — Garder son moment de plaisir.** Demander de passer aux vidéos. Le navigateur intégré ouvre les vrais Reels Instagram ; une fois la vidéo chargée, dire « La suivante ». Observer le changement réel. Une page de connexion exige de se connecter ; elle ne vaut pas vidéo consultée.

**2:10 — Garder le contrôle.** Montrer l’état dans la Dynamic Island. Dire « Pause » : le microphone est libéré. Toucher Reprendre dans la Dynamic Island pour rouvrir MORE et continuer, puis dire « Arrête la routine ». MORE s’arrête sans annoncer de nouvelles actions.

Le rythme dépend de la conversation et des fournisseurs. Mieux vaut montrer ces quelques effets lisibles que multiplier les étapes ou réciter un texte exact.

## Si quelque chose ne répond pas

- Un envoi incertain se vérifie dans Gmail ; ne pas recommencer une nouvelle session pour le renvoyer. Le service conserve le journal et peut rechercher le résultat sans répéter l’envoi.
- Un rappel incertain se vérifie dans Rappels ; ne pas demander une seconde création pour masquer l’incertitude.
- Une connexion Instagram expirée se prépare à nouveau dans le navigateur ; ne pas prétendre qu’une vidéo a été parcourue si la page n’est pas disponible.
- Une panne du Mac, du réseau ou d’un fournisseur appelle un arrêt clair du passage.

Les tests du service et la preuve d’un envoi Gmail réel sont détaillés dans [le service jury](../Services/JuryDemo/README.md). Ce mode opératoire ne certifie pas encore le parcours complet sur iPhone ; les preuves téléphone restent à établir séparément.
