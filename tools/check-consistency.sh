#!/usr/bin/env bash
# check-consistency.sh - cross-document agreement.
#
# ⭐ WHAT DEFECT THIS CATCHES
#
# `check-links.sh` proves that a document's references RESOLVE. It cannot see
# that two documents which never link to each other say different things. That
# gap was recorded in docs/history/README.md as the one review pass 3 did not
# sweep, and sweeping it by hand found five defects in one afternoon:
#
#   - docs/registry/index-and-search.md used a media type the normative
#     registry did not contain, on a page that states it is the only place
#     those strings are written;
#   - docs/build/static-linking.md invented a second one;
#   - four documents used CLI verbs absent from docs/client/cli.md, whose
#     first line claims an implementation can build the command surface from
#     that file alone;
#   - a citation named migration.md §6, which does not exist.
#
# Five checks, each an agreement between a document that DECLARES something
# and every document that USES it:
#
#   1. media types      declared in docs/registry/media-types.md
#   2. CLI verbs        declared in docs/client/cli.md §3
#   3. section refs     `file.md §N` names a heading that exists
#   4. identifiers      R##, I##, Q## resolve to their defining table
#   5. tool versions    a version cited in prose matches the pin in
#                       experiments/00-fetch-tools.sh
#
# ⛔ WHAT IT CANNOT CATCH: two documents that describe the same BEHAVIOUR
# differently in prose. There is no declaring file to check against, so that
# stays a reading. This closes the mechanical half of the gap, not the gap.
#
# Usage:
#   check-consistency.sh              check, print a report
#   check-consistency.sh --quiet      only print failures
#   check-consistency.sh --json       machine-readable summary
#
# Exit codes: 0 everything agrees, 1 a check failed, 2 could not run.
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

SKIP_DIRS = {".git", ".tmp", "references", "node_modules", "out", ".work"}

docs = []
for dirpath, dirnames, filenames in os.walk("."):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for fn in filenames:
        if fn.endswith(".md"):
            docs.append(os.path.normpath(os.path.join(dirpath, fn)))
docs.sort()

TEXT = {d: open(d, encoding="utf-8").read() for d in docs}


def read(path):
    """Ground truth reads the file even when it is not a scanned document."""
    if path in TEXT:
        return TEXT[path]
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return ""


failures = []          # (check, where, detail)
#
# ⛔ Every check reports its DENOMINATOR. "0 failures" over 0 things
# examined is the vacuous pass this file was itself caught committing:
# the section check resolved a link label instead of its href, matched
# nothing, and reported success. A count makes that visible on the way
# out instead of on the day someone plants a defect.
examined = {}          # check -> how many claims were actually tested


def seen(check, n=1):
    examined[check] = examined.get(check, 0) + n



def fail(check, where, detail):
    failures.append((check, where, detail))


# ---------------------------------------------------------------- 1. media types
#
# docs/registry/media-types.md line 6 states it is the only place these
# strings are written. That is a checkable claim.
MT_HOME = "docs/registry/media-types.md"
mt_re = re.compile(r'application/vnd\.opk\.[a-z0-9][a-z0-9.+-]*')

declared_mt = set(mt_re.findall(read(MT_HOME)))
# ⚠ The naming-rule section shows the SHAPE `application/vnd.opk.<thing>...`,
# which the regex truncates to a bare prefix. It declares nothing.
declared_mt.discard("application/vnd.opk.")
# §3 names one rejected spelling to say an SBOM layer is NOT it. A
# counter-example is not a registration.
declared_mt.discard("application/vnd.opk.sbom-content.v1+json")

# ⚠ open-questions.md probes a live registry with a deliberately meaningless
# artifactType to see whether it is accepted. That is a test input, not a
# type this system defines.
PROBE_MT = {"application/vnd.opk.test.v1"}

for doc in docs:
    if doc == MT_HOME:
        continue
    for mt in sorted(set(mt_re.findall(TEXT[doc]))):
        if mt == "application/vnd.opk." or mt in PROBE_MT:
            continue
        seen("media-type")
        if mt not in declared_mt:
            fail("media-type", doc, f"{mt} is not in {MT_HOME}")


# ------------------------------------------------------------------ 2. CLI verbs
#
# docs/client/cli.md line 3 claims an implementation can build the whole
# command surface from that file. A verb used elsewhere and absent there
# falsifies it.
CLI_HOME = "docs/client/cli.md"
cli_text = read(CLI_HOME)

# Declared: the leading verb of every `opk ...` code span in the command
# tables. Taking only code spans keeps prose like "opk does not manage
# services" out of the vocabulary.
declared_verbs = set()
for span in re.findall(r'`opk ([a-z][a-z-]*)', cli_text):
    declared_verbs.add(span)
