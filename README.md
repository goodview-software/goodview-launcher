# Goodview Launcher

Bundle logiciel Godot : liste les repos de l'organisation GitHub
[goodview-software](https://github.com/goodview-software), installe la dernière
release (asset Linux : `.zip`, `.tar.gz`, `.x86_64`, `.AppImage`), met à jour et lance chaque app.

- Catalogue : org `goodview-software` (constante `ORGS`). Une app est installable dès que son repo publie une **release GitHub** avec un asset Linux.
- Données : `user://apps/<repo>/`, état dans `user://installed.json`.
- Lancer : `flatpak run org.godotengine.Godot --path ~/goodview-launcher`
