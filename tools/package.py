#!/usr/bin/env python3
"""Builds the release zip by hand, the way the BigWigs packager does in CI:
dist/Circlet-<version>.zip with a Circlet/ folder inside, without the files .pkgmeta
ignores, and with @project-version@ filled in.

    python3 tools/package.py            version from the top of CHANGELOG.md
    python3 tools/package.py 0.62.1     a given version
"""
import os, re, sys, zipfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def version():
    if len(sys.argv) > 1:
        return sys.argv[1]
    for line in open(os.path.join(root, 'CHANGELOG.md'), encoding='utf-8'):
        m = re.match(r'##\s+v?([\w.\-]+)', line)
        if m:
            return m.group(1)
    sys.exit('No version given and none found in CHANGELOG.md')

def ignored():
    names, inside = [], False
    for line in open(os.path.join(root, '.pkgmeta'), encoding='utf-8'):
        if re.match(r'^ignore:', line):
            inside = True
        elif inside and re.match(r'^\s+-\s+', line):
            names.append(line.split('-', 1)[1].strip())
        elif inside and line.strip() and not line.startswith(' '):
            inside = False
    return set(names) | {'.git', 'dist', '__pycache__'}

ver = version()
skip = ignored()
os.makedirs(os.path.join(root, 'dist'), exist_ok=True)
out = os.path.join(root, 'dist', f'Circlet-{ver}.zip')
count = 0
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        top = rel.split(os.sep)[0]
        if top in skip:
            dirnames[:] = []
            continue
        dirnames[:] = sorted(d for d in dirnames if d not in skip)
        for name in sorted(filenames):
            if rel == '.' and name in skip:
                continue
            path = os.path.join(dirpath, name)
            arc = os.path.join('Circlet', os.path.relpath(path, root)).replace(os.sep, '/')
            data = open(path, 'rb').read()
            if name.endswith(('.toc', '.lua', '.md')):
                data = data.replace(b'@project-version@', ver.encode())
            z.writestr(arc, data)
            count += 1
print(f'{out}: {count} files')
