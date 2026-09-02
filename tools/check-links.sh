#!/usr/bin/env bash
# check-links.sh - the mechanical half of reviewing this documentation tree.
#
# ⭐ WHAT DEFECT THIS CATCHES
#
# Four failure modes, each of which has been observed in documentation sets
# and none of which a reading reliably catches:
#
#   1. A relative link that resolves to nothing. The reader follows it and
#      finds a 404, which teaches them to stop following links.
#   2. A cited path that does not exist. A document naming a file is making a
#      claim, and an unchecked claim rots the first time something is renamed.
#   3. A page unreachable from README.md. The deliverable's contract is that
#      an implementer reads only the README and follows its links, so a page
#      no path from README reaches is a page that contract does not deliver.
#   4. Banned vocabulary: words that assert quality instead of demonstrating
#      it, and em dashes, which this tree does not use.
#
# ⛔ WHAT IT CANNOT CATCH: whether a claim is TRUE. That is a reading, and it
# belongs to the review pass. A guard that tried to verify prose would either
# pass vacuously or refuse legitimate writing.
#
# Usage:
#   check-links.sh              check, print a report
#   check-links.sh --quiet      only print failures
#   check-links.sh --json       machine-readable summary
#
# Exit codes: 0 everything resolves, 1 a check failed, 2 could not run.
# ⛔ Read the exit code from this process, unpiped.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}" || exit 2
command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 2; }

QUIET=0; JSON=0
for a in "$@"; do
  case "$a" in
    --quiet) QUIET=1 ;;
    --json)  JSON=1 ;;
    -h|--help) awk 'NR>1 && /^#/ { sub(/^# ?/,""); print; next } NR>1 { exit }' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

QUIET="${QUIET}" JSON="${JSON}" python3 - <<'PY'
import json, os, re, sys

quiet = os.environ.get("QUIET") == "1"
as_json = os.environ.get("JSON") == "1"

# Files this tree authors. The mined corpus under references/ is somebody
# else's text and is deliberately not held to these rules.
DOC_ROOTS = ("README.md", "AGENTS.md", "CHANGELOG.md", "SECURITY.md")
# ⛔ Prune by PATH, not by basename. Pruning every directory named
# "references" also pruned docs/history/references/, a 16 KB authored
# document in this tree, which was silently exempt from every check here
# until review pass 6 counted the files by hand. The mined corpus this
# means to skip is the one at the repository root.
SKIP_NAMES = {".git", ".tmp", "node_modules", "out", ".work"}
SKIP_PATHS = {os.path.normpath("./references")}


def prune(dirpath, dirnames):
    keep = []
    for d in dirnames:
        if d in SKIP_NAMES:
            continue
        if os.path.normpath(os.path.join(dirpath, d)) in SKIP_PATHS:
            continue
        keep.append(d)
    return keep

BANNED_WORDS = [
    "seamless", "blazing", "effortless", "robust", "powerful", "cutting-edge",
    "state-of-the-art", "world-class", "elegant", "revolutionary",
    "game-changing", "rock-solid", "bulletproof", "lightning-fast",
]

docs, others = [], []
for dirpath, dirnames, filenames in os.walk("."):
    dirnames[:] = prune(dirpath, dirnames)
    for fn in filenames:
        p = os.path.normpath(os.path.join(dirpath, fn))
        if fn.endswith(".md"):
            docs.append(p)
        elif fn.endswith((".sh", ".py")):
            others.append(p)

link_re = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')
code_span_re = re.compile(r'`([^`\n]+)`')
fence_re = re.compile(r'^\s*```')


def strip_fences(text):
    """Drop fenced blocks.

    ⛔ A link or a path inside a fenced block is a SPECIMEN, not a reference.
    Checking them reported three false positives on a document showing an
    example pull-request comment containing `[log](...)`, and a page whose
    whole job is listing banned words as failing for containing them.
    """
    out, in_fence = [], False
    for line in text.splitlines():
        if fence_re.match(line):
            in_fence = not in_fence
            out.append("")
            continue
        out.append("" if in_fence else line)
    return "\n".join(out)

broken_links, broken_paths, banned_hits, emdash_hits = [], [], [], []
linked_targets = set()

