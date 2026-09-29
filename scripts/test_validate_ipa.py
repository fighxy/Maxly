import importlib.util
import pathlib
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    "validate_ipa", pathlib.Path(__file__).with_name("validate-ipa.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class IpaValidationTests(unittest.TestCase):
    def check_archive(self, *, missing=(), platform="iPhoneOS", executable_mode=0o100755,
                      alternates=("AppIconLight",), required=()):
        info = {
            "CFBundleIdentifier": "app.orbitl.ios",
            "CFBundleExecutable": "Orbitl",
            "CFBundleSupportedPlatforms": [platform],
            "CFBundleIcons": {
                "CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon60x60"]},
                "CFBundleAlternateIcons": {
                    name: {"CFBundleIconFiles": [name + "60x60"]} for name in alternates
                },
            },
        }
        files = {
            "Info.plist": plistlib.dumps(info), "Orbitl": b"test executable",
            "Assets.car": b"test catalog", "AppIcon60x60@2x.png": b"test icon",
        }
        files.update({name + "60x60@2x.png": b"test icon" for name in alternates})
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "Orbitl.ipa"
            with zipfile.ZipFile(path, "w") as archive:
                for name, data in files.items():
                    if name not in missing:
                        entry = zipfile.ZipInfo("Payload/Orbitl.app/" + name)
                        entry.create_system = 3
                        entry.external_attr = (executable_mode if name == "Orbitl" else 0o100644) << 16
                        archive.writestr(entry, data)
            return validator.validate(path, required)

    def test_complete_device_bundle(self):
        self.assertEqual(self.check_archive(), "app.orbitl.ios")

    def test_missing_catalog(self):
        with self.assertRaisesRegex(ValueError, "Assets.car"):
            self.check_archive(missing=("Assets.car",))

    def test_missing_icon(self):
        with self.assertRaisesRegex(ValueError, "icon PNG"):
            self.check_archive(missing=("AppIcon60x60@2x.png",))

    def test_alternate_icons(self):
        self.assertEqual(self.check_archive(required=("AppIconLight",)), "app.orbitl.ios")
        with self.assertRaisesRegex(ValueError, "no alternate app icon AppIconBlue"):
            self.check_archive(required=("AppIconLight", "AppIconBlue"))
        with self.assertRaisesRegex(ValueError, "AppIconLight PNG"):
            self.check_archive(missing=("AppIconLight60x60@2x.png",), required=("AppIconLight",))

    def test_simulator_bundle(self):
        with self.assertRaisesRegex(ValueError, "Simulator"):
            self.check_archive(platform="iPhoneSimulator")

    def test_executable_permission(self):
        with self.assertRaisesRegex(ValueError, "permission"):
            self.check_archive(executable_mode=0o100644)

    def test_outer_actions_zip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "artifact.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("Orbitl.ipa", b"nested archive")
            with self.assertRaisesRegex(ValueError, "outer Actions ZIP"):
                validator.validate(path)


if __name__ == "__main__":
    unittest.main()
