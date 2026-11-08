# Virage

Compteur de vitesse GPS et navigation pour moto, sur iPhone et Apple Watch. Pensé pour rouler avec des gants : interface native, grandes commandes bien espacées, plein écran pendant le trajet, guidage par vibrations au poignet.

## Fonctions

### Compteur et trajets

- Vitesse, angle d'inclinaison (instantané et max gauche/droite), distance, temps, vitesse max et moyenne, altitude, cap.
- Tableau de bord plein écran pendant le trajet, en portrait comme en paysage, avec boutons ronds de pause et d'arrivée.
- Trois styles de compteur (Réglages › Apparence) : *Classique* (natif iOS), *Rétro* (chiffres en Rockwell et libellés en Copperplate, façon café racer : encre sur papier ou crème sur noir) et *Sport* (barre de vitesse segmentée façon compte-tours, grands chiffres penchés, accent rouge). Chacun existe en clair et en sombre, selon le réglage Apparence.
- Trajets enregistrés : carte, statistiques, export GPX.
- Trace colorée selon la vitesse ou l'inclinaison, avec les trois virages les plus penchés épinglés sur la carte.
- Records (plus longue sortie, vitesse max, inclinaison max, dénivelé, point le plus haut, plus longue en temps) et bilan de chaque mois.
- Trajets renommables (« Tour du lac », « Les Aravis avec Paul ») : le nom remplace la date dans la liste, sur l'image partagée et dans le GPX.
- Dénivelé positif, altitude max et cols franchis, épinglés sur la carte du trajet.
- Les photos prises pendant la sortie, retrouvées toutes seules et placées sur la trace (là où elles ont été prises, ou d'après leur heure).
- Image à partager : une carte (fond de carte, trace colorée, chiffres, cols) dans le style du compteur, ou un tracé PNG transparent façon Strava à poser sur une photo.
- Widgets d'écran d'accueil et d'écran verrouillé : km depuis le plein, dernière sortie, total du mois.
- Mini lecteur Apple Music sur le compteur, seulement quand une musique joue : pochette, titre, précédent, lecture/pause, suivant.
- Activité en direct sur l'écran verrouillé et dans la Dynamic Island.
- Alerte de vitesse réglable sur la montre.

### Navigation

- Destination cherchée avec Apple Plans, favoris (maison, travail) et trajets récents, étapes comprises.
- Mode *Itinéraire* : prochain virage, recalcul automatique en cas d'écart, étapes, « Passer l'étape ».
- Routes *Rapide*, *Sans autoroute* ou *Plaisir* (la plus sinueuse proposée), et option « éviter les péages ».
- Mode *Boussole* : une flèche vers la destination, tu choisis tes routes.
- Cols et points de vue autour de toi et plus loin sur l'itinéraire (pastille montagne du compteur) ; celui choisi devient la prochaine étape.
- Sur la montre, façon Beeline : une grande flèche dans un anneau qui se ferme à l'approche du virage, la distance, la rue, la distance restante et l'heure d'arrivée. Une vibration à 300 m d'un virage, puis deux au virage (sens du virage optionnel).

### Traces GPX

- Import depuis l'onglet Rechercher, ou « Ouvrir avec Virage » depuis Fichiers, Mail ou AirDrop.
- La trace est suivie telle quelle, dans un sens ou dans l'autre ; les virages sont lus dans sa forme.
- Bibliothèque : chaque trace ouverte est gardée dans l'onglet Rechercher.
- Dans les lacets, une seule annonce pour une série de virages (« 8 virages sur 1,2 km »).

### Carburant

- Compteur « depuis le plein », remis à zéro par « Plein fait » (pastille du compteur, Réglages, raccourci).
- Autonomie d'un plein et seuil d'alerte réglables, en option.
- Pastille d'autonomie sur le compteur, rouge sur la réserve, avec vibration sur l'iPhone et la montre.
- Stations autour de soi et plus loin sur l'itinéraire, classées par détour ; celle choisie devient la prochaine étape.

### Bouton Action

- **iPhone 15 Pro et plus récents** : raccourcis Passer l'étape, Pause / reprise, Démarrer un trajet, Plein fait (Réglages › Bouton Action › Raccourci). Ils marchent aussi avec Siri.
- **Apple Watch Ultra** : Virage se choisit comme exercice du bouton Action (Réglages › Bouton Action › Exercice) ; un appui démarre le trajet, Action + bouton latéral met en pause et reprend.

### Apple Watch

- Affiche la vitesse de l'iPhone tant qu'il est joignable, et bascule sur son propre GPS sinon. Un trajet démarré sur l'un démarre aussi sur l'autre.
- Fonctionne sans l'iPhone : destination depuis les favoris, les récents ou une recherche, itinéraire calculé sur la montre, trajet envoyé à l'iPhone plus tard.
- Pages vitesse, inclinaison, totaux, relief et navigation ; écran toujours allumé.
- Complications et widget de la Smart Stack : entre deux sorties, les km depuis le plein (ou une jauge d'autonomie) et le total du mois ; pendant un trajet, le chrono, la distance et le prochain virage.

## Prérequis

- Xcode 26 ou plus récent, et [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- iPhone sous iOS 18 ou plus récent ; Apple Watch sous watchOS 11 ou plus récent.
- Pour installer sur de vrais appareils : un compte développeur Apple, avec HealthKit et l'App Group `group.com.guillaumeprost.Virage`.

## Structure

| Dossier | Contenu |
| --- | --- |
| `iOS/` | App iPhone : tableau de bord, recherche, navigation, trajets, carburant, réglages, raccourcis |
| `Watch/` | App Apple Watch : écrans du trajet, navigation, vibrations, exercice du bouton Action |
| `Shared/` | Code commun : statistiques, inclinaison, guidage, calcul et construction d'itinéraire, GPX, carburant, messages iPhone ↔ montre |
| `LiveActivity/`, `Widgets/` | Activité en direct de l'iPhone |
| `WatchShared/`, `WatchWidgets/` | Complications et widget de la montre |
| `Resources/` | Icône (document Icon Composer) |
| `Tests/` | Tests unitaires (Swift Testing) |
| `project.yml` | Définition du projet Xcode pour XcodeGen |

## Démarrer

Le projet Xcode est généré à partir de `project.yml` (il n'est pas versionné) :

```bash
brew install xcodegen
xcodegen generate
open Virage.xcodeproj
```

Pour installer sur un vrai iPhone ou une vraie Watch, choisis ton équipe dans *Signing & Capabilities* pour toutes les cibles. Les complications partagent l'App Group `group.com.guillaumeprost.Virage` avec l'app Watch : il doit exister dans ton compte développeur.

Tests :

```bash
xcodebuild -scheme Virage -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Simuler un trajet dans le simulateur :

```bash
xcrun simctl location booted start --speed=25 45.8992,6.1294 45.8800,6.1700 45.8200,6.2000
```

Démarrer directement une navigation au lancement (builds Debug uniquement) :

```bash
xcrun simctl launch booted com.guillaumeprost.Virage -demoDestination "45.8406,6.2131,Talloires"
```

Ajouter `-demoMode compass` pour le mode boussole. `-demoPreview "45.8406,6.2131,Talloires"` ouvre plutôt l'aperçu d'itinéraire dans l'onglet Rechercher, et `-demoStops "45.8603,6.1953,Menthon-Saint-Bernard"` y ajoute des étapes (séparées par `;`). `-demoGPX /chemin/vers/fichier.gpx` ouvre un GPX comme s'il venait de Fichiers (le fichier doit être dans le conteneur de l'app, par exemple son dossier Documents).

Remplir l'onglet Trajets avec quelques sorties fictives (vitesse et inclinaison), sur une app sans trajet :

```bash
xcrun simctl launch booted com.guillaumeprost.Virage -demoTrips YES
```

## Choix techniques

- **Navigation** : MapKit (`MKDirections`, profil voiture faute de profil moto). MapKit ne donne les manœuvres qu'en texte : le sens du virage est lu dans la géométrie, à la fin du tracé de chaque étape. Le guidage tourne sur la montre à partir de la position reçue (iPhone ou GPS de la montre), donc les vibrations ne dépendent pas de la liaison. L'iPhone recalcule l'itinéraire et l'envoie ; la montre ne recalcule seule que si l'iPhone ne répond plus.

- **Inclinaison** : calculée avec `tan(angle) = v · ω / g` (vitesse GPS × vitesse de rotation autour de la verticale), et non à partir de la direction de la gravité. Dans un virage stabilisé, l'accéléromètre indique toujours « vers le bas » dans l'axe de la moto, ce qui fausse cette approche. Le calcul ne dépend pas de la fixation du téléphone. En dessous de 10 km/h, l'angle vaut 0.
- **Sans l'iPhone** : la montre reçoit les favoris et récents (transfert en file d'attente, plus un envoi direct quand elle se reconnecte), calcule elle-même l'itinéraire avec MapKit, et envoie à l'iPhone, en fichier, un trajet enregistré sur son seul GPS.
- **Alerte de vitesse** : logique pure dans `SpeedAlert` (une alerte au franchissement, rappel chaque minute, réarmée 5 km/h sous la limite). Réglée sur la montre, en m/s pour ne pas dépendre de l'unité.
- **Icône** : document Icon Composer en calques (`Resources/AppIcon.icon` : cadran, inclinaison tracée, aiguille, en SVG). Le système en dérive les modes clair, sombre, transparent et teinté, et la version ronde de la montre. À ouvrir avec Icon Composer (dans Xcode) pour la retoucher.
- **Pause** : `RideStats` met la distance, le temps, la vitesse max et la trace en attente, mais garde la position et la vitesse à jour (le guidage continue). Le chrono affiché part de `timerStart` (départ décalé des pauses), y compris sur l'écran verrouillé et les complications.
- **Étapes** : MapKit ne calcule que d'un point à un autre ; chaque tronçon est calculé en parallèle puis assemblé par `RouteBuilder.join`. Chaque étape est annoncée comme un virage (« Étape : … »), et un recalcul repart par les étapes pas encore atteintes. « Passer l'étape » (bandeau iPhone, contrôles de la montre) recalcule depuis la position actuelle sans la prochaine étape ; la montre le demande à l'iPhone quand il est joignable.
- **Import GPX** : bouton dans l'onglet Rechercher, ou « Ouvrir avec Virage » depuis Fichiers, Mail ou AirDrop (type `com.topografix.gpx` déclaré). L'itinéraire suit la trace telle quelle (`RouteBuilder.follow`) : priorité aux points de route (`rtept`), sinon la trace (`trkpt`). Les virages sont lus dans la géométrie (plus de 45°, un seul par tranche de 60 m), sans nom de rue. Hors trace, pas de recalcul Apple Plans : on invite à rejoindre la trace.
- **Route plaisir** : sans autoroute, MapKit propose plusieurs itinéraires (`requestsAlternateRoutes`) ; on garde le plus sinueux (degrés de changement de cap par km, mesurés tous les 50 m) parmi ceux qui prennent au plus 30 % de temps en plus que le plus rapide.
- **Bibliothèque GPX** : chaque trace ouverte est gardée (`SavedTrack`, section « Traces GPX » de l'onglet Rechercher). Dans les lacets, 3 virages ou plus espacés de moins de 250 m sont annoncés une fois (« 8 virages sur 1,2 km »).
- **Carburant** : pas de capteur, l'app compte les km roulés depuis le dernier « Plein fait » (trajets iPhone et montre) contre l'autonomie réglée. Passage sur la réserve : pastille rouge, vibration sur l'iPhone et la montre. Les stations (catégorie et recherche « station-service », autour de soi et 15 et 35 km plus loin sur l'itinéraire) sont classées par détour ; celle choisie devient la prochaine étape.
- **Bouton Action** : iPhone, via les raccourcis fournis (Passer l'étape, Pause / reprise, Démarrer un trajet, Plein fait), qui agissent sans ouvrir l'app. Apple Watch Ultra : Virage se choisit comme exercice du bouton Action (`StartWorkoutIntent`) ; Action + bouton latéral met en pause et reprend.
- **Trajets enrichis** : chaque point de la trace garde l'inclinaison (`TrackPoint.lean`, absente des anciens trajets et de ceux de la montre seule, qui ne montrent alors que la vitesse). La trace est découpée en tronçons par tranche de couleur, sur la médiane de 5 points pour qu'un à-coup ne change pas la couleur (`TripInsights`). Les virages épinglés sont distants d'au moins 1,5 km.
- **Styles** : `DashboardStyle`, passé dans l'environnement. Seuls les éléments visuels changent (vitesse, inclinaison, tuiles, pastille, boutons) : l'agencement et les fonctions sont communs. Leurs couleurs ont une version claire et une sombre (`Color(light:dark:)`) et suivent le réglage Apparence ; l'accent est l'encre (Rétro) ou le rouge (Sport).
- **Cols et points de vue** : Apple Plans n'a pas de catégorie pour eux ; ils sont cherchés par nom (« col », « le col », « point de vue », « belvédère ») et reconnus à leur nom (`ScenicSearch.kind`). Un col est franchi quand la trace passe à moins de 200 m ; le long d'un trajet, au plus 20 petites recherches réparties sur la trace, pour rester dans la limite d'Apple Plans. Résultat gardé dans le trajet (`Trip.passes`). Certains cols trouvés ne sont accessibles qu'à pied.
- **Dénivelé** : altitude lissée (médiane de 5 points) puis seuil de 5 m, pour que le bruit du GPS ne s'additionne pas (`TripInsights.elevation`). Mesuré à l'enregistrement, et une fois pour les anciens trajets.
- **Photos** : PhotoKit, photos prises entre le départ et l'arrivée (± 10 min). L'accès est demandé depuis un trajet, pas au lancement.
- **Partage** : `ImageRenderer` en PNG à 1080 px de large ; la carte vient de `MKMapSnapshotter`, la trace y est posée avec `snapshot.point(for:)`.
- **Widgets** : l'app écrit un petit état JSON dans l'App Group (`HomeWidgetState`) quand elle passe en arrière-plan, après un trajet et au plein, puis recharge les widgets. Le même état part vers la montre par `transferCurrentComplicationUserInfo` (livré tout de suite quand une complication Virage est sur le cadran, dans un budget quotidien ; sinon en simple `transferUserInfo`). Les timelines prévoient une entrée au 1er du mois suivant, où le total du mois repart de zéro.
- **Historique** : un trajet récent garde ses étapes (`RecentDestination.viaData`) ; la même destination par d'autres étapes est une entrée distincte.
- **Complications** : l'app Watch écrit l'état du trajet dans l'App Group et recharge les widgets seulement quand le virage change, au début et à la fin d'un trajet, et sinon au plus une fois par minute. Elles montrent la rue et l'heure d'arrivée, pas la distance au virage, qui serait périmée entre deux rechargements.
- **Watch** : une `HKWorkoutSession` (jamais enregistrée dans Santé) garde l'app active pendant le trajet. L'iPhone ouvre l'app Watch via `HKHealthStore.startWatchApp` au démarrage d'un trajet.
- **Arrière-plan** : le GPS ne tourne en arrière-plan que pendant un trajet ; l'écran reste allumé pendant le trajet.

## Limites connues

- MapKit n'a pas de profil moto : les itinéraires sont calculés pour une voiture.
- L'autonomie est une estimation à partir des km roulés, sans lien avec la moto.
- L'inclinaison est déduite de la vitesse et de la rotation : elle est fiable en virage stabilisé, moins dans les transitions rapides, et vaut 0 sous 10 km/h.
- Le bouton Action n'a pas pu être essayé dans le simulateur : à vérifier sur un iPhone et une Apple Watch Ultra.
