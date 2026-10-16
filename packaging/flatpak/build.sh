#!/bin/sh
# Build the Go engine and the Flutter Linux bundle inside the Flatpak SDK.
set -eu

cd "$(dirname "$0")/../.."
if [ ! -f go.mod ]; then
  echo "build.sh must run from a checkout that contains go.mod" >&2
  exit 1
fi

if [ -x "$PWD/sdk/go/bin/go" ]; then
  export GOROOT="$PWD/sdk/go"
  export PATH="/usr/lib/sdk/llvm20/bin:$PWD/sdk/go/bin:$PWD/sdk/flutter/bin:${PATH}"
else
  export GOROOT=/app/go
  export PATH="/usr/lib/sdk/llvm20/bin:/app/go/bin:/app/flutter/bin:${PATH}"
fi
export PUB_CACHE="${PUB_CACHE:-/run/build/pub-cache}"
export GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"

flutter config --no-analytics --enable-linux-desktop
flutter precache --linux

go build -trimpath -ldflags='-s -w -X main.version=0.1.0-flatpak' -o /tmp/cliamp-engine .

cd desktop
flutter pub get --enforce-lockfile
flutter build linux --release --no-tree-shake-icons
cd ..

# shellcheck disable=SC2086
set -- desktop/build/linux/*/release/bundle
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "expected one Linux bundle, found: $*" >&2
  exit 1
fi

install -d /app/cliamp /app/bin /app/etc \
  /app/share/applications /app/share/metainfo \
  /app/share/icons/hicolor/scalable/apps
cp -a "$1"/. /app/cliamp/
install -m 755 /tmp/cliamp-engine /app/cliamp/cliamp
install -m 755 packaging/flatpak/cliamp-desktop.sh /app/bin/cliamp-desktop
install -m 644 packaging/flatpak/asound.conf /app/etc/asound.conf
install -m 644 packaging/flatpak/io.github.goshitsarch_eng.Cliamp.desktop \
  /app/share/applications/io.github.goshitsarch_eng.Cliamp.desktop
install -m 644 packaging/flatpak/io.github.goshitsarch_eng.Cliamp.metainfo.xml \
  /app/share/metainfo/io.github.goshitsarch_eng.Cliamp.metainfo.xml
install -m 644 Cliamp.svg \
  /app/share/icons/hicolor/scalable/apps/io.github.goshitsarch_eng.Cliamp.svg
install -m 644 LICENSE /app/cliamp/CLIAMP-LICENSE.txt
