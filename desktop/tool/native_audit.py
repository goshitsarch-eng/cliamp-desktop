#!/usr/bin/env python3
"""Run the Linux desktop audit in an isolated profile and X11 session.
Requires Flutter, a built Cliamp engine, Xvfb, xfwm4, ImageMagick, ffmpeg, dbus-run-session and libXtst.
"""
import argparse
import json
import math
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import tempfile
import time
import wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--display', default=':105')
    args = parser.parse_args()
    root = (args.output or Path(tempfile.mkdtemp(prefix='cliamp-audit-'))).resolve()
    root.mkdir(parents=True, exist_ok=True)
    music = root / 'profile/home/Music'
    music.mkdir(parents=True, exist_ok=True)
    fixture_names = ['Aurora - Blue Hour.wav', 'Björk Test - Café 春.wav',
                     'Long Artist Name - ' + ('Long title ' * 14).strip() + '.wav']
    samples = b''.join(struct.pack('<h', int(1000 * math.sin(2 * math.pi * 220 * i / 8000)))
                       for i in range(8000)) * 120
    for name in fixture_names:
        with wave.open(str(music / name), 'wb') as audio:
            audio.setparams((1, 2, 8000, 0, 'NONE', 'not compressed'))
            audio.writeframes(samples)
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                    '-i', str(music / fixture_names[0]), '-metadata', 'title=Audit lyrics',
                    '-metadata', 'artist=Audit', '-metadata',
                    'lyrics=[00:00.00]First Café 春 line\n[00:30.00]Second line\n[01:00.00]Final line',
                    str(music / 'Audit lyrics.flac')], check=True)
    large = root / 'profile/large-library'
    large.mkdir(exist_ok=True)
    for index in range(205):
        link = large / f'Audit {index:03}.wav'
        if not link.exists():
            os.link(music / fixture_names[0], link)
    (music / 'broken.wav').write_text('not an audio file')
    (music / 'not-audio.txt').write_text('unsupported input')
    (music / 'list.m3u').write_text('#EXTM3U\n' + '\n'.join(fixture_names[:2]) + '\n')
    (music / 'relative.pls').write_text('[playlist]\nNumberOfEntries=1\nFile1=' + fixture_names[0] + '\n')
    (music / 'broken.m3u').write_text('#EXTM3U\nmissing-file.wav\n')
    (root / 'profile/asound.conf').write_text('pcm.!default { type null }\nctl.!default { type hw card 0 }\n')
    shutil.copyfile(Path(__file__).with_name('x11_audit.py'), root / 'window.py')
    engine = str(args.engine.resolve())
    env = dict(os.environ, DISPLAY=args.display, CLIAMP_BINARY=engine, CLIAMP_AUDIT_ROOT=str(root))
    # A full audit must not inherit an incremental phase or skip switch.
    for key in ('CLIAMP_AUDIT_PHASE', 'CLIAMP_AUDIT_PROFILE',
                'CLIAMP_AUDIT_OPERATIONS_FAST', 'CLIAMP_AUDIT_INTERACTIONS_ONLY',
                'CLIAMP_AUDIT_PREFERENCE_START'):
        env.pop(key, None)
    setup_env = dict(env, HOME=str(root / 'profile/home'), CLIAMP_CONFIG_DIR=str(root / 'profile/config'))
    (root / 'profile/config').mkdir(exist_ok=True)
    schema = subprocess.check_output([engine, 'setup', 'schema'], env=setup_env, text=True)
    json.loads(schema)
    (root / 'setup-schema.json').write_text(schema)
    services = []
    try:
        for command, log in [(['Xvfb', args.display, '-screen', '0', '2560x1600x24', '-nolisten', 'tcp'], 'xvfb.log'),
                             (['dbus-run-session', '--', 'xfwm4', '--compositor=off'], 'wm.log')]:
            with (root / log).open('w') as output:
                proc = subprocess.Popen(command, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            services.append(proc)
            time.sleep(.5)
            if proc.poll() is not None:
                raise RuntimeError(f'{command[0]} exited; see {root / log}')
        wm_ready = False
        for _ in range(40):
            status = subprocess.run(['xprop', '-root', '_NET_SUPPORTING_WM_CHECK'],
                                    env=env, capture_output=True, text=True, check=True)
            if 'window id # 0x' in status.stdout:
                wm_ready = True
                break
            time.sleep(.25)
        if not wm_ready:
            raise RuntimeError(f'Window manager did not claim the display; see {root / "wm.log"}')
        command = ['dbus-run-session', '--', 'flutter', 'test', 'integration_test/native_audit_test.dart', '-d', 'linux', '--reporter', 'expanded']
        (root / 'native-results.json').unlink(missing_ok=True)
        with (root / 'native.log').open('w') as output:
            proc = subprocess.Popen(command, cwd=Path(__file__).resolve().parents[1], env=env,
                                    stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            services.append(proc)
            code = proc.wait()
        if code == 0:
            walkthrough = json.loads((root / 'native-results.json').read_text())
            (root / 'walkthrough-results.json').write_text(json.dumps(walkthrough, indent=2))
            persisted_profile = (root / 'profile-path.txt').read_text().strip()
            combined = list(walkthrough)
            for phase in ('reopen', 'location-allow'):
                phase_env = dict(env, CLIAMP_AUDIT_PHASE=phase)
                if phase == 'reopen':
                    phase_env['CLIAMP_AUDIT_PROFILE'] = persisted_profile
                (root / 'native-results.json').unlink(missing_ok=True)
                with (root / f'{phase}.log').open('w') as output:
                    proc = subprocess.Popen(command, cwd=Path(__file__).resolve().parents[1], env=phase_env,
                                            stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
                    services.append(proc)
                    code = proc.wait()
                phase_results = json.loads((root / 'native-results.json').read_text())
                (root / f'{phase}-results.json').write_text(json.dumps(phase_results, indent=2))
                combined.extend(phase_results)
                (root / 'native-results.json').write_text(json.dumps(combined, indent=2))
                if code != 0:
                    break
        print(f'Audit exit {code}. Results, logs and screenshots: {root}')
        return code
    finally:
        for proc in reversed(services):
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()


if __name__ == '__main__':
    raise SystemExit(main())
