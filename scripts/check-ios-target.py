#!/usr/bin/env python3
"""Validate the checked-in iOS app source membership and shared launch scheme."""
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[^\s{}()=;,]+|[{}()=;,]', re.S)


def parse_project(text):
    tokens = [m.group() for m in TOKEN.finditer(text) if not m.group().startswith(('//', '/*'))]
    position = 0

    def consume(expected=None):
        nonlocal position
        token = tokens[position]
        position += 1
        if expected is not None and token != expected:
            raise ValueError(f'Expected {expected}, found {token}')
        return token

    def value():
        token = consume()
        if token == '{':
            result = {}
            while tokens[position] != '}':
                key = consume()
                if key.startswith('"'):
                    key = json.loads(key)
                consume('=')
                result[key] = value()
                consume(';')
            consume('}')
            return result
        if token == '(':
            result = []
            while tokens[position] != ')':
                result.append(value())
                if tokens[position] == ',':
                    consume(',')
            consume(')')
            return result
        return json.loads(token) if token.startswith('"') else token

    result = value()
    if position != len(tokens):
        raise ValueError('Unexpected trailing project contents')
    return result


def validate_membership(project, expected, scheme):
    objects = project['objects']
    targets = [(key, obj) for key, obj in objects.items()
               if obj.get('isa') == 'PBXNativeTarget' and obj.get('name') == 'LeanLog'
               and obj.get('productType') == 'com.apple.product-type.application']
    assert len(targets) == 1, 'Expected exactly one LeanLog iOS application target'
    target_id, target = targets[0]
    phases = [objects[key] for key in target['buildPhases']
              if objects[key].get('isa') == 'PBXSourcesBuildPhase']
    assert len(phases) == 1, 'Expected one application Compile Sources phase'
    paths = []
    for key in phases[0]['files']:
        build = objects[key]
        assert build['isa'] == 'PBXBuildFile', f'Invalid source build entry: {key}'
        reference = objects[build['fileRef']]
        assert reference.get('sourceTree') == 'SOURCE_ROOT', 'Resolve non-root source paths before validating'
        paths.append(reference['path'])
    assert len(paths) == len(set(paths)), 'Duplicate Compile Sources entries'
    missing = expected - set(paths)
    extra = set(paths) - expected
    assert not missing and not extra, f'LeanLog membership mismatch: missing={sorted(missing)}, extra={sorted(extra)}'
    launch = scheme.find('./LaunchAction/BuildableProductRunnable/BuildableReference')
    assert launch is not None and launch.get('BlueprintIdentifier') == target_id, 'LeanLog scheme launches a different target'
    build_refs = scheme.findall('./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference')
    assert any(ref.get('BlueprintIdentifier') == target_id for ref in build_refs), 'LeanLog scheme does not build the app target'
    return len(paths)


def main():
    project = parse_project((ROOT / 'FitnessApp.xcodeproj/project.pbxproj').read_text())
    expected = {str(path.relative_to(ROOT)) for path in (ROOT / 'FitnessApp').rglob('*.swift')}
    scheme = ET.parse(ROOT / 'FitnessApp.xcodeproj/xcshareddata/xcschemes/LeanLog.xcscheme').getroot()
    count = validate_membership(project, expected, scheme)
    print(f'LeanLog iOS app Compile Sources includes all {count} app Swift files; shared scheme targets LeanLog for build and launch.')


if __name__ == '__main__':
    main()
