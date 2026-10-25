#!/bin/sh
# Build the Go engine and export the Godot Linux app inside the Flatpak SDK.
set -eu

cd "$(dirname "$0")/../.."
if [ ! -f go.mod ]; then
  echo "build.sh must run from a checkout that contains go.mod" >&2
  exit 1
fi

if [ -x "$PWD/sdk/go/bin/go" ]; then
  export GOROOT="$PWD/sdk/go"
  export PATH="/usr/lib/sdk/llvm20/bin:$PWD/sdk/go/bin:${PATH}"
else
  export GOROOT=/app/go
  export PATH="/usr/lib/sdk/llvm20/bin:/app/go/bin:${PATH}"
fi
export GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"

go build -trimpath -ldflags='-s -w -X main.version=0.1.0-flatpak' -o /tmp/cliamp-engine .

# Godot reads export templates from its data directory, named by version.
godot_bin=$(set -- sdk/godot/Godot_v*_linux.x86_64; echo "$1")
chmod +x "$godot_bin"
export HOME="${HOME:-/tmp}"
templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.7.2.stable"
mkdir -p "$templates" sdk/templates
unzip -q -o sdk/Godot_v4.7.2-stable_export_templates.tpz -d sdk/templates
cp -a sdk/templates/templates/. "$templates/"

"$godot_bin" --headless --path godot --import --quit
mkdir -p godot/build/linux
"$godot_bin" --headless --path godot --export-release Linux build/linux/Cliamp-Desktop.x86_64

install -d /app/cliamp /app/bin /app/etc   /app/share/applications /app/share/metainfo   /app/share/icons/hicolor/scalable/apps
install -m 755 godot/build/linux/Cliamp-Desktop.x86_64 /app/cliamp/Cliamp-Desktop.x86_64
install -m 755 /tmp/cliamp-engine /app/cliamp/cliamp
install -m 755 packaging/flatpak/cliamp-desktop.sh /app/bin/cliamp-desktop
install -m 644 packaging/flatpak/asound.conf /app/etc/asound.conf
install -m 644 packaging/flatpak/io.github.goshitsarch_eng.Cliamp.desktop   /app/share/applications/io.github.goshitsarch_eng.Cliamp.desktop
install -m 644 packaging/flatpak/io.github.goshitsarch_eng.Cliamp.metainfo.xml   /app/share/metainfo/io.github.goshitsarch_eng.Cliamp.metainfo.xml
install -m 644 Cliamp.svg   /app/share/icons/hicolor/scalable/apps/io.github.goshitsarch_eng.Cliamp.svg
install -m 644 LICENSE /app/cliamp/CLIAMP-LICENSE.txt
