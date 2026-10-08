#!/usr/bin/env python3
"""Validate native strings files and coverage of explicit localization calls."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STRING = r'"(?:\\.|[^"\\])*"'
PAIR = re.compile(r'(' + STRING + r')\s*=\s*(' + STRING + r')\s*;')

def load(path):
    source = path.read_text()
    values = {}
    for key, value in PAIR.findall(source):
        key, value = json.loads(key), json.loads(value)
        assert key not in values, f'{path}: duplicate key {key}'
        values[key] = value
    remainder = PAIR.sub('', re.sub(r'/\*.*?\*/', '', source, flags=re.S)).strip()
    assert not remainder, f'{path}: unparsed strings syntax'
    return values

for table in ('Localizable', 'InfoPlist'):
    english = load(ROOT / f'FitnessApp/Resources/en.lproj/{table}.strings')
    chinese = load(ROOT / f'FitnessApp/Resources/zh-Hans.lproj/{table}.strings')
    assert english.keys() == chinese.keys(), f'{table}: language key mismatch'
    for key, value in chinese.items():
        assert value.strip(), f'{table}: empty translation {key}'
        assert key.count('%@') == value.count('%@'), f'{table}: format argument mismatch {key}'
    if table == 'Localizable':
        assert all(key == value for key, value in english.items()), 'English fallback changed'
        references = set()
        for path in (ROOT / 'FitnessApp').rglob('*.swift'):
            references.update(json.loads(value) for value in re.findall(r'L10n\.text\((' + STRING + ')', path.read_text()))
        assert not references - english.keys(), f'Untranslated keys: {references - english.keys()}'
        print(f'{len(english)} English/Chinese strings; {len(references)} static localization calls covered.')
print('Permission explanations, key coverage and formatting placeholders verified.')
