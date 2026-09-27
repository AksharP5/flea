#!/bin/bash
# Drives the real binary over stdin and asserts the exact stdout contract.
set -u
# Hard rule 9's guard, which owns FIXTURE_ROOT and every create and delete below.
. "$(dirname "$0")/../tools/flea-sandbox-guard"

cd "$(dirname "$0")/.." || exit 1

BIN=${BIN:-./target/debug/flea}
# A clean git archive export carries no target/, and without this the suite runs every case
# against a missing binary and reports them as product failures.
if [ ! -x "$BIN" ]; then
    printf 'protocol.sh: no binary at %s\n' "$BIN" >&2
    printf 'protocol.sh: build it (cargo build) or set BIN to one; refusing to report on nothing\n' >&2
    exit 1
fi
if ! command -v cc >/dev/null 2>&1; then
    echo 'protocol.sh: cc is required to build the directory-size syscall barrier' >&2
    exit 1
fi
# The sandbox is the parent and the listing is a directory inside it, because the guard's marker is
# a real dotfile and this suite asserts what a hidden:true listing contains.
SB="$FIXTURE_ROOT/flea-proto-test-$$"
D="$SB/tree"
SIZES="$SB/sizes"
# damson.txt's size: far above any folder's walked size, so the folder sorts below it on every filesystem.
LARGEST_BYTES=1000000
# src/backend/thumbcache.rs honours XDG_CACHE_HOME, so this suite's thumbnails land inside its own
# sandbox and the operator's real cache is never written to, read from, or cleaned up after.
export XDG_CACHE_HOME="$SB/cache"
fail=0

setup() {
  sandbox_make "$SB"
  mkdir -p "$D/sub"
  printf 'abc' > "$D/three.txt"
  : > "$D/empty.txt"
  # Name order and size order disagree here, so an anchored size sort cannot pass on name order.
  mkdir -p "$SIZES"
  # The anchors sit two or more places from both ends of every name order, so no name order puts either at 1.
  printf '123' > "$SIZES/apple.txt"
  printf '12345' > "$SIZES/berry.txt"
  printf '1' > "$SIZES/cherry.txt"
  head -c "$LARGEST_BYTES" /dev/zero > "$SIZES/damson.txt"
  printf '1234567' > "$SIZES/elder.txt"
  printf '123456789' > "$SIZES/fig.txt"
  # A folder orders by its walked size (src/backend/ordering.rs): its 4 bytes plus its own entry, a few KB at most.
  mkdir -p "$SIZES/box"
  printf '1234' > "$SIZES/box/four.txt"
}

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    fail=1
  else
    echo "ok   $label"
  fi
}

setup

