#!/usr/bin/env python3
# Lists interface texts (the literals inside tr(...)) that have no English in Sources/Fishbots/L10nEnglish.swift.
#   python3 scripts/l10n-check.py
import re, glob, os, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
lit = re.compile(r'(?<!#)"((?:\\.|[^"\\])*)"')
table = open(os.path.join(root, 'Sources/Fishbots/L10nEnglish.swift')).read()
known = {m.group(1) for m in re.finditer(r'^\s*"((?:\\.|[^"\\])*)":', table, re.M)}
missing = []
for f in sorted(glob.glob(os.path.join(root, 'Sources/Fishbots/*.swift')) + glob.glob(os.path.join(root, 'Saver/*.swift')) + glob.glob(os.path.join(root, 'iOS/*.swift'))):
    if f.endswith('L10nEnglish.swift'):
        continue
    for n, line in enumerate(open(f), 1):
        code = line.split('//')[0] if '"' not in line.split('//')[0][-1:] else line
        for m in re.finditer(r'\btr\(', code):
            depth, seg = 0, ''
            for ch in code[m.end() - 1:]:
                seg += ch
                depth += ch == '('
                depth -= ch == ')'
                if depth == 0:
                    break
            seg = re.sub(r'\["(?:\\.|[^"\\])*"\]', '', seg)   # dictionary subscripts aren't texts
            for k in lit.findall(seg):
                if re.search(r'[A-Za-zÀ-ú]', k) and not k.startswith('\\(') and k not in known and k not in ('minimal', 'full', 'none'):
                    missing.append(f'{os.path.relpath(f, root)}:{n}: {k}')
print('\n'.join(missing) if missing else 'every tr() text has English')
sys.exit(1 if missing else 0)
