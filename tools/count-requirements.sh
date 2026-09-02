#!/usr/bin/env bash
# count-requirements.sh - count the requirement rows and their check status.
#
# ⭐ WHAT DEFECT THIS EXISTS TO CATCH
#
# A coverage table written from memory. The first draft of the table in
# docs/requirements.md said 67 requirements, 20 checked and 45 unchecked. The
# real numbers were 72, 33 and 35: every one wrong, in a document whose whole
# job is to say honestly what is and is not verified.
#
# ⛔ A number in a document that nothing derives is a number that drifts the
# first time a row is added. This derives it.
#
# Usage:
#   count-requirements.sh            print the table
#   count-requirements.sh --check    ⭐ exit 1 if the document disagrees
#
# Exit codes: 0 counted (and agreed, with --check), 1 the document disagrees,
# 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}" || exit 2
DOC="${ROOT}/docs/requirements.md"
[ -f "${DOC}" ] || { echo "missing ${DOC}" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 2; }

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

DOC="${DOC}" CHECK="${CHECK}" python3 - <<'PY'
import os, re, sys

doc = os.environ["DOC"]
check = os.environ["CHECK"] == "1"
text = open(doc, encoding="utf-8").read()

# A requirement row is a table row whose first cell is R<n>.<n>. Anything else
# in the file, including the coverage table itself, is not counted.
rows = re.findall(r'^\| (R\d+\.\d+) \|(.*)$', text, re.M)

buckets = {"checked": 0, "none yet": 0, "reading": 0, "partial": 0, "not run": 0}
for _, rest in rows:
    if "none yet" in rest:
        buckets["none yet"] += 1
    elif "⚠ reading" in rest:
        buckets["reading"] += 1
    elif "⚠ partial" in rest:
        buckets["partial"] += 1
    elif "not run here" in rest:
        buckets["not run"] += 1
    else:
        buckets["checked"] += 1

total = len(rows)
print(f"requirements stated          {total}")
print(f"with an automated check      {buckets['checked']}")
print(f"with 'none yet'              {buckets['none yet']}")
print(f"checked by reading only      {buckets['reading']}")
print(f"partial                      {buckets['partial']}")
print(f"specified but not run here   {buckets['not run']}")
print(f"sum                          {sum(buckets.values())}")

if sum(buckets.values()) != total:
    print("::error:: bucket sum does not equal the row count", file=sys.stderr)
    sys.exit(1)

if not check:
    sys.exit(0)

# ⭐ Compare against the numbers the document publishes, so the two cannot
# drift apart silently. The coverage table's rows are matched by their label.
want = {}
for label, key in [
    (r"requirements stated", "total"),
    (r"with an automated check today", "checked"),
    (r"with `none yet`", "none yet"),
    (r"checked by reading only", "reading"),
    (r"partial", "partial"),
    (r"specified but not run here", "not run"),
]:
    m = re.search(r'^\|[^|]*' + label + r'[^|]*\|\s*(\d+)\s*\|$', text, re.M)
    if m:
        want[key] = int(m.group(1))

got = dict(buckets); got["total"] = total
bad = 0
for key, value in want.items():
    if got.get(key) != value:
        print(f"::error:: document says {key} = {value}, counted {got.get(key)}", file=sys.stderr)
        bad = 1
if not want:
    print("::error:: could not find the coverage table to compare against", file=sys.stderr)
    bad = 1

# ⭐ The same pair of numbers is quoted OUTSIDE requirements.md, and those
# copies drifted the moment three rows were added: the coverage table was
# regenerated and SECURITY.md and lessons.md were not. Checking only the
# defining document made the guard look green while two live pages were
# wrong, which is the exact failure conventions.md §5 warns about.
#
# ⚠ docs/history/ is excluded on purpose. It records what a number WAS on a
# date, and rewriting that would destroy the record the tree keeps.
CITATION_PATTERNS = [
    re.compile(r'(\d+)\s+of\s+(\d+)\s+requirements'),
    re.compile(r'(\d+)\s+automated checks out of\s+(\d+)\s+requirements'),
]

cited = 0
for dirpath, dirnames, filenames in os.walk("."):
    dirnames[:] = [d for d in dirnames
                   if d not in {".git", ".tmp", "references", "out", ".work"}]
    if os.path.normpath(dirpath).startswith(os.path.join("docs", "history")):
        continue
    for fn in filenames:
        if not fn.endswith(".md"):
            continue
        path = os.path.normpath(os.path.join(dirpath, fn))
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            for pat in CITATION_PATTERNS:
                for c, t in pat.findall(line):
                    cited += 1
                    if int(t) != total or int(c) != buckets["checked"]:
                        print(f"::error:: {path}:{n} says {c} of {t} requirements; "
                              f"counted {buckets['checked']} of {total}", file=sys.stderr)
                        bad = 1

print(f"citations checked outside the table   {cited}")
sys.exit(bad)
PY
