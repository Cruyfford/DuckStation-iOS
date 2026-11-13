#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0
"""One-off rebrand of user-visible UI text in the ARMSX2-derived frontend for Psxp (PS1).

- Localizable.xcstrings: rewrites every translation value and adds an English value for keys that
  mention ARMSX2 / PCSX2 / PS2, so the key itself (used for lookup) stays untouched.
- Swift sources: rewrites plain string literals that are not localization keys, skipping storage
  keys, folder/resource names and the license/credits list (attribution must stay intact).
"""
import json, re, sys, pathlib

UI = pathlib.Path(sys.argv[1])
TOKENS = re.compile(r'(?<![A-Za-z0-9_])(ARMSX2/PCSX2|ARMSX2 iOS|ARMSX2|PCSX2|PlayStation 2|PS2)(?![A-Za-z0-9_\-]|\.[A-Za-z])')
MAP = {'ARMSX2/PCSX2': 'Psxp', 'ARMSX2 iOS': 'Psxp', 'ARMSX2': 'Psxp', 'PCSX2': 'Psxp',
       'PlayStation 2': 'PlayStation', 'PS2': 'PS1'}


def sub(text):
    return TOKENS.sub(lambda m: MAP[m.group(1)], text)


xc_path = UI / 'assets/resources/Localizable.xcstrings'
xc = json.loads(xc_path.read_text(encoding='utf-8'))
keys = set(xc['strings'].keys())
changed = 0
for key, entry in xc['strings'].items():
    locs = entry.setdefault('localizations', {})
    for lang, loc in locs.items():
        unit = loc.get('stringUnit')
        if unit and 'value' in unit:
            new = sub(unit['value'])
            if new != unit['value']:
                unit['value'] = new
                changed += 1
    if TOKENS.search(key) and 'en' not in locs:
        locs['en'] = {'stringUnit': {'state': 'translated', 'value': sub(key)}}
        changed += 1
xc_path.write_text(json.dumps(xc, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'xcstrings: {changed} values updated')

SKIP_FILES = {'LicenseView.swift', 'AppLanguage.swift'}
SKIP_LINE = re.compile(r'appendingPathComponent|named:|forResource|forKey|UserDefaults|Notification\.Name|subdirectory|bundleIdentifier')
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
edits = 0
for path in (UI / 'Swift').rglob('*.swift'):
    if path.name in SKIP_FILES:
        continue
    lines = path.read_text(encoding='utf-8').split('\n')
    dirty = False
    for i, line in enumerate(lines):
        if not TOKENS.search(line) or SKIP_LINE.search(line) or line.lstrip().startswith('//'):
            continue

        def repl(m):
            body = m.group(1)
            if body in keys or not TOKENS.search(body):
                return m.group(0)
            return '"' + sub(body) + '"'

        new = LITERAL.sub(repl, line)
        if new != line:
            lines[i] = new
            dirty = True
            edits += 1
    if dirty:
        path.write_text('\n'.join(lines), encoding='utf-8')
print(f'swift: {edits} lines updated')
