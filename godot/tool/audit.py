"""Run the windowed desktop audit with disposable player profiles and local media."""
import argparse
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import wave

PROJECT = Path(__file__).resolve().parents[1]
SCENES = (
    "walk_shell sources library playlists collections pagination keyboard "
    "lyrics plugin_workflow operations pickers preferences services service_save "
    "settings1 settings2 forms providers dialogs_audit resize_audit themes "
    "geometry disconnect click_all streams messages catalog commands activity row_actions sliders"
).split()


class FixtureHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow.pls":
            time.sleep(24)
        try:
            super().do_GET()
        except (BrokenPipeError, ConnectionResetError):
            # The player can cancel a request or close after reading media headers.
            pass


def fixtures(base, selected):
    music = base / "music"
    media = base / "served"
    music.mkdir()
    media.mkdir()
    tone = music / "alpha tone.wav"
    with wave.open(str(tone), "wb") as stream:
        stream.setparams((1, 2, 8000, 0, "NONE", ""))
        stream.writeframes(bytes(8000 * 2 * 90))
    for name in ("bravo.wav", "Café 日本語.wav", "delta & (mix).wav"):
        shutil.copy(tone, music / name)
    shutil.copy(tone, media / "tone.wav")
    shutil.copy(tone, media / "read-only.wav")
    (media / "read-only.wav").chmod(0o444)
    (media / "audit-fixture.lua").write_text(
        'local p = plugin.register({name="audit-fixture", type="hook", version="1", permissions={"keymap"}})\n'
        'p:command("echo", function(args) return args[1] end)\n'
        'p:bind("ctrl+n", "Test action", function() end)\n'
    )
    if "lyrics" in selected:
        for name, lyrics in (("timed", "[00:00.00]Café 日本語\n[00:30.00]Thirty seconds\n[01:00.00]One minute"),
                             ("plain", "Café 日本語\nPlain verse")):
            subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(tone), "-metadata",
                            "title=QA " + name, "-metadata", "lyrics=" + lyrics, str(media / (name + ".flac"))], check=True)
    if "streams" in selected:
        subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(tone), "-t", "18", "-c:a", "aac",
                        "-f", "hls", "-hls_time", "5", "-hls_list_size", "0", str(media / "stream.m3u8")], check=True)
    return music, media