# §7 shows completions and env inside fenced blocks as well; a verb declared
# anywhere in its own home file counts as declared.
for m in re.findall(r'^\s*opk ([a-z][a-z-]*)', cli_text, re.M):
    declared_verbs.add(m)

# ⚠ Used: only a genuine command position. Two forms count, and prose does
# not: a fenced line beginning `opk verb`, or a code span `opk verb`.
#
# ⚠ A fenced block is not always shell. This tree fences sample CLI OUTPUT
# too, and one such block contains the sentence "opk does not install or
# manage services", whose second word is English rather than a verb. A stop
# list is the honest discriminator: these words cannot be commands.
ENGLISH_AFTER_OPK = {
    "does", "do", "is", "are", "was", "were", "will", "can", "cannot",
    "has", "have", "had", "would", "should", "must", "may", "might",
    "and", "or", "but", "the", "a", "an", "then", "than", "also",
    "never", "always", "only", "still", "just", "already", "itself",
    "reads", "writes", "keeps", "treats", "refuses", "prints", "stores",
}
used_verbs = {}          # verb -> [(doc, line)]
for doc in docs:
    if doc == CLI_HOME:
        continue
    for n, line in enumerate(TEXT[doc].splitlines(), 1):
        cands = re.findall(r'^\s*(?:\$ )?opk ([a-z][a-z-]*)', line)
        cands += re.findall(r'`opk ([a-z][a-z-]*)', line)
        for v in cands:
            if v in ENGLISH_AFTER_OPK:
                continue
            used_verbs.setdefault(v, []).append((doc, n))

for verb, sites in sorted(used_verbs.items()):
    seen("cli-verb", len(sites))
    if verb not in declared_verbs:
        doc, n = sites[0]
        extra = f" (+{len(sites)-1} more)" if len(sites) > 1 else ""
        fail("cli-verb", f"{doc}:{n}", f"`opk {verb}` is not in {CLI_HOME}{extra}")


# ------------------------------------------------------------- 3. section refs
#
# `some/file.md` §4 is a claim that the file has a section 4. Citing a
# section that does not exist sends the reader to a page and abandons them.
# ⛔ Resolve the HREF, never the link label.
#
# The first version of this check captured the label, because in this tree a
# citation is almost always written [`../client/cli.md`](../client/cli.md) and
# the two are the same string. They are not the same thing. A label of
# `cli.md` under a href of `client/cli.md` resolved to a file that does not
# exist, the check skipped it as "not our file", and the guard-mutation test
# caught a check that had never once run.
sec_re = re.compile(
    r'\[[^\]]*\]\(([^)\s#]+\.md)(?:#[^)\s]*)?\)\s*(?:and\s+)?§([0-9]+(?:\.[0-9]+)*)')
inline_sec_re = re.compile(r'`([a-z0-9./_-]+\.md)`\s+§([0-9]+(?:\.[0-9]+)*)')


def headings(path):
    out = set()
    for line in read(path).splitlines():
        m = re.match(r'^#{2,4}\s+(?:[⭐⛔⚠]\s*)?([0-9]+(?:\.[0-9]+)*)\.?\s', line)
        if m:
            out.add(m.group(1))
    return out


HEAD = {}
for doc in docs:
    base = os.path.dirname(doc)
    for pat in (sec_re, inline_sec_re):
        for target, sec in pat.findall(TEXT[doc]):
            resolved = os.path.normpath(os.path.join(base, target))
            if not os.path.exists(resolved):
                continue        # check-links.sh owns the missing-file case
            if resolved not in HEAD:
                HEAD[resolved] = headings(resolved)
            hs = HEAD[resolved]
            if not hs:
                continue        # a file with no numbered sections; nothing to check
            # §3.1 is satisfied by a "### 3.1" heading; §3 by "## 3".
            seen("section-ref")
            if sec not in hs:
                fail("section-ref", doc, f"{target} §{sec} does not exist")


# -------------------------------------------------------------- 4. identifiers
#
# R##, I## and Q## are cited across the tree. Each has exactly one defining
# document, and a citation of an identifier that was never defined is a
# dangling reference a link checker cannot see.
def defined_ids(path, pattern):
    return set(re.findall(pattern, read(path)))


ID_SOURCES = [
    # label,   defining file,           definition pattern,      citation pattern
    ("requirement", "docs/requirements.md",
     r'^\|\s*\*?\*?(R[0-9]+)', r'\b(R[0-9]{1,3})\b'),
    ("invariant", "docs/architecture.md",
     r'^\|\s*\*?\*?(I[0-9]+)', r'\b(I[0-9]{1,2})\b'),
    ("open-question", "docs/open-questions.md",
     r'^#{2,4}\s*(?:[⭐⛔⚠]\s*)?(Q[0-9]+)|^\|\s*\*?\*?(Q[0-9]+)', r'\b(Q[0-9]{1,2})\b'),
]

