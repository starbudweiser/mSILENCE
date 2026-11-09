# mSILENCE

Version personnelle de Radio Silence (pare-feu par appli, Juuso Salonen) : filtre réseau `NEFilterDataProvider` (extension système) + appli SwiftUI/AppKit. Aucun code de Radio Silence repris.

- Projet Xcode généré par XcodeGen (`project.yml`) ; ne pas committer `mSILENCE.xcodeproj`. Build : `./build_app.sh` (installe dans /Applications, exigé par macOS pour activer l'extension système, et pose un lien dans ~/Applications/Applications Personnelles).
- Signature : l'extension exige des droits Apple (profil). `build_app.sh` archive sans signature, signe ad hoc avec les droits, puis `exportArchive -allowProvisioningUpdates` (method developer-id) crée le profil « Mac Team Direct » sans enregistrer d'appareil. Ne pas utiliser `sign_app.sh` (le certificat local casserait les droits).
- Appli (`App/`) : `Socle.swift`, `WindowPresent.swift`, `Updater.swift`, `UpdaterView.swift` sont recopiés par `build_app.sh`, ne pas les modifier ici. Extension (`Extension/FilterDataProvider.swift`) : liste d'applis lue dans `vendorConfiguration` (clé `blocked`, chemins de .app), journal des connexions servi par XPC (mach service `35KLMK53PN.fr.stephan.msilence.xpc`, accès limité à l'équipe 35KLMK53PN).
- Import : `RadioSilenceImport` lit `blacklist` dans `com.radiosilenceapp.client` (jamais la licence), automatique à la première ouverture (marqueur `.radio-silence-imported`).
- Textes : `Resources/<langue>.lproj/Localizable.strings` (fr, en, es, it, mêmes clés). Données : `~/Library/Application Support/mSILENCE/rules.json` (`MSILENCE_DATA_DIR` pour les essais).
- Essais sans fenêtre : `mSILENCE --capture sortie.png [--tab monitor|settings] [--demo]`, `--capture-about`, `--import-radio-silence`.
- Activer l'extension demande l'accord de l'utilisateur dans Réglages Système (mot de passe) : ne pas le déclencher sans son feu vert (alerte système).
