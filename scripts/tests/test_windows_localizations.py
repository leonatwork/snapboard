"""Linux regression tests: python3 -B -m unittest discover -s scripts/tests -v."""
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "scripts/check_windows_localizations.py"
NAMES = ["Strings.resx"] + [f"Strings.{lang}.resx" for lang in
    ("de", "fr", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "ko")]


class WindowsLocalizationsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        for name in NAMES:
            self.write(name, {"message": "Value {0}, {1:N2}, {0}; {{literal}}"})

    def write(self, name, values):
        root = ET.Element("root")
        for key, value in values.items():
            ET.SubElement(ET.SubElement(root, "data", name=key), "value").text = value
        ET.ElementTree(root).write(self.directory / name, encoding="utf-8")

    def run_checker(self, *args):
        result = subprocess.run([sys.executable, "-B", str(CHECKER), *map(str, args)],
                                capture_output=True, text=True)
        self.assertNotIn("can't open file", result.stderr, "Checker is not implemented")
        return result

    def fixture(self):
        return self.run_checker("--resources", self.directory, "--source", self.directory)

    def assert_rejected(self, diagnostic):
        result = self.fixture()
        self.assertNotEqual(0, result.returncode)
        self.assertIn(diagnostic, result.stdout + result.stderr)

    def test_repository_has_ten_resource_catalogs(self):
        resources = ROOT / "windows/Snapboard.Windows/Resources"
        self.assertEqual(set(NAMES), {p.name for p in resources.glob("*.resx")})

    def test_repository_passes_checker(self):
        result = self.run_checker()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_accepts_reordered_placeholders_and_escaped_braces(self):
        self.write("Strings.ja.resx", {"message": "{{literal}} {1:N2} {0} {0}"})
        result = self.fixture()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_missing_language(self):
        (self.directory / "Strings.ko.resx").unlink()
        self.assert_rejected("missing catalog")

    def test_extra_language(self):
        self.write("Strings.pl.resx", {"message": "Value"})
        self.assert_rejected("unexpected catalog")

    def test_missing_key(self):
        self.write("Strings.de.resx", {"other": "Value"})
        self.assert_rejected("missing keys")

    def test_extra_key(self):
        self.write("Strings.fr.resx", {"message": "{0} {1:N2} {0}", "other": "Value"})
        self.assert_rejected("extra keys")

    def test_duplicate_key(self):
        tree = ET.parse(self.directory / "Strings.es.resx")
        ET.SubElement(ET.SubElement(tree.getroot(), "data", name="message"), "value").text = "Duplicate"
        tree.write(self.directory / "Strings.es.resx")
        self.assert_rejected("duplicate key")

    def test_placeholder_index_count_and_format(self):
        for value in ("{0} {2:N2} {0}", "{0} {1:N2}", "{0} {1} {0}"):
            with self.subTest(value=value):
                self.write("Strings.it.resx", {"message": value})
                self.assert_rejected("placeholders differ")

    def test_invalid_format_in_neutral_catalog(self):
        self.write("Strings.resx", {"message": "Unclosed {0"})
        self.assert_rejected("invalid placeholder")

    def test_malformed_xml(self):
        (self.directory / "Strings.nl.resx").write_text("<root>", encoding="utf-8")
        self.assert_rejected("invalid XML")

    def test_empty_value(self):
        self.write("Strings.pt-BR.resx", {"message": ""})
        self.assert_rejected("empty value")

    def test_undefined_source_key(self):
        (self.directory / "Example.cs").write_text('L10n.Get("unknown");', encoding="utf-8")
        self.assert_rejected("undefined source keys")

    def test_no_mac_shortcuts(self):
        self.write("Strings.zh-Hans.resx", {"message": "⌘ {0} {1:N2} {0}"})
        self.assert_rejected("macOS shortcut")


if __name__ == "__main__":
    unittest.main()
