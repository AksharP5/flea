#!/bin/bash
# Gates tools/flea-bench-manifest, the record that makes a bench number citable, and the two values
# the harness derives from its own entrant table to feed it. Nothing here launches an entrant: this
# suite exists because the field bench had no gate at all and its first manifest reported Flea as
# quickshell 0.3.1.
set -u
# The cd comes first: a trap installed above it fires against the caller's working directory when
# the cd fails, which is a relative-path rm -rf in somebody else's tree.
cd "$(dirname "$0")/.." || exit 1
repo=$PWD
tool="$repo/tools/flea-bench-manifest"

# The fixture is a mktemp -d of its own, which is what hard rule 9 allows outright. Nothing here
# reads or writes the real fixture root, and the only delete is checked absolute below.
scratch=$(mktemp -d) || exit 1
# GNU mktemp -d honours a relative TMPDIR verbatim, so the one delete this suite makes is checked
# absolute and two components deep here, before the trap that runs it is installed.
case $scratch in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$scratch', which is not an absolute path two components deep"; exit 1 ;;
esac
trap 'rm -rf "$scratch"' EXIT

fail=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label"; echo "  expected: $expected"; echo "  actual:   $actual"; fail=1
  else
    echo "ok   $label"
  fi
}
holds() {
  local label="$1" needle="$2" file="$3"
  if grep -q -- "$needle" "$file"; then echo "ok   $label"; else
    echo "FAIL $label: '$needle' is not in $file"; fail=1
  fi
}
lacks() {
  local label="$1" needle="$2" file="$3"
  if grep -q -- "$needle" "$file"; then
    echo "FAIL $label: '$needle' should not be in $file"; fail=1
  else echo "ok   $label"; fi
}

fixture="$scratch/fix"
mkdir -p "$fixture"
touch "$fixture/a.jpg" "$fixture/b.jpg" "$fixture/c.png" "$fixture/d.txt" "$fixture/README"
payload=$(ls -U "$fixture" | wc -l)

"$tool" >/dev/null 2>&1
check "no arguments is a usage error" 2 $?
"$tool" "$scratch/m1.md" "$scratch/nothing-here" >/dev/null 2>&1
check "a missing fixture is refused" 1 $?

# Named beside $scratch/run.csv below, because flea-bench-report finds a manifest by the CSV's own
# name. Every entrant that run holds is listed here too: the report refuses an id it has no kind for.
man="$scratch/run.manifest.md"
printf '%s\n' "flea|gui|qs" "dolphin|gui|dolphin" "definitely-not-a-file-manager|gui|definitely-not-a-file-manager" \
  "strata|gui|strata" "yazi|tui|yazi" "xplr|tui|xplr" \
  | EXPECT_FILES="$payload" "$tool" "$man" "$fixture" >/dev/null 2>&1
check "a normal run writes a manifest" 0 $?

holds "the payload is counted from the fixture" "fixture payload: $payload visible entries" "$man"
holds "the histogram counts the jpgs it holds" "2 jpg" "$man"
holds "and the one file with no extension at all" "1 no extension" "$man"
holds "an entrant that is not installed is named" "NOT INSTALLED" "$man"
holds "flea's row is its own source, not a package" "^flea .* source " "$man"
# The defect this check exists for: an untrimmed id missed its own case arm, so flea fell to the
# packaged arm and pacman -Qo on its launcher reported it as quickshell.
lacks "and flea never reports itself as its launcher" "flea.*quickshell" "$man"
holds "a package that is not installed reads absent" " absent" "$man"

# The same rows indented, which is how they arrive when they are grepped out of the harness rather
# than expanded from its array. This is the whole of the trim regression.
indented="$scratch/indented.md"
printf '%s\n' '  flea|gui|qs' '  dolphin|gui|dolphin' | "$tool" "$indented" "$fixture" >/dev/null 2>&1
holds "an indented row still reaches its own arm" "^flea .* source " "$indented"
lacks "and is not silently mis-attributed" "flea.*quickshell" "$indented"

