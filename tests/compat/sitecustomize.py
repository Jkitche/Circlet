# Loaded into every test by run_tests.py (through PYTHONPATH) so the suite, written on Linux,
# also runs on Windows and macOS. Changes nothing where the Linux paths work.
#  - subprocess.run(['python3', ...]): runs with this interpreter (Windows has no python3,
#    only a Microsoft Store stub of that name).
#  - ImageFont.truetype('/usr/share/fonts/.../DejaVuSans*.ttf'): when that file isn't there,
#    a font this system has instead. Fonts only affect the pictures the tests save, never
#    the output compared with golden/.
import os, subprocess, sys

_run = subprocess.run
def _run_with_this_python(args, *a, **kw):
    if isinstance(args, (list, tuple)) and args and args[0] == 'python3':
        args = [sys.executable] + list(args[1:])
    return _run(args, *a, **kw)
subprocess.run = _run_with_this_python

try:
    from PIL import ImageFont
except ImportError:
    ImageFont = None

if ImageFont is not None:
    _truetype = ImageFont.truetype
    _windir = os.environ.get('WINDIR', r'C:\Windows')
    _fallbacks = {
        'bold': [os.path.join(_windir, 'Fonts', 'arialbd.ttf'), '/Library/Fonts/Arial Bold.ttf'],
        'regular': [os.path.join(_windir, 'Fonts', 'arial.ttf'), '/Library/Fonts/Arial.ttf'],
    }
    def _truetype_anywhere(font=None, size=10, *a, **kw):
        if isinstance(font, str) and font.startswith('/usr/share/fonts/') and not os.path.exists(font):
            kind = 'bold' if 'Bold' in font else 'regular'
            for alt in _fallbacks[kind]:
                if os.path.exists(alt):
                    return _truetype(alt, size, *a, **kw)
            return ImageFont.load_default(size)
        return _truetype(font, size, *a, **kw)
    ImageFont.truetype = _truetype_anywhere