for doc in docs:
    raw = open(doc, encoding="utf-8").read()
    text = strip_fences(raw)
    base = os.path.dirname(doc)

    # ---- 1. relative links resolve
    for label, target in link_re.findall(text):
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        clean = target.split("#", 1)[0]
        if not clean:
            continue
        resolved = os.path.normpath(os.path.join(base, clean))
        linked_targets.add(resolved)
        if not os.path.exists(resolved):
            broken_links.append((doc, target, resolved))

    # ---- 2. cited paths in code spans exist
    # Only spans that LOOK like a repo path: contains a slash and ends in a
    # known extension, or is a known directory. Anything else is prose in
    # backticks and checking it would produce noise nobody acts on.
    for span in code_span_re.findall(text):
        s = span.strip()
        if s.startswith(("http", "$", "-", "/", "~")) or " " in s:
            continue
        # A glob names a set, not a file. Checking it as a path is a category
        # error that produces noise nobody can act on.
        if any(ch in s for ch in "*?["):
            continue
        if not ("/" in s and re.search(r"\.(md|sh|py|toml|json|yaml|yml)$", s)):
            continue
        # ⚠ Only paths in THIS repository. A citation of another project's
        # file, which this tree does a great deal of, is evidence about them
        # and not a claim that the file exists here. Those are written with a
        # repository prefix, for example `pkgforge/builds build.py`, and do
        # not match the prefixes below.
        if s.startswith(("docs/", "experiments/", "tools/", "references/")):
            # Resolve from the repository root OR from the citing document's
            # own directory. A page in docs/history/ citing
            # `references/README.md` means its own subdirectory.
            if not (os.path.exists(s) or os.path.exists(os.path.join(base, s))):
                broken_paths.append((doc, s))

    # ---- 4. banned vocabulary and em dashes, outside fenced blocks
    in_fence = False
    for n, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        stripped = re.sub(r'`[^`]*`', '', line)
        low = stripped.lower()
        for w in BANNED_WORDS:
            if re.search(rf'\b{re.escape(w)}\b', low):
                banned_hits.append((doc, n, w))
        if "—" in stripped:
            emdash_hits.append((doc, n))

# ---- 3. every doc is REACHABLE FROM README.md
#
# ⛔ "Linked from somewhere" is the weaker property and it was what this
# check tested until review pass 6. A set of orphan pages linking only to
# each other satisfies it while being unreachable from the entrypoint.
#
# ⭐ The deliverable's stated contract is that an implementer reads only
# README.md and follows its links, so reachability from README is the
# property that actually has to hold. This walks it.
def outbound(path):
    try:
        text = strip_fences(open(path, encoding="utf-8").read())
    except OSError:
        return []
    base = os.path.dirname(path)
    out = []
    for _, target in link_re.findall(text):
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        clean = target.split("#", 1)[0]
        if not clean:
            continue
        resolved = os.path.normpath(os.path.join(base, clean))
        if resolved.endswith(".md") and os.path.exists(resolved):
            out.append(resolved)
    return out


reachable, queue = set(), ["README.md"]
while queue:
    cur = queue.pop(0)
    if cur in reachable:
        continue
    reachable.add(cur)
    queue.extend(outbound(cur))

unlinked = [d for d in docs if d not in reachable]

fails = len(broken_links) + len(broken_paths) + len(unlinked) + len(banned_hits) + len(emdash_hits)

if as_json:
    print(json.dumps({
        "documents": len(docs), "broken_links": len(broken_links),
        "broken_paths": len(broken_paths), "unreachable": len(unlinked),
        "reachable_from_readme": len(reachable),
        "banned_vocabulary": len(banned_hits), "em_dashes": len(emdash_hits),
        "failures": fails,
        "unlinked_files": sorted(unlinked),
        "broken_link_targets": [t for _, t, _ in broken_links],
    }, indent=2))
else:
    if not quiet:
        print(f"documents scanned      {len(docs)}")
        print(f"scripts scanned        {len(others)}")
        print()
    if broken_links:
        print(f"BROKEN LINKS ({len(broken_links)})")
        for doc, target, resolved in sorted(broken_links):
            print(f"  {doc}: [{target}] -> {resolved}")
        print()
    if broken_paths:
        print(f"CITED PATHS THAT DO NOT EXIST ({len(broken_paths)})")
        for doc, s in sorted(set(broken_paths)):
            print(f"  {doc}: `{s}`")
        print()
    if unlinked:
        print(f"PAGES UNREACHABLE FROM README.md ({len(unlinked)})")
        for doc in sorted(unlinked):
            print(f"  {doc}")
        print()
    if banned_hits:
        print(f"BANNED VOCABULARY ({len(banned_hits)})")
        for doc, n, w in sorted(banned_hits):
            print(f"  {doc}:{n}: {w}")
        print()
    if emdash_hits:
        print(f"EM DASHES ({len(emdash_hits)})")
        for doc, n in sorted(emdash_hits):
            print(f"  {doc}:{n}")
        print()
    if fails == 0 and not quiet:
        print(f"all links resolve, all cited paths exist, and all {len(reachable)}")
        print("pages are reachable by following links from README.md")

sys.exit(1 if fails else 0)
PY