for label, home, defpat, citepat in ID_SOURCES:
    raw = re.findall(defpat, read(home), re.M)
    defined = {g for tup in raw for g in (tup if isinstance(tup, tuple) else (tup,)) if g}
    if not defined:
        fail("identifier", home, f"no {label} definitions found; the pattern has rotted")
        continue
    for doc in docs:
        # ⚠ docs/history/ QUOTES superseded identifiers by design: its own
        # rule is "do not edit the original wording, quote it". An entry
        # recording that R1..R15 were renamed to D1..D15 necessarily contains
        # R15, and flagging it would force the record to be falsified.
        if doc.startswith(os.path.join("docs", "history")):
            continue
        for n, line in enumerate(TEXT[doc].splitlines(), 1):
            # Only citations that clearly reference an identifier, not prose
            # that happens to contain a capital letter and a digit.
            for ident in re.findall(citepat, line):
                if doc != home:
                    seen("identifier")
                if ident in defined:
                    continue
                # ⚠ A range like "R1 to R72" or a table of contents in the
                # defining file itself is not a citation of a missing id.
                if doc == home:
                    continue
                fail("identifier", f"{doc}:{n}",
                     f"{label} {ident} is not defined in {home}")


# ------------------------------------------------------------ 5. tool versions
#
# A version in prose that disagrees with the pin is worse than no version:
# a reader reproduces with the wrong tool and gets a different answer.
PIN_FILE = "experiments/00-fetch-tools.sh"
pins = {}
for m in re.finditer(r'^([A-Z][A-Z0-9_]*)_VERSION="?([0-9][0-9A-Za-z.+-]*)"?', read(PIN_FILE), re.M):
    pins[m.group(1).lower()] = m.group(2)

if not pins:
    fail("tool-version", PIN_FILE, "no *_VERSION pins found; the pattern has rotted")
else:
    for doc in docs:
        for n, line in enumerate(TEXT[doc].splitlines(), 1):
            for tool, ver in pins.items():
                # "oras 1.2.2" or "oras 1.2.1" in prose. Only flag a version
                # that differs from the pin, never a bare mention.
                for found in re.findall(rf'\b{re.escape(tool)}\s+v?([0-9]+\.[0-9]+(?:\.[0-9]+)?)', line, re.I):
                    seen("tool-version")
                    if found != ver and not ver.startswith(found + "."):
                        fail("tool-version", f"{doc}:{n}",
                             f"{tool} {found} contradicts the pin {ver} in {PIN_FILE}")

# ------------------------------------------------------------------- report
by_check = {}
for check, where, detail in failures:
    by_check.setdefault(check, []).append((where, detail))

if as_json:
    print(json.dumps({
        "documents": len(docs),
        "media_types_declared": len(declared_mt),
        "cli_verbs_declared": len(declared_verbs),
        "examined": dict(sorted(examined.items())),
        "failures": len(failures),
        "by_check": {k: len(v) for k, v in sorted(by_check.items())},
        "detail": [{"check": c, "where": w, "detail": d} for c, w, d in failures],
    }, indent=2))
else:
    if not quiet:
        print(f"documents scanned      {len(docs)}")
        print(f"media types declared   {len(declared_mt)}")
        print(f"CLI verbs declared     {len(declared_verbs)}")
        print(f"tool pins read         {len(pins)}")
        print()
    for check in sorted(by_check):
        rows = by_check[check]
        print(f"{check.upper().replace('-', ' ')} ({len(rows)})")
        for where, detail in sorted(set(rows)):
            print(f"  {where}: {detail}")
        print()
    if not quiet:
        print("claims examined")
        for check in sorted(examined):
            print(f"  {check:<14} {examined[check]}")
        # ⛔ A check that examined nothing has rotted, whatever its patterns
        # once matched. That is a failure of the checker, not a clean tree.
        empty = [c for c in ("media-type", "cli-verb", "section-ref",
                             "identifier", "tool-version")
                 if examined.get(c, 0) == 0]
        if empty:
            print()
            print(f"⛔ CHECKS THAT EXAMINED NOTHING ({len(empty)})")
            for c in empty:
                print(f"  {c}: matched no claims; the pattern has rotted")
            sys.exit(1)
        print()
    if not failures and not quiet:
        print("every used media type, CLI verb, section reference and identifier")
        print("is declared where its home document says it is declared")

sys.exit(1 if failures else 0)
PY
