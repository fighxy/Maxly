#!/usr/bin/env python3
"""Check the final device IPA before uploading it (Python standard library only)."""
import argparse
import plistlib
import stat
import sys
import zipfile


def validate(path, alternate_icons=()):
    with zipfile.ZipFile(path) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"CRC check failed: {bad}")
        names = set(archive.namelist())
        plists = [name for name in names
                  if name.startswith("Payload/") and name.endswith(".app/Info.plist")
                  and name.count("/") == 2]
        if len(plists) != 1:
            raise ValueError("Expected one Payload/*.app/Info.plist; use the IPA, not the outer Actions ZIP")
        info = plistlib.loads(archive.read(plists[0]))
        root = plists[0].removesuffix("Info.plist")
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("Expected an iPhoneOS build, not an iOS Simulator build")
        executable = info.get("CFBundleExecutable", "")
        if not executable or "/" in executable or root + executable not in names:
            raise ValueError("Missing app executable")
        mode = archive.getinfo(root + executable).external_attr >> 16
        if not mode & stat.S_IXUSR:
            raise ValueError("App executable lost its execute permission")
        if root + "Assets.car" not in names:
            raise ValueError("Missing Assets.car: check the app target's Resources build phase")
        icon = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
        files = icon.get("CFBundleIconFiles", [])
        if not files:
            raise ValueError("Compiled Info.plist has no primary app icon")
        pngs = [name.removeprefix(root) for name in names
                if name.startswith(root) and name.endswith(".png")]
        if not any(png.startswith(icon_file) for icon_file in files for png in pngs):
            raise ValueError("Primary app icon PNG is missing from the bundle")
        # Alternate icons for setAlternateIconName: listed in the compiled Info.plist, with a PNG.
        alternates = info.get("CFBundleIcons", {}).get("CFBundleAlternateIcons", {})
        for name in alternate_icons:
            alternate = alternates.get(name, {}).get("CFBundleIconFiles", [])
            if not alternate:
                raise ValueError(f"Compiled Info.plist has no alternate app icon {name}")
            if not any(png.startswith(icon_file) for icon_file in alternate for png in pngs):
                raise ValueError(f"Alternate app icon {name} PNG is missing from the bundle")
        return info["CFBundleIdentifier"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--alternate-icon", action="append", default=[],
                        help="alternate app icon name that must be in the bundle (repeatable)")
    args = parser.parse_args()
    try:
        bundle = validate(args.ipa, args.alternate_icon)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"IPA validation failed: {error}", file=sys.stderr)
        sys.exit(1)
    print(f"IPA validated: {bundle} (CRC, device platform, executable, assets and icon)")
