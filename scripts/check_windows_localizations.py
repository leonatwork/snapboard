#!/usr/bin/env python3
"""Check Windows .resx catalogs on Linux/Windows using Python 3 (stdlib only).

Run from any directory: python3 -B scripts/check_windows_localizations.py
Regression tests: python3 -B -m unittest discover -s scripts/tests -v
Exit codes: 0 = valid; 1 = catalog/key/placeholder error; 2 = CLI usage error.
The Windows catalogs are maintained independently; this is not a generator.
"""
import argparse
from collections import Counter
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {"Strings.resx"} | {f"Strings.{lang}.resx" for lang in
    ("de", "fr", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "ko")}
PLACEHOLDER = re.compile(r"\{([0-9]+)(?:,\s*(-?[0-9]+))?(?::([^{}]*))?\}")


def placeholders(value):
    """Compare argument index, alignment, format and multiplicity, not order."""
    result = Counter()
    index = 0
    while index < len(value):
        if value[index:index + 2] in ("{{", "}}"):
            index += 2
        elif value[index] == "{":
            match = PLACEHOLDER.match(value, index)
            if not match:
                raise ValueError("invalid placeholder")
            result[(int(match[1]), int(match[2]) if match[2] else None, match[3])] += 1
            index = match.end()
        elif value[index] == "}":
            raise ValueError("invalid placeholder")
        else:
            index += 1
    return result


def check(resources, source):
    errors = []
    actual = {p.name for p in resources.glob("*.resx")}
    for name in sorted(EXPECTED - actual):
        errors.append(f"missing catalog: {name}")
    for name in sorted(actual - EXPECTED):
        errors.append(f"unexpected catalog: {name}")
    catalogs = {}
    signatures = {}
    for name in sorted(actual):
        try:
            root = ET.parse(resources / name).getroot()
        except (ET.ParseError, OSError) as error:
            errors.append(f"{name}: invalid XML: {error}")
            continue
        if root.tag != "root":
            errors.append(f"{name}: invalid XML root")
        values = {}
        formats = {}
        for entry in root.findall("data"):
            key = entry.get("name")
            if not key:
                errors.append(f"{name}: missing key name")
                continue
            if key in values:
                errors.append(f"{name}: duplicate key: {key}")
            value = entry.findtext("value", "")
            values[key] = value
            if not value.strip():
                errors.append(f"{name}: empty value: {key}")
            if entry.get("type") or entry.get("mimetype"):
                errors.append(f"{name}: non-string resource: {key}")
            if "⌘" in value or "⇧" in value:
                errors.append(f"{name}: macOS shortcut: {key}")
            try:
                formats[key] = placeholders(value)
            except ValueError as error:
                errors.append(f"{name}: {error}: {key}")
        if not values:
            errors.append(f"{name}: empty catalog")
        catalogs[name] = values
        signatures[name] = formats

    neutral = catalogs.get("Strings.resx", {})
    base_keys = set(neutral)
    for name, values in catalogs.items():
        missing, extra = base_keys - values.keys(), values.keys() - base_keys
        if missing:
            errors.append(f"{name}: missing keys: {', '.join(sorted(missing))}")
        if extra:
            errors.append(f"{name}: extra keys: {', '.join(sorted(extra))}")
        for key in base_keys & values.keys():
            if signatures[name].get(key) != signatures.get("Strings.resx", {}).get(key):
                errors.append(f"{name}: placeholders differ: {key}")

    used = set()
    for path in source.rglob("*.cs"):
        used.update(re.findall(r'L10n\.(?:Get|Format)\("([^"]+)"', path.read_text(encoding="utf-8")))
    if used - base_keys:
        errors.append(f"undefined source keys: {', '.join(sorted(used - base_keys))}")
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        print(f"Windows localization check failed: {len(errors)} errors.")
        return 1
    print(f"Windows localizations OK: {len(catalogs)} languages, {len(base_keys)} keys.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resources", type=Path, default=ROOT / "windows/Snapboard.Windows/Resources")
    parser.add_argument("--source", type=Path, default=ROOT / "windows/Snapboard.Windows")
    args = parser.parse_args()
    return check(args.resources, args.source)


if __name__ == "__main__":
    raise SystemExit(main())
