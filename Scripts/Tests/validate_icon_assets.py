"""Validate exported assets and iOS declarations without modifying any images."""
import hashlib
import json
import pathlib
import plistlib
import struct
import sys

root = pathlib.Path(__file__).resolve().parents[2]
assets = root / 'Myaow/Assets.xcassets'
variants = ['oledNoir', 'cyberNeon', 'furry', 'liquidGlass', 'pixel8bit', 'holoSpace', 'matcha', 'magma', 'gold']
for variant in variants:
    iconset = assets / f'AppIcon_{variant}.appiconset'
    manifest = json.loads((iconset / 'Contents.json').read_text())
    image = iconset / manifest['images'][0]['filename']
    data = image.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == (1024, 1024), variant
    assert data[25] == 2, f'{variant}: must be opaque RGB'
    preview = assets / f'IconPreview_{variant}.imageset'
    assert json.loads((preview / 'Contents.json').read_text())['images'][0]['filename'] == 'icon.png'
    expected = hashlib.sha256(data).digest()
    for duplicate in [preview / 'icon.png', root / f'Myaow/AppIcon_{variant}.png', root / f'Myaow/AppIcon_{variant}@2x.png']:
        assert hashlib.sha256(duplicate.read_bytes()).digest() == expected, str(duplicate)
assert (assets / 'IconPreview_classic.imageset/icon.png').read_bytes() == (assets / 'AppIcon.appiconset/AppIcon-Default.png').read_bytes()
if len(sys.argv) > 1:
    with open(sys.argv[1], 'rb') as f:
        info = plistlib.load(f)
    declarations = info['CFBundleIcons']['CFBundleAlternateIcons']
    for variant in variants:
        name = f'AppIcon_{variant}'
        assert declarations[name]['CFBundleIconName'] == name, name
print('PASS: 9 opaque 1024px icons, exact previews and bundle copies, unchanged classic, alternate-icon declarations verified.')
