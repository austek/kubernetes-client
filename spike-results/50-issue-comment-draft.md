**DRAFT ONLY — NOT POSTED.** Three comments awaiting review before posting: two for
https://github.com/fabric8io/kubernetes-client/issues/7986 and one for
https://github.com/fabric8io/kubernetes-client/pull/7911.
Everything above and below a `>>>` / `<<<` marker pair is scaffolding, not comment text.

Suggested order: comment 1 on the issue first, then the PR comment (which references the issue).
Comment 2 is better held until someone responds — #7986 is assigned to `ash-thakur-rh` and
milestoned 8.0.0, so an unsolicited task breakdown may step on work that is now theirs.

---

**Comment 1 of 2 — recommendation (word-limited, no headers)**

>>> BEGIN COMMENT 1

Adopt bnd if converting the 9 already-bnd-wired `packaging=jar` modules to `packaging=bundle` —
dropping the published `-bundle` classifier karaf's `feature.xml` references — is acceptable;
otherwise use moditect for those 9. Everything else follows from that answer.

bnd needs one instruction on the existing `maven-bundle-plugin` config plus a central name macro:
59 of 74 published modules unchanged, 68 of 74 after the conversion (6 have no bnd wiring).
Gated on pinning bndlib >= 6.4.0, untested: at 6.3.1 a `serviceLoaderUses` NPE leaves
`kubernetes-model-core` unbuildable and `uses` unreachable.

moditect gets `requires` names right, including multi-release jars where bnd emits
`requires jackson-core`, but costs a name property per module and a split-package exclusion list;
last release 2025-07-20, checked 2026-08-09.

Strongest argument against bnd: its wrong names ship and fail at consumer resolution; moditect's
fail in CI.

Measurements, 10 unmeasured cells, and the next experiment (does bnd read a
dependency's `Automatic-Module-Name`?):
[40-comparison.md](https://github.com/austek/kubernetes-client/blob/spike/jpms-bnd/spike-results/40-comparison.md).
Branches: [bnd](https://github.com/austek/kubernetes-client/tree/spike/jpms-bnd),
[moditect](https://github.com/austek/kubernetes-client/tree/spike/jpms-moditect).

<<< END COMMENT 1

---

**Comment 2 of 2 — follow-up tasks (separate comment; answers the issue's second ask)**

>>> BEGIN COMMENT 2

Offering these as input in case they're useful to whoever picks this up. Follow-up tasks with
acceptance criteria; 2-8 are sequenced behind the packaging decision above.

1. Compare both mechanisms on a representative module slice and resolve the packaging question.
   AC: both arms build on JDK 11; `jar --describe-module` captured per arm and diffed against
   #7911's hand-written descriptors; recommendation recorded on this issue. Done, above.
2. Central module-name derivation, preserving the 5 published httpclient names.
   AC: every published jar carries `Automatic-Module-Name`; those 5 byte-identical to 7.x; the
   filename-derived-automodule warning this issue reports is gone from a modular consumer build.
3. Descriptor generation across the published set, with a documented exclusion list.
   AC: every BOM artifact contains `module-info.class` except listed exclusions, each justified
   inline in its pom. Edge case: `kubernetes-openshift-uberjar` is a BOM artifact whose lack of a
   descriptor today is accidental under both mechanisms (under moditect the build fails outright),
   so excluding it has to be an explicit decision.
4. Close the ServiceLoader `provides` gap.
   AC: discovery works from a named module for all 4 service interfaces, nested
   `HttpClient$Factory` included.
5. Eliminate split packages across the published set.
   AC: the automated scan reports zero. Edge case: the `provided`-scope Sundr/lombok split that
   forced a 13-artifact exclusion in the moditect arm — the same class of problem that made #7911
   abandon generated descriptors.
6. Verification harness, both layers: committed golden descriptor dumps, plus a real module-path
   resolution test that loads each service.
   AC: runs in the existing matrix on JDK 11/17/21 and Windows; a deliberately corrupted
   descriptor fails the build. Both mechanisms proved descriptor-stable across JDK 11 and 17, so
   golden files are viable; JDK 21 is unmeasured.
7. Document module names as public API.
   AC: a `doc/` page giving the naming rule, the 5 frozen exceptions and why, and what adding a
   new module requires (nothing).
8. OSGi and revapi non-regression.
   AC: karaf itests and revapi pass with no new suppressions. Edge case: task 1's packaging change
   moves karaf's `feature.xml` coordinates, so this gate has to be in place before that change
   lands, not after.

To reproduce any of the measurements: the tooling is on
[spike/jpms-harness](https://github.com/austek/kubernetes-client/tree/spike/jpms-harness) —
a descriptor dump normalised for byte-stable diffing, a split-package scan, and JDK pinning,
since both arms had to be built under a fixed JDK to rule out environmental drift. Raw evidence
per arm: [20-moditect-all-modules.txt](https://github.com/austek/kubernetes-client/blob/spike/jpms-moditect/spike-results/20-moditect-all-modules.txt)
for moditect, and the `10-`/`11-`/`12-`/`30-` files alongside
[40-comparison.md](https://github.com/austek/kubernetes-client/blob/spike/jpms-bnd/spike-results/40-comparison.md)
for bnd and the cross-cutting checks.

Tasks 5 and 8 have a head start: #8028 fixes the two split packages that exist today
(`openshift-model` shipping `openshift-model-config`'s classes, and
`Fabric8ClientInjectionHandler` sharing a package with `kube-api-test` core). Both are defects
independent of the mechanism choice.

<<< END COMMENT 2

---

**Comment for PR #7911 — separate thread, post after comment 1 is on the issue**

>>> BEGIN PR COMMENT

The automation question behind this PR is now investigated in #7986: bnd's `-jpms-module-info`
compared against moditect's `add-module-info` on a 7-module slice of the real build, with the
measurements and the remaining open questions linked from there.

Both mechanisms generate descriptors rather than hand-maintaining them, so this PR's approach is
superseded either way. Happy to close it.

Two changes in here are worth keeping regardless of which mechanism wins, since they are real
defects independent of the choice: the `openshift-model` / `openshift-model-config` split package,
and moving `Fabric8ClientInjectionHandler` out of the package it shares with `kube-api-test`. I can
open a separate PR for just those if that's useful.

<<< END PR COMMENT
