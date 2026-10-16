# MORE Démo — passage devant le jury

MORE Démo est un doublon isolé de MORE. Le parcours conserve l’accueil, le paysage et les commandes habituelles : aucun écran ni panneau de présentation supplémentaire.

Avant de commencer, préciser oralement : **« Le sommeil, la météo et le message de départ sont préparés pour ce matin. La rédaction et l’envoi du mail utilisent de vrais services. »** Le message annoncé ne provient pas d’une lecture en direct de l’inbox.

## État vérifié au 16 octobre 2026

- **Services réels :** rédaction libre puis révision avec OpenAI, synthèse ElevenLabs, un seul mail envoyé au compte lui-même et relu avec label SENT, destinataire et contenu exacts. La reprise serveur retrouve le reçu sans nouvel envoi.
- **iPhone et Dynamic Island :** le dernier passage isolé valide les deux tests d’interface et les commandes pause, reprise au premier plan avec nouvelle lecture réelle, puis arrêt depuis la Dynamic Island (98,557 s, avec neuf secondes sur l’accueil iOS à chaque phase). Le résultat local `work/jury-demo-isolated-final-acceptance.xcresult` compte quatre tests : trois réussites et un échec de reconnaissance acoustique. L’ensemble ne valide donc pas la conversation. Un contrôle séparé arrête ensuite la répétition par les paramètres ordinaires et vérifie le retour au repos (20,925 s), sans démarrer de nouveau matin.
- **Logique partagée :** commande Swift réussie après intégration de `main` (`e01c964`), avec 1 961 tests rapportés dans 226 suites et 7 tests optionnels ignorés ; 36 tests du service réussis. Les changements du graphe audio conditionnel iOS restent distincts de cette couverture macOS.
- **Python :** le contrôle historique sur `463af5f` comptait 33 méthodes réussies et une en échec pour 133 traductions anglaises absentes (104 dans le catalogue principal, 29 dans MorningApple). La PR 207 et le correctif `aff97cb` ont corrigé ces catalogues ; les 34 méthodes passent après intégration de `main` (`43d1d04`) et [l’issue 208](https://github.com/gibouu/morning-operator/issues/208) est résolue.
- **Conversion audio numérique :** quatre cas Float32 à 44,1 kHz, mono/stéréo vers 48 kHz mono, passent sur des signaux d’une seconde et de 8,4 secondes : écart de durée nul et fin conservée. Cela ne valide pas la reconnaissance acoustique.
- **Microphone :** la parole réelle diffusée par le Mac pendant l’essai de 45 secondes ne produit aucun caractère reconnu. Un lancement autonome, hors XCTest, reproduit cette absence. Le diagnostic brut passe son cycle de vie en 81,97 s, mais capture uniquement des zéros sur environ 1,8 million de trames, même en mode `.measurement`, sans traitement vocal ni reconnaissance. Ce succès de harnais ne valide aucune voix.
- **Nouvel essai physique :** après confirmation du téléphone éveillé et hors Recopie, une première tentative est invalidée car le haut-parleur du Mac avait changé d’identifiant. Le harnais corrigé diffuse ensuite réellement la phrase ; l’essai échoue encore en 86,167 s, avec 2 683 200 trames et aucun échantillon non nul. La personne confirme séparément que sa voix est audible dans Dictaphone. Cela justifie de comparer les méthodes de capture de MORE ; cela ne démontre pas encore une cause.
- **Isolation des essais :** un premier lot de trois contrôles UI échoue pendant une autre exécution sur le même téléphone. Les trois contrôles passent ensuite sans autre lanceur concurrent ; la reconnaissance reste en échec. L’interférence n’explique donc pas à elle seule le silence microphone. Réserver le téléphone à un seul lanceur pendant chaque passage.
- **Encore non prouvés :** conversation acoustique interactive complète, création réelle d’un rappel — jamais atteinte —, connexion Instagram et vidéo suivante. La démo complète devant jury n’est pas déclarée validée ; suivi ouvert dans [l’issue 205](https://github.com/gibouu/morning-operator/issues/205).

Apple indique que [le microphone est indisponible avec iPhone Mirroring](https://support.apple.com/en-us/120421). Mirroring n’était pas actif lors du contrôle et la nouvelle répétition physique conserve le problème : cette limite ne démontre pas la cause du silence observé.

Le diagnostic brut est réservé aux builds DEBUG et s’active explicitement avec `--jury-raw-microphone-diagnostic`. Il désactive la reconnaissance et les tours externes, ne conserve aucun audio et ne fournit que des compteurs numériques. Il ne doit pas être activé pour le passage normal.

Un second diagnostic DEBUG, `--jury-recorder-microphone-diagnostic`, compare un `AVAudioRecorder` natif indépendant, sans moteur de lecture ni reconnaissance. Il n’appelle aucun service externe et conserve l’identifiant backend antérieur pour sa réconciliation normale. Il mesure les niveaux pendant trente secondes au maximum dans un fichier temporaire privé et protégé. Pause, arrêt et expiration suppriment le fichier et restaurent la configuration audio ; après une terminaison brutale, un éventuel fichier orphelin est supprimé au prochain lancement. Vérifier le journal numérique `recorder_restored fileRemoved=true` après le contrôle.

La compilation iPhone, la signature stricte et l’installation de ce diagnostic sont vérifiées (`18080a2`), ainsi que 17 tests partagés du transport jury, 25 tests des extras après intégration de `main`, et les 34 contrôles Python. Les deux lancements XCTest suivants expirent avant le premier test sur « Timed out while enabling automation mode ». Le Mac ne détecte alors aucun iPhone avec `idevice_id`, tandis que CoreDevice reste connecté en `localNetwork` ; le relais syslog USB ne fournit aucune mesure. Un lancement autonome ne produit donc pas non plus de preuve instrumentée. Ces essais ne valident ni n’invalident la capture AVAudioRecorder. Le retour à un lancement normal est effectué et l’inventaire des temporaires ne contient aucun dossier `jury-mic-*`. Rebrancher le câble et vérifier la visibilité USB avant de reprendre sur un créneau exclusif.

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

**2:10 — Garder le contrôle.** Montrer l’état et les commandes de la Dynamic Island : pause, reprise vers MORE avec lecture effective, puis arrêt. Ces commandes sont vérifiées sur téléphone ; leur déclenchement par une conversation acoustique reste non validé.

Le rythme dépend de la conversation et des fournisseurs. Mieux vaut montrer ces quelques effets lisibles que multiplier les étapes ou réciter un texte exact.

## Si quelque chose ne répond pas

- Un envoi incertain se vérifie dans Gmail ; ne pas recommencer une nouvelle session pour le renvoyer. Le service conserve le journal et peut rechercher le résultat sans répéter l’envoi.
- Un rappel incertain se vérifie dans Rappels ; ne pas demander une seconde création pour masquer l’incertitude.
- Une connexion Instagram expirée se prépare à nouveau dans le navigateur ; ne pas prétendre qu’une vidéo a été parcourue si la page n’est pas disponible.
- Une panne du Mac, du réseau ou d’un fournisseur appelle un arrêt clair du passage.

Les détails des services et les limites de leurs preuves figurent dans [le service jury](../Services/JuryDemo/README.md). Actualiser ce statut seulement après observation du résultat correspondant sur le téléphone.
