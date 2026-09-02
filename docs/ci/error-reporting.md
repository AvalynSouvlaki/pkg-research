# error reporting

What a failure produces, where each audience reads it, and the rule that a
failure is never silent.

---

## 1. ⛔ The rule

**Every failure produces a durable record a human can reach without
credentials.**

⚠ **The failure mode this prevents**: a package quietly missing for one
architecture, with the reason in a CI log that expired, and a user who cannot
find out why.

| audience | reads |
| --- | --- |
| ⭐ a user | ⭐ `opk log --failed`, or the package page |
| a contributor | the pull-request comment and the annotations |
| a maintainer | the failure dashboard and the alert |
| ⭐ an auditor | ⭐ the failure record in the registry |

---

## 2. Failure classes

⛔ **Classified, because the response differs.**

| class | example | published | alerts |
| --- | --- | --- | --- |
| `validation` | a missing field, an unpinned image | ⛔ no | ⚠ no: it is on the pull request |
| `source` | the pinned commit is gone | ⭐ yes | ⭐ yes |
| `build` | compilation failed | ⭐ yes | ⚠ only if it was previously succeeding |
| `verify` | ⛔ the artefact is dynamic, or the wrong architecture | ⭐ yes | ⭐ yes |
| `publish` | the registry refused | ⚠ no artefact record | ⭐ yes |
| `sign` | ⛔ the signing workflow failed | ⚠ the artefact is unsigned | ⭐ yes, urgent |
| `index` | generation failed | ⚠ the previous index stands | ⭐ yes, urgent |
| `reproduce` | ⛔ a rebuild differs | ⭐ yes, marks SUSPECT | ⭐ yes |

⭐ **`sign` and `index` are urgent because they are silent to a user.** An
unsigned artefact is refused by clients under the default policy, and a stale
index means nobody sees new packages. Neither produces an error a user can
attribute.

⚠ **`build` alerts only on a regression** because a package that has never
built for riscv64 failing again is not news, and alerting on it trains
maintainers to ignore the channel.

---

## 3. The failure record

Published at the coordinate the package would have had, with `artifactType`
`application/vnd.opk.buildfailure.v1+json` and ⛔ no payload layer.

```json
{
  "schemaVersion": 1,
  "name": "ripgrep", "version": "14.1.1", "revision": 1,
  "host": "riscv64-linux",
  "status": "failed",
  "class": "build",
  "phase": "run",
  "exit_code": 101,
  "summary": "linking with `cc` failed: cannot find -lz",
  "suggestion": "add \"zlib-static\" to [build].deps",
  "recipe_url": "https://github.com/example/opk-packages/blob/4d5e6f/packages/ripgrep/opk.toml",
  "run_url": "https://github.com/example/opk-packages/actions/runs/1234567890",
  "started": "2026-09-01T10:00:00Z",
  "finished": "2026-09-01T10:01:44Z",
  "previous_success": { "version": "14.1.0", "revision": 1 }
}
```

| field | why |
| --- | --- |
| ⭐ `summary` | ⭐ the one line that says what went wrong, extracted per §4 |
| `suggestion` | ⭐ a known-pattern fix, absent when there is none |
| `phase` | ⭐ which of the nine build phases; a fetch failure is not a compile failure |
| `previous_success` | ⭐ turns "it is broken" into "it regressed" |

⛔ **`summary` and `suggestion` are the difference between a record and a
log.** A user who wanted to know why `ripgrep` is missing for riscv64 gets an
answer, not a 4,000-line file.

---

## 4. Extracting the summary

⭐ **Pattern matching against a table of known failure shapes**, falling back to
the last non-empty stderr line.

| pattern | class | suggestion |
| --- | --- | --- |
| `cannot find -l(\w+)` | build | ⭐ add the static package for that library to `[build].deps` |
| `No such file or directory` on a declared artefact | verify | the artifact map does not match what the build produced |
| ⛔ `dynamically linked` from the verifier | verify | ⭐ the build linked dynamically; check the target and flags |
| `built for e_machine` from the verifier | verify | ⭐ the cross-compile fell back to the native compiler |
| `commit mismatch` | source | the pinned commit is not what the remote served |
| `no space left on device` | build | ⚠ infrastructure, not the package |
| ⚠ `Killed` with exit 137 | build | ⭐ out of memory; raise `[build].memory` |
| `context deadline exceeded` | build | timeout; raise `[build].timeout` |

⚠ **A wrong suggestion is worse than none**, so the table is conservative and
the record shows the matched pattern so a maintainer can see why it said that.

⛔ **Infrastructure failures are labelled as such.** A disk-full or a runner
loss reported as a package failure sends a maintainer to debug a package that is
fine.

---

## 5. What a user sees

```
$ opk install ripgrep
opk: no build of ripgrep 14.1.1-1 for riscv64-linux

  the build failed on 2026-09-01
    phase   run
    error   linking with `cc` failed: cannot find -lz
    fix     add "zlib-static" to [build].deps

  full log     opk log ripgrep --failed --host riscv64-linux
  the recipe   https://github.com/example/opk-packages/blob/4d5e6f/packages/ripgrep/opk.toml
  report it    https://github.com/example/opk-packages/issues/new?template=broken.yml&title=ripgrep+riscv64

  ⭐ ripgrep 14.1.0-1 does build for riscv64-linux:
       opk install ripgrep@14.1.0-1
```

⭐ **The last line is the one that helps most.** A user who wanted the tool gets
a working version rather than an explanation.

⚠ **The issue link is prefilled** with the package, the host and the version.
An issue template a user has to fill in by hand gets reports with none of the
information needed to act on them.

---

## 6. Alerting

| channel | for |
| --- | --- |
| ⭐ a GitHub issue, one per package, reopened | ⭐ a persistent build failure |
| a chat webhook | ⚠ urgent classes only: `sign`, `index`, `publish` |
| the job summary | every run |
| a dashboard | trends |

⛔ **One issue per package, reopened rather than duplicated.** A bot filing a
new issue per failed run produces a tracker nobody can use, and it is the most
common way an alerting system becomes noise.

⚠ **Alert on the transition, not on the state.** A package that has been broken
for a month generates one alert, not thirty.

---

## 7. What a maintainer sees

```
$ opk-admin failures --since 7d
package       host              class     since       previous  issue
ripgrep       riscv64-linux     build     2026-09-01  14.1.0-1  #412
somelib       aarch64-linux     source    2026-08-28  2.1.0-1   #408
oldthing      x86_64-linux      build     2026-06-02  never     ⚠ (none)

3 failures, 2 regressions, 1 never-built
```

⭐ **Separating regressions from never-built is what makes the list
actionable.** A regression is a fix; a never-built package may be a package that
should be marked `disabled` with a reason, and conflating them means the list
grows until nobody reads it.

⚠ **That distinction is what era 1 lacked**, and its 385 disabled recipes out
of 871 carry almost no reasons. The information about why each was disabled is
simply gone.
