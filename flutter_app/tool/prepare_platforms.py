#!/usr/bin/env python3
"""Carry the registered iOS Firebase client config into a generated Flutter scaffold."""
from pathlib import Path
import plistlib
import re
import shutil
import sys

BUNDLE_ID = "com.omnistudio.omnistudioFlutterPrototype"
FIREBASE_PLIST = Path("ios/Runner/GoogleService-Info.plist")
BUILD_FILE_ID = "F1A5E0000000000000000001"
FILE_REF_ID = "F1A5E0000000000000000002"


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 tool/prepare_platforms.py <generated-scaffold-dir>")
    scaffold = Path(sys.argv[1])
    runner = scaffold / "ios/Runner"
    project_file = scaffold / "ios/Runner.xcodeproj/project.pbxproj"
    plist_source = FIREBASE_PLIST
    info_plist = runner / "Info.plist"
    if not plist_source.is_file() or not project_file.is_file() or not info_plist.is_file():
        raise SystemExit("Generated iOS scaffold or registered Firebase plist is missing")

    with plist_source.open("rb") as stream:
        firebase_config = plistlib.load(stream)
    if firebase_config.get("BUNDLE_ID") != BUNDLE_ID:
        raise SystemExit("Registered iOS Firebase config does not match the app bundle identifier")

    shutil.copy2(plist_source, runner / "GoogleService-Info.plist")
    project = project_file.read_text(encoding="utf-8")
    if "GoogleService-Info.plist" not in project:
        project = project.replace(
            "/* Begin PBXBuildFile section */",
            "/* Begin PBXBuildFile section */\n\t\t"
            + BUILD_FILE_ID
            + " /* GoogleService-Info.plist in Resources */ = {isa = PBXBuildFile; fileRef = "
            + FILE_REF_ID
            + " /* GoogleService-Info.plist */; };",
            1,
        )
        project = project.replace(
            "/* Begin PBXFileReference section */",
            "/* Begin PBXFileReference section */\n\t\t"
            + FILE_REF_ID
            + ' /* GoogleService-Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "GoogleService-Info.plist"; sourceTree = "<group>"; };',
            1,
        )
        runner_group = re.compile(r"(/\* Runner \*/ = \{\s*isa = PBXGroup;\s*children = \()(.*?)(\);)", re.S)
        project, group_count = runner_group.subn(
            lambda match: match.group(1)
            + match.group(2)
            + "\n\t\t\t\t"
            + FILE_REF_ID
            + " /* GoogleService-Info.plist */,"
            + match.group(3),
            project,
            count=1,
        )
        if group_count != 1:
            raise SystemExit("Could not add Firebase plist to the generated Runner Xcode group")
        resources_phase = re.compile(
            r"(/\* Resources \*/ = \{\s*isa = PBXResourcesBuildPhase;\s*buildActionMask = [^;]+;\s*files = \()(.*?)(\);)",
            re.S,
        )
        project, phase_count = resources_phase.subn(
            lambda match: match.group(1)
            + match.group(2)
            + "\n\t\t\t\t"
            + BUILD_FILE_ID
            + " /* GoogleService-Info.plist in Resources */,"
            + match.group(3),
            project,
            count=1,
        )
        if phase_count != 1:
            raise SystemExit("Could not add Firebase plist to Runner's resources build phase")
    else:
        if FILE_REF_ID not in project or BUILD_FILE_ID not in project:
            raise SystemExit("Firebase plist exists in generated Xcode project but resource wiring is incomplete")

    def set_bundle_id(match: re.Match[str]) -> str:
        existing = match.group(0)
        suffix = ".RunnerTests" if "RunnerTests" in existing else ""
        return f"{match.group(1)}{BUNDLE_ID}{suffix};"

    project, matches = re.subn(
        r"(?m)(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)[^;]+;",
        set_bundle_id,
        project,
    )
    if matches < 1:
        raise SystemExit("Could not set the generated iOS bundle identifier")
    project_file.write_text(project, encoding="utf-8")

    with info_plist.open("rb") as stream:
        app_info = plistlib.load(stream)
    # The standard Flutter template uses $(PRODUCT_BUNDLE_IDENTIFIER); keep it dynamic.
    app_info["CFBundleIdentifier"] = "$(PRODUCT_BUNDLE_IDENTIFIER)"
    app_info["NSPhotoLibraryUsageDescription"] = (
        "Permite seleccionar fotos y videos para publicarlos de forma privada en tu cuenta de Social."
    )
    with info_plist.open("wb") as stream:
        plistlib.dump(app_info, stream)

    print("Prepared iOS scaffold with the registered Firebase client plist and bundle ID.")


if __name__ == "__main__":
    main()
