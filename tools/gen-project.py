#!/usr/bin/env python3
"""Generate CourseMate.xcodeproj (project + shared scheme).

Xcode's project file is an OpenStep plist keyed by 24-hex object IDs, and this
project has four targets sharing source files — hand-editing that graph is a
losing game. This script owns it instead: the file lists live below, IDs are
derived from names so diffs stay readable, and one run regenerates everything.

    python3 tools/gen-project.py

Re-run after adding, renaming or moving a source file. Xcode will happily
rewrite the project if you prefer its UI; just be aware that this script then
becomes the stale copy.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "CourseMate.xcodeproj"

APP = "CourseMate"
EXT = "CourseMateBroadcast"
WIDGET = "CourseMateWidget"
TESTS = "CourseMateTests"

APP_BUNDLE = "us.innotel.coursemate"
EXT_BUNDLE = APP_BUNDLE + ".broadcast"
WIDGET_BUNDLE = APP_BUNDLE + ".widget"
TESTS_BUNDLE = APP_BUNDLE + ".tests"
APP_GROUP = "group.us.innotel.coursemate"

DEPLOYMENT_TARGET = "17.0"
MARKETING_VERSION = "1.0"
CURRENT_PROJECT_VERSION = "1"

#: (folder, filename, file type, targets that compile or bundle it)
FILES = [
    ("CourseMate", "CourseMateApp.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "ContentView.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "SettingsView.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "AppModel.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "BroadcastLauncher.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "Decisions.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "ReviewView.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "AnswerNotifier.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "AnswerActivity.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "PushRegistration.swift", "sourcecode.swift", (APP,)),
    ("CourseMate", "Assets.xcassets", "folder.assetcatalog", (APP,)),
    ("CourseMate", "Info.plist", "text.plist.xml", ()),
    ("CourseMate", "CourseMate.entitlements", "text.plist.entitlements", ()),
    ("CourseMateBroadcast", "SampleHandler.swift", "sourcecode.swift", (EXT,)),
    ("CourseMateBroadcast", "FrameSampler.swift", "sourcecode.swift", (EXT,)),
    ("CourseMateBroadcast", "AudioChunker.swift", "sourcecode.swift", (EXT,)),
    ("CourseMateBroadcast", "Info.plist", "text.plist.xml", ()),
    ("CourseMateBroadcast", "CourseMateBroadcast.entitlements", "text.plist.entitlements", ()),
    ("CourseMateWidget", "CourseMateWidgetBundle.swift", "sourcecode.swift", (WIDGET,)),
    ("CourseMateWidget", "Info.plist", "text.plist.xml", ()),
    ("CourseMateTests", "DecoderTests.swift", "sourcecode.swift", (TESTS,)),
    # The Live Activity attributes must match byte for byte on both sides.
    ("Shared", "AnswerActivityAttributes.swift", "sourcecode.swift", (APP, WIDGET)),
    ("Shared", "Settings.swift", "sourcecode.swift", (APP, EXT)),
    ("Shared", "CourseMateAPI.swift", "sourcecode.swift", (APP, EXT)),
    ("Shared", "ControlChannel.swift", "sourcecode.swift", (APP, EXT)),
]

PRODUCTS = [
    (APP, "CourseMate.app", "wrapper.application"),
    (EXT, "CourseMateBroadcast.appex", "wrapper.app-extension"),
    (WIDGET, "CourseMateWidget.appex", "wrapper.app-extension"),
    (TESTS, "CourseMateTests.xctest", "wrapper.cfbundle"),
]

PRODUCT_TYPES = {
    APP: "com.apple.product-type.application",
    EXT: "com.apple.product-type.app-extension",
    WIDGET: "com.apple.product-type.app-extension",
    TESTS: "com.apple.product-type.bundle.unit-test",
}

FOLDERS = ["CourseMate", "CourseMateBroadcast", "CourseMateWidget", "CourseMateTests", "Shared"]

#: target -> appex products it embeds
EMBEDS = {APP: [EXT, WIDGET]}

#: target -> targets it depends on (build order)
DEPENDS = {APP: [EXT, WIDGET], TESTS: [APP]}

PROJECT_COMMON = {
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "SDKROOT": "iphoneos",
    "SWIFT_STRICT_CONCURRENCY": "minimal",
    "SWIFT_VERSION": "5.0",
}

PROJECT_DEBUG = {
    **PROJECT_COMMON,
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)", )',
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}

PROJECT_RELEASE = {
    **PROJECT_COMMON,
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
}

APP_SETTINGS = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "CourseMate/CourseMate.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": CURRENT_PROJECT_VERSION,
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "CourseMate/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", )',
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": APP_BUNDLE,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"',
    "SUPPORTS_MACCATALYST": "NO",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
}

EXT_SETTINGS = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "CODE_SIGN_ENTITLEMENTS": "CourseMateBroadcast/CourseMateBroadcast.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": CURRENT_PROJECT_VERSION,
    "DEVELOPMENT_TEAM": '""',
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "CourseMateBroadcast/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": (
        '("$(inherited)", "@executable_path/Frameworks", '
        '"@executable_path/../../Frameworks", )'
    ),
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": EXT_BUNDLE,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
}

WIDGET_SETTINGS = {
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": CURRENT_PROJECT_VERSION,
    "DEVELOPMENT_TEAM": '""',
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "CourseMateWidget/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": (
        '("$(inherited)", "@executable_path/Frameworks", '
        '"@executable_path/../../Frameworks", )'
    ),
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": WIDGET_BUNDLE,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
}

TESTS_SETTINGS = {
    # Hosted by the app so @testable import works; a hostless bundle cannot link
    # an application target.
    "BUNDLE_LOADER": '"$(TEST_HOST)"',
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": CURRENT_PROJECT_VERSION,
    "DEVELOPMENT_TEAM": '""',
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": (
        '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks", )'
    ),
    "MARKETING_VERSION": MARKETING_VERSION,
    "PRODUCT_BUNDLE_IDENTIFIER": TESTS_BUNDLE,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
    "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/CourseMate.app/CourseMate"',
}

SETTINGS = {
    APP: APP_SETTINGS,
    EXT: EXT_SETTINGS,
    WIDGET: WIDGET_SETTINGS,
    TESTS: TESTS_SETTINGS,
}

SECTION_ORDER = [
    "PBXBuildFile",
    "PBXContainerItemProxy",
    "PBXCopyFilesBuildPhase",
    "PBXFileReference",
    "PBXFrameworksBuildPhase",
    "PBXGroup",
    "PBXNativeTarget",
    "PBXProject",
    "PBXResourcesBuildPhase",
    "PBXSourcesBuildPhase",
    "PBXTargetDependency",
    "XCBuildConfiguration",
    "XCConfigurationList",
]


def oid(kind: str, name: str) -> str:
    """A stable 24-hex object ID derived from what the object means."""
    return hashlib.sha1(f"coursemate:{kind}:{name}".encode()).hexdigest()[:24].upper()


class Builder:
    def __init__(self) -> None:
        self.objects: list[tuple[str, str, list[str]]] = []

    def add(self, obj_id: str, section: str, lines: list[str]) -> None:
        if len(obj_id) != 24:
            raise ValueError(f"bad object id length: {obj_id}")
        self.objects.append((section, obj_id, lines))

    def render(self, root: str) -> str:
        out = [
            "// !$*UTF8*$!",
            "{",
            "\tarchiveVersion = 1;",
            "\tclasses = {",
            "\t};",
            "\tobjectVersion = 56;",
            "\tobjects = {",
        ]
        for section in SECTION_ORDER:
            entries = sorted(
                (entry for entry in self.objects if entry[0] == section),
                key=lambda entry: entry[1],
            )
            if not entries:
                continue
            out.append(f"/* Begin {section} section */")
            for _, obj_id, lines in entries:
                out.append(f"\t\t{obj_id} = {{")
                out.extend(lines)
                out.append("\t\t};")
            out.append(f"/* End {section} section */")
        out.append("\t};")
        out.append(f"\trootObject = {root};")
        out.append("}")
        return "\n".join(out) + "\n"


def phase(name: str, isa: str, members: list[str]) -> list[str]:
    lines = [f"\t\t\tisa = {isa};", "\t\t\tbuildActionMask = 2147483647;", "\t\t\tfiles = ("]
    lines += [f"\t\t\t\t{member}," for member in members]
    lines += ["\t\t\t);"]
    if name:
        lines.append(f"\t\t\tname = {name};")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    return lines


def settings_lines(settings: dict[str, str]) -> list[str]:
    lines = ["\t\t\tbuildSettings = {"]
    lines += [f"\t\t\t\t{key} = {settings[key]};" for key in sorted(settings)]
    lines.append("\t\t\t};")
    return lines


def build_project() -> str:
    builder = Builder()

    project_id = oid("project", "CourseMate")
    target_ids = {name: oid("target", name) for name in SETTINGS}
    list_ids = {name: oid("configlist", name) for name in ["project", *SETTINGS]}
    file_ids: dict[tuple[str, str], str] = {}
    product_ids: dict[str, str] = {}

    # File references
    for folder, name, file_type, _ in FILES:
        file_id = oid("fileref", f"{folder}/{name}")
        file_ids[(folder, name)] = file_id
        builder.add(file_id, "PBXFileReference", [
            "\t\t\tisa = PBXFileReference;",
            f"\t\t\tlastKnownFileType = {file_type};",
            f"\t\t\tpath = {name};",
            '\t\t\tsourceTree = "<group>";',
        ])

    for owner, filename, file_type in PRODUCTS:
        product_id = oid("product", filename)
        product_ids[owner] = product_id
        builder.add(product_id, "PBXFileReference", [
            "\t\t\tisa = PBXFileReference;",
            f'\t\t\texplicitFileType = "{file_type}";',
            "\t\t\tincludeInIndex = 0;",
            f"\t\t\tpath = {filename};",
            "\t\t\tsourceTree = BUILT_PRODUCTS_DIR;",
        ])

    # Build files per target
    sources: dict[str, list[str]] = {name: [] for name in SETTINGS}
    resources: dict[str, list[str]] = {name: [] for name in SETTINGS}
    for folder, name, file_type, targets in FILES:
        for target in targets:
            build_id = oid("buildfile", f"{folder}/{name}@{target}")
            builder.add(build_id, "PBXBuildFile", [
                "\t\t\tisa = PBXBuildFile;",
                f"\t\t\tfileRef = {file_ids[(folder, name)]};",
            ])
            if file_type == "folder.assetcatalog":
                resources[target].append(build_id)
            else:
                sources[target].append(build_id)

    embed_builds: dict[str, str] = {}
    for host, guests in EMBEDS.items():
        for guest in guests:
            embed_id = oid("buildfile", f"embed-{guest}")
            embed_builds[guest] = embed_id
            builder.add(embed_id, "PBXBuildFile", [
                "\t\t\tisa = PBXBuildFile;",
                f"\t\t\tfileRef = {product_ids[guest]};",
                "\t\t\tsettings = {ATTRIBUTES = (RemoveHeadersOnCopy, );};",
            ])

    # Groups
    main_group = oid("group", "main")
    products_group = oid("group", "Products")
    folder_groups = {folder: oid("group", folder) for folder in FOLDERS}
    children_by_folder: dict[str, list[str]] = {folder: [] for folder in FOLDERS}
    for folder, name, _, _ in FILES:
        children_by_folder[folder].append(file_ids[(folder, name)])

    for folder in FOLDERS:
        builder.add(folder_groups[folder], "PBXGroup", [
            "\t\t\tisa = PBXGroup;",
            "\t\t\tchildren = (",
            *[f"\t\t\t\t{child}," for child in children_by_folder[folder]],
            "\t\t\t);",
            f"\t\t\tpath = {folder};",
            '\t\t\tsourceTree = "<group>";',
        ])

    builder.add(products_group, "PBXGroup", [
        "\t\t\tisa = PBXGroup;",
        "\t\t\tchildren = (",
        *[f"\t\t\t\t{product_ids[owner]}," for owner, _, _ in PRODUCTS],
        "\t\t\t);",
        "\t\t\tname = Products;",
        '\t\t\tsourceTree = "<group>";',
    ])

    builder.add(main_group, "PBXGroup", [
        "\t\t\tisa = PBXGroup;",
        "\t\t\tchildren = (",
        *[f"\t\t\t\t{folder_groups[folder]}," for folder in FOLDERS],
        f"\t\t\t\t{products_group},",
        "\t\t\t);",
        '\t\t\tsourceTree = "<group>";',
    ])

    # Phases
    sources_phase = {name: oid("phase", f"sources-{name}") for name in SETTINGS}
    frameworks_phase = {name: oid("phase", f"frameworks-{name}") for name in SETTINGS}
    resources_phase = {name: oid("phase", f"resources-{name}") for name in SETTINGS}
    embed_phase = oid("phase", "embed-extensions")

    for name in SETTINGS:
        builder.add(sources_phase[name], "PBXSourcesBuildPhase",
                    phase("", "PBXSourcesBuildPhase", sources[name]))
        builder.add(frameworks_phase[name], "PBXFrameworksBuildPhase",
                    phase("", "PBXFrameworksBuildPhase", []))
        if name != TESTS:
            builder.add(resources_phase[name], "PBXResourcesBuildPhase",
                        phase("", "PBXResourcesBuildPhase", resources[name]))

    embedded = [embed_builds[guest] for guests in EMBEDS.values() for guest in guests]
    builder.add(embed_phase, "PBXCopyFilesBuildPhase", [
        "\t\t\tisa = PBXCopyFilesBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        '\t\t\tdstPath = "";',
        "\t\t\tdstSubfolderSpec = 13;",
        "\t\t\tfiles = (",
        *[f"\t\t\t\t{member}," for member in embedded],
        "\t\t\t);",
        '\t\t\tname = "Embed App Extensions";',
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
    ])

    # Target dependencies
    dependencies: dict[str, list[str]] = {name: [] for name in SETTINGS}
    for owner, needed in DEPENDS.items():
        for dependency in needed:
            key = f"{owner}->{dependency}"
            proxy_id = oid("proxy", key)
            dependency_id = oid("dependency", key)
            builder.add(proxy_id, "PBXContainerItemProxy", [
                "\t\t\tisa = PBXContainerItemProxy;",
                f"\t\t\tcontainerPortal = {project_id};",
                "\t\t\tproxyType = 1;",
                f"\t\t\tremoteGlobalIDString = {target_ids[dependency]};",
                f'\t\t\tremoteInfo = "{dependency}";',
            ])
            builder.add(dependency_id, "PBXTargetDependency", [
                "\t\t\tisa = PBXTargetDependency;",
                f"\t\t\ttarget = {target_ids[dependency]};",
                f"\t\t\ttargetProxy = {proxy_id};",
            ])
            dependencies[owner].append(dependency_id)

    # Native targets
    for name in SETTINGS:
        phases = [sources_phase[name], frameworks_phase[name]]
        if name != TESTS:
            phases.append(resources_phase[name])
        if name in EMBEDS:
            phases.append(embed_phase)
        builder.add(target_ids[name], "PBXNativeTarget", [
            "\t\t\tisa = PBXNativeTarget;",
            f"\t\t\tbuildConfigurationList = {list_ids[name]};",
            "\t\t\tbuildPhases = (",
            *[f"\t\t\t\t{value}," for value in phases],
            "\t\t\t);",
            "\t\t\tbuildRules = (",
            "\t\t\t);",
            "\t\t\tdependencies = (",
            *[f"\t\t\t\t{value}," for value in dependencies[name]],
            "\t\t\t);",
            f"\t\t\tname = {name};",
            f"\t\t\tproductName = {name};",
            f"\t\t\tproductReference = {product_ids[name]};",
            f'\t\t\tproductType = "{PRODUCT_TYPES[name]}";',
        ])

    builder.add(project_id, "PBXProject", [
        "\t\t\tisa = PBXProject;",
        "\t\t\tattributes = {",
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;",
        "\t\t\t\tLastSwiftUpdateCheck = 1600;",
        "\t\t\t\tLastUpgradeCheck = 1600;",
        "\t\t\t\tTargetAttributes = {",
        *[
            f"\t\t\t\t\t{target_ids[name]} = {{CreatedOnToolsVersion = 16.0;}};"
            for name in SETTINGS
        ],
        "\t\t\t\t};",
        "\t\t\t};",
        f"\t\t\tbuildConfigurationList = {list_ids['project']};",
        '\t\t\tcompatibilityVersion = "Xcode 14.0";',
        "\t\t\tdevelopmentRegion = en;",
        "\t\t\thasScannedForEncodings = 0;",
        "\t\t\tknownRegions = (en, Base, );",
        f"\t\t\tmainGroup = {main_group};",
        f"\t\t\tproductRefGroup = {products_group};",
        '\t\t\tprojectDirPath = "";',
        '\t\t\tprojectRoot = "";',
        "\t\t\ttargets = (",
        *[f"\t\t\t\t{target_ids[name]}," for name in SETTINGS],
        "\t\t\t);",
    ])

    # Build configurations
    config_ids = {value: [] for value in list_ids.values()}
    entries = [
        ("project-debug", "Debug", PROJECT_DEBUG, list_ids["project"]),
        ("project-release", "Release", PROJECT_RELEASE, list_ids["project"]),
    ]
    for name in SETTINGS:
        entries.append((f"{name}-debug", "Debug", SETTINGS[name], list_ids[name]))
        entries.append((f"{name}-release", "Release", SETTINGS[name], list_ids[name]))

    for key, name, settings, owner in entries:
        config_id = oid("config", key)
        config_ids[owner].append(config_id)
        builder.add(config_id, "XCBuildConfiguration", [
            "\t\t\tisa = XCBuildConfiguration;",
            *settings_lines(settings),
            f"\t\t\tname = {name};",
        ])

    for owner, ids in config_ids.items():
        builder.add(owner, "XCConfigurationList", [
            "\t\t\tisa = XCConfigurationList;",
            "\t\t\tbuildConfigurations = (",
            *[f"\t\t\t\t{config_id}," for config_id in ids],
            "\t\t\t);",
            "\t\t\tdefaultConfigurationIsVisible = 0;",
            "\t\t\tdefaultConfigurationName = Release;",
        ])

    return builder.render(project_id)


def buildable(name: str, product: str) -> str:
    return (
        '<BuildableReference BuildableIdentifier="primary" '
        f'BlueprintIdentifier="{oid("target", name)}" BuildableName="{product}" '
        f'BlueprintName="{name}" ReferencedContainer="container:CourseMate.xcodeproj"/>'
    )


def build_scheme() -> str:
    app = buildable(APP, "CourseMate.app")
    tests = buildable(TESTS, "CourseMateTests.xctest")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            {app}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO">
            {tests}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         {app}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         {app}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES">
   </ArchiveAction>
</Scheme>
"""


