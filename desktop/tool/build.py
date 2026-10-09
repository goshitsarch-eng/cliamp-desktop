#!/usr/bin/env python3
"""Build the Flutter app and stage its Go sidecar on the current desktop OS."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess


def run(*args, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--debug', action='store_true')
    options = parser.parse_args()
    desktop = Path(__file__).resolve().parents[1]
    repo = desktop.parent
    target = {'Linux': 'linux', 'Darwin': 'macos', 'Windows': 'windows'}.get(platform.system())
    if target is None:
        parser.error('Linux, macOS, or Windows is required')
    mode = 'debug' if options.debug else 'release'
    flutter = shutil.which('flutter')
    go = shutil.which('go')
    if not flutter or not go:
        parser.error('Install Flutter and Go from mise.toml and add both to PATH')
    run(flutter, 'pub', 'get', '--enforce-lockfile', cwd=desktop)
    # Keep the complete Material icon font in desktop bundles. Flutter's Linux
    # release asset target can reuse an old subset after Dart-only changes,
    # producing invisible new icons beside a freshly compiled app library.
    # The full font costs about 1.6 MB and avoids that incremental cache hazard.
    run(flutter, 'build', target, '--' + mode, '--no-tree-shake-icons', cwd=desktop)
    if target == 'linux':
        bundles = list((desktop / 'build/linux').glob('*/' + mode + '/bundle'))
        if len(bundles) != 1:
            raise RuntimeError('Expected one Linux build architecture; clean stale builds first')
        bundle = bundles[0]
        binary = bundle / 'cliamp'
    elif target == 'macos':
        bundle = desktop / 'build/macos/Build/Products' / mode.capitalize() / 'Cliamp.app'
        binary = bundle / 'Contents/MacOS/cliamp'
    else:
        bundles = list((desktop / 'build/windows').glob('*/runner/' + mode.capitalize()))
        if len(bundles) != 1:
            raise RuntimeError('Expected one Windows build architecture; clean stale builds first')
        bundle = bundles[0]
        binary = bundle / 'cliamp.exe'
    build_env = dict(os.environ, CGO_ENABLED='1')
    run(go, 'build', '-trimpath', '-o', str(binary), '.', cwd=repo, env=build_env)
    license_dir = bundle / 'Contents/Resources' if target == 'macos' else bundle
    shutil.copy2(repo / 'LICENSE', license_dir / 'CLIAMP-LICENSE.txt')
    if target == 'macos':
        # Staging the sidecar changes the app seal. Re-sign for local development;
        # release signing and notarization require a distributor's identity.
        run('codesign', '--force', '--sign', '-', str(binary))
        run('codesign', '--force', '--deep', '--sign', '-', str(bundle))
    print(f'Built {bundle}')
    print('The sidecar uses system codec libraries. Install the runtime prerequisites in docs/desktop.md before distributing this development bundle.')


if __name__ == '__main__':
    main()