def profile(root, scene):
    root.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for key, folder in {
        "HOME": "home", "CFFIXED_USER_HOME": "home", "USERPROFILE": "home",
        "APPDATA": "roaming", "LOCALAPPDATA": "local", "CLIAMP_CONFIG_DIR": "c",
        **{"XDG_" + key: folder for key, folder in (
            ("CONFIG_HOME", "conf"), ("STATE_HOME", "state"), ("CACHE_HOME", "cache"),
            ("DATA_HOME", "data"), ("RUNTIME_DIR", "run"), ("CONFIG_DIRS", "conf"),
            ("DATA_DIRS", "data"), ("BIN_HOME", "bin"))},
    }.items():
        path = root / folder
        path.mkdir(mode=0o700, exist_ok=True)
        env[key] = str(path)
    if scene == "geometry":
        directory = {"darwin": root / "home/Library/Application Support",
                     "win32": root / "roaming"}.get(sys.platform, root / "data") / "cliamp"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "window.ini").write_text('[window]\nmode="bad"\nscreen="bad"\nsize="bad"\nposition="bad"\n[ui]\nscale="large"\n')
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True, help="Built cliamp executable")
    parser.add_argument("--output", type=Path, required=True, help="New directory for screenshots and logs")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("scenes", nargs="*", metavar="SCENE")
    args = parser.parse_args()
    scenes = args.scenes or SCENES
    if "navidrome" in scenes and not all(os.environ.get("CLIAMP_QA_NAVIDROME_" + key) for key in ("URL", "USER", "PASSWORD")):
        parser.error("navidrome requires a disposable local server and CLIAMP_QA_NAVIDROME_URL, USER and PASSWORD")
    if "audio_outputs" in scenes and os.environ.get("CLIAMP_QA_AUDIO") not in ("system", "switcher"):
        parser.error("audio_outputs requires CLIAMP_QA_AUDIO=system or switcher on a disposable Windows profile")
    if set(scenes) - set(SCENES + ["navidrome", "audio_outputs"]):
        parser.error("Unknown scene. Choose from " + ", ".join(SCENES))
    binary = args.binary.resolve()
    if not binary.is_file():
        parser.error("Build the Go engine first")
    if ({"streams", "lyrics"} & set(scenes)) and not shutil.which("ffmpeg"):
        parser.error("Install FFmpeg to create the stream and lyrics fixtures")
    output = args.output.resolve()
    output.mkdir(parents=True)
    failures = []
    temp_root = Path(tempfile.gettempdir()).resolve()
    if os.name != "nt":
        # Darwin limits Unix socket paths to 103 bytes. Resolving its normal
        # per-user temp directory can push the longer scenario names past it.
        socket = temp_root / "cliamp-qa-XXXXXXXX" / max(scenes, key=len) / "c" / "cliamp.sock"
        if len(os.fsencode(socket)) > 103:
            temp_root = Path("/tmp").resolve()
    cleanup_root = str(temp_root)
    if os.name == "nt":
        # Long playlist names can exceed MAX_PATH during recursive removal.
        # Keep the paths typed into the app in their ordinary user-facing form.
        prefix = "\\\\?\\"
        if cleanup_root.startswith("\\\\"):
            cleanup_root = prefix + "UNC\\" + cleanup_root[2:]
        else:
            cleanup_root = prefix + cleanup_root
    with tempfile.TemporaryDirectory(prefix="cliamp-qa-", dir=cleanup_root) as temp:
        base = temp_root / Path(temp).name
        music, media = fixtures(base, scenes)
        handler = functools.partial(FixtureHandler, directory=str(media))
        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
            url = "http://127.0.0.1:" + str(server.server_port)
            (media / "test.pls").write_text("[playlist]\nNumberOfEntries=1\nFile1=" + url + "/tone.wav\nVersion=2\n")
            shutil.copy(media / "test.pls", media / "slow.pls")
            episodes = "".join(
                f'<item><title>Episode {i}</title><guid>fixture-{i}</guid><enclosure url="{url}/tone.wav?ep={i}" type="audio/wav" length="1440044"/></item>'
                for i in range(2)
            )
            (media / "feed.xml").write_text('<rss version="2.0"><channel><title>QA show</title>' + episodes + '</channel></rss>')
            threading.Thread(target=server.serve_forever, daemon=True).start()
            try:
                for scene in scenes:
                    name = "settings" if scene in ("settings1", "settings2") else scene
                    target = output / scene
                    target.mkdir()
                    env = profile(base / name, name)
                    if os.name != "nt":
                        # The player recognizes generated recordings under its
                        # own temp directory as eligible for Download.
                        env["TMPDIR"] = str(base)
                    if name == "catalog":
                        subscriptions = Path(env["CLIAMP_CONFIG_DIR"]) / "podcast_subscriptions.json"
                        subscriptions.write_text(json.dumps([{"id":"qa", "title":"QA show", "feed_url":url + "/feed.xml"}]))
                    env.update(CLIAMP_BINARY=str(binary), MUSIC=str(music), SHOT_WAV=str(music / "alpha tone.wav"),
                               SHOT_DIR=str(target), PLUGIN_URL=url + "/audit-fixture.lua", TAGGED_MUSIC=str(media),
                               STREAM_URL=url, STREAM_FIXTURES=str(media), THEMES="catppuccin-latte,dracula,winamp",
                               PHASE=scene[-1] if name == "settings" else "")
                    if scene == "catalog" and env.get("CLIAMP_QA_RADIO_TIMEZONE"):
                        env["TZ"] = env["CLIAMP_QA_RADIO_TIMEZONE"]
                    log = target / "run.log"
                    with log.open("w") as stream:
                        try:
                            run = subprocess.run([args.godot, "--single-window", "--path", str(PROJECT),
                                                  "res://tests/audit/" + name + ".tscn"], env=env, timeout=360,
                                                 stdout=stream, stderr=subprocess.STDOUT)
                            exit_code = run.returncode
                        except subprocess.TimeoutExpired:
                            print("Timed out after 360 seconds", file=stream)
                            exit_code = 1
                            try:
                                subprocess.run([str(binary), "remote", "call", "--", "desktop.quit"],
                                               env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=10)
                            except subprocess.TimeoutExpired:
                                print("Sidecar did not acknowledge shutdown within ten seconds", file=stream)
                    body = log.read_text(errors="replace")
                    passed = exit_code == 0 and "audit: 0 finding(s)" in body and "ERROR:" not in body and "WARNING:" not in body
                    print(scene, "PASS" if passed else "FAIL", flush=True)
                    if not passed:
                        failures.append(scene)
            finally:
                server.shutdown()
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
