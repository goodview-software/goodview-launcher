# Goodview Launcher

Bundle logiciel Godot 4.7 : liste les repos de l'organisation GitHub
[goodview-software](https://github.com/goodview-software), installe la dernière
release (asset Linux : `.zip`, `.tar.gz`, `.x86_64`, `.AppImage`), met à jour et lance chaque app.

## Fonctions

- Catalogue en cache (`user://catalog.json`) : affichage immédiat, puis rafraîchissement en arrière-plan ; mode hors-ligne.
- Fiche d'app : installer / mettre à jour / lancer, progression avec annulation, notes de version avant mise à jour, raccourci bureau, désinstallation (confirmation légère), QR code APK.
- Mises à jour : vérification au démarrage puis toutes les 30 min (réglable), badges, « Tout mettre à jour » (installation séquentielle), mise à jour du launcher par `.pck` (bannière sur l'accueil).
- Accueil : favoris (étoile), tri (récents / A-Z / mises à jour d'abord), recherche au-delà de 6 apps.
- Profil (pseudo + 8 mascottes) écrit dans `~/.config/goodview/profile.json`, lu par les autres apps ; page de bienvenue au premier lancement.
- Paramètres (vérification auto, dossier d'installation, cache), À propos ; taille/position de fenêtre mémorisées ; Échap / Retour Android pour revenir.

## Architecture

| Dossier | Rôle |
|---|---|
| `main.gd`, `boot.gd` | amorçage (`boot.gd` charge la mise à jour `.pck`, puis `main.tscn`) |
| `core/` | `ctx` (services partagés), `store` (fichiers), `catalog` (GitHub + cache), `installer`, `updater` |
| `ui/` | `theme`, `icons`, `widgets` (composants dessinés), `router` (pile de pages + transitions), `profile_editor` |
| `pages/` | `home`, `app_page`, `profile`, `settings`, `about`, `welcome` (base : `page.gd`) |
| `qr.gd` | encodeur QR code |
| `test_run.gd` | test headless sans réseau |

Fichiers de données (formats stables) : `installed.json`, `settings.cfg`, `~/.config/goodview/profile.json`.
Convention par repo : `icon.png|svg` et `app.json` (`name`, `tagline`, `description`, `screenshots`) à la racine.

## Commandes

```sh
flatpak run org.godotengine.Godot --path ~/goodview-launcher                      # lancer
flatpak run --env=GL_TEST=1 org.godotengine.Godot --headless --path ~/goodview-launcher   # tests (affiche « OK »)
flatpak run org.godotengine.Godot --headless --path . --export-release Linux build/linux/GoodviewLauncher.x86_64
./release.sh 0.3.0 "Notes"                                                        # publie (pck + zip + release GitHub)
```

Une app est installable dès que son repo publie une **release GitHub** avec un asset Linux.
