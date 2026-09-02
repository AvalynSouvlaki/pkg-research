# conventions

How these documents are written, and what a number owes.

⭐ **The mechanical half is checked by `tools/check-links.sh` and
`tools/count-requirements.sh`. The rest is a reading.**

---

## 1. Normative strength

| word | means |
| --- | --- |
| **MUST** / **MUST NOT** | an implementation that does otherwise is not conformant |
| **SHOULD** / **SHOULD NOT** | do this unless you have a stated reason not to |
| **MAY** | genuinely optional |
| *(unmarked prose)* | explanation. ⛔ Never normative. |

⛔ **A requirement that is not marked is not a requirement.** If a paragraph
means to bind an implementation, it says MUST.

Blocks are labelled `EXAMPLE`, `HISTORICAL NOTE` or `OPEN QUESTION` where they
are not specification.

---

## 2. The three markers

⛔ **⛔ ⭐ ⚠ and no others in prose.**

| marker | means |
| --- | --- |
| ⛔ | a rule that has already been broken, or one whose violation is unrecoverable. A hard stop. |
| ⭐ | reach for this first. The highest-value item on the page. |
| ⚠ | a trap. It works until it does not, and the failure is quiet. |

⛔ **They do not stack.** There is no `⛔⛔`. Escalating a marker is how a
vocabulary stops meaning anything.

⭐ **Status glyphs are a second tier and a different job.** ✅ and ❌ report a
result, in machine output and result tables. ⛔ A status glyph never carries a
rule, and a marker never reports a result.

---

## 3. Evidence labels

⛔ **Every claim carries one, every time.**

| label | means |
| --- | --- |
| ⭐ **measured** | produced by a script in `experiments/`, on the host in `experiments/out/10-probe-host.txt` |
| **documented** | from a specification or a tool's own documentation; not run here |
| ⚠ **inferred** | a conclusion drawn from the two above, labelled as a conclusion |
| ⚠ **estimated** | a judgement with no measurement behind it, labelled in the same sentence |

⚠ **A measured result is one machine on one day.** It is stronger than a
documented one and it is not a guarantee about your machine.

---

## 4. Numbers

⛔ **Never a fabricated number. A dash where the value is unknown.** A wrong
number on a report is worse than no number, because a blank gets checked and a
number gets used.

⛔ **A measurement carries its conditions or it is not a measurement.** Host,
tool versions, date, sample count, input size. A rate with none of those cannot
be compared to anything, which makes it worse than an absence: it invites a
comparison that means nothing.

⭐ **Prefer a number a script derives.** `tools/count-requirements.sh` exists
because a coverage table written from memory said 67, 20 and 45 where the real
values were 72, 33 and 35.

⚠ **Two numbers in this tree were published wrong and corrected**, and they are
listed in [`history/README.md`](history/README.md). ⛔ Assume more remain.

---

## 5. One fact, one home

⛔ **Every fact lives in exactly one document.** Where a second document needs
it, it links rather than repeating.

⚠ **A value in two places with no check between them drifts, and the copy a
reader trusts is the wrong one.** The trap is that a value which never changes
cannot expose a missing check: it sits correct for a year and drifts the first
time it moves.

⛔ **When any document conflicts with [`architecture.md`](architecture.md), the
reference is right and the other is the defect.** Fix it in the same change.

---

## 6. Amend in place

⛔ **When a rule changes, rewrite the rule.** Do not append a dated box under
the old text saying the text above is retired.

⚠ **A document written by accretion, where a paragraph says one thing and a box
below says the opposite, has a documented failure mode**: a reader reads the
first paragraph, stops, and acts on the retired rule.

What to do instead:

1. rewrite the rule to what it is now; the current text is the only text;
2. ⭐ move the superseded wording to [`history/README.md`](history/README.md),
   with the date and why it changed;
3. link to it once, from the rule, in a sentence.

⚠ **This is not licence to delete.** A superseded rule is moved, never dropped,
so a future reader who wonders why the rule is what it is can find out instead
of re-deriving it wrongly.

---

## 7. Say what is not true

⛔ **A limit hidden is a defect filed against a user later.**

Every document reserves a place for the truths that are tempting to omit:
this is slower than it looks, this has a known gap, this was not measured here.

⭐ `README.md` opens its "what this does not establish" section **before** the
recommendations, because a reader who reaches the recommendation first has
already stopped reading.

---

## 8. What a document is not

**A document says what the thing does. It does not say what the project did.**

| the text is | where it goes |
| --- | --- |
| a fact, limit or constraint a reader needs | ⭐ the document |
| a measurement with its conditions | the document, as a table |
| ⭐ the story of a fix, or a superseded claim | ⭐ [`history/README.md`](history/README.md) |
| what shipped, when | `CHANGELOG.md` |

⭐ **The test for a passage you are unsure about: does a reader need this to use
the thing correctly today?** Yes, it is a constraint and it stays. No, it is
history.

---

## 9. The mechanical checks

```sh
sh tools/check-links.sh
sh tools/count-requirements.sh --check
```

`check-links.sh` refuses:

1. a relative link that resolves to nothing;
2. a cited path that does not exist;
3. ⭐ a page under `docs/` that nothing links to;
4. banned vocabulary;
5. an em dash.

⛔ **What no check can answer is whether a claim is true.** That is a reading,
and it belongs to the review pass. A guard that tried to verify prose would
either pass vacuously or refuse legitimate writing.

### 9.1 Banned vocabulary

Words that assert quality instead of demonstrating it:

```text
seamless, blazing, effortless, robust, powerful, cutting-edge,
state-of-the-art, world-class, elegant, revolutionary, game-changing,
rock-solid, bulletproof, lightning-fast
```

⚠ **Replace the adjective with the measurement, or delete it.** `fast` becomes
the number and its conditions. `robust` becomes what it survives.

⭐ **A specimen inside a code span is permitted**, and it has to be: a page that
bans a word cannot otherwise show which one it means.

---

## 10. Prose

- Short sentences. Present tense.
- ⛔ No em dashes.
- Every claim backed by a command a reader can run or a path a reader can open.
- ⛔ **No defensive framing.** Describe what something does in plain technical
  terms; do not write disclaimers arguing that it is legitimate. A defensive
  paragraph primes a skeptical reader to look for the thing it denies.
- Write for a reader with no memory of the session that wrote the file, and for
  a person looking for one fact.

---

## 11. Shell in documents

⛔ **Every fenced shell block parses.** A block that does not parse is a block
nobody can copy and paste.

⛔ **No angle-bracket placeholders inside a shell block.** A human reads
`<deployment-id>` as "fill this in" and the shell reads it as a redirect, so the
reader gets a syntax error instead of an instruction. Use an upper-case name or
a quoted variable.

⛔ **No literal control bytes.** Documentation about escape sequences has a
proven habit of containing the character it warns about.
