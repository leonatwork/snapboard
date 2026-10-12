#!/bin/bash
# Prüft die Lokalisierungen der macOS-App:
#  - jede Localizable.strings besteht `plutil -lint`
#  - jeder Schlüssel aus en.lproj existiert in jeder Sprache (und umgekehrt)
#  - Platzhalter (%@, %d …) stimmen pro Schlüssel mit Englisch überein
#  - CFBundleLocalizations in Info.plist passt zu den vorhandenen .lproj-Ordnern
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$PROJECT_DIR/Resources"
BASE="en"
EXPECTED_LANGS=(en de fr es it pt-BR nl ja zh-Hans ko)

errors=0
fail() { echo "❌ $*"; errors=$((errors + 1)); }

keys_of() {
    sed -n 's/^"\([^"]*\)"[[:space:]]*=.*/\1/p' "$1" | sort
}

placeholders_of() {
    # $1 = Datei, $2 = Schlüssel → sortierte Liste der Formatplatzhalter
    grep -E "^\"$2\"[[:space:]]*=" "$1" | sed 's/^"[^"]*"[[:space:]]*=//' \
        | grep -oE '%(@|[0-9]*\$?[dDiuUxXoOfeEgGcCsSaAp@]|ld|lu|lld|llu)' | sort | tr '\n' ' ' || true
}

# 1. Erwartete Sprachen vorhanden?
for lang in "${EXPECTED_LANGS[@]}"; do
    [[ -f "$RES/$lang.lproj/Localizable.strings" ]] || fail "$lang.lproj/Localizable.strings fehlt"
done

# 2. plutil -lint
for f in "$RES"/*.lproj/*.strings; do
    plutil -lint -s "$f" >/dev/null || fail "plutil -lint fehlgeschlagen: ${f#$PROJECT_DIR/}"
done

# 3. Schlüssel & Platzhalter vergleichen
BASE_FILE="$RES/$BASE.lproj/Localizable.strings"
BASE_KEYS="$(keys_of "$BASE_FILE")"
key_count="$(echo "$BASE_KEYS" | grep -c . || true)"

for dir in "$RES"/*.lproj; do
    lang="$(basename "$dir" .lproj)"
    file="$dir/Localizable.strings"
    [[ -f "$file" ]] || continue

    dupes="$(keys_of "$file" | uniq -d)"
    [[ -z "$dupes" ]] || fail "$lang: doppelte Schlüssel: $(echo $dupes)"

    [[ "$lang" == "$BASE" ]] && continue
    missing="$(comm -23 <(echo "$BASE_KEYS") <(keys_of "$file" | uniq))"
    extra="$(comm -13 <(echo "$BASE_KEYS") <(keys_of "$file" | uniq))"
    [[ -z "$missing" ]] || fail "$lang: fehlende Schlüssel: $(echo $missing)"
    [[ -z "$extra" ]] || fail "$lang: zusätzliche Schlüssel: $(echo $extra)"

    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        a="$(placeholders_of "$BASE_FILE" "$key")"
        b="$(placeholders_of "$file" "$key")"
        [[ "$a" == "$b" ]] || fail "$lang: Platzhalter in \"$key\" weichen ab (en: '$a', $lang: '$b')"
    done <<< "$BASE_KEYS"
done

# 4. Alle im Code verwendeten Schlüssel existieren in en
used="$(grep -rhoE 'L10n\.(tr|format)\("[^"]+"' "$PROJECT_DIR/Sources" | sed -E 's/.*\("//; s/"$//' | sort -u)"
undefined="$(comm -23 <(echo "$used") <(echo "$BASE_KEYS"))"
[[ -z "$undefined" ]] || fail "Im Code verwendet, aber nicht in en.lproj: $(echo $undefined)"

# 5. Info.plist ↔ .lproj-Ordner
plist_langs="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleLocalizations' "$RES/Info.plist" \
    | sed -n 's/^[[:space:]]*\([A-Za-z-]*\)[[:space:]]*$/\1/p' | sort)"
dir_langs="$(for d in "$RES"/*.lproj; do basename "$d" .lproj; done | sort)"
[[ "$plist_langs" == "$dir_langs" ]] || fail "CFBundleLocalizations ($(echo $plist_langs)) passt nicht zu .lproj-Ordnern ($(echo $dir_langs))"

if [[ $errors -gt 0 ]]; then
    echo "Lokalisierungsprüfung fehlgeschlagen: $errors Fehler."
    exit 1
fi
echo "✅ Lokalisierungen OK: $(echo "$dir_langs" | wc -l | tr -d ' ') Sprachen, $key_count Schlüssel."
