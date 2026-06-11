#!/usr/bin/env bash
set -euo pipefail

failures=0
swift_files=()

while IFS= read -r file; do
    swift_files+=("$file")
done < <(find Sources Entry Tests Benchmarks scripts -name '*.swift' -print)
swift_files+=("Package.swift")

fail() {
    printf 'policy: %s\n' "$1" >&2
    failures=$((failures + 1))
}

check_no_output() {
    local message=$1
    shift
    local output
    if output=$("$@" 2>/dev/null) && [ -n "$output" ]; then
        printf '%s\n' "$output" >&2
        fail "$message"
    fi
}

if grep -n -E '\.package[[:space:]]*\(' Package.swift >/tmp/parket-policy-deps.$$ 2>/dev/null; then
    cat /tmp/parket-policy-deps.$$ >&2
    fail "Package.swift must not declare external package dependencies"
fi
rm -f /tmp/parket-policy-deps.$$

check_no_output "Swift files must not use private window APIs, CGWindowList, or AXTabs" \
    grep -R -n -E 'CGWindowList|(^|[^A-Za-z0-9_])CGS[A-Z_]|(^|[^A-Za-z0-9_])SLS[A-Z_]|_AX|AXTabs' \
    "${swift_files[@]}"

if ! awk '/^install:/ { in_install = 1 } in_install && /^[[:alnum:]_.-]+:/ && $0 !~ /^install:/ { in_install = 0 } in_install { print }' Makefile \
    | grep -F '[ ! -d "$(INSTALL_DIR)" ]' >/dev/null; then
    fail "make install must preserve an existing /Applications/parket.app bundle"
fi

if awk '/^install:/ { in_install = 1 } in_install && /^[[:alnum:]_.-]+:/ && $0 !~ /^install:/ { in_install = 0 } in_install { print }' Makefile \
    | grep -n -E 'rm[[:space:]]+-rf[[:space:]].*(INSTALL_DIR|/Applications/.*/?parket\.app)' >/tmp/parket-policy-install.$$ 2>/dev/null; then
    cat /tmp/parket-policy-install.$$ >&2
    fail "make install must not remove /Applications/parket.app"
fi
rm -f /tmp/parket-policy-install.$$

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)
if [ "$bundle_id" != "com.parket.app" ]; then
    fail "Info.plist CFBundleIdentifier must be com.parket.app"
fi

lsui=$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' Info.plist)
if [ "$lsui" != "true" ]; then
    fail "Info.plist LSUIElement must be true"
fi

text_paths=()
for path in README.md config.example.toml AGENTS.md CLAUDE.md CONTEXT.md scripts docs .github .agents; do
    if [ -e "$path" ]; then
        text_paths+=("$path")
    fi
done

if [ "${#text_paths[@]}" -gt 0 ]; then
    check_no_output "text artifacts must use ASCII punctuation only" \
        perl -Mutf8 -ne 'print "$ARGV:$.:$_" if /[\x{2013}\x{2014}\x{2026}\x{2190}\x{2192}\x{00AB}\x{00BB}\x{2018}\x{2019}\x{201C}\x{201D}]/' \
        "${text_paths[@]}"
fi

check_no_output "Swift code must not contain ordinary comments" \
    sh -c "grep -n -E '//|/\\*|\\*/' \"\$@\" | grep -v '^Package.swift:1:// swift-tools-version:'" sh \
    "${swift_files[@]}"

if [ "$failures" -gt 0 ]; then
    exit 1
fi