# The denominator and the run conditions, both added because a number nobody can re-derive is a
# number nobody can check. The fixture holds one txt of its five files.
holds "the denominator excludes what nobody thumbnails" "thumbnailable denominator: 4" "$man"
holds "and names what it excluded" "1 .txt files" "$man"
holds "the load average is recorded, not assumed" "load average at start:" "$man"
holds "and the payload assertion is recorded as having passed" "payload assertion: PASSED" "$man"
# The line used to write PASSED from the presence of EXPECT_FILES alone, so a wrong count still read
# as a pass. It compares now, and this is the check that says so.
wrongman="$scratch/wrong.md"
printf '%s\n' "flea|gui|qs" | EXPECT_FILES=999 "$tool" "$wrongman" "$fixture" >/dev/null 2>&1
holds "a payload that does not match is recorded as a failure" "payload assertion: \*\*FAILED\*\*" "$wrongman"
lacks "and is not also recorded as a pass" "payload assertion: PASSED" "$wrongman"

# tools/flea-bench-keys. The shell key derivation is proved to match the backend's by
# tests/thumbs.sh, which asks the real binary for a thumbnail and finds it at the key this same
# printf-and-md5sum produces. What is proved here is that the map and the classifier agree with the
# fixture they are given.
keys="$repo/tools/flea-bench-keys"
map="$scratch/fix.map"
"$keys" map "$fixture" "$map" >/dev/null 2>&1
check "a map builds from a plain fixture" 0 $?
check "one line per fixture file" "$payload" "$(wc -l < "$map")"
check "and the extensions are counted off the names" "2" "$(cut -d' ' -f2 "$map" | grep -c '^jpg$')"
check "a name with no dot maps to none" "1" "$(cut -d' ' -f2 "$map" | grep -c '^none$')"

# The refusal that keeps a wrong key from looking like a zero result for every entrant at once.
mkdir -p "$scratch/needs-encoding"
touch "$scratch/needs-encoding/two words.jpg"
"$keys" map "$scratch/needs-encoding" "$scratch/enc.map" >/dev/null 2>&1
check "a name needing percent-encoding is refused" 1 $?

# An entrant that thumbnailed both jpgs and the png, and nothing else.
produced="$scratch/produced.keys"
grep -E ' (jpg|png)$' "$map" | cut -d' ' -f1 | LC_ALL=C sort -u > "$produced"
line=$("$keys" classify "$map" "$produced")
case $line in
  *"jpg=2"*) echo "ok   the classifier counts the jpgs" ;;
  *) echo "FAIL the classifier said '$line'"; fail=1 ;;
esac
case $line in
  *"txt=0"*) echo "ok   and a format nobody produced still gets a row" ;;
  *) echo "FAIL a zero format has no row in '$line'"; fail=1 ;;
esac
case $line in
  *"unknown=0"*) echo "ok   with nothing unexplained" ;;
  *) echo "FAIL unknown is not zero in '$line'"; fail=1 ;;
esac

# A key the fixture cannot explain means the cache was not clean, so the row is not comparable.
printf '%s\n' "ffffffffffffffffffffffffffffffff" >> "$produced"
LC_ALL=C sort -u -o "$produced" "$produced"
case $("$keys" classify "$map" "$produced") in
  *"unknown=1"*) echo "ok   a key the fixture does not explain is named" ;;
  *) echo "FAIL an unexplained key was folded into the total"; fail=1 ;;
esac

: > "$scratch/empty.keys"
check "an entrant that produced nothing is a result, not an error" 0 \
  "$("$keys" classify "$map" "$scratch/empty.keys" >/dev/null 2>&1; echo $?)"

# The close pass. Its CSV header and every row are GENERATED from the bench's own header line, so
# the fixture cannot fall a column behind the artefact it tests. It did exactly that: preview_ms was
# appended as column 16, this fixture stayed at 15, its rows still ended in ",yes", and the suite
# stayed green over a refusal that had stopped firing in production.
bench_header=$(sed -n 's/^echo "\(id,run,[^"]*\)".*/\1/p' "$repo/tools/flea-field-bench")
[ -n "$bench_header" ] || { echo "FAIL: could not read the bench's own CSV header"; fail=1; }
declare -A CELL
emit_row() {
  local out="" name
  while IFS= read -r name; do
    out="${out:+$out,}${CELL[$name]:--}"
  done < <(printf '%s\n' "$bench_header" | tr ',' '\n')
  printf '%s\n' "$out"
  CELL=()
}