out=$(printf '{"c":"list","path":"%s","first":2}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "listed count" "3" "$(echo "$out" | head -1 | grep -oE '"n":[0-9]+' | cut -d: -f2)"
# One field for the whole listing, because every file in a directory shares its filesystem.
check "listed names the directory's own filesystem" "1" "$(echo "$out" | head -1 | grep -c '"v":[1-9]')"
check "list is followed by rows" "rows" "$(echo "$out" | sed -n 2p | grep -oE '"t":"[a-z]+"' | head -1 | cut -d'"' -f4)"
check "first window honours the count" "2" "$(echo "$out" | sed -n 2p | grep -o '"n":"' | wc -l | tr -d ' ')"

out=$(printf '{"c":"list","path":"%s","first":0}\n{"c":"window","start":0,"count":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a rows object follows list even when first is 0" "rows" "$(echo "$out" | sed -n 2p | grep -oE '"t":"[a-z]+"' | head -1 | cut -d'"' -f4)"
check "that rows object is empty" "0" "$(echo "$out" | sed -n 2p | grep -o '"n":"' | wc -l | tr -d ' ')"
check "directories sort first" "sub" "$(echo "$out" | sed -n 3p | grep -oE '"n":"[^"]+"' | head -1 | cut -d'"' -f4)"

# ui/js/Swap.js onListed drops a listed line whose path is not the one it asked for, so each spelling comes back byte for byte.
ln -s "$D/sub" "$SB/sublink"
for asked in "$D/sub/" "$SB/sublink" "$D/sub/.."; do
  out=$(printf '{"c":"list","path":"%s","first":0}\n{"c":"quit"}\n' "$asked" | $BIN --backend)
  # Sample output, the listed line: {"t":"listed","n":2,"read":0.040,"sort":0.010,"v":42,"path":"/tmp/flea/sub/"}
  check "listed names ${asked#"$SB"/} exactly as it was asked" "\"path\":\"$asked\"" "$(echo "$out" | grep -F '"t":"listed"' | head -1 | grep -oE '"path":"[^"]*"')"
done

# listpaths: the picker's Recent, a listing built from the client's own list; see docs/protocol.md "listpaths".
# The order is the client's, a path that is gone is dropped, and every name is relative to the base "/".
out=$(printf '{"c":"listpaths","paths":["%s/three.txt","%s/gone.txt","%s/sub","%s/empty.txt"],"first":10}\n{"c":"quit"}\n' \
  "$D" "$D" "$D" "$D" | $BIN --backend)
check "listpaths drops the path that is gone" "3" "$(echo "$out" | head -1 | grep -oE '"n":[0-9]+' | cut -d: -f2)"
check "listpaths is followed by rows" "rows" "$(echo "$out" | sed -n 2p | grep -oE '"t":"[a-z]+"' | head -1 | cut -d'"' -f4)"
check "listpaths keeps the client's order and never sorts" "${D#/}/three.txt" \
  "$(echo "$out" | sed -n 2p | grep -oE '"n":"[^"]+"' | head -1 | cut -d'"' -f4)"
check "a directory in the list is still marked one" "1" "$(echo "$out" | sed -n 2p | grep -c "\"n\":\"${D#/}/sub\",\"d\":true")"
check "listpaths reports no sort pass" "0.000" "$(echo "$out" | head -1 | grep -oE '"sort":[0-9.]+' | cut -d: -f2)"
# A relative path and the root itself are refused: this list is read out of a file every application writes.
out=$(printf '{"c":"listpaths","paths":["etc/hostname","/",""],"first":10}\n{"c":"quit"}\n' | $BIN --backend)
check "listpaths refuses a path that is not absolute" "0" "$(echo "$out" | head -1 | grep -oE '"n":[0-9]+' | cut -d: -f2)"

# Task 11: rows carries a per-response Kind dictionary, read against the box's real freedesktop tables, see docs/protocol.md "rows".
kind_out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
kind_row=$(echo "$kind_out" | sed -n 2p)
check "rows carries a kinds dictionary" "1" "$(echo "$kind_row" | grep -c '"kinds":\[')"
check "a directory's kind is Folder" "1" "$(echo "$kind_row" | grep -c '"Folder"')"
check "the two text files share one Plain text document entry, not two" "1" "$(echo "$kind_row" | grep -o '"Plain text document"' | wc -l | tr -d ' ')"
check "every one of the three rows names its kind by an index" "3" "$(echo "$kind_row" | grep -o '"k":[0-9]*' | wc -l | tr -d ' ')"
# A drop destination is always a directory, so only a directory row carries its filesystem id. The
# 100k scale fixture holds no directories, which is why this field costs the headline listing nothing.
check "only the directory row carries a filesystem id" "1" "$(echo "$kind_row" | grep -o '"v":[0-9]*' | wc -l | tr -d ' ')"
check "and that id is a real device, not a zero placeholder" "0" "$(echo "$kind_row" | grep -c '"v":0[,}]')"

# A request naming a replaced numbering (docs/protocol.md "listing") resolves nothing: $D/sub/kept.txt, row 0 of listing 2, survives a trash sent with 1.
printf 'x' > "$D/sub/kept.txt"
# The stale refusal's leading fields, which the check below cuts the first refusal to.
stale_paths='{"t":"error","where":"stale","path":"paths"'
# Sample output: {"t":"error","where":"stale","path":"paths","msg":"the listing changed before this request arrived, so its rows name other files; nothing was done"}
out=$(printf '{"c":"list","path":"%s","first":5}\n{"c":"list","path":"%s/sub","first":5}\n{"c":"paths","rows":[0],"listing":1}\n{"c":"trash","rows":[0],"menuId":0,"listing":1}\n{"c":"menuaction","op":"snapshot","id":3,"rows":[0],"cursor":0,"listing":1}\n{"c":"paths","rows":[0],"listing":2}\n{"c":"paths","rows":[0]}\n{"c":"sort","by":"size","desc":false}\n{"c":"paths","rows":[0],"listing":2}\n{"c":"quit"}\n' "$D" "$D" | $BIN --backend)
check "each rows line names its listing's numbering" "1 2" "$(echo "$out" | grep '"t":"rows"' | grep -oE '"listing":[0-9]+' | cut -d: -f2 | tr '\n' ' ' | sed 's/ $//')"
check "paths naming the replaced numbering is refused by name and resolves nothing" "$stale_paths" \
  "$(echo "$out" | grep '"where":"stale"' | sed -n 1p | cut -c1-${#stale_paths})"
check "trash naming it is refused the same way" "1" "$(echo "$out" | grep -c '"where":"stale","path":"trash"')"
check "and the file that request would have trashed is still there" "yes" "$([ -f "$D/sub/kept.txt" ] && echo yes || echo no)"
check "a menu snapshot naming it is refused in the menu's own shape" "1" \
  "$(echo "$out" | grep '"t":"menuaction","id":3' | grep -c '"ok":false')"
check "the numbering in force resolves, and so does a request that names none" "2" \
  "$(echo "$out" | grep -c "\"t\":\"paths\",\"paths\":\[\"$D/sub/kept.txt\"\]")"
check "a sort renumbers, so the numbering the rows were read in is refused after it too" "2" \
  "$(echo "$out" | grep -c '"where":"stale","path":"paths"')"
rm -f "$D/sub/kept.txt"

# Size and mtime are orders now: answered with listed like name, and the pass rides in read.
# Sample output: {"t":"listed","n":3,"read":0.041,"sort":0.003}
out=$(printf '{"c":"list","path":"%s","first":0}\n{"c":"sort","by":"size","desc":false}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "sorting by size answers a listed line, not an error" "listed" "$(echo "$out" | sed -n 3p | grep -oE '"t":"[a-z]+"' | cut -d'"' -f4)"
check "and sorting by mtime does too" "listed" "$(printf '{"c":"list","path":"%s","first":0}\n{"c":"sort","by":"mtime","desc":true}\n{"c":"quit"}\n' "$D" | $BIN --backend | sed -n 3p | grep -oE '"t":"[a-z]+"' | cut -d'"' -f4)"
check "a sort that names no anchor answers the plain listed line" "0" "$(echo "$out" | sed -n 3p | grep -c anchor)"

# A re-sort that names the cursor's row answers that row's index in the new order, through handle_line itself.
# Sample output: {"t":"listed","n":4,"read":0.041,"sort":0.003,"v":56,"path":"/x","anchor":"/x/cherry.txt","anchorIndex":2}
anchored() {
  printf '{"c":"list","path":"%s","first":0}\n{"c":"sort","by":"%s","desc":%s,"foldersFirst":true,"anchor":"%s"}\n{"c":"quit"}\n' \
    "$SIZES" "$1" "$2" "$3" | $BIN --backend | sed -n 3p
}
# Each anchor is 1 only in its own order: every name order, the other direction and size without folders first answer otherwise.
out=$(anchored size false "$SIZES/cherry.txt")
check "an anchored sort echoes the anchor it was given" "1" "$(echo "$out" | grep -c "\"anchor\":\"$SIZES/cherry.txt\"")"
check "and answers its index in the size order: [box, cherry, apple, berry, elder, fig, damson]" '"anchorIndex":1' "$(echo "$out" | grep -oE '"anchorIndex":-?[0-9]+')"
check "descending, the largest file answers its index: [box, damson, fig, elder, berry, apple, cherry]" '"anchorIndex":1' "$(anchored size true "$SIZES/damson.txt" | grep -oE '"anchorIndex":-?[0-9]+')"
check "a name sort answers the anchor's index too: [box, apple, berry, cherry, damson, elder, fig]" '"anchorIndex":3' "$(anchored name false "$SIZES/cherry.txt" | grep -oE '"anchorIndex":-?[0-9]+')"
check "an anchor the listing never held answers -1" '"anchorIndex":-1' "$(anchored name false "$SIZES/gone.txt" | grep -oE '"anchorIndex":-?[0-9]+')"

# Prefetch record (src/prefetch.rs): this shell plays the launcher's, since a pipeline's last command is its child.
PREFETCH_WAIT_TENTHS=30
LIST="$SB/prefetch-list"
SEEN="$SB/prefetch-seen"
REPLY="$SB/prefetch-reply"
# Runs a backend as this shell's child, naming pid $1 as the launcher's shell, until the list differs from $3 (marking $SEEN) or the wait runs out.
prefetch_run() {
  rm -f "$SEEN"
  { printf '{"c":"list","path":"%s","first":10}\n' "$D"
    for _ in $(seq 1 "$PREFETCH_WAIT_TENTHS"); do
      [ "$(cat "$2" 2>/dev/null)" != "$3" ] && { : > "$SEEN"; break; }
      sleep 0.1
    done
    printf '{"c":"quit"}\n'; } | FLEA_PREFETCH="$2" FLEA_PREFETCH_SHELL="$1" $BIN --backend > "$REPLY"
  PREFETCH_RC=${PIPESTATUS[1]}
}
# Sample reply line: {"t":"listed","n":3,"read":0.041,"sort":0.003,"v":1,"path":"/x"}, the proof the backend served the list.
answered() { echo "$PREFETCH_RC $(grep -c '"t":"listed"' "$REPLY")"; }
# A live process of this user, not the backend's parent: a missing parent check would read its maps and record.
sleep 30 &
stranger=$!
prefetch_run "$stranger" "$LIST" ""
kill "$stranger" 2>/dev/null; wait "$stranger" 2>/dev/null
check "a backend whose parent is not the named shell serves the list and exits cleanly" "0 1" "$(answered)"
check "and records no prefetch list" "absent" "$([ -e "$LIST" ] && echo present || echo absent)"
prefetch_run $$ "$LIST" ""
check "the named shell's own backend records one while it runs, before quit" "0 1 seen" "$(answered) $([ -e "$SEEN" ] && echo seen)"
# Sample line 2: "shell 4242 5561234", the shell's pid and start time.
identity=$(sed -n 2p "$LIST")
# Sample stat: "4242 (bash) S 1 ... 0 5561234 ...": after the name's ") ", starttime (field 22) is the 20th field.
stat_line=$(cat /proc/$$/stat)
check "and names this shell by its pid and start time" "shell $$ $(echo "${stat_line##*) }" | cut -d' ' -f20)" "$identity"
shell_exe=$(readlink -f /proc/$$/exe)
# Sample range line: "0 32768 /usr/bin/bash", offset, length and path, so " <path>" matches only the path field.
check "and lists the shell's own executable, not the backend's" "yes no" \
  "$(grep -qF " $shell_exe" "$LIST" && echo yes || echo no) $(grep -qF " $(readlink -f $BIN)" "$LIST" && echo yes || echo no)"
printf 'flea-prefetch 2\nshell %s 1\n0 4096 /sentinel\n' "$$" > "$LIST"
prefetch_run $$ "$LIST" "$(cat "$LIST")"
check "a list naming this pid with another start time is an earlier shell's, and is replaced" "$identity no" \
  "$(sed -n 2p "$LIST") $(grep -qF /sentinel "$LIST" && echo yes || echo no)"
printf 'flea-prefetch 2\n%s\n0 4096 /sentinel\n' "$identity" > "$LIST"
recorded=$(cat "$LIST")
prefetch_run $$ "$LIST" "$recorded"
check "a later backend of the same shell serves its list and leaves the launch's list alone" "0 1 same" \
  "$(answered) $([ "$(cat "$LIST")" = "$recorded" ] && echo same)"

out=$(printf '{"c":"list","path":"%s","first":0}\n{"c":"sort","by":"name","desc":true}\n{"c":"window","start":0,"count":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "descending name sort keeps directories first" "sub" "$(echo "$out" | sed -n 4p | grep -oE '"n":"[^"]+"' | head -1 | cut -d'"' -f4)"
check "descending name sort reverses the files" "three.txt" "$(echo "$out" | sed -n 4p | grep -oE '"n":"[^"]+"' | sed -n 2p | cut -d'"' -f4)"

out=$(printf '{"c":"list","path":"%s","first":0}\n{"c":"window","start":999999,"count":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a window past the end echoes the clamped start" '"start":3' "$(echo "$out" | sed -n 3p | grep -o '"start":[0-9]*')"
check "and returns no rows" "0" "$(echo "$out" | sed -n 3p | grep -o '"n":"' | wc -l | tr -d ' ')"

out=$(printf '{"c":"list","path":"/definitely/not/here","first":1}\n{"c":"quit"}\n' | $BIN --backend)
check "a missing path is an error message" "error" "$(echo "$out" | head -1 | grep -oE '"t":"[a-z]+"' | cut -d'"' -f4)"
# rename-kept carries a hyphen, so a [a-z]+ class matches no part of that line and yields nothing.
check "the error names the operation" "scan" "$(echo "$out" | head -1 | grep -oE '"where":"[a-z-]+"' | cut -d'"' -f4)"

printf '{"c":"list","path":"/definitely/not/here","first":1}\n{"c":"quit"}\n' | $BIN --backend >/dev/null
check "the backend exits 0 even after an error" "0" "$?"

out=$(printf 'total junk\n{"c":"quit"}\n' | $BIN --backend)
check "junk produces no output and no crash" "" "$out"

ND_SB="$FIXTURE_ROOT/flea-newline-test-$$"
ND="$ND_SB/tree"
sandbox_make "$ND_SB"
mkdir -p "$ND"
: > "$ND/$(printf 'two\nlines.txt')"
out=$(printf '{"c":"list","path":"%s","first":5}\n{"c":"quit"}\n' "$ND" | $BIN --backend)
check "a newline in a real filename keeps the response on two lines" "2" "$(echo "$out" | wc -l | tr -d ' ')"
check "and the name is escaped in the row" "1" "$(echo "$out" | sed -n 2p | grep -c 'two\\nlines.txt')"
sandbox_remove "$ND_SB"

SD_SB="$FIXTURE_ROOT/flea-symlink-test-$$"
SD="$SD_SB/tree"
sandbox_make "$SD_SB"
mkdir -p "$SD"
mkdir -p "$SD/realdir"
ln -s "$SD/realdir" "$SD/linkdir"
ln -s "$SD/nowhere" "$SD/brokenlink"
out=$(printf '{"c":"list","path":"%s","first":5}\n{"c":"quit"}\n' "$SD" | $BIN --backend)
check "a broken symlink is listed, not dropped" "1" "$(echo "$out" | sed -n 2p | grep -c '"n":"brokenlink"')"
check "a symlink to a directory reports d false" "1" "$(echo "$out" | sed -n 2p | grep -c '"n":"linkdir","d":false')"
# The target the row list draws beside the name, verbatim: absolute stays absolute, relative stays
# relative, and a broken link still names where it points. See docs/protocol.md "rows".
ln -s ../elsewhere "$SD/relativelink"
printf 'abc' > "$SD/plain.txt"
out=$(printf '{"c":"list","path":"%s","first":9}\n{"c":"quit"}\n' "$SD" | $BIN --backend)
check "a symlink carries its target" "1" "$(echo "$out" | sed -n 2p | grep -c "\"n\":\"linkdir\",\"d\":false,[^}]*\"l\":\"$SD/realdir\"")"
check "a broken symlink still names where it points" "1" "$(echo "$out" | sed -n 2p | grep -c "\"n\":\"brokenlink\",[^}]*\"l\":\"$SD/nowhere\"")"
check "a relative target stays relative" "1" "$(echo "$out" | sed -n 2p | grep -c '"n":"relativelink",[^}]*"l":"../elsewhere"')"
check "a plain file carries no target at all" "0" "$(echo "$out" | sed -n 2p | grep -c '"n":"plain.txt",[^}]*"l":')"
check "and exactly the three links carry one" "3" "$(echo "$out" | sed -n 2p | grep -o '"l":"' | wc -l | tr -d ' ')"
sandbox_remove "$SD_SB"

# Directories first is not optional, so the fixture that proves it has to be one the two orders can
# actually disagree about. Directories "1" and "11" beside a file "2": grouped gives 1 11 2 and
# ungrouped gives 1 2 11, so a build with the grouping taken out fails this and only this shape can
# tell them apart. Descending needs the whole order and not the first name: grouped gives 11 1 2 and
# ungrouped gives 11 2 1, which share a first row.
GR_SB="$FIXTURE_ROOT/flea-grouping-test-$$"
GR="$GR_SB/tree"
sandbox_make "$GR_SB"
mkdir -p "$GR/1" "$GR/11"
: > "$GR/2"

# Sample input: {"t":"rows","start":0,"rows":[{"n":"1","d":true,...},{"n":"11",...}],...} becomes "1 11 2".
row_names() {
  grep -oE '"n":"[^"]+"' | cut -d'"' -f4 | tr '\n' ' ' | sed 's/ $//'
}

grouping_order() {
  local by="$1" desc="$2"
  printf '{"c":"list","path":"%s","first":0}\n{"c":"sort","by":"%s","desc":%s}\n{"c":"window","start":0,"count":10}\n{"c":"quit"}\n' \
    "$GR" "$by" "$desc" | $BIN --backend | sed -n 4p | row_names
}

check "ascending name sort groups the directories ahead of a file that sorts between them" \
  "1 11 2" "$(grouping_order name false)"
check "descending name sort keeps that grouping, and reverses only inside it" \
  "11 1 2" "$(grouping_order name true)"

# Kind order must differ from name order; filename MIME lookup needs no image decoding.
KIND="$GR_SB/kind"
mkdir -p "$KIND"
printf 'text' > "$KIND/a.txt"
printf 'image fixture' > "$KIND/z.png"
out=$(printf '{"c":"list","path":"%s","first":0}\n{"c":"sort","by":"kind","desc":false}\n{"c":"window","start":0,"count":10}\n{"c":"quit"}\n' "$KIND" | "$BIN" --backend)
check "Kind is a supported sort and answers a listing" \
  "listed" "$(echo "$out" | sed -n 3p | grep -oE '"t":"[a-z]+"' | cut -d'"' -f4)"
check "Kind orders image/png before text/plain rather than sorting their names" \
  "z.png a.txt" "$(echo "$out" | sed -n 4p | row_names)"

# Sample input: {"t":"error","where":"sort","path":"mode","msg":"no such sort key; send name, size, mtime or kind"}
sort_reply() {
  printf '{"c":"list","path":"%s","first":0}\n%s\n{"c":"quit"}\n' "$GR" "$1" | $BIN --backend | sed -n 3p
}

unknown_reply=$(sort_reply '{"c":"sort","by":"mode","desc":false}')
check "a header column that is no sort key is refused, not answered as name order" \
  "error" "$(echo "$unknown_reply" | grep -oE '"t":"[a-z]+"' | cut -d'"' -f4)"
check "and the refusal names the key it refused" \
  "mode" "$(echo "$unknown_reply" | grep -oE '"path":"[a-z]*"' | cut -d'"' -f4)"
check "and the refusal names every supported sort key" \
  "no such sort key; send name, size, mtime or kind" "$(echo "$unknown_reply" | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4)"

nokey_reply=$(sort_reply '{"c":"sort","desc":false}')
check "a sort with no by at all is refused by the same sentence" \
  "no such sort key; send name, size, mtime or kind" "$(echo "$nokey_reply" | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4)"
check "and its refusal carries back the empty key it was sent" \
  '"path":""' "$(echo "$nokey_reply" | grep -o '"path":""')"

# A silent fallback to name ascending would undo this descending order.
for request in '{"c":"sort","by":"mode"}' '{"c":"sort"}'; do
  out=$(printf '{"c":"list","path":"%s","first":0}\n{"c":"sort","by":"name","desc":true}\n%s\n{"c":"window","start":0,"count":10}\n{"c":"quit"}\n' "$GR" "$request" | "$BIN" --backend)
  check "a refused sort keeps the previous descending order: $request" \
    "11 1 2" "$(echo "$out" | sed -n 5p | row_names)"
done

# Size and mtime go through the metadata pass and must keep the grouping. Each key is made to
# disagree with the others: 2 is the larger file and the oldest entry, 3 the smaller and the
# newest, 11 is older than 1, and 1 holds 20 bytes so its walked size is above 11's whatever
# the two directory entries measure. A build ordering folders by name would answer "1 11 3 2"
# for size ascending; one that lost the grouping would answer "2 11 1 3" for mtime ascending.
printf '%020d' 0 > "$GR/1/x"
printf '%05d' 0 > "$GR/2"
printf '0' > "$GR/3"
touch -d '2020-01-01 00:00:00' "$GR/2"
touch -d '2020-01-01 00:00:01' "$GR/11"
touch -d '2020-01-01 00:00:02' "$GR/1"
touch -d '2020-01-01 00:00:03' "$GR/3"
check "name ascending still groups the directories with the two files in place" \
  "1 11 2 3" "$(grouping_order name false)"
check "size ascending orders the files by size and the folders by walked size" \
  "11 1 3 2" "$(grouping_order size false)"
check "size descending keeps the folders first and reverses inside each group" \
  "1 11 2 3" "$(grouping_order size true)"
check "mtime ascending orders both groups by time, directories still first" \
  "11 1 2 3" "$(grouping_order mtime false)"
check "mtime descending keeps the directories first and reverses inside each group" \
  "1 11 3 2" "$(grouping_order mtime true)"
# The order must agree with the column: the window after a size sort carries each row's own s.
check "the reordered window carries the sizes the order was built from" \
  '"n":"3","d":false,"s":1 "n":"2","d":false,"s":5' \
  "$(printf '{"c":"list","path":"%s","first":0}\n{"c":"sort","by":"size","desc":false}\n{"c":"window","start":0,"count":10}\n{"c":"quit"}\n' "$GR" | $BIN --backend | sed -n 4p | grep -oE '"n":"[23]","d":false,"s":[0-9]+' | tr '\n' ' ' | sed 's/ $//')"
sandbox_remove "$GR_SB"

out=$(printf '{"c":"list","path":"%s","first":0}\n{"c":"list","path":"/definitely/not/here","first":0}\n{"c":"window","start":0,"count":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a failed list leaves the previous listing intact" "sub" "$(echo "$out" | sed -n 4p | grep -oE '"n":"[^"]+"' | head -1 | cut -d'"' -f4)"
check "and that listing still stats against its own directory" '"n":"three.txt","d":false,"s":3' "$(echo "$out" | sed -n 4p | grep -o '"n":"three.txt","d":false,"s":3')"

setup
PW="$FIXTURE_ROOT/flea-prewarm-test-$$.json"
rm -f "$PW"
$BIN --prewarm "$D" 2 "$PW"
check "prewarm file exists" "0" "$([ -f "$PW" ] && echo 0 || echo 1)"
check "prewarm first line is listed" "listed" "$(head -1 "$PW" | grep -oE '"t":"[a-z]+"' | cut -d'"' -f4)"
check "prewarm second line is rows" "rows" "$(sed -n 2p "$PW" | grep -oE '"t":"[a-z]+"' | head -1 | cut -d'"' -f4)"
check "prewarm rows honour the count" "2" "$(sed -n 2p "$PW" | grep -o '"n":"' | wc -l | tr -d ' ')"
first_listing=$(printf '{"c":"list","path":"%s","first":2}\n{"c":"quit"}\n' "$D" | $BIN --backend | sed -n 2p | grep -oE '"listing":[0-9]+}$')
check "prewarm rows name the numbering a backend's first list answers in" "${first_listing:-no numbering from the backend}" \
  "$(sed -n 2p "$PW" | grep -oE '"listing":[0-9]+}$')"
check "no temp file is left behind" "0" "$(ls "$PW".*.tmp 2>/dev/null | wc -l | tr -d ' ')"
check "the prewarm file is owner-only" "600" "$(stat -c '%a' "$PW")"

printf 'STALE\n' > "$PW"
$BIN --prewarm /definitely/not/here 2 "$PW" >/dev/null 2>&1
check "a failed prewarm exits non-zero" "1" "$?"

TGT="$FIXTURE_ROOT/flea-prewarm-target-$$.txt"
printf 'TARGET UNTOUCHED' > "$TGT"
rm -f "$PW"
ln -s "$TGT" "$PW"
$BIN --prewarm "$D" 2 "$PW" >/dev/null 2>&1
check "a symlink at the destination is replaced" "1" "$([ -L "$PW" ] && echo 0 || echo 1)"
check "and the symlink target is untouched" "TARGET UNTOUCHED" "$(cat "$TGT")"
rm -f "$PW" "$TGT"

# Directories sort first, so index 1 of the row order is "sub" and index 2 is "empty.txt".
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a directory row carries the folder icon" "folder" "$(echo "$out" | sed -n 2p | grep -oE '"i":"[^"]+"' | sed -n 1p | cut -d'"' -f4)"
check "a file row carries an icon name" "text-x-generic" "$(echo "$out" | sed -n 2p | grep -oE '"i":"[^"]+"' | sed -n 2p | cut -d'"' -f4)"

setup
printf 'x' > "$D/photo.jpg"
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "an image row carries the image icon" "1" "$(echo "$out" | sed -n 2p | grep -c '"i":"image-x-generic"')"
check "the icon field never arrives empty" "0" "$(echo "$out" | sed -n 2p | grep -c '"i":""')"

# A symlink to a directory carries d:false by contract, so only its icon follows the target.
setup
ln -s "$D/sub" "$D/linkdir"
printf 'x' > "$D/cert.pem"
chmod 0644 "$D/cert.pem"
# *.so is application/x-sharedlib, one of the 190 application types generic-icons does not list.
cp /usr/bin/true "$D/prog.so"
chmod 0755 "$D/prog.so"
# Row order is sub, cert.pem, empty.txt, linkdir, prog.so, three.txt.
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a symlink to a directory keeps d false" "false" "$(echo "$out" | sed -n 2p | grep -oE '"n":"linkdir","d":(true|false)' | cut -d: -f3)"
check "and draws as a folder" "1" "$(echo "$out" | sed -n 2p | grep -c '"n":"linkdir","d":false,"s":[0-9]*,"m":[0-9-]*,"p":[0-9]*,"i":"folder"')"
# Each icon grep is anchored to its own row's fields: a .* here spans into the next row's icon.
check "a pem is not an executable" "0" "$(echo "$out" | sed -n 2p | grep -c '"n":"cert.pem","d":false,"s":[0-9]*,"m":[0-9-]*,"p":[0-9]*,"i":"application-x-executable"')"
check "a pem draws as a generic file" "1" "$(echo "$out" | sed -n 2p | grep -c '"n":"cert.pem","d":false,"s":[0-9]*,"m":[0-9-]*,"p":[0-9]*,"i":"application-x-generic"')"
check "an executable shared object still draws as an executable" "1" "$(echo "$out" | sed -n 2p | grep -c '"n":"prog.so","d":false,"s":[0-9]*,"m":[0-9-]*,"p":[0-9]*,"i":"application-x-executable"')"

# Row order after setup plus the copy is sub, empty.txt, photo.jpg, three.txt, so the indices are 1, 3 and 4.
setup
cp "$FIXTURE_ROOT/flea-media-btrfs/photo_0.jpg" "$D/photo.jpg" 2>/dev/null || printf 'x' > "$D/photo.jpg"
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a directory row cannot be thumbnailed" "false" "$(echo "$out" | sed -n 2p | grep -oE '"t":(true|false)' | sed -n 1p | cut -d: -f2)"
check "a jpeg row can be thumbnailed" "true" "$(echo "$out" | sed -n 2p | grep -oE '"t":(true|false)' | sed -n 3p | cut -d: -f2)"
check "a text row cannot be thumbnailed" "false" "$(echo "$out" | sed -n 2p | grep -oE '"t":(true|false)' | sed -n 4p | cut -d: -f2)"
check "every row carries the field" "4" "$(echo "$out" | sed -n 2p | grep -oE '"t":(true|false)' | wc -l | tr -d ' ')"

# Guards the channel restructure: a reader thread that never closes would hang here instead.
out=$(printf '{"c":"list","path":"%s","first":1}\n' "$D" | timeout 10 $BIN --backend; echo "rc=$?")
check "a closed stdin ends the loop without a quit" "rc=0" "$(echo "$out" | tail -1)"

# Row order after setup plus the copy is sub, empty.txt, photo.jpg, three.txt, so row 2 is the jpeg.
setup
cp "$FIXTURE_ROOT/flea-media-btrfs/photo_0.jpg" "$D/photo.jpg"
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"thumb","rows":[2]}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a thumb request answers a thumbed line" "thumbed" "$(echo "$out" | grep -oE '"t":"thumbed"' | head -1 | cut -d'"' -f4)"
check "the thumbed line names its row" '"row":2' "$(echo "$out" | grep -o '"row":2' | head -1)"
check "the thumbed line carries a file path" "1" "$(echo "$out" | grep -c '"file":"/')"

out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"thumb","rows":[3]}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a row with no thumbnailer answers an empty file" "1" "$(echo "$out" | grep -c '"file":""')"

printf '{"c":"list","path":"%s","first":10}\n{"c":"thumb","rows":[2]}\n{"c":"thumbcancel","rows":[2]}\n{"c":"quit"}\n' "$D" | timeout 30 $BIN --backend >/dev/null
check "a cancelled row is not waited on at quit" "0" "$?"

out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"thumb","rows":[99999]}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a row past the end of the listing is answered with silence" "0" "$(echo "$out" | grep -c '"t":"thumbed"')"

out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"thumb","rows":[0,1,3]}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "every row of a multi-row request is answered" "3" "$(echo "$out" | grep -c '"t":"thumbed"')"
check "a directory row answers an empty file" '"row":0,"file":""' "$(echo "$out" | grep -o '"row":0,"file":""')"

# ExtThumbs, callout 3: off is cache-only. A fake thumbnailer whose only act is touching
# a canary says whether a decode started: the full path touches it, cache-only never does.
setup
printf 'x' > "$D/photo-a.jpg"
printf 'x' > "$D/photo-b.jpg"
mkdir -p "$SB/xdg/thumbnailers"
CANARY="$SB/canary"
printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$CANARY" > "$SB/mark.sh"
chmod +x "$SB/mark.sh"
printf '[Thumbnailer Entry]\nExec=%s %%i %%o\nMimeType=image/jpeg;\n' "$SB/mark.sh" > "$SB/xdg/thumbnailers/mark.thumbnailer"
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"thumb","rows":[2]}\n{"c":"quit"}\n' "$D" | XDG_DATA_HOME="$SB/xdg" $BIN --backend)
check "the full path starts the decoder" "1" "$([ -e "$CANARY" ] && echo 1 || echo 0)"
rm -f "$CANARY"
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"thumb","rows":[3],"cacheOnly":true}\n{"c":"quit"}\n' "$D" | XDG_DATA_HOME="$SB/xdg" $BIN --backend)
check "a cache-only miss answers none" "1" "$(echo "$out" | grep -c '"row":3,"file":""')"
check "and it never starts the decoder" "0" "$([ -e "$CANARY" ] && echo 1 || echo 0)"

