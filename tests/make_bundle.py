# Bundles the addon's Lua files, in Circlet.toc order, into one chunk for the tests:
# chunk(name, ns) runs every file with the same name/ns, the way the game loads them.
import os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
files = [l.strip() for l in open(os.path.join(root, 'Circlet.toc'))
         if l.strip().endswith('.lua') and not l.startswith('Libs')]
out = ['local name, ns = ...']
for f in files:
    src = open(os.path.join(root, f.replace('\\', '/'))).read()
    assert ']====]' not in src
    out.append(f'assert(load([====[{src}]====], "@{f.replace(chr(92), "/")}"))(name, ns)')
open(os.path.join(here, 'bundle.lua'), 'w').write('\n'.join(out) + '\n')