csv="$scratch/run.csv"
keys_dir="$scratch/run.keys"
mkdir -p "$keys_dir"
cp "$map" "$keys_dir/fixture.map"
{
  printf '%s\n' "$bench_header"
  CELL=([id]=flea [run]=1 [thumbs_n]=36 [thumbs_by_format]="jpg=2;png=0;txt=0;none=0;unknown=0" [ranked]=yes [preview_ms]=-)
  emit_row
  CELL=([id]=dolphin [run]=1 [thumbs_n]=790 [thumbs_by_format]="jpg=2;png=1;txt=0;none=0;unknown=0" [ranked]=yes [preview_ms]=-)
  emit_row
  CELL=([id]=strata [run]=1 [thumbs_n]=unmeasurable [thumbs_by_format]=unmeasurable [ranked]="unranked: nothing reached the thumbnail cache so its work was not measured" [preview_ms]=-)
  emit_row
  CELL=([id]=yazi [run]=1 [thumbs_n]=n/a [thumbs_by_format]=n/a [ranked]="n/a: tui in kitty" [preview_ms]=745)
  emit_row
  CELL=([id]=xplr [run]=1 [thumbs_n]=n/a [thumbs_by_format]=n/a [ranked]="n/a: tui in kitty" [preview_ms]=-1)
  emit_row
} > "$csv"
# The generated fixture has to be exactly as wide as the header it was generated from, or the
# generation is the next defect rather than the fix for the last one.
want_cols=$(printf '%s\n' "$bench_header" | tr ',' '\n' | wc -l)
got_cols=$(sed -n '2p' "$csv" | tr ',' '\n' | wc -l)
check "the synthetic run is as wide as the bench's own header" "$want_cols" "$got_cols"

# One refused key for dolphin, so the three-state line has something in every state to report.
# It sits on an entrant that also produced thumbnails, because that is the only shape a refusal
# marker occurs in: an entrant the cache never saw at all leaves no marker either.
grep ' jpg$' "$map" | head -1 | cut -d' ' -f1 > "$keys_dir/dolphin-run1.fail.keys"

"$tool" "$man" close "$csv" >/dev/null 2>&1
check "the manifest closes against a finished run" 0 $?
holds "an entrant's produced formats are named" "flea produced jpg 2" "$man"
holds "a format nobody reached is never-attempted, not absent" "flea .*never attempted .*png 1" "$man"
holds "a refusal marker is its own state" "dolphin produced .*; refused jpg 1" "$man"
holds "an entrant the cache never saw makes no format claim" "strata: nothing reached the thumbnail cache" "$man"
lacks "and is never recorded as having produced nothing" "strata produced nothing" "$man"
holds "a TUI is not given a format line it cannot earn" "yazi: a TUI previews the cursor file" "$man"
holds "every unranked row is repeated as a refusal" "strata run 1: unranked" "$man"
holds "including the TUI bracket's" "yazi run 1: n/a: tui in kitty" "$man"
holds "and a ten-times work gap refuses the comparison outright" "differ in thumbnail work by 21x" "$man"
lacks "so the manifest never calls that run comparable" "every row in this run is comparable" "$man"
holds "an entrant with no preview feature is stated, not left as a sentinel" "xplr: no image preview feature" "$man"
"$tool" "$man" close "$scratch/nothing.csv" >/dev/null 2>&1
check "closing against a missing run is refused" 1 $?
# A second close would append a second set of blocks rather than replace the first, and a manifest
# with two Run close sections is a document a reader has to reconcile.
"$tool" "$man" close "$csv" >/dev/null 2>&1
check "closing an already-closed manifest is refused" 1 $?
check "and it still carries exactly one close section" 1 "$(grep -c '^## Run close' "$man")"