# The class rides beside the fsinfo figures, once per directory change and never per row.
out=$(printf '{"c":"list","path":"%s","first":1}\n{"c":"fsinfo"}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "a local directory answers an empty class" "1" "$(echo "$out" | grep -c '"t":"fsinfo".*"class":""')"

# Dotfiles are dropped from the scan itself, so they never reach the sort at all.
setup
: > "$D/.dotfile"
mkdir -p "$D/.dotdir"
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "hidden defaults to false, so the count excludes both dotfile entries" "3" "$(echo "$out" | head -1 | grep -oE '"n":[0-9]+' | cut -d: -f2)"
check "and neither dotfile row is emitted" "0" "$(echo "$out" | sed -n 2p | grep -c '"n":"\.')"

out=$(printf '{"c":"list","path":"%s","first":10,"hidden":false}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "hidden explicitly false is the same as omitted" "3" "$(echo "$out" | head -1 | grep -oE '"n":[0-9]+' | cut -d: -f2)"

out=$(printf '{"c":"list","path":"%s","first":10,"hidden":true}\n{"c":"quit"}\n' "$D" | $BIN --backend)
check "hidden true includes both dotfile entries" "5" "$(echo "$out" | head -1 | grep -oE '"n":[0-9]+' | cut -d: -f2)"
check "the dotfile row is present" "1" "$(echo "$out" | sed -n 2p | grep -c '"n":"\.dotfile"')"
check "the dot-directory row is present and marked a directory" "1" "$(echo "$out" | sed -n 2p | grep -c '"n":"\.dotdir","d":true')"

# Directory sizes: each argument is one stage; pacing allows asynchronous replies between stages.
dirsize_run() {
  ( for stage in "$@"; do
      # $(...) strips a stage's trailing newline, so it comes back here or the next stage glues onto this one's last line.
      printf '%s\n' "$stage"
      sleep 0.3
    done
    printf '{"c":"quit"}\n'
  ) | $BIN --backend
}

DZ_SB="$FIXTURE_ROOT/flea-dirsize-test-$$"
DZ="$DZ_SB/tree"
sandbox_make "$DZ_SB"
mkdir -p "$DZ"
mkdir -p "$DZ/sub"
printf 'abc' > "$DZ/sub/a.txt"
printf 'de' > "$DZ/file.txt"
# Directories sort first, so row 0 is sub and row 1 is file.txt.
out=$(dirsize_run "$(printf '{"c":"list","path":"%s","first":10}\n{"c":"dirsize","rows":[0]}\n' "$DZ")")
check "a dirsize request answers one dirsized line" "1" "$(echo "$out" | grep -c '"t":"dirsized"')"
check "it names the row it was asked for" "1" "$(echo "$out" | grep -c '"row":0')"
check "the walk is not marked partial well inside the 2000 ms deadline" "1" "$(echo "$out" | grep -c '"partial":false')"
bytes=$(echo "$out" | grep -oE '"bytes":[0-9]+' | cut -d: -f2)
[ -n "$bytes" ] && [ "$bytes" -gt 3 ] 2>/dev/null
check "sub's size counts its own entry plus a.txt inside it" "0" "$?"

# A file row is never a valid dirsize target, and neither is one past the end.
out=$(dirsize_run "$(printf '{"c":"list","path":"%s","first":10}\n{"c":"dirsize","rows":[1,99999]}\n' "$DZ")")
check "a file row and an out-of-range row both answer nothing" "0" "$(echo "$out" | grep -c '"t":"dirsized"')"

# A row already answered is re-answered at once from the cache; staged separately, or two requests sent together would just dedup against the queue instead.
out=$(dirsize_run \
    "$(printf '{"c":"list","path":"%s","first":10}\n{"c":"dirsize","rows":[0]}\n' "$DZ")" \
    "$(printf '{"c":"dirsize","rows":[0]}\n')")
check "a repeated ask for an already-answered row still answers" "2" "$(echo "$out" | grep -c '"t":"dirsized"')"

# A queued cancellation suppresses the result even if the worker has already picked up the row.
out=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"dirsize","rows":[0]}\n{"c":"dirsizecancel"}\n{"c":"quit"}\n' "$DZ" | $BIN --backend)
check "a row cancelled before it was walked is never answered" "0" "$(echo "$out" | grep -c '"t":"dirsized"')"

# list and sort both reassign what a row index names, the same reason a list or a sort clears the thumbnail map, see docs/protocol.md "dirsized".
SZ_SB="$FIXTURE_ROOT/flea-dirsize-sort-test-$$"
SZ="$SZ_SB/tree"
sandbox_make "$SZ_SB"
mkdir -p "$SZ"
mkdir -p "$SZ/aaa" "$SZ/zzz"
printf 'abc' > "$SZ/aaa/small.txt"
printf '%050d' 0 > "$SZ/zzz/bigger.txt"
out=$(dirsize_run \
    "$(printf '{"c":"list","path":"%s","first":10}\n{"c":"dirsize","rows":[0]}\n' "$SZ")" \
    "$(printf '{"c":"sort","by":"name","desc":true}\n{"c":"dirsize","rows":[0]}\n')")
check "a sort still answers a fresh dirsize for the row at its new position" "2" "$(echo "$out" | grep -c '"t":"dirsized"')"
first_bytes=$(echo "$out" | grep -oE '"bytes":[0-9]+' | head -1 | cut -d: -f2)
second_bytes=$(echo "$out" | grep -oE '"bytes":[0-9]+' | sed -n 2p | cut -d: -f2)
# aaa sorts first ascending (the list default) and zzz first descending; a stale cache would repeat aaa's answer.
[ -n "$first_bytes" ] && [ -n "$second_bytes" ] && [ "$second_bytes" -gt "$first_bytes" ] 2>/dev/null
check "row 0's answer after the sort is zzz's larger size, not aaa's stale cache entry" "0" "$?"
sandbox_remove "$SZ_SB"; sandbox_remove "$DZ_SB"

# A new folder: one mkdir(2), answered like rename and journaled so z removes it; see docs/protocol.md "mkdir".
MK_SB="$FIXTURE_ROOT/flea-mkdir-test-$$"
MK="$MK_SB/tree"
sandbox_make "$MK_SB"
mkdir -p "$MK"
out=$(printf '{"c":"mkdir","path":"%s","name":"Invoices"}\n{"c":"quit"}\n' "$MK" | $BIN --backend)
check "a named mkdir answers made with the full path" "{\"t\":\"made\",\"ok\":true,\"path\":\"$MK/Invoices\"}" "$out"
check "and the folder is on disk" "yes" "$([ -d "$MK/Invoices" ] && echo yes || echo no)"

# The default name, numbered past a taken one whatever kind of entry holds it.
: > "$MK/New Folder 2"
out=$(printf '{"c":"mkdir","path":"%s"}\n{"c":"mkdir","path":"%s"}\n{"c":"quit"}\n' "$MK" "$MK" | $BIN --backend)
check "a mkdir with no name makes New Folder" "1" "$(echo "$out" | sed -n 1p | grep -c "\"path\":\"$MK/New Folder\"")"
check "the next one steps past the taken number to New Folder 3" "1" "$(echo "$out" | sed -n 2p | grep -c "\"path\":\"$MK/New Folder 3\"")"

