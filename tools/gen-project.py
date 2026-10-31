#!/usr/bin/env python3
"""Generate CourseMate.xcodeproj (project + shared scheme).

Xcode's project file is an OpenStep plist keyed by 24-hex object IDs, and this
project has two targets sharing source files — hand-editing that graph is a
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
APP_BUNDLE = "us.innotel.coursemate"
EXT_BUNDLE = APP_BUNDLE + ".broadcast"
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
    ("CourseMate", "Assets.xcassets", "folder.assetcatalog", (APP,)),
    ("CourseMate", "Info.plist", "text.plist.xml", ()),
    ("CourseMate", "CourseMate.entitlements", "text.plist.entitlements", ()),
    ("CourseMateBroadcast", "SampleHandler.swift", "sourcecode.swift", (EXT,)),
    ("CourseMateBroadcast", "FrameSampler.swift", "sourcecode.swift", (EXT,)),
    ("CourseMateBroadcast", "AudioChunker.swift", "sourcecode.swift", (EXT,)),
    ("CourseMateBroadcast", "Info.plist", "text.plist.xml", ()),
    ("CourseMateBroadcast", "CourseMateBroadcast.entitlements", "text.plist.entitlements", ()),
    ("Shared", "Settings.swift", "sourcecode.swift", (APP, EXT)),
    ("Shared", "CourseMateAPI.swift", "sourcecode.swift", (APP, EXT)),
    ("Shared", "ControlChannel.swift", "sourcecode.swift", (APP, EXT)),
]

PRODUCTS = [
    (APP, "CourseMate.app", "wrapper.application"),
    (EXT, "CourseMateBroadcast.appex", "wrapper.app-extension"),
]

FOLDERS = ["CourseMate", "CourseMateBroadcast", "Shared"]

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


def phase(obj_id: str, name: str, isa: str, members: list[str], extra: list[str] | None = None) -> list[str]:
    lines = [f"\t\t\tisa = {isa};", "\t\t\tbuildActionMask = 2147483647;", "\t\t\tfiles = ("]
    lines += [f"\t\t\t\t{member}," for member in members]
    lines += ["\t\t\t);"]
    if name:
        lines.append(f"\t\t\tname = {name};")
    lines += extra or []
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
    file_ids: dict[tuple[str, str], str] = {}
    product_ids: dict[str, str] = {}
    target_ids = {APP: oid("target", APP), EXT: oid("target", EXT)}
    list_ids = {
        "project": oid("configlist", "project"),
        APP: oid("configlist", APP),
        EXT: oid("configlist", EXT),
    }

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

    # Build files, grouped per target phase
    sources: dict[str, list[str]] = {APP: [], EXT: []}
    resources: dict[str, list[str]] = {APP: [], EXT: []}
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

    embed_build = oid("buildfile", "embed-appex")
    builder.add(embed_build, "PBXBuildFile", [
        "\t\t\tisa = PBXBuildFile;",
        f"\t\t\tfileRef = {product_ids[EXT]};",
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
    sources_phase = {target: oid("phase", f"sources-{target}") for target in (APP, EXT)}
    frameworks_phase = {target: oid("phase", f"frameworks-{target}") for target in (APP, EXT)}
    resources_phase = {target: oid("phase", f"resources-{target}") for target in (APP, EXT)}
    embed_phase = oid("phase", "embed-extensions")

    for target in (APP, EXT):
        builder.add(sources_phase[target], "PBXSourcesBuildPhase",
                    phase(sources_phase[target], "", "PBXSourcesBuildPhase", sources[target]))
        builder.add(frameworks_phase[target], "PBXFrameworksBuildPhase",
                    phase(frameworks_phase[target], "", "PBXFrameworksBuildPhase", []))
        builder.add(resources_phase[target], "PBXResourcesBuildPhase",
                    phase(resources_phase[target], "", "PBXResourcesBuildPhase", resources[target]))

    builder.add(embed_phase, "PBXCopyFilesBuildPhase", [
        "\t\t\tisa = PBXCopyFilesBuildPhase;",
        "\t\t\tbuildActionMask = 2147483647;",
        '\t\t\tdstPath = "";',
        "\t\t\tdstSubfolderSpec = 13;",
        "\t\t\tfiles = (",
        f"\t\t\t\t{embed_build},",
        "\t\t\t);",
        '\t\t\tname = "Embed App Extensions";',
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
    ])

    # Target dependency: the app embeds the extension
    proxy_id = oid("proxy", "app->extension")
    dependency_id = oid("dependency", "app->extension")
    builder.add(proxy_id, "PBXContainerItemProxy", [
        "\t\t\tisa = PBXContainerItemProxy;",
        f"\t\t\tcontainerPortal = {project_id};",
        "\t\t\tproxyType = 1;",
        f"\t\t\tremoteGlobalIDString = {target_ids[EXT]};",
        f'\t\t\tremoteInfo = "{EXT}";',
    ])
    builder.add(dependency_id, "PBXTargetDependency", [
        "\t\t\tisa = PBXTargetDependency;",
        f"\t\t\ttarget = {target_ids[EXT]};",
        f"\t\t\ttargetProxy = {proxy_id};",
    ])

    # Native targets
    builder.add(target_ids[APP], "PBXNativeTarget", [
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {list_ids[APP]};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{sources_phase[APP]},",
        f"\t\t\t\t{frameworks_phase[APP]},",
        f"\t\t\t\t{resources_phase[APP]},",
        f"\t\t\t\t{embed_phase},",
        "\t\t\t);",
        "\t\t\tbuildRules = (",
        "\t\t\t);",
        "\t\t\tdependencies = (",
        "\t\t\t);",
        f"\t\t\tname = {APP};",
        f"\t\t\tproductName = {APP};",
        f"\t\t\tproductReference = {product_ids[APP]};",
        '\t\t\tproductType = "com.apple.product-type.application";',
    ])

    builder.add(target_ids[EXT], "PBXNativeTarget", [
        "\t\t\tisa = PBXNativeTarget;",
        f"\t\t\tbuildConfigurationList = {list_ids[EXT]};",
        "\t\t\tbuildPhases = (",
        f"\t\t\t\t{sources_phase[EXT]},",
        f"\t\t\t\t{frameworks_phase[EXT]},",
        f"\t\t\t\t{resources_phase[EXT]},",
        "\t\t\t);",
        "\t\t\tbuildRules = (",
        "\t\t\t);",
        "\t\t\tdependencies = (",
        "\t\t\t);",
        f"\t\t\tname = {EXT};",
        f"\t\t\tproductName = {EXT};",
        f"\t\t\tproductReference = {product_ids[EXT]};",
        '\t\t\tproductType = "com.apple.product-type.app-extension";',
    ])

    builder.add(project_id, "PBXProject", [
        "\t\t\tisa = PBXProject;",
        "\t\t\tattributes = {",
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;",
        "\t\t\t\tLastSwiftUpdateCheck = 1600;",
        "\t\t\t\tLastUpgradeCheck = 1600;",
        "\t\t\t\tTargetAttributes = {",
        f"\t\t\t\t\t{target_ids[APP]} = {{CreatedOnToolsVersion = 16.0;}};",
        f"\t\t\t\t\t{target_ids[EXT]} = {{CreatedOnToolsVersion = 16.0;}};",
        "\t\t\t\t};",
        "\t\t\t};",
        f"\t\t\tbuildConfigurationList = {list_ids['project']};",
        '\t\t\tcompatibilityVersion = "Xcode 14.0";',
        "\t\t\tdevelopmentRegion = en;",
        "\t\t\thasScannedForEncodings = 0;",
        "\t\t\t			knownRegions = (en, Base, );",
        f"\t\t\tmainGroup = {main_group};",
        f"\t\t\tproductRefGroup = {products_group};",
        '\t\t\tprojectDirPath = "";',
        '\t\t\tprojectRoot = "";',
        "\t\t\ttargets = (",
        f"\t\t\t\t{target_ids[APP]},",
        f"\t\t\t\t{target_ids[EXT]},",
        "\t\t\t);",
    ])

    # Build configurations
    configs = [
        ("project-debug", "Debug", PROJECT_DEBUG, list_ids["project"]),
        ("project-release", "Release", PROJECT_RELEASE, list_ids["project"]),
        (f"{APP}-debug", "Debug", APP_SETTINGS, list_ids[APP]),
        (f"{APP}-release", "Release", APP_SETTINGS, list_ids[APP]),
        (f"{EXT}-debug", "Debug", EXT_SETTINGS, list_ids[EXT]),
        (f"{EXT}-release", "Release", EXT_SETTINGS, list_ids[EXT]),
    ]
    config_ids: dict[str, list[str]] = {list_ids["project"]: [], list_ids[APP]: [], list_ids[EXT]: []}
    for key, name, settings, owner in configs:
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
            '\t\t\tdefaultConfigurationIsVisible = 0;',
            "\t\t\tdefaultConfigurationName = Release;",
        ])

    return builder.render(project_id)


def build_scheme() -> str:
    app_target = oid("target", APP)
    reference = (
        '<BuildableReference BuildableIdentifier="primary" '
        f'BlueprintIdentifier="{app_target}" BuildableName="CourseMate.app" '
        'BlueprintName="CourseMate" ReferencedContainer="container:CourseMate.xcodeproj"/>'
    )
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            {reference}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         {reference}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         {reference}
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
        "appGroup": APP_GROUP,
        "deploymentTarget": DEPLOYMENT_TARGET,
    }
    entitlement = APP_GROUP
    for folder, name in (
        ("CourseMate", "CourseMate.entitlements"),
        ("CourseMateBroadcast", "CourseMateBroadcast.entitlements"),
    ):
        text = (ROOT / folder / name).read_text()
        if entitlement not in text:
            print(f"warning: {folder}/{name} does not list {entitlement}", file=sys.stderr)

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
