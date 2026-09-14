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

while IFS= read -r line; do
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
done < <(grep -E '^\s*signal [a-zA-Z]+\(' "$file")

printf 'signalarity: %s emit(s) checked, %s failed\n' "$checks" "$failed"
[[ "$failed" == 0 ]]
