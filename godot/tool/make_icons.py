#!/usr/bin/env python3
"""Build icon/icon.ico and icon/icon.icns from icon/icon.svg.

Godot rasterizes the SVG (it already ships an SVG renderer), then the PNGs are
packed into the ICO and ICNS containers directly, so no image tools are needed.
"""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

SCRIPT = '''extends SceneTree
func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon/icon.svg")
	for size in [16, 32, 48, 64, 128, 256, 512, 1024]:
		var image := Image.new()
		image.load_svg_from_string(svg, size / 128.0)
		image.save_png(OS.get_environment("ICON_OUT").path_join("%d.png" % size))
	quit()
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', default=os.environ.get('GODOT') or shutil.which('godot'))
    options = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    icons = project / 'icon'
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        script = tmp / 'render.gd'
        script.write_text(SCRIPT)
        env = dict(os.environ, ICON_OUT=str(tmp))
        subprocess.run([options.godot, '--headless', '--path', str(project), '--script', str(script)], check=True, env=env)
        png = {s: (tmp / f'{s}.png').read_bytes() for s in (16, 32, 48, 64, 128, 256, 512, 1024)}

    # ICO: PNG-compressed entries (Windows Vista and later).
    sizes = (16, 32, 48, 64, 128, 256)
    header = struct.pack('<HHH', 0, 1, len(sizes))
    offset = 6 + 16 * len(sizes)
    entries, data = b'', b''
    for s in sizes:
        entries += struct.pack('<BBBBHHII', s % 256, s % 256, 0, 0, 1, 32, len(png[s]), offset + len(data))
        data += png[s]
    (icons / 'icon.ico').write_bytes(header + entries + data)

    # ICNS: PNG-compressed icon types.
    kinds = {b'icp4': 16, b'icp5': 32, b'icp6': 64, b'ic07': 128, b'ic08': 256, b'ic09': 512, b'ic10': 1024}
    body = b''.join(k + struct.pack('>I', 8 + len(png[s])) + png[s] for k, s in kinds.items())
    (icons / 'icon.icns').write_bytes(b'icns' + struct.pack('>I', 8 + len(body)) + body)
    print('Wrote', icons / 'icon.ico', icons / 'icon.icns')


if __name__ == '__main__':
    main()