# Sample output: {"t":"error","where":"mkdir","path":"/x/Invoices","msg":"a folder or file with that name already exists"}
before=$(ls -A "$MK" | wc -l | tr -d ' ')
out=$(printf '{"c":"mkdir","path":"%s","name":"Invoices"}\n{"c":"quit"}\n' "$MK" | $BIN --backend)
check "a name already taken is refused with a sentence" "{\"t\":\"error\",\"where\":\"mkdir\",\"path\":\"$MK/Invoices\",\"msg\":\"a folder or file with that name already exists\"}" "$out"

mkdir_refusal() {
  printf '{"c":"mkdir","path":"%s","name":"%s"}\n{"c":"quit"}\n' "$MK" "$1" | $BIN --backend | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4
}
for bad in 'a/b' '.' '..'; do
  check "a name of $bad is refused before any syscall" "a name cannot be . or .., or contain a separator" "$(mkdir_refusal "$bad")"
done
long=$(head -c 256 /dev/zero | tr '\0' a)
check "a name past NAME_MAX names the cause in words" "file name is too long" "$(mkdir_refusal "$long")"
check "a relative parent is refused" "a parent must be an absolute path" "$(printf '{"c":"mkdir","path":"relative","name":"x"}\n{"c":"quit"}\n' | $BIN --backend | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4)"
check "a parent that vanished since the listing names the cause in words" "file or folder not found" "$(printf '{"c":"mkdir","path":"%s/gone","name":"x"}\n{"c":"quit"}\n' "$MK" | $BIN --backend | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4)"
check "no refusal made anything" "$before" "$(ls -A "$MK" | wc -l | tr -d ' ')"

