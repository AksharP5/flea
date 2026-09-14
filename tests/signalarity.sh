#!/bin/bash
# Every signal ui/Backend.qml declares against every emit of it in the same file. A QML signal drops
# an argument past its own parameter list without a word, which is how the transfer card spent a
# release reading an undefined byte total off a wire that carried the number: see V7 in the ledger.
set -uo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
file="$repo/ui/Backend.qml"
checks=0
failed=0

fail() {
    printf 'FAIL: %s\n' "$1"
    failed=$((failed + 1))
}

# Sample input: "    signal transferProgress(int id, int index, string name, real bytes, real total, real scanned)"
# and its emit: "            root.transferProgress(message.id, ..., message.scanned || 0)"
count_arguments() {
    local text="$1"
    [[ -z "${text//[[:space:]]/}" ]] && { printf '0\n'; return; }
    # An argument holding a comma of its own would need a parser, so the one shape this refuses to
    # guess at is a nested call, and it says so rather than reporting a number nobody can trust.
    case "$text" in *'('*) printf 'nested\n'; return ;; esac
    printf '%s\n' "$(( $(tr -cd ',' <<< "$text" | wc -c) + 1 ))"
}

declarations=0
while IFS= read -r line; do
    declarations=$((declarations + 1))
    name=${line#*signal }
    name=${name%%(*}
    params=${line#*"$name"(}
    params=${params%)}
    declared=$(count_arguments "$params")
    # An emit wrapped onto a second line is joined first, so a continuation is not read as the whole.
    while IFS= read -r emit; do
        args=${emit#*"$name"(}
        args=${args%)*}
        passed=$(count_arguments "$args")
        checks=$((checks + 1))
        if [[ "$passed" == nested ]]; then
            fail "$name is emitted with an argument this check cannot count: $emit"
        elif [[ "$passed" != "$declared" ]]; then
            fail "$name declares $declared parameter(s) and is emitted with $passed: $emit"
        fi
    done < <(tr '\n' '\r' < "$file" | sed 's/,\r */, /g' | tr '\r' '\n' | grep -E "root\.$name\(")
done < <(grep -E '^[[:space:]]*signal [A-Za-z_][A-Za-z0-9_]*\(' "$file")

# A suite that checked nothing is the shape this whole class hides in, so the floors are its own
# first check: ui/Backend.qml is the file the wire is decoded in and it has never held fewer than
# twenty signals or thirty emits of them.
[[ "$declarations" -ge 20 ]] || fail "only $declarations signal declaration(s) found in $file, so this suite read the wrong file or the wrong shape"
[[ "$checks" -ge 30 ]] || fail "only $checks emit(s) found for $declarations signal(s), so the emits are not being matched"
printf 'signalarity: %s signal(s), %s emit(s) checked, %s failed\n' "$declarations" "$checks" "$failed"
[[ "$failed" == 0 ]]