def main() -> int:
    missing = [
        f"{folder}/{name}"
        for folder, name, _, _ in FILES
        if not (ROOT / folder / name).exists()
    ]
    if missing:
        print("cannot generate project — missing files:", file=sys.stderr)
        for path in missing:
            print(f"  {path}", file=sys.stderr)
        return 1

    constants = {
        "appBundle": APP_BUNDLE,
        "extensionBundle": EXT_BUNDLE,
        "widgetBundle": WIDGET_BUNDLE,
        "testsBundle": TESTS_BUNDLE,
        "appGroup": APP_GROUP,
        "deploymentTarget": DEPLOYMENT_TARGET,
    }

    for folder, name in (
        ("CourseMate", "CourseMate.entitlements"),
        ("CourseMateBroadcast", "CourseMateBroadcast.entitlements"),
    ):
        text = (ROOT / folder / name).read_text()
        if APP_GROUP not in text:
            print(f"warning: {folder}/{name} does not list {APP_GROUP}", file=sys.stderr)

    settings_file = (ROOT / "Shared" / "Settings.swift").read_text()
    if APP_GROUP not in settings_file:
        print(f"warning: Shared/Settings.swift does not define {APP_GROUP}", file=sys.stderr)

    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(build_project())
    (scheme_dir / "CourseMate.xcscheme").write_text(build_scheme())

    print(f"wrote {PROJECT.relative_to(ROOT)}/project.pbxproj")
    print(f"wrote {scheme_dir.relative_to(ROOT)}/CourseMate.xcscheme")
    print("constants:", json.dumps(constants))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
