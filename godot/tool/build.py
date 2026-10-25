#!/usr/bin/env python3
"""Export the Godot app and stage its Go sidecar on the current desktop OS."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess

GODOT_VERSION = '4.7.2'


def run(*args, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--debug', action='store_true')
    parser.add_argument('--godot', default=os.environ.get('GODOT') or shutil.which('godot'),
                        help='Godot %s executable (default: $GODOT or godot on PATH)' % GODOT_VERSION)
    options = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    repo = project.parent
    target = {'Linux': 'linux', 'Darwin': 'macos', 'Windows': 'windows'}.get(platform.system())
    if target is None:
        parser.error('Linux, macOS, or Windows is required')
    go = shutil.which('go')
    if not options.godot or not go:
        parser.error('Install Godot %s and Go (see mise.toml) and add both to PATH, or pass --godot' % GODOT_VERSION)

    out = project / 'build' / target
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    # The presets in export_presets.cfg embed the PCK, so the export is one executable.
    if target == 'linux':
        executable = out / 'Cliamp-Desktop.x86_64'
        sidecar = out / 'cliamp'
        preset = 'Linux'
    elif target == 'windows':
        executable = out / 'Cliamp-Desktop.exe'
        sidecar = out / 'cliamp.exe'
        preset = 'Windows'
    else:
        # Godot names the bundle and its executable after the project. The sidecar goes in
        # Resources, where the app looks, because Contents/MacOS/Cliamp and cliamp are one
        # file on a case-insensitive volume.
        executable = out / 'Cliamp.app'
        sidecar = executable / 'Contents/Resources/cliamp'
        preset = 'macOS'
    flag = '--export-debug' if options.debug else '--export-release'
    # macOS exports a zip of the app; the other platforms export the executable.
    export_path = out / 'Cliamp-Desktop.zip' if target == 'macos' else executable
    run(options.godot, '--headless', '--path', str(project), flag, preset, str(export_path))
    if target == 'macos':
        run('unzip', '-q', str(export_path), '-d', str(out))
        export_path.unlink()

    build_env = dict(os.environ, CGO_ENABLED='1')
    if target == 'windows':
        # The MSYS2 libogg exports ogg_stream_iovecin only from the static archive;
        # the release workflow links it the same way.
        build_env.setdefault('CGO_LDFLAGS', '-Wl,-Bstatic -logg -Wl,-Bdynamic')
    run(go, 'build', '-trimpath', '-o', str(sidecar), '.', cwd=repo, env=build_env)
    license_dir = executable / 'Contents/Resources' if target == 'macos' else out
    license_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo / 'LICENSE', license_dir / 'CLIAMP-LICENSE.txt')
    if target == 'linux':
        executable.chmod(0o755)
    if target == 'macos':
        # Staging the sidecar changes the app seal. Re-sign for local development;
        # release signing and notarization require a distributor's identity.
        run('codesign', '--force', '--sign', '-', str(sidecar))
        run('codesign', '--force', '--deep', '--sign', '-', str(executable))
    print(f'Built {out}')
    print('The sidecar uses system codec libraries. Install the runtime prerequisites in docs/desktop.md before distributing this development bundle.')


if __name__ == '__main__':
    main()
