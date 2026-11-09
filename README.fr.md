# mSILENCE

[English](README.md)

Version personnelle et indépendante d'un pare-feu par application et moniteur réseau pour macOS, inspirée de [Radio Silence](https://radiosilenceapp.com/) (aucun code en commun, aucun lien avec son auteur).

- **Bloquer une appli** : glisser-déposer ou choix dans une liste ; ses helpers et processus enfants sont bloqués avec elle, les échanges locaux restent permis.
- **Invisible, toujours actif** : un filtre réseau (extension système) tourne en arrière-plan, sans fenêtre ni icône dans la barre des menus, même appli fermée.
- **Moniteur en direct** des connexions sortantes, avec blocage en un clic.
- **Import de Radio Silence** : reprend sa liste d'applis bloquées (jamais sa licence ni ses autres réglages), automatiquement à la première ouverture.
- Mise à jour automatique, 4 langues (fr, en, es, it), interface sombre Socle.

Build : `./build_app.sh` (Xcode + XcodeGen). Première ouverture : « Installer le filtre réseau », puis autoriser mSILENCE dans Réglages Système › Général › Ouverture et extensions › Extensions réseau.