# A name of only spaces is legal, the same as it is for rename; the field trims, the wire does not.
printf '{"c":"mkdir","path":"%s","name":"   "}\n{"c":"quit"}\n' "$MK" | $BIN --backend >/dev/null
check "a name of only spaces is created as sent" "yes" "$([ -d "$MK/   " ] && echo yes || echo no)"

# The write bit and not root: this suite runs as a plain user, so 0555 is a real denial.
mkdir -p "$MK/locked"; chmod 0555 "$MK/locked"
out=$(printf '{"c":"mkdir","path":"%s/locked","name":"x"}\n{"c":"quit"}\n' "$MK" | $BIN --backend)
chmod 0755 "$MK/locked"
check "a parent the user cannot write answers permission denied honestly" "permission denied" "$(echo "$out" | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4)"

# Undo, in the one process that holds the journal: an empty new folder goes, a filled one stays.
out=$(printf '{"c":"mkdir","path":"%s","name":"empty"}\n{"c":"undo"}\n{"c":"quit"}\n' "$MK" | $BIN --backend)
check "undo names mkdir as what it reversed" '{"t":"undone","op":"mkdir","ok":true}' "$(echo "$out" | sed -n 2p)"
check "and the empty folder is gone" "no" "$([ -e "$MK/empty" ] && echo yes || echo no)"
# The file lands between the two requests, from outside, the way a user would put it there.
out=$( ( printf '{"c":"mkdir","path":"%s","name":"filled"}\n' "$MK"; sleep 0.3; : > "$MK/filled/theirs.txt"; printf '{"c":"undo"}\n{"c":"quit"}\n' ) | $BIN --backend)
check "undo refuses a new folder the user has filled" "the new folder has been filled since, so undo left it in place" "$(echo "$out" | sed -n 2p | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4)"
check "and what they put inside is still there" "yes" "$([ -f "$MK/filled/theirs.txt" ] && echo yes || echo no)"
sandbox_remove "$MK_SB"

