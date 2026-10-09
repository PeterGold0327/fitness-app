#!/usr/bin/env python3
"""Regression checks: missing app membership or a wrong launch target must fail."""
import importlib.util
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ios_target', ROOT / 'scripts/check-ios-target.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class AppTargetTests(unittest.TestCase):
    def setUp(self):
        self.project = checker.parse_project((ROOT / 'FitnessApp.xcodeproj/project.pbxproj').read_text())
        self.expected = {str(path.relative_to(ROOT)) for path in (ROOT / 'FitnessApp').rglob('*.swift')}
        self.scheme = ET.parse(ROOT / 'FitnessApp.xcodeproj/xcshareddata/xcschemes/LeanLog.xcscheme').getroot()

    def test_current_app_membership_and_launch_scheme(self):
        self.assertEqual(checker.validate_membership(self.project, self.expected, self.scheme), len(self.expected))

    def test_timeline_file_reference_without_app_compile_membership_is_rejected(self):
        objects = self.project['objects']
        reference = next(key for key, obj in objects.items() if obj.get('path') == 'FitnessApp/Views/GrowthTimelineView.swift')
        build = next(key for key, obj in objects.items() if obj.get('isa') == 'PBXBuildFile' and obj.get('fileRef') == reference)
        for obj in objects.values():
            if obj.get('isa') == 'PBXSourcesBuildPhase' and build in obj['files']:
                obj['files'].remove(build)
        with self.assertRaisesRegex(AssertionError, 'GrowthTimelineView.swift'):
            checker.validate_membership(self.project, self.expected, self.scheme)

    def test_scheme_launching_test_target_is_rejected(self):
        test_target = next(key for key, obj in self.project['objects'].items() if obj.get('name') == 'LeanLogTests')
        self.scheme.find('./LaunchAction/BuildableProductRunnable/BuildableReference').set('BlueprintIdentifier', test_target)
        with self.assertRaisesRegex(AssertionError, 'launches a different target'):
            checker.validate_membership(self.project, self.expected, self.scheme)


if __name__ == '__main__':
    unittest.main()
