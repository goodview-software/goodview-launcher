#!/bin/sh
# Retour rapide : ./tools/t.sh        -> tests headless (~15 s), affiche OK / ECHECS + erreurs de script
#                 ./tools/t.sh lint   -> idem, lint rapide (2 largeurs) ; GL_LINT_ONLY=page1,page2 pour cibler
#                 ./tools/t.sh load   -> simple chargement des scripts (~5 s), n'affiche que les erreurs
cd "$(dirname "$0")/.."
G="flatpak run"
case "$1" in
  load) timeout 90 $G org.godotengine.Godot --headless --quit --path . 2>&1 | grep -E "ERROR|SCRIPT|Parse|WARNING: .*gd" | grep -v "ObjectDB\|still in use\|Lambda capture" ;;
  lint) GL_TEST=1 GL_LINT_FAST=1 timeout 200 $G --env=GL_TEST=1 --env=GL_LINT_FAST=1 org.godotengine.Godot --headless --path . 2>&1 | grep -vE "ObjectDB|still in use|at: |Lambda capture" | tail -30 ;;
  *) timeout 200 $G --env=GL_TEST=1 org.godotengine.Godot --headless --path . 2>&1 | grep -vE "ObjectDB|still in use|at: cleanup|at: clear|Lambda capture" | tail -30 ;;
esac