# Names a transfer would land on, asked first, then one choice for them; see docs/protocol.md "collisions".
CO_SB="$FIXTURE_ROOT/flea-collide-test-$$"
CO="$CO_SB/tree"
collide_fixture() {
  sandbox_remove "$CO_SB"
  sandbox_make "$CO_SB"
  mkdir -p "$CO/from/album" "$CO/to/album" "$CO_SB/data"
  printf 'yours' > "$CO/from/photo.png"
  printf 'there' > "$CO/to/photo.png"
  printf 'notes' > "$CO/from/notes.txt"
}
collide_ask() {
  printf '{"c":"collisions","id":%s,"paths":["%s/from/photo.png","%s/from/notes.txt","%s/from/album"],"dest":"%s/to"}\n' "$1" "$CO" "$CO" "$CO" "$CO"
}
collide_transfer() {
  printf '{"c":"transfer","op":"%s","paths":["%s/from/photo.png","%s/from/notes.txt"],"dest":"%s/to"%s}\n' "${2:-copy}" "$CO" "$CO" "$CO" "$1"
}
# One backend session run in steps, so quit is sent only once the reply it waits for is out and a loaded box cannot cancel a transfer.
# Sample steps: '{"c":"collisions",...}' 'wait:"t":"collisions"' 'do:printf x > "$CO/to/notes.txt"' 'wait:"t":"transferdone"'
backend_steps() {
  local out="$CO_SB/steps.out" in="$CO_SB/steps.in" step waited pid
  rm -f "$out" "$in"
  mkfifo "$in"
  : > "$out"
  ${step_wrap[@]+"${step_wrap[@]}"} $BIN --backend < "$in" > "$out" &
  pid=$!
  exec 8> "$in"
  for step in "$@"; do
    case "$step" in
      wait:*)
        waited=0
        until grep -qF -- "${step#wait:}" "$out"; do
          waited=$((waited + 1))
          [ "$waited" -le "$STEP_WAIT_TENTHS" ] || { echo "backend_steps: no ${step#wait:} within the wait" >&2; break; }
          sleep 0.1
        done ;;
      do:*) eval "${step#do:}" ;;
      *) printf '%s\n' "$step" >&8 ;;
    esac
  done
  printf '{"c":"quit"}\n' >&8
  exec 8>&-
  wait "$pid"
  cat "$out"
  rm -f "$out" "$in"
}
# Ten seconds, far past a transfer of three small files on a loaded box, and short enough to fail a stuck one.
STEP_WAIT_TENTHS=100
# What backend_steps runs the backend under, empty but for the Replace cases below.
step_wrap=()
collide_fixture
# Sample output: {"t":"collisions","id":7,"total":2,"names":[{"n":"photo.png","d":false,"i":"image-x-generic"},{"n":"album","d":true,"i":"folder"}]}
out=$(backend_steps "$(collide_ask 7)" 'wait:"t":"collisions"')
check "collisions counts only the names the destination holds" '"total":2' "$(echo "$out" | grep -oE '"total":[0-9]+')"
check "and names them in request order" '"n":"photo.png","n":"album"' "$(echo "$out" | grep -oE '"n":"[^"]+"' | paste -sd, -)"
check "a folder carries the directory bit and its mark" "1" "$(echo "$out" | grep -c '{"n":"album","d":true,"i":"folder"}')"
out=$(backend_steps "$(printf '{"c":"collisions","id":8,"paths":["%s/from/photo.png"],"dest":"relative"}' "$CO")" 'wait:"t":"collisions"')
check "an unusable destination asks nothing and leaves the error to the transfer" '{"t":"collisions","id":8,"total":0,"names":[]}' "$out"
# Rows resolve against the listing the way a transfer's do: album, notes.txt, photo.png, folders first.
out=$(backend_steps "$(printf '{"c":"list","path":"%s/from","first":10}' "$CO")" 'wait:"t":"rows"' "$(printf '{"c":"collisions","id":9,"rows":[2],"dest":"%s/to"}' "$CO")" 'wait:"t":"collisions"')
check "a rows question names the row's own file" '"id":9,"total":1,"names":[{"n":"photo.png"' "$(echo "$out" | grep -oE '"id":9,"total":[0-9]+,"names":\[\{"n":"[^"]+"')"

out=$(backend_steps "$(collide_ask 7)" 'wait:"t":"collisions"' "$(collide_transfer ',"collide":"keep","collideId":7')" 'wait:"t":"transferdone"')
check "keep both copies every item" '"ok":2,"failed":0,"skipped":0' "$(echo "$out" | grep -oE '"ok":[0-9]+,"failed":[0-9]+,"skipped":[0-9]+')"
check "and names the incoming one as Duplicate does" "yours" "$(cat "$CO/to/photo copy.png" 2>/dev/null)"
check "and leaves the one already there" "there" "$(cat "$CO/to/photo.png")"

collide_fixture
out=$(backend_steps "$(collide_ask 7)" 'wait:"t":"collisions"' "$(collide_transfer ',"collide":"skip","collideId":7')" 'wait:"t":"transferdone"')
check "skip counts the collision in skipped and copies the rest" '"ok":1,"failed":0,"skipped":1' "$(echo "$out" | grep -oE '"ok":[0-9]+,"failed":[0-9]+,"skipped":[0-9]+')"
check "and the name it skipped is untouched" "there" "$(cat "$CO/to/photo.png")"
check "and the free name was copied" "notes" "$(cat "$CO/to/notes.txt" 2>/dev/null)"

# A name that appears after the question is refused whatever the choice, exactly as before.
collide_fixture
out=$(backend_steps "$(collide_ask 7)" 'wait:"t":"collisions"' 'do:printf "arrived later" > "$CO/to/notes.txt"' "$(collide_transfer ',"collide":"keep","collideId":7')" 'wait:"t":"transferdone"')
check "a name that appeared after the question is refused" '"name":"notes.txt","ok":false,"err":"already exists"' "$(echo "$out" | grep -oE '"name":"notes.txt","ok":false,"err":"[^"]+"')"
check "and never replaced" "arrived later" "$(cat "$CO/to/notes.txt")"
check "while the name the question saw was kept both" "yours" "$(cat "$CO/to/photo copy.png" 2>/dev/null)"
# Copy to asks about its menu's selection, and its dialog's close expires that selection before the answer.
collide_fixture
# A snapshot publishes from the menu worker and answers nothing, so its step alone waits a fixed second; the app takes it when the menu opens.
out=$(backend_steps "$(printf '{"c":"list","path":"%s/from","first":10}' "$CO")" 'wait:"t":"rows"' '{"c":"menuaction","op":"snapshot","id":4,"rows":[2]}' 'do:sleep 1' \
  "$(printf '{"c":"collisions","id":7,"menuId":4,"dest":"%s/to"}' "$CO")" 'wait:"t":"collisions"' '{"c":"menuaction","op":"close","id":4}' \
  "$(printf '{"c":"transfer","op":"copy","menuId":4,"dest":"%s/to"}' "$CO")" 'wait:Menu selection expired' \
  "$(printf '{"c":"transfer","op":"copy","menuId":4,"dest":"%s/to","collide":"keep","collideId":7}' "$CO")" 'wait:"t":"transferdone"' \
  "$(printf '{"c":"collisions","id":8,"menuId":4,"dest":"%s/to"}' "$CO")" 'wait:"id":8')
check "a menu question names the menu's own selection" '"id":7,"total":1,"names":[{"n":"photo.png"' "$(echo "$out" | grep -oE '"id":7,"total":[0-9]+,"names":\[\{"n":"[^"]+"')"
check "the close expired the live selection in this same process" "1" "$(echo "$out" | grep -c '"where":"transfer","path":"","msg":"Menu selection expired; reopen the menu."')"
check "and its transfer runs on what it captured after the menu closed" '"ok":1,"failed":0,"skipped":0' "$(echo "$out" | grep -oE '"ok":[0-9]+,"failed":[0-9]+,"skipped":[0-9]+')"
check "keeping both beside the name that was there" "yours" "$(cat "$CO/to/photo copy.png" 2>/dev/null)"
check "a menu selection that is not there asks nothing" '{"t":"collisions","id":8,"total":0,"names":[]}' "$(echo "$out" | grep '"id":8')"
# From here a case can send replace, so the backend runs with HOME and XDG_DATA_HOME in this sandbox and a private bus that starts gvfsd with them.
collide_env=(env HOME="$CO_SB" XDG_DATA_HOME="$CO_SB/data")
! command -v dbus-run-session >/dev/null || collide_env+=(dbus-run-session --)
step_wrap=("${collide_env[@]}")
# A choice naming no question covers nothing, and a transfer with no choice at all is today's.
collide_fixture
out=$(backend_steps "$(collide_transfer ',"collide":"replace","collideId":99')" 'wait:"t":"transferdone"')
check "a choice for a question never asked is refused" '"err":"already exists"' "$(echo "$out" | grep -oE '"err":"[^"]+"')"
check "and leaves the name already there untouched" "there" "$(cat "$CO/to/photo.png")"
collide_fixture
out=$(backend_steps "$(collide_ask 7)" 'wait:"t":"collisions"' "$(collide_transfer ',"collide":"replace","collideId":99')" 'wait:"t":"transferdone"')
check "a choice naming another id than the question kept is refused" '"name":"photo.png","ok":false,"err":"already exists"' "$(echo "$out" | grep -oE '"name":"photo.png","ok":false,"err":"[^"]+"')"
check "and the kept question's name is untouched" "there" "$(cat "$CO/to/photo.png")"
collide_fixture
out=$(backend_steps "$(collide_transfer '')" 'wait:"t":"transferdone"')
check "and so is a transfer with no choice at all" '"err":"already exists"' "$(echo "$out" | grep -oE '"err":"[^"]+"')"
check "neither touched the name already there" "there" "$(cat "$CO/to/photo.png")"

# Same folder: a copy keeps both under Duplicate's name, a move onto itself is no error and no work.
collide_fixture
out=$(backend_steps "$(printf '{"c":"transfer","op":"copy","paths":["%s/to/photo.png"],"dest":"%s/to","collide":"refuse"}' "$CO" "$CO")" 'wait:"t":"transferdone"')
check "a copy into its own folder keeps both" "there" "$(cat "$CO/to/photo copy.png" 2>/dev/null)"
out=$(backend_steps "$(printf '{"c":"transfer","op":"move","paths":["%s/to/photo.png"],"dest":"%s/to","collide":"refuse"}' "$CO" "$CO")" 'wait:"t":"transferdone"')
check "a move onto itself is skipped, not failed" '"ok":0,"failed":0,"skipped":1' "$(echo "$out" | grep -oE '"ok":[0-9]+,"failed":[0-9]+,"skipped":[0-9]+')"
out=$(backend_steps "$(printf '{"c":"transfer","op":"copy","paths":["%s/to/photo.png"],"dest":"%s/to"}' "$CO" "$CO")" 'wait:"t":"transferdone"')
check "an older client's same-folder copy is refused as before" '"err":"already in that folder"' "$(echo "$out" | grep -oE '"err":"[^"]+"')"

# A move whose Replace would trash the folder holding its own source is refused before any trash is tried.
collide_fixture
mkdir -p "$CO/to/album/album"
printf 'inner' > "$CO/to/album/album/in.txt"
out=$(backend_steps "$(printf '{"c":"collisions","id":7,"paths":["%s/to/album/album"],"dest":"%s/to"}' "$CO" "$CO")" 'wait:"t":"collisions"' \
  "$(printf '{"c":"transfer","op":"move","paths":["%s/to/album/album"],"dest":"%s/to","collide":"replace","collideId":7}' "$CO" "$CO")" 'wait:"t":"transferdone"')
check "a move replacing the folder it sits in is refused" "the item already there holds the one being moved in, so it was not replaced" "$(echo "$out" | grep -oE '"err":"[^"]+"' | cut -d'"' -f4)"
check "and both folders stay where they were" "inner" "$(cat "$CO/to/album/album/in.txt" 2>/dev/null)"

# gio alone decides which branch runs, never the output under test: a scratch file it trashes here, then lists.
collide_trash_state() {
  collide_fixture
  printf 'probe' > "$CO_SB/probe"
  "${collide_env[@]}" sh -c 'gio trash -- "$1" >/dev/null 2>&1; [ ! -e "$1" ] || { echo refuses; exit; }
    if gio trash --list 2>/dev/null | grep -qF "$1"; then echo listed; else echo unlisted; fi' _ "$CO_SB/probe"
}
trash_state=$(collide_trash_state)
echo "note gio trash in this sandbox: $trash_state (a box with gvfs lists, a build container only trashes)"
for op in copy move; do
  collide_fixture
  undone='wait:"t":"undone"'
  [ "$trash_state" = unlisted ] && undone='wait:"where":"undo"'
  out=$(backend_steps "$(collide_ask 7)" 'wait:"t":"collisions"' "$(collide_transfer ',"collide":"replace","collideId":7' "$op")" 'wait:"t":"transferdone"' \
    'do:cat "$CO/to/photo.png" > "$CO_SB/landed"; cat "$CO_SB/data/Trash/files/photo.png" > "$CO_SB/trashed" 2>/dev/null; if [ -e "$CO/from/photo.png" ]; then echo stayed; else echo left; fi > "$CO_SB/source"' \
    '{"c":"undo"}' "$undone")
  counts=$(echo "$out" | grep -oE '"ok":[0-9]+,"failed":[0-9]+,"skipped":[0-9]+')
  if [ "$trash_state" = refuses ]; then
    check "$op: a trash that refuses replaces nothing" '"ok":1,"failed":1,"skipped":0' "$counts"
    check "$op: and says so" "the item already there could not be moved to Trash, so nothing was replaced" "$(echo "$out" | grep -oE '"err":"[^"]+"' | cut -d'"' -f4)"
    check "$op: and the item that was there is there now" "there" "$(cat "$CO/to/photo.png")"
    continue
  fi
  check "$op: replace lands every item" '"ok":2,"failed":0,"skipped":0' "$counts"
  check "$op: the incoming photo took the name" "yours" "$(cat "$CO_SB/landed" 2>/dev/null)"
  check "$op: and the one it replaced went to this sandbox's trash" "there" "$(cat "$CO_SB/trashed" 2>/dev/null)"
  if [ "$op" = move ]; then
    check "move: the source left its folder" "left" "$(cat "$CO_SB/source" 2>/dev/null)"
    check "move: and undo puts it back where it was" "yours" "$(cat "$CO/from/photo.png" 2>/dev/null)"
  else
    check "copy: the source stays in its folder" "stayed" "$(cat "$CO_SB/source" 2>/dev/null)"
  fi
  if [ "$trash_state" = listed ]; then
    check "$op: and one undo reverses the whole transfer" "{\"t\":\"undone\",\"op\":\"$op\",\"ok\":true}" "$(echo "$out" | grep '"t":"undone"')"
    check "$op: restoring the item that was there to its name" "there" "$(cat "$CO/to/photo.png" 2>/dev/null)"
    check "$op: and out of the trash" "no" "$([ -e "$CO_SB/data/Trash/files/photo.png" ] && echo yes || echo no)"
  else
    check "$op: a trash gio cannot list leaves undo nothing to restore by, and it says so" "this item was trashed without a trash entry, so it cannot be restored" "$(echo "$out" | grep '"where":"undo"' | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4)"
    check "$op: so the item that was there waits in the sandbox trash" "there" "$(cat "$CO_SB/data/Trash/files/photo.png" 2>/dev/null)"
    check "$op: while undo still took the incoming photo off the name" "no" "$([ -e "$CO/to/photo.png" ] && echo yes || echo no)"
  fi
done
step_wrap=()
sandbox_remove "$CO_SB"

# An op that names neither compress nor extract used to fall through to extract, which would have
# unpacked into a destination the caller never meant. It is refused by name and starts no job.
out=$(printf '{"c":"archive","op":"bogus","paths":[],"path":"%s/three.txt","dest":"%s/out","format":"zip"}\n{"c":"quit"}\n' "$D" "$D" | $BIN --backend)
check "an archive op that names neither is refused by name" "op must be compress or extract" "$(echo "$out" | grep -oE '"msg":"[^"]+"' | cut -d'"' -f4)"
check "and the refusal names the op it was given" "bogus" "$(echo "$out" | grep -oE '"path":"[^"]*"' | head -1 | cut -d'"' -f4)"
check "and no job was started for it" "0" "$(echo "$out" | grep -c '"t":"archivestarted"')"

# Issue 68: the listed directory is watched, so a change made from outside answers a changed line.
# The only unsolicited line on the wire, so every case here is driven by a real create, rename or
# delete landing between two requests rather than by a request asking for it.
WT_SB="$FIXTURE_ROOT/flea-watch-test-$$"
WT="$WT_SB/tree"
OTHER="$WT_SB/other"
sandbox_make "$WT_SB"
mkdir -p "$WT" "$OTHER"
printf 'a' > "$WT/alpha.txt"

# The change runs argv-direct between the list and the quit, which is where an outside write lands.
watch_run() {
  local dir="$1"
  shift
  ( printf '{"c":"list","path":"%s","first":10}\n' "$dir"
    sleep 0.4
    "$@"
    sleep 0.6
    printf '{"c":"quit"}\n'
  ) | $BIN --backend
}

# One create can wake the reader once or twice (the create, then the close and the timestamp), so
# the assertion is that the wire said something and did not say it per event, never an exact count.
check_changed() {
  local label="$1" out="$2" low="$3" high="$4"
  local n
  n=$(echo "$out" | grep -c '"t":"changed"')
  [ "$n" -ge "$low" ] && [ "$n" -le "$high" ]
  check "$label (saw $n)" "0" "$?"
}

burst_of_creates() {
  local i
  for i in $(seq 1 100); do
    : > "$WT/burst-$i.txt"
  done
}

out=$(watch_run "$WT" touch "$WT/created.txt")
check_changed "a create from outside answers a changed line" "$out" 1 3
check "and that line names the directory being listed" "$WT" "$(echo "$out" | grep '"t":"changed"' | head -1 | grep -oE '"path":"[^"]*"' | cut -d'"' -f4)"
check "and the listing itself is not re-sent, because the client asks for that" "1" "$(echo "$out" | grep -c '"t":"listed"')"

out=$(watch_run "$WT" mv "$WT/created.txt" "$WT/renamed.txt")
check_changed "a rename from outside answers a changed line" "$out" 1 3

out=$(watch_run "$WT" rm -f "$WT/renamed.txt")
check_changed "a delete from outside answers a changed line" "$out" 1 3

out=$(watch_run "$WT" mkdir "$WT/made")
check_changed "a new directory from outside answers a changed line" "$out" 1 3
rmdir "$WT/made"

# The negative control, which is what proves the watch is on the listed directory and not on the box.
out=$(watch_run "$WT" touch "$OTHER/elsewhere.txt")
check_changed "a change in a directory that is not listed answers nothing" "$out" 0 0

# Navigating drops the old watch. Without the descriptor check in src/backend/watch.rs the removal's
# own IN_IGNORED would answer here, so this case reddens on exactly the bug it was written for.
out=$( ( printf '{"c":"list","path":"%s","first":10}\n' "$WT"
         sleep 0.4
         printf '{"c":"list","path":"%s","first":10}\n' "$OTHER"
         sleep 0.6
         touch "$WT/after-leaving.txt"
         sleep 0.6
         printf '{"c":"quit"}\n' ) | $BIN --backend)
check_changed "a change in the directory just left answers nothing" "$out" 0 0
check "and moving to a new directory answers nothing on its own" "2" "$(echo "$out" | grep -c '"t":"listed"')"

# A search replaces the listing with matches, which are not a directory, so nothing is watched. The
# list comes first on purpose: without a watch to stop, this case passes with the stop deleted.
out=$( ( printf '{"c":"list","path":"%s","first":10}\n' "$WT"
         sleep 0.4
         printf '{"c":"search","path":"%s","query":"alpha"}\n' "$WT"
         sleep 0.6
         touch "$WT/during-search.txt"
         sleep 0.6
         printf '{"c":"quit"}\n' ) | $BIN --backend)
check_changed "a change under a search answers nothing, because matches are not a directory" "$out" 0 0

# listpaths lists a set the client named, whose base is the root; watching that would be a lie.
out=$( ( printf '{"c":"list","path":"%s","first":10}\n' "$WT"
         sleep 0.4
         printf '{"c":"listpaths","paths":["%s/alpha.txt"],"first":10}\n' "$WT"
         sleep 0.6
         touch "$WT/during-listpaths.txt"
         sleep 0.6
         printf '{"c":"quit"}\n' ) | $BIN --backend)
check_changed "a change under listpaths answers nothing, because named paths are not a directory" "$out" 0 0

# One bit of MASK each, isolated: a chmod is IN_ATTRIB alone, and appending to a file that already
# exists is IN_CLOSE_WRITE alone, since IN_MODIFY is deliberately not in the mask.
append_to_alpha() {
  printf 'x' >> "$WT/alpha.txt"
}

out=$(watch_run "$WT" chmod 0640 "$WT/alpha.txt")
check_changed "a chmod from outside answers a changed line" "$out" 1 3
chmod 0644 "$WT/alpha.txt"

out=$(watch_run "$WT" append_to_alpha)
check_changed "a writer closing a file it appended to answers a changed line" "$out" 1 3

# The watched directory itself: a move keeps the watch, which IN_MOVE_SELF is what reports, and a
# delete takes the watch with it, which the kernel reports as IN_IGNORED whatever the mask holds.
SELFDIR="$WT_SB/self-move"
mkdir -p "$SELFDIR"
out=$(watch_run "$SELFDIR" mv "$SELFDIR" "$WT_SB/self-moved")
check_changed "moving the watched directory itself answers a changed line" "$out" 1 3

SELFDEL="$WT_SB/self-delete"
mkdir -p "$SELFDEL"
out=$(watch_run "$SELFDEL" rmdir "$SELFDEL")
check_changed "deleting the watched directory answers a changed line, from the watch's own removal" "$out" 1 3

# A failed list answers its error and the directory still on screen keeps answering changed. Two changes
# a burst apart, because a watch the failure took away answers the one line its own removal made.
out=$( ( printf '{"c":"list","path":"%s","first":10}\n' "$WT"
         sleep 0.4
         printf '{"c":"list","path":"/no/such/directory","first":10}\n'
         sleep 0.4
         touch "$WT/after-a-failed-list-one.txt"
         sleep 1.0
         touch "$WT/after-a-failed-list-two.txt"
         sleep 0.8
         printf '{"c":"quit"}\n' ) | $BIN --backend)
check "a failed list still answers its error" "1" "$(echo "$out" | grep -c '"t":"error"')"
check_changed "and the directory still on screen is still watched after it" "$out" 2 4

# inotify answers the descriptor it already holds, so a commit that dropped it would unwatch the folder.
out=$( ( printf '{"c":"list","path":"%s","first":10}\n' "$WT"
         sleep 0.5
         printf '{"c":"list","path":"%s","first":10}\n' "$WT"
         sleep 1.5
         printf '{"c":"quit"}\n' ) | $BIN --backend)
check_changed "re-listing the same directory answers nothing on its own" "$out" 0 0

# Two changes, a second apart so each is its own burst: a dead watch answers the one spurious line
# its own removal made and nothing else, which one change alone could not be told apart from.
out=$( ( printf '{"c":"list","path":"%s","first":10}\n' "$WT"
         sleep 0.5
         printf '{"c":"list","path":"%s","first":10}\n' "$WT"
         sleep 0.5
         touch "$WT/after-a-relist-one.txt"
         sleep 1.0
         touch "$WT/after-a-relist-two.txt"
         sleep 0.8
         printf '{"c":"quit"}\n' ) | $BIN --backend)
check_changed "and two changes after that re-list are both answered" "$out" 2 4

# A burst is coalesced by the reader, so a hundred creates cost a handful of lines, not a hundred.
out=$(watch_run "$WT" burst_of_creates)
check_changed "a hundred creates answer a handful of changed lines, not a hundred" "$out" 1 10
sandbox_remove "$WT_SB"

# A test-only opendir barrier pins a real size worker until the parent releases it. These
# requests must finish while it is blocked; no sleeps or tree-size guesses choose the race.
ASYNC_SB="$FIXTURE_ROOT/flea-dirsize-async-$$"
sandbox_make "$ASYNC_SB"
python3 tests/dirsize-async.py "$ASYNC_SB" "$BIN"
check "running size jobs allow cancel, list, sort and quit without stale replies" "0" "$?"
sandbox_remove "$ASYNC_SB"

# The folder jump through the real binary, with a zoxide of this suite's own first on PATH, so the
# operator's database is never read. The missing favourite and zoxide row are dropped, the recent file
# stands for its folder, each folder is answered once, in the first source that names it, and zoxide's
# score rides along for every folder it ranks, the favourite it also ranks included.
JUMP_BIN="$SB/jump-bin"
NO_ZOXIDE="$SB/no-zoxide"
mkdir -p "$JUMP_BIN" "$NO_ZOXIDE" "$D/ranked"
cat > "$JUMP_BIN/zoxide" <<EOF
#!/bin/sh
[ "\$*" = "query --list --all --score" ] || exit 3
printf '  %s %s\n' 9.5 '$D/ranked' 4.0 '$D/gone' 2.0 '$D/sub'
EOF
chmod +x "$JUMP_BIN/zoxide"
jump_run() {
  ( printf '{"c":"jump","id":7,"favourites":["%s/sub","%s/nope"],"recent":["%s/three.txt"]}\n' "$D" "$D" "$D"
    sleep 1
    printf '{"c":"quit"}\n' ) | PATH="$1" $BIN --backend 2>/dev/null | grep '"t":"jumped"' | sed 's/,"ms":[0-9.]*}$//'
}
check "jump answers each source's existing folders once, in order" \
  "{\"t\":\"jumped\",\"id\":7,\"favourites\":[\"$D/sub\"],\"zoxide\":[\"$D/ranked\"],\"recent\":[\"$D\"],\"frecency\":{\"$D/sub\":2,\"$D/ranked\":9.5}" \
  "$(jump_run "$JUMP_BIN:$PATH")"
check "with no zoxide installed its source is empty and nothing else changes" \
  "{\"t\":\"jumped\",\"id\":7,\"favourites\":[\"$D/sub\"],\"zoxide\":[],\"recent\":[\"$D\"],\"frecency\":{}" \
  "$(jump_run "$NO_ZOXIDE")"

# A photos walk streams one DCIM folder's photos and videos newest first, through the
# same listed/searching/searched lines a search uses. The text file is not a photo, the
# directory itself is never a row, and every row names its path relative to DCIM.
PHOTOS="$SB/photos"
mkdir -p "$PHOTOS/DCIM/sub"
printf 'a' > "$PHOTOS/DCIM/a.jpg"
printf 'b' > "$PHOTOS/DCIM/sub/b.mov"
printf 'notes' > "$PHOTOS/DCIM/notes.txt"
touch -d "2026-01-01 10:00:00" "$PHOTOS/DCIM/a.jpg"
touch -d "2026-06-01 10:00:00" "$PHOTOS/DCIM/sub/b.mov"
out=$(( printf '{"c":"photos","path":"%s/DCIM"}\n' "$PHOTOS"
  sleep 2
  printf '{"c":"window","start":0,"count":10}\n'
  sleep 1
  printf '{"c":"quit"}\n' ) | $BIN --backend)
check "a photos walk opens with an empty listed line" "0" "$(echo "$out" | grep '"t":"listed"' | grep -oE '"n":[0-9]+' | cut -d: -f2)"
check "and ends with a searched line carrying the find" "{\"t\":\"searched\",\"n\":2" "$(echo "$out" | grep -oE '\{"t":"searched","n":[0-9]+' | head -1)"
check "the walk is not a cancel" "false" "$(echo "$out" | grep '"t":"searched"' | grep -oE '"cancelled":[a-z]+' | cut -d: -f2)"
check "newest sorts first" "sub/b.mov a.jpg" "$(echo "$out" | grep '"t":"rows"' | tail -1 | grep -oE '"n":"[^"]+"' | cut -d'"' -f4 | tr '\n' ' ' | sed 's/ $//')"

# A photoscancel with no walk running does nothing and answers nothing.
out=$(printf '{"c":"photoscancel"}\n{"c":"quit"}\n' | $BIN --backend)
check "a photoscancel with no walk answers nothing" "" "$out"

# No per-key cleanup: the cache is inside the sandbox, so it goes when the sandbox does.
sandbox_remove "$SB"
exit $fail
