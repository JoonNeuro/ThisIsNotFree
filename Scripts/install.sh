#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
zsh Scripts/build-app.sh
install_dir="${TNF_INSTALL_DIR:-$HOME/Applications}"
mkdir -p "$install_dir"
ditto dist/ThisIsNotFree.app "$install_dir/ThisIsNotFree.app"
codesign --verify --strict "$install_dir/ThisIsNotFree.app"
print -r -- "Installed: $install_dir/ThisIsNotFree.app"
if [[ "${1:-}" != "--no-open" ]]; then open "$install_dir/ThisIsNotFree.app"; fi
