#!/usr/bin/env python3
"""Build the Windows installer: stage the engine's MinGW DLLs next to the bundle
from `godot/tool/build.py`, then run Inno Setup (ISCC). Run from MSYS2 MinGW64 or
with its bin directory on PATH (ldd must resolve the engine's DLLs)."""
import argparse
import os
import re
from pathlib import Path
import shutil
import subprocess

ISCC_CANDIDATES = [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/Inno Setup 6/ISCC.exe',
    Path('C:/Program Files (x86)/Inno Setup 6/ISCC.exe'),
    Path('C:/Program Files/Inno Setup 6/ISCC.exe'),
]


def msys_to_windows(path):
    """ldd prints MSYS paths: /c/msys64/mingw64/bin/x.dll or /mingw64/bin/x.dll."""
    match = re.match(r'^/([a-zA-Z])/(.*)$', path)
    if match:
        return Path('%s:/%s' % (match.group(1), match.group(2)))
    return Path(os.environ.get('MSYS2_ROOT', 'C:/msys64')) / path.lstrip('/')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', default='0.1.0')
    options = parser.parse_args()
    here = Path(__file__).resolve().parent
    bundle = here.parents[1] / 'godot/build/windows'
    if not (bundle / 'cliamp.exe').exists() or not (bundle / 'Cliamp-Desktop.exe').exists():
        parser.error('Run `python godot/tool/build.py` first (no bundle in %s)' % bundle)
    ldd = shutil.which('ldd')
    if not ldd:
        parser.error('ldd not found; run from an MSYS2 MinGW64 shell or put its bin directory on PATH')
    listing = subprocess.run([ldd, str(bundle / 'cliamp.exe')], capture_output=True, text=True, check=True).stdout
    staged = []
    for line in listing.splitlines():
        parts = line.split('=>')
        if len(parts) == 2 and '/mingw64/bin/' in parts[1].replace(chr(92), '/'):
            source = msys_to_windows(parts[1].split('(')[0].strip())
            shutil.copy2(source, bundle / source.name)
            staged.append(source.name)
    print('Staged DLLs:', ', '.join(sorted(staged)))
    iscc = next((p for p in ISCC_CANDIDATES if p.exists()), None) or shutil.which('ISCC')
    if not iscc:
        parser.error('Install Inno Setup 6 (winget install JRSoftware.InnoSetup)')
    subprocess.run([str(iscc), '/Qp', '/DAppVersion=' + options.version, str(here / 'cliamp-desktop.iss')], check=True)
    print('Built', bundle.parent / 'installer')


if __name__ == '__main__':
    main()
