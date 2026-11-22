# Goodview Launcher — règles de travail (Godot 4.7, GDScript)

Voir `README.md` (fonctions, architecture), `TODO.md`, `kit/README.md` (kit UI). Ne pas les recopier ici.

## Boucle rapide (toujours dans cet ordre, une seule vérification ciblée)
1. Après un edit : `./tools/t.sh load` (~5 s) → n'affiche que les erreurs de script/parse. Vide = bon.
2. Avant de conclure : `./tools/t.sh` (~15 s) → doit afficher `OK` ; sinon `ECHECS : …` (lire le message du `check`).
3. UI/mise en page : `./tools/t.sh lint` ; cibler avec `GL_LINT_ONLY=chat,home`, détails `GL_LINT_DBG=1`, `GL_DBG=1`.
4. Pas de capture d'écran par défaut. Voir une page précise : `flatpak run --env=GL_PAGE=<page> org.godotengine.Godot --path .` (une seule fois, en fin de chantier).
- `godot` n'est PAS dans le PATH : toujours `flatpak run org.godotengine.Godot`.
- Les messages « ObjectDB leaked », « resources still in use », « Lambda capture freed » en fin de test sont bénins (voir TODO.md).
- Fermer les autres instances Godot/launcher avant de relancer.

## Où chercher (ne pas lire les gros fichiers en entier : grep puis offset/limit)
- Le chat IA n'est plus ici : c'est l'app autonome `~/chat-rapide` (repo goodview-software/chat-rapide, listée par le catalogue une fois publiée). `ui/universe.gd` ne sert qu'au profil (8 mascottes/thèmes).
- Navigation : `ui/router.gd` (pages enregistrées + `TABS`), démarrage dans `main.gd`, page de départ `ctx.start_page()`.
- Catalogue/installation : `core/catalog.gd`, `installer.gd`, `updater.gd`, `pages/home.gd`, `app_page.gd`.
- **Plan 2D supprimé** (ne pas le recréer). Pas de chat ni d'Ollama dans le launcher.

## Conventions
- Pas de `class_name` : tout par `preload("res://…")`. Un fichier de page = une page (base `pages/page.gd`) ; l'enregistrer dans `ui/router.gd`.
- Textes UI en français. Couleurs/tailles via `ui/theme.gd` (`T.`) et `kit/tokens.gd`, widgets via `ui/widgets.gd` (`W.`) ou `kit/` (`K.`) ; pas de valeurs en dur si un jeton existe.
- Données utilisateur : `user://` (`chats/`, `settings.cfg`, `installed.json`) ; formats stables → toute évolution = migration (voir `scene.gd` « migré »), jamais de rupture.
- Tout reste local (Ollama `127.0.0.1:11434`) : aucun appel réseau externe dans le code ni dans les tests (faux serveur dans `test_run.gd`).
- Modèle Ollama par défaut économique ; pas de nouveau test « réel » dans la suite par défaut.
- Ajout de fonctionnalité → ajouter un `check(...)` dans `test_run.gd` dans le même chantier.

## Debug
- Erreur de script : `./tools/t.sh load` donne fichier:ligne. Lire seulement ces lignes (`Read` offset/limit).
- Test rouge : relancer seulement `./tools/t.sh`, corriger, relancer une fois. Ne pas empiler d'essais.
- Piège connu : lambdas qui capturent un nœud libéré ; `await` dans un callback après `queue_free` ; signaux connectés deux fois lors d'un `build()` rappelé.
- Pour tracer : `print("DBG …")` temporaire, à retirer avant commit (grep `DBG` : ceux déjà présents dans `test_run.gd` sont légitimes).

## Git / release
- Commits en français, courts, au format du log (ex. « Chat : … »). Branche `main`. Commit + push sans redemander quand les tests sont verts.
- `.godot/`, `build/`, `export/` ignorés. Ne pas committer `export_presets.cfg` modifié par accident.
- Release uniquement sur demande (« publie ») : `./release.sh X.Y.Z "Notes"` (incrémente `version.gd`, exporte pck+zip+APK, tag, release GitHub).
