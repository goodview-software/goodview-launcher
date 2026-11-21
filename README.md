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

## Assistants, chat et univers (nouveau)

- Les 8 mascottes sont 8 **assistants** (tableau unique `ALL` dans `ui/universe.gd`) : Goody (généraliste, chef d'orchestre, `llama3.1:8b`),
  Rosie (écriture, traduction, correction, `gemma3:4b`), Bleu (code, Godot/GDScript, `qwen2.5-coder:7b`), Ambre (données, calculs, fichiers, `qwen3:8b`),
  Mauve (idées, histoires, game design, `qwen3:8b`), Soleil (langues, espagnol, `gemma3:4b`), Braise (jeux, modding Arma, optimisation PC, `llama3.1:8b`),
  Brume (recherche, résumés, documents et images, `llama3.2-vision`). Chacun a son prompt, sa température, son modèle préféré (repli sur un modèle installé) et sa charte de couleurs.
- Changer d'assistant (bandeau en haut du chat, `@Nom`, Ctrl+1..8) recolore toute l'app ; le profil partagé `~/.config/goodview/profile.json` reçoit en plus `"theme": {name, accent, bg, card}`.
- Skin pixel art (kit) ; barre de navigation basse : Apps | Profil ; l'assistant IA est une sous-app (carte « Assistant IA » en tête de la grille d'Apps), avec scène fixe de la mascotte, route en perspective, tableau de réponses rapides, cadre pixel pour les images, saisie style Minecraft. Chat Ollama local en streaming (`core/ollama.gd`, HTTPClient), Markdown, pièces jointes
  (texte/code, images pour les modèles vision), historique (`user://chats/`), export Markdown, modèles (liste, téléchargement `/api/pull`), réglages.
- Les assistants s'appellent entre eux (`core/orchestra.gd`) : outil Ollama `ask_assistant` (repli texte `<<ask:Nom>> question <</ask>>`), cartes repliables visibles dans le fil,
  garde-fous (profondeur 2, pas de boucle, 4 appels max, séquentiel, Stop global, réglage on/off). Mascottes animées : `mascot/goody_extra.png` (talk/think/call/listen, `tools/make_mascot.py --extra`).
- Tout reste local : aucune donnée ne quitte le PC (seul Ollama sur `127.0.0.1:11434`, URL réglable).

## Architecture

| Dossier | Rôle |
|---|---|
| `main.gd`, `boot.gd` | amorçage (`boot.gd` charge la mise à jour `.pck`, puis `main.tscn`) |
| `core/` | `ctx` (services partagés), `store` (fichiers), `catalog` (GitHub + cache), `installer`, `updater`, `ollama` (client streaming), `orchestra` (délégations), `chats` (historique), `attach` (pièces jointes) |
| `ui/` | `theme` (dynamique), `universe` (8 assistants), `icons`, `widgets`, `router` (onglets + pile + recoloration), `nav`, `markdown`, `chat_ui`, `app_card`, `profile_editor` |
| `pages/` | `home` (grille d'apps), `app_page`, `chat`, `chat_history`, `chat_settings`, `profile`, `settings`, `about`, `welcome` (base : `page.gd`) |
| `qr.gd` | encodeur QR code |
| `test_run.gd` | tests headless sans réseau externe (faux serveur Ollama local) ; `GL_TEST_OLLAMA=1` ajoute un test réel avec `llama3.2:3b` |

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
