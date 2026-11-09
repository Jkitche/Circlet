#!/usr/bin/env python3
"""Runs every *_test.py here against the addon and compares its output with the saved
golden output in golden/. Any difference (or a Lua error) fails.

    python3 tests/run_tests.py            run everything
    python3 tests/run_tests.py quest cast  run some
    python3 tests/run_tests.py --update   accept the current output as the new golden

Needs Python 3 with lupa (pip install lupa)."""
import difflib, glob, os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
args = [a for a in sys.argv[1:] if not a.startswith('--')]
update = '--update' in sys.argv

subprocess.run([sys.executable, os.path.join(here, 'make_bundle.py')], check=True)
tests = sorted(os.path.basename(p)[:-8] for p in glob.glob(os.path.join(here, '*_test.py')))
if args:
    tests = [t for t in tests if t in args]

failed = []
for name in tests:
    r = subprocess.run([sys.executable, name + '_test.py'], cwd=here, capture_output=True, text=True, timeout=300)
    out = r.stdout + (('\n[stderr]\n' + r.stderr) if r.returncode else '')
    golden = os.path.join(here, 'golden', name + '.txt')
    if update:
        open(golden, 'w').write(out)
        print(f'updated  {name}')
        continue
    want = open(golden).read() if os.path.exists(golden) else None
    if r.returncode or want != out:
        failed.append(name)
        print(f'FAIL     {name}')
        if want is None:
            print('  (no golden output yet: run with --update)')
        else:
            diff = difflib.unified_diff(want.splitlines(), out.splitlines(), 'golden', 'now', lineterm='', n=1)
            for line in list(diff)[:40]:
                print('  ' + line)
    else:
        print(f'ok       {name}')

if not update:
    print(f'\n{len(tests) - len(failed)}/{len(tests)} passed')
    sys.exit(1 if failed else 0)