# ---------------------------------------------------------------- tools/flea-bench-report
# The report renders the work column that carried the wrong claim. A cache count that saw nothing
# must reach the page as "not measured": a 0 there was published as a capability claim about strata
# for the whole v0.1.0 release while it drew six of the eight formats offered.
report_out="$scratch/report.md"
"$repo/tools/flea-bench-report" "$csv" > "$report_out" 2>"$scratch/report.err"
check "the report runs against a closed manifest" 0 $?
lacks "a sentinel never reaches the page as a number" "unmeasurable thumbnails" "$report_out"
lacks "and an unseen entrant is never called a zero" "| 0 thumbnails |" "$report_out"
holds "it reads not measured instead" "strata.*not measured" "$report_out"
holds "and the refusal names the instrument, not the entrant" "nothing reached the thumbnail cache" "$report_out"
lacks "the old claim about the entrant's ability is gone" "drew no thumbnails" "$report_out"
# A verdict holding a comma shifts every column right of it, and the failure then surfaces against
# whichever column the shifted row lands in rather than against the verdict that caused it.
comma_csv="$scratch/comma.csv"
sed 's/cache so its work was not measured/cache, so its work was not measured/' "$csv" > "$comma_csv"
cp "$man" "${comma_csv%.csv}.manifest.md"
"$repo/tools/flea-bench-report" "$comma_csv" >/dev/null 2>"$scratch/comma.err"
check "a comma inside a verdict is refused" 1 $?
holds "and the refusal names the field that holds it" "so a field holds a comma" "$scratch/comma.err"

# The two CSVs this repo ships. Their values are not asserted here, only that the report can read
# them: rows have been spliced into these by hand and a lost column is the failure that produces.
for shipped in scale-rc-2026 media-rc-2044; do
  "$repo/tools/flea-bench-report" "$repo/docs/bench/$shipped.csv" >/dev/null 2>&1
  check "the shipped $shipped.csv still parses" 0 $?
done

# The launch line the harness derives from its own table, and the terminal it names once. A renamed
# or reordered field makes the first empty, and an empty launch line in the manifest is the exact
# trap hard rule 7 names first. The second was derived from the class field and quietly resolved to
# a window class rather than a program, which the manifest would have printed as "absent".
bench="$repo/tools/flea-field-bench"
rows=$(sed -n '/^declare -a ENTRANTS=(/,/^)/p' "$bench" | grep '^  "' | tr -d '"')
# -f8-, matching the bench: the command field may hold a pipe and cut -f8 would stop at it.
flea_cmd=$(printf '%s\n' "$rows" | grep '^  flea|' | cut -d'|' -f8-)
tui_term=$(grep -m1 '^TUI_TERM=' "$bench" | cut -d= -f2)
# The header and the row are written in two different places, so a column added to one and not the
# other produces a CSV that parses and is wrong from that column rightward.
header_fields=$(sed -n 's/^echo "\(id,run,[^"]*\)".*/\1/p' "$bench" | tr ',' '\n' | wc -l)
row_fields=$(grep '^  printf .%s,%s' "$bench" | head -1 | grep -o '%s' | wc -l)
check "the CSV header and the row have the same column count" "$header_fields" "$row_fields"

# tools/flea-bench-capability reads the same entrant table. A row extraction that comes back empty
# would report every entrant as capable of nothing, which reads as a result.
cap_gui=$(sed -n '/^declare -a ENTRANTS=(/,/^)/p' "$bench" | grep '^  "' | tr -d '"' | grep -c '|gui|')
if [ "$cap_gui" -ge 5 ]; then
  echo "ok   the capability pass can see the GUI entrants: $cap_gui of them"
else
  echo "FAIL the capability pass derived $cap_gui GUI entrants from the bench table"; fail=1
fi

case $flea_cmd in
  *"--gui"*) echo "ok   the flea launch line is derived and names --gui" ;;
  *) echo "FAIL the flea launch line derived to '$flea_cmd'"; fail=1 ;;
esac
if [ -n "$tui_term" ] && command -v "$tui_term" >/dev/null 2>&1; then
  echo "ok   the TUI terminal is derived and installed: $tui_term"
else
  echo "FAIL the TUI terminal derived to '$tui_term', which is not an installed program"; fail=1
fi

