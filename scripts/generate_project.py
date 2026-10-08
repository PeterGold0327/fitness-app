#!/usr/bin/env python3
"""Deterministic, dependency-free generator for the checked-in Xcode project."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}
def uid(key): return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def q(text): return json.dumps(str(text))
def add(key, body):
    key_id = uid(key)
    objects[key_id] = body
    return key_id
def refs(items): return '(' + ', '.join(items) + (',' if items else '') + ')'

def file(path, kind):
    return add('file:' + path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(path)}; sourceTree = SOURCE_ROOT;')

app_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'FitnessApp').rglob('*.swift'))
test_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'FitnessAppTests').rglob('*.swift'))
ui_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "FitnessAppUITests").rglob("*.swift"))
file_ids = {p: file(p, 'sourcecode.swift') for p in app_sources + test_sources + ui_sources}
resource_paths = ['FitnessApp/Resources/Info.plist', 'FitnessApp/Resources/FitnessApp.entitlements', 'FitnessApp/Resources/PrivacyInfo.xcprivacy']
resource_ids = [file(p, 'text.plist.xml') for p in resource_paths]
# Variant groups preserve .lproj directories and let iOS select the system language.
for name in ['Localizable.strings', 'InfoPlist.strings']:
    children = []
    for language in ['en', 'zh-Hans']:
        path = f'FitnessApp/Resources/{language}.lproj/{name}'
        children.append(add('file:' + path,
            f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {q(language)}; path = {q(path)}; sourceTree = SOURCE_ROOT;'))
    variant = add('localized:' + name,
        f'isa = PBXVariantGroup; children = {refs(children)}; name = {q(name)}; sourceTree = "<group>";')
    file_ids[name] = variant
    resource_ids.append(variant)
app_product = add('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LeanLog.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LeanLogTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
app_group = add('app-group', f'isa = PBXGroup; children = {refs([file_ids[p] for p in app_sources] + resource_ids)}; name = FitnessApp; sourceTree = "<group>";')
test_group = add('test-group', f'isa = PBXGroup; children = {refs([file_ids[p] for p in test_sources])}; name = FitnessAppTests; sourceTree = "<group>";')
ui_product = add('ui-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LeanLogUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
ui_group = add('ui-group', f'isa = PBXGroup; children = {refs([file_ids[p] for p in ui_sources])}; name = FitnessAppUITests; sourceTree = "<group>";')
products = add('products', f'isa = PBXGroup; children = {refs([app_product, test_product, ui_product])}; name = Products; sourceTree = "<group>";')
main_group = add('main-group', f'isa = PBXGroup; children = {refs([app_group, test_group, ui_group, products])}; sourceTree = "<group>";')

def phase(key, isa, paths):
    builds = [add(f'build:{key}:{p}', f'isa = PBXBuildFile; fileRef = {file_ids[p] if p in file_ids else uid("file:" + p)};') for p in paths]
    return add(key, f'isa = {isa}; buildActionMask = 2147483647; files = {refs(builds)}; runOnlyForDeploymentPostprocessing = 0;')

app_phases = [phase('app-sources', 'PBXSourcesBuildPhase', app_sources), phase('app-frameworks', 'PBXFrameworksBuildPhase', []), phase('app-resources', 'PBXResourcesBuildPhase', ['FitnessApp/Resources/PrivacyInfo.xcprivacy', 'Localizable.strings', 'InfoPlist.strings'])]
test_phases = [phase('test-sources', 'PBXSourcesBuildPhase', test_sources), phase('test-frameworks', 'PBXFrameworksBuildPhase', []), phase('test-resources', 'PBXResourcesBuildPhase', [])]

ui_phases = [phase('ui-sources', 'PBXSourcesBuildPhase', ui_sources), phase('ui-frameworks', 'PBXFrameworksBuildPhase', []), phase('ui-resources', 'PBXResourcesBuildPhase', [])]

def config_list(scope, settings):
    ids = []
    for name in ['Debug', 'Release']:
        combined = dict(settings)
        if scope == 'project':
            combined.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if name == 'Debug' else '-O',
                             'DEBUG_INFORMATION_FORMAT': 'dwarf' if name == 'Debug' else 'dwarf-with-dsym'})
            if name == 'Debug': combined.update({'ENABLE_TESTABILITY': 'YES', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG'})
        pairs = ' '.join(f'{k} = {q(v)};' for k, v in sorted(combined.items()))
        ids.append(add(f'{scope}-{name}', f'isa = XCBuildConfiguration; buildSettings = {{ {pairs} }}; name = {name};'))
    return add(scope + '-config-list', f'isa = XCConfigurationList; buildConfigurations = {refs(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_configs = config_list('project', {'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0'})
app_configs = config_list('app', {'PRODUCT_NAME': 'LeanLog', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.personal.LeanLog',
    'INFOPLIST_FILE': 'FitnessApp/Resources/Info.plist', 'CODE_SIGN_ENTITLEMENTS': 'FitnessApp/Resources/FitnessApp.entitlements',
    'CODE_SIGN_STYLE': 'Automatic', 'TARGETED_DEVICE_FAMILY': '1', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
    'SUPPORTS_MACCATALYST': 'NO', 'MARKETING_VERSION': '0.1.0', 'CURRENT_PROJECT_VERSION': '1',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks'})
test_configs = config_list('test', {'PRODUCT_NAME': 'LeanLogTests', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.personal.LeanLogTests',
    'GENERATE_INFOPLIST_FILE': 'YES', 'CODE_SIGN_STYLE': 'Automatic', 'TARGETED_DEVICE_FAMILY': '1',
    'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/LeanLog.app/LeanLog',
    'BUNDLE_LOADER': '$(TEST_HOST)', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'})
ui_configs = config_list('ui', {'PRODUCT_NAME': 'LeanLogUITests', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.personal.LeanLogUITests',
    'GENERATE_INFOPLIST_FILE': 'YES', 'CODE_SIGN_STYLE': 'Automatic', 'TARGETED_DEVICE_FAMILY': '1',
    'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'TEST_TARGET_NAME': 'LeanLog',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'})
app_target = add('app-target', f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {refs(app_phases)}; buildRules = (); dependencies = (); name = LeanLog; productName = LeanLog; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy = add('test-proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = LeanLog;')
dependency = add('test-dependency', f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
test_target = add('test-target', f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {refs(test_phases)}; buildRules = (); dependencies = {refs([dependency])}; name = LeanLogTests; productName = LeanLogTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
ui_dependency = add('ui-dependency', f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
ui_target = add('ui-target', f'isa = PBXNativeTarget; buildConfigurationList = {ui_configs}; buildPhases = {refs(ui_phases)}; buildRules = (); dependencies = {refs([ui_dependency])}; name = LeanLogUITests; productName = LeanLogUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
project = add('project', f'''isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {app_target} = {{ CreatedOnToolsVersion = 16.0; SystemCapabilities = {{ com.apple.HealthKit = {{ enabled = 1; }}; }}; }}; {test_target} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {app_target}; }}; {ui_target} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {app_target}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([app_target, test_target, ui_target])};''')
text = '// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'
text += ''.join(f'  {key} = {{ {value} }};\n' for key, value in sorted(objects.items()))
text += f' }};\n rootObject = {project};\n}}\n'
project_dir = ROOT / 'FitnessApp.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir / 'project.pbxproj').write_text(text)

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
  <BuildActionEntries>
   <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
    <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="LeanLog.app" BlueprintName="LeanLog" ReferencedContainer="container:FitnessApp.xcodeproj"/>
   </BuildActionEntry>
  </BuildActionEntries>
 </BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
  <Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="LeanLogTests.xctest" BlueprintName="LeanLogTests" ReferencedContainer="container:FitnessApp.xcodeproj"/></TestableReference><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui_target}" BuildableName="LeanLogUITests.xctest" BlueprintName="LeanLogUITests" ReferencedContainer="container:FitnessApp.xcodeproj"/></TestableReference></Testables>
 </TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="LeanLog.app" BlueprintName="LeanLog" ReferencedContainer="container:FitnessApp.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugServiceExtension="internal">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="LeanLog.app" BlueprintName="LeanLog" ReferencedContainer="container:FitnessApp.xcodeproj"/></BuildableProductRunnable>
 </ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = project_dir / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / 'LeanLog.xcscheme').write_text(scheme)
print(f'Generated project: {len(app_sources)} app sources, {len(test_sources)} unit test sources, {len(ui_sources)} UI test sources.')