# The harness's control-group helpers, pulled out whole: only a field run executed them before, and it lost thunar and yazi.
eval "$(sed -n '/^pids_for() {/,/^}/p; /^cpu_ticks() {/,/^}/p; /^find_helper() {/,/^}/p; /^settle_ticks() {/,/^}/p; /^entrant_cg() {/,/^}/p; /^cg_empty() {/,/^}/p; /^sweep_cg() {/,/^}/p; /^release_run_cg() {/,/^}/p' "$bench")"
eval "$(grep -m1 '^HELPER_SEARCH_POLLS=' "$bench")"
declare -A WATCHED=()
own_cg="/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)"
not_a_leaf="$scratch/not-a-leaf"
# Named copies of sleep, so pgrep -x finds this suite's stand-ins and nothing else on the box.
cp "$(command -v sleep)" "$scratch/fbhelper" && cp "$(command -v sleep)" "$scratch/fbtui" || exit 1
# Longer than sweep_cg can wait, so an unswept stand-in is still alive when the check reads it.
stand_in_s=120
"$scratch/fbhelper" "$stand_in_s" & helper=$!
# Until the forked child has exec'd, its comm is still bash and pgrep -x cannot see it.
exec_polls=50
for _ in $(seq "$exec_polls"); do [ "$(cat "/proc/$helper/comm" 2>/dev/null)" = fbhelper ] && break; sleep 0.1; done

# tumblerd's shape: a helper outside the leaf, found on the first poll, while the entrant is alive.
RUN_CG=$not_a_leaf HELPER_COMM=fbhelper HELPER_TOKEN="" HELPER_PID="" HELPER_POLLS_LEFT=0 HELPER_SIDE=""
settle_ticks $$
check "a helper outside the leaf leaves settle_ticks true, as tumblerd beside thunar" 0 $?
check "and that helper is recorded as outside" outside "$HELPER_SIDE"
kill "$helper"; wait "$helper" 2>/dev/null

RUN_CG=$own_cg ENTRANT_SCOPE=""
entrant_cg $$ gui
check "an entrant in the run's own group is in its group" 0 $?
# systemd-run execs the stand-in in a scope named the way kitty 0.48 names its own, after this shell.
systemd-run --user --scope -q --unit="kitty-$$-7" "$scratch/fbtui" "$stand_in_s" & tui=$!
placed=no
placement_polls=50
for _ in $(seq "$placement_polls"); do
  case "$(cut -d: -f3 "/proc/$tui/cgroup" 2>/dev/null)" in */kitty-$$-7.scope) placed=yes; break ;; esac
  sleep 0.1
done
check "systemd placed the stand-in TUI in kitty-$$-7.scope" yes "$placed"
scope_cg="/sys/fs/cgroup$(cut -d: -f3 "/proc/$tui/cgroup" 2>/dev/null)"
# Only a group proved to be this scope is swept: an empty read would make it the root group.
case $scope_cg in
  */kitty-$$-7.scope)
    entrant_cg "$tui" gui
    check "a GUI entrant is never taken from a kitty scope" 1 $?
    RUN_CG=$not_a_leaf ENTRANT_SCOPE=""
    entrant_cg "$tui" tui
    check "a kitty scope whose kitty is outside the leaf does not count" 1 $?
    check "and is never recorded for the sweep, which would end an operator's own kitty" "" "$ENTRANT_SCOPE"
    RUN_CG=$own_cg
    entrant_cg "$tui" tui
    check "a TUI in the scope of a kitty inside the leaf counts" 0 $?
    check "and that scope is recorded for the sweep" "$scope_cg" "$ENTRANT_SCOPE"
    # A plain directory stands in for the leaf, so the kitty scope is the only group holding a process.
    BENCH_CG=$scratch RUN_CG="$scratch/run-bench"
    mkdir "$RUN_CG"
    release_run_cg 2> "$scratch/sweep.err"
    # Sample input: /proc/<pid>/stat "4242 (fbtui) S 4241 ...", state third; Z or no file is ended.
    state=$(cut -d' ' -f3 "/proc/$tui/stat" 2>/dev/null)
    case $state in ''|Z) state=ended ;; esac
    check "release_run_cg ends what is left in the kitty scope" ended "$state"
    check "and forgets the scope once it is swept" "" "$ENTRANT_SCOPE"
    kill -9 "$tui" 2>/dev/null; wait "$tui" 2>/dev/null
    holds "and names it as a leftover" "LEFTOVER: pid $tui (fbtui)" "$scratch/sweep.err"
    ;;
  *) echo "FAIL the stand-in's group read as '$scope_cg', so the scope checks did not run"; fail=1; kill "$tui" 2>/dev/null ;;
esac

exit $fail
