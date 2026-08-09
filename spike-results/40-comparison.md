# JPMS module descriptors: bnd vs moditect — comparison and recommendation

Issue #7986 asked for an **automation-driven** way to put real `module-info.class` descriptors in
the published artifacts, after PR #7911 (which hand-wrote `<moduleInfoSource>` into 74 poms) was
rejected. This spike measured the two candidate mechanisms:

- **bnd arm** (`spike/jpms-bnd`): bnd's `-jpms-module-info` instruction, added once to the root
  pom's existing `maven-bundle-plugin` configuration (`pom.xml:1332` on `spike/jpms-bnd`). Plugin
  pinned at `maven-bundle-plugin` 5.1.9 (`pom.xml:150`), which embeds bndlib 6.3.1.
- **moditect arm** (`spike/jpms-moditect`): `moditect-maven-plugin` 1.3.0.Final `add-module-info`,
  bound once in the root pom, generating descriptors post-compile via `jdeps`.

Neither arm is shippable as measured. What follows is what was actually measured, what was not,
and what the choice depends on.

## Evidence legend

Cells cite `file:lines`. All files are in `spike-results/`.

| Short ref | File | Branch |
|---|---|---|
| `00-base` | `00-baseline-main.txt` | both (harness) |
| `10-bnd` | `10-bnd-bundle-modules.txt` | `spike/jpms-bnd` |
| `11-bnd` | `11-bnd-packaging-gap.txt` | `spike/jpms-bnd` |
| `12-bnd` | `12-bnd-serviceloader.txt` | `spike/jpms-bnd` |
| `20-mod` | `20-moditect-all-modules.txt` | `spike/jpms-moditect` only |
| `30-cross` | `30-cross-cutting.txt` | both (byte-identical) |

Baseline for both arms: at `999-SNAPSHOT` no published jar can even form a *legal* automatic
module name — `kubernetes.client.999.SNAPSHOT: Invalid module name: '999' is not a Java
identifier` — because Java only strips a filename version matching `-(\d+(\.|$))`
(`00-base:1-39`). Only `httpclient-jdk` survives, and only because it already ships an
`Automatic-Module-Name` (`00-base:13-19`). At a release version such as 7.9.0 these same jars
would instead become filename-derived automodules, which is the defect #7986 reports.

## Calibration you must read before the table

The moditect arm measured **1 of 7** modules getting a descriptor (`20-mod:432`). That figure is
**an artifact of this spike's 7-module slice combined with the harness's no-`-am`/no-full-install
constraint, not a ceiling**. `zjsonpatch` is the only slice module with no fabric8 compile
dependency, so it is the only one immune to the `999-SNAPSHOT` naming failure; every other slice
module depends on an out-of-slice fabric8 jar that has neither a descriptor nor an
`Automatic-Module-Name` purely because the spike applied moditect to only 7 modules
(`20-mod:457-471`).

Experiment A tested the bootstrap hypothesis on the cheapest edge and **it holds**: naming
`kubernetes-model-common` and single-module-installing it made `kubernetes-model-core` build and
resolve `requires io.fabric8.kubernetes.model.common` correctly, with `provides` and `uses` for
free (`20-mod:481-553`). So the closure bootstraps **per-edge**.

**Boundary of what was proven: one dependency edge.** Whether all ~20 out-of-scope closure
members (`kubernetes-model-rbac`, `-apps`, `-batch`, … ) bootstrap cleanly is **unproven and must
not be extrapolated in either direction** (`20-mod:570-595`, `20-mod:642-657`). Each may carry its
own Sundr split package, as `kubernetes-model-common` did.

Do not read this document as "moditect only manages 1/7", and do not read it as "moditect covers
everything".

**One question that looked like coverage is separate, and is now closed.** A follow-up measured
whether moditect writes a descriptor into a plain `packaging=jar` **main** jar at all — the arm's
central claimed advantage over bnd, previously an inference from the plugin wiring. It does:
`generator-annotations` (`packaging=jar`, and deliberately chosen because it has **zero** compile
dependencies, so no jdeps closure could confound the result) builds successfully and its plain
unclassified main jar carries a real `module-info.class` (`20-mod:659-728`). Boundary, and it is a
tight one: this proves the **mechanism** reaches `packaging=jar` main jars. It does **not** prove
the three failing slice modules (`kubernetes-client-api`, `kubernetes-client`, `httpclient-jdk`)
would succeed — those fail on the independent jdeps closure-naming problem, which is unrelated to
packaging and already blocked `packaging=bundle` modules too. `generator-annotations` also sits
outside the original 7-module slice, so it changes neither the **1/7** figure nor the
**6 new / 7 total** naming-cost figure.

## Corrected figures

Earlier drafts of the plan circulated 60 / a homogeneous 15 / 11. Those are wrong. The figures
below were re-derived in Task 3 and independently re-verified:

| Figure | Value | Derivation |
|---|---|---|
| Published modules (poms touched by the rejected PR `da342969c4`) | **74** | `11-bnd:226-227` |
| Reached by bnd with no other change (`packaging=bundle` already) | **59** | `11-bnd:229-230` |
| Gap, wired for bnd → fixed by `packaging=bundle` conversion | **9** | `11-bnd:232-244` |
| Gap, no bnd wiring at all → conversion does nothing | **6** | `11-bnd:246-252` |
| bnd ceiling **after** paying the conversion cost | **68 of 74** | 59 + 9 |
| Poms declaring `<classifier>bundle</classifier>` repo-wide | **10** (9 producers + 1 consumer) | `11-bnd:166`, `11-bnd:287-289` |

The 15-module gap is **not homogeneous**. The 9 that convert are
`kubernetes-client`, `kubernetes-client-api`, `openshift-client`, `openshift-client-api` and all
five httpclients — i.e. exactly the artifacts a consumer puts on a module path. The 6 that do not
are `junit/kube-api-test/core`, `junit/kube-api-test/client-inject`,
`junit/kubernetes-junit-jupiter`, `junit/kubernetes-server-mock`, `junit/mockwebserver` and
`extensions/open-virtual-network/client`; they run no `maven-bundle-plugin` execution in any form
and would need OSGi metadata authored from scratch — per-module work of exactly the kind this
arm's thesis rejects (`11-bnd:272-277`).

## Descriptor fidelity vs the rejected hand-written baseline

Comparing each arm's generated descriptor against what a human wrote by hand on
`feat/1996-jpms-module-descriptors`. This is the check the spec flagged as load-bearing: a
`requires` present by hand but absent from the generated descriptor is a silent omission.

### `openshift-model` — bnd vs hand-written

Hand-written (`git show feat/1996-jpms-module-descriptors:kubernetes-model-generator/openshift-model/pom.xml`,
`<moduleInfoSource>` block) vs bnd-generated (`10-bnd:33-44`):

| Hand-written | bnd generated | Difference |
|---|---|---|
| `open module io.fabric8.openshift.model` | `io.fabric8.openshift.model … open` | none |
| `exports io.fabric8.openshift.api.model` | same | none |
| `exports …customresourcestatus.conditions.v1` | same | none |
| `requires transitive io.fabric8.kubernetes.model.core` | `requires kubernetes-model-core transitive` | **wrong name**, right relationship |
| `requires transitive io.fabric8.kubernetes.model.rbac` | `requires kubernetes-model-rbac transitive` | **wrong name**, right relationship |
| `requires transitive io.fabric8.openshift.model.config` | *absent* | **omitted** — justified: zero bytecode references (`10-bnd:159-169`) |
| `requires transitive com.fasterxml.jackson.annotation` | same, correct dotted name | none |
| `requires com.fasterxml.jackson.databind` | `requires jackson-databind transitive` | **wrong name**, and `transitive` added where the human wrote plain |
| `requires static builder.annotations` | *absent* | **omitted** — dropped entirely, not marked `static` (`10-bnd:188-195`) |
| — | `requires jackson-core transitive` | added, **wrong name** |
| — | `requires kubernetes-model-common transitive` | added, **wrong name** |

Four of eight hand-written `requires` come out with a wrong module name; two are omitted.

### `kubernetes-model-core` — moditect vs hand-written

Hand-written (`…/kubernetes-model-core/pom.xml`, `<moduleInfoSource>`) vs moditect-generated in
Experiment A (`20-mod:537-553`):

| Hand-written | moditect generated | Difference |
|---|---|---|
| `open module io.fabric8.kubernetes.model.core` | `io.fabric8.kubernetes.model.core … open` | none |
| 6 `exports` (`…api`, `…api.model`, `…clusterapi.core.v1beta1`, `…runtime`, `…version`, `…internal`) | identical 6 | none |
| `requires transitive io.fabric8.kubernetes.model.common` | `requires io.fabric8.kubernetes.model.common` | correct name, **`transitive` lost** |
| `requires transitive com.fasterxml.jackson.annotation` | `requires com.fasterxml.jackson.annotation` | correct name, **`transitive` lost** |
| `requires com.fasterxml.jackson.databind` | same | none |
| `requires static builder.annotations` | *absent* | **omitted** — dropped, not marked `static` |
| — | `requires com.fasterxml.jackson.core` | added, correct name |
| — | `provides …KubernetesResource with …` (48 impls) | added; hand-written had none |
| — | `uses io.fabric8.kubernetes.api.model.KubernetesResource` | added; hand-written had none |

**The two arms fail in opposite directions.** bnd preserves `transitive` but gets the module names
wrong. moditect gets the names right but drops every `transitive` modifier — jdeps does not infer
re-export, so a consumer that relied on `io.fabric8.kubernetes.model.core` re-exporting
`…model.common` would break. Neither reproduces the hand-written descriptor exactly. Both drop
`requires static builder.annotations`.

Not comparable: `openshift-model` under moditect (never built, `30-cross:117`,
`20-mod:180-183`) and `kubernetes-model-core` under bnd (never built, `10-bnd:74-130`) — so the
same module could not be diffed under both arms.

## Comparison table

| Question | bnd | moditect | Evidence |
|---|---|---|---|
| **Modules covered without other changes** | **59 of 74** — every `packaging=bundle` module gets its main jar's descriptor for free | **1 of 7** slice modules as measured — confounded, see Calibration. Separately, **moditect's claimed "writes the main jar regardless of packaging" advantage is now measured and confirmed**: on `generator-annotations` (`packaging=jar`, zero compile dependencies, so no closure could confound it) the plain unclassified main jar carries a real `module-info.class` with the correct name and both `exports`. Repo-wide coverage remains **not measured** (would need Task 5's config applied to all 74 with an ordered `install`) | `11-bnd:229-230`, `11-bnd:254-260`; `20-mod:432`, `20-mod:659-728`, `20-mod:642-657` |
| **Prerequisite change needed** | Convert the **9** wired `packaging=jar` modules to `packaging=bundle`. Prototype proven on `kubernetes-client-api`: main jar gained the real descriptor and the `-bundle` classified artifact disappeared. Cost: drops a published classified artifact; `platforms/karaf/features/src/main/resources/feature.xml:65,66,71` and `platforms/karaf/itests/pom.xml:41,47` must be updated first. Reaches **68 of 74** after paying it; the other 6 need bnd wiring from scratch — or moditect, whose execution is bound unconditionally in the root pom with no packaging guard and needs no OSGi wiring | No packaging change. Instead requires **every jar in the transitive closure** to resolve to a legal module name before `jdeps` will run at all — i.e. a fully ordered install with all ~74 named — plus a central 13-artifact provided-scope exclusion list | `11-bnd:168-219`, `11-bnd:152-166`, `11-bnd:279-296`; `20-mod:229-240`, `20-mod:505-512` |
| **Per-module pom lines required (74-module scale)** | **5** name properties (the frozen httpclient names), because the `${replace}` macro derives the rest centrally. **Plus** a `register:` clause per ServiceLoader provider: 1 clause for `httpclient-jdk`, 4 for `kubernetes-client`. Repo-wide count of affected modules **not measured** — 21 poms mention `osgi.serviceloader` (measured here, see below), but that count mixes provide- and require-capability and is a proxy, not the answer | **~74** `<jpms.module.name>` properties (6 new + 1 pre-existing over the 7-module slice; Maven has no string-replace primitive, full stop). **Plus** 1 central 13-artifact exclusion list, with no bnd equivalent, likely to recur as the closure widens. Experiment A needed an 8th module named to unblock one of the 7 | `10-bnd:1-7`; `12-bnd:28-46`, `12-bnd:91-123`; `20-mod:57-75`, `20-mod:440-448`, `20-mod:652-657` |
| **Central name derivation possible** | **Yes.** `${replace;${project.artifactId};-;.}` evaluated first try; manifest read `Automatic-Module-Name: io.fabric8.zjsonpatch`. No fallback needed | **No.** Maven property interpolation has no string-replace; no build-helper or extension alternative found | `10-bnd:1-7`; `20-mod:70-75` |
| **`kubernetes-model-core` buildability** | **Does not build.** NPE in bndlib 6.3.1 `JPMSModuleInfoPlugin.serviceLoaderUses:515` → `Descriptors.getTypeRefFromFQN:703`. `serviceLoaderUses` does a plain `attrs.get(osgi.serviceloader)`, which is null because the pom expresses the value the spec-correct way, via `filter:="(osgi.serviceloader=…)"`. Genuine bndlib bug; no instruction-level escape hatch. Fails identically on JDK 11 and 17 | **Builds**, once `kubernetes-model-common` is named and installed (Experiment A). Emits correct dotted `requires`, plus `provides` and `uses` | `10-bnd:74-130`, `30-cross:53-62`; `20-mod:481-553` |
| **Class-file version, and `open` flag** | **major 53** (Java 9 format) + `flags: (0x8000) ACC_MODULE`, via `javap -v` — safe for the Java 11 floor. Every bnd descriptor dump reports the module as `open`, though `ACC_OPEN` itself was read from `jar --describe-module`, not from the bytecode | **major 53, minor 0** + `ACC_MODULE` — identical to bnd, so **no Java 11 floor concern either way**. `open` verified in the **bytecode**: `open module io.fabric8.generator.annotations@999-SNAPSHOT` and `ACC_OPEN` on the constant-pool Module entry, so the shared `<open>true</open>` config demonstrably takes effect rather than being silently accepted | `10-bnd:9-17`, `10-bnd:35`; `20-mod:740-791` |
| **Internal packages leaked into `exports`** | **No leak beyond the curated list.** bnd's `exports` come straight from the pre-existing `osgi.export` property, so the surface is whatever the project already publishes to OSGi — `internal`-named packages do appear (`…dsl.internal`, `…utils.internal`, `…kubernetes.internal`) but only because `osgi.export` already lists them. The build also warned that `io.fabric8.kubernetes.client.handlers` is an unused `-privatepackage` instruction | **Not measured** for the intended target. `kubernetes-client` never produced a descriptor, so the check returned nothing. The one module measured (`kubernetes-model-core`, Experiment A) exported exactly the 6 packages the hand-written descriptor exports — no leak there. jdeps's documented default is to export every package it sees class files for, so a leak is expected on a module whose `osgi.export` excludes packages; that remains unverified. Step that would take it: install `kubernetes-client-api` with a descriptor, rebuild `kubernetes-client`, diff `exports` against `osgi.export` | `11-bnd:34-61`, `12-bnd:149`; `20-mod:396-408`, `20-mod:541-546` |
| **`provides` emitted, incl. nested `HttpClient$Factory`** | **Yes, with per-module work.** Absent by default (0 clauses). Adding `register:` produced `provides io.fabric8.kubernetes.client.http.HttpClient$Factory with io.fabric8.kubernetes.client.jdkhttp.JdkHttpClientFactory` — character-for-character, `$` intact. Four `ServiceToURLProvider` impls merged into one clause with plain repeated syntax; the feared `~2`/`~3`/`~4` duplicate-marker workaround was **not** needed | **Yes for free, on the one module measured.** `provides …KubernetesResource with …` (48 impls) **and** `uses`, from `META-INF/services` with zero `register:`-equivalent config. **The nested `HttpClient$Factory` case is NOT measured for moditect**: `httpclient-jdk`'s moditect build failed, and the `provides` clause visible for it is the JDK's own automatic-module synthesis, not a moditect-authored descriptor. Step that would take it: install `kubernetes-client-api` with a descriptor, rebuild `httpclient-jdk`, dump | `12-bnd:6-26`, `12-bnd:82-89`, `12-bnd:159-182`; `20-mod:410-428`, `20-mod:547-568` |
| **`uses` clause emitted** | **No — and unreachable at bndlib 6.3.1.** `kubernetes-client-api` emits none. Getting one requires a `Require-Capability osgi.serviceloader`, whose spec-correct form is `filter:="(osgi.serviceloader=…)"` — exactly the shape that NPEs bndlib 6.3.1. So `uses` is blocked by the same defect that blocks `kubernetes-model-core`. Not needed for ServiceLoader at runtime; needed for a correct descriptor and for `jlink` | **Yes, free.** `uses io.fabric8.kubernetes.api.model.KubernetesResource` emitted for `kubernetes-model-core` from `META-INF/services` + `addServiceUses`, no configuration | `12-bnd:187-210`, `12-bnd:212-223`; `20-mod:553`, `20-mod:562-568` |
| **Silently omitted `requires`** | **The failure mode is worse than omission: silently WRONG names.** bnd never fails to find *a* name — the brief's target debug string `Can't find a module name for imported package` never appears — it falls back to the raw Maven artifactId. 19 dependency names guessed on one module, none of them legal JPMS names. **The wrong names split into two kinds — see "Which wrong names self-heal" below; only one kind survives full rollout.** Two hand-written entries were also omitted outright: `openshift-model-config` (justified — zero bytecode references) and `requires static builder.annotations` (dropped, not marked `static`) | **Names correct, but `transitive` silently lost** on every `requires` — jdeps does not infer re-export. `requires static builder.annotations` also dropped. When a name cannot be resolved, moditect does not emit a wrong one: the build fails outright | `10-bnd:212-292`, `10-bnd:159-195`; `20-mod:537-553`, and the fidelity diffs above |
| **Multi-release-jar dependency names correct** | **No.** `jackson-core` and `jackson-databind` ship `module-info.class` only at `META-INF/versions/9/`; bnd reads the jar root only, so it emits `requires jackson-core` / `requires jackson-databind` instead of `com.fasterxml.jackson.core` / `com.fasterxml.jackson.databind`. `jackson-annotations`, which ships its `module-info` at the root, resolves correctly — confirming the mechanism. A consumer on a real module path fails resolution even though the build succeeds and the descriptor looks plausible. Fix would be `-jpms-module-info-options …;substitute=` per affected dependency. (Jackson injects that `module-info` using moditect.) | **Yes.** With `<jdepsExtraArgs>--multi-release 9</jdepsExtraArgs>` moditect emits `requires com.fasterxml.jackson.core` and `requires com.fasterxml.jackson.databind`, read from the MR-jar `module-info`. `--multi-release 11` also worked; 9 is the precise documented value. Note the flag is **mandatory**: without it jdeps refuses to run at all (`jackson-core-2.21.4.jar is a multi-release jar file but --multi-release option is not set`) | `10-bnd:274-292`, `10-bnd:280-282`; `20-mod:597-638`, `20-mod:15-32` |
| **Split package honoured** | **Yes for the declarative case.** The `osgi.export` exclusion in `openshift-model/pom.xml` took effect: `OK no split packages`, exit 0. This mattered because bnd's wildcard `Export-Package` (`io.fabric8.openshift.api.model**`) can over-claim the `config.*` sub-package declaratively even with no such class files present. Behaviour against a **real physical** split package was not tested under bnd | **Structurally cannot over-claim, and hard-fails on a real split.** jdeps computes `exports` from class files physically present, so bnd's wildcard mistake is inapplicable — but moditect does **not** read `osgi.export` at all, so the same scan measured only that the two jars never physically overlapped (0 `api/model/config` entries). Against a genuine physical split, jdeps refuses: `Modules sundr.model.utils and sundr.model.base export package io.sundr.model to module sundr.codegen.apt`, then a second independent split (`io.sundr.builder`). That forced the 13-artifact exclusion list — a direct reproduction of what made PR #7911 abandon generated descriptors | `10-bnd:132-140`; `20-mod:92-132`, `20-mod:487-512`, `20-mod:377-388` |
| **Descriptors JDK-stable across 11/17** | **Yes.** Both JDKs captured back-to-back in one session and diffed against each other (not against historical captures, which had drifted via `~/.m2`). `diff` exit 0, no output; both dumps 22 lines, md5 `716333e5…` on both. Non-degeneracy verified line by line. Consistent with bnd's `DEFAULT_MODULE_EE` resolving to a fixed `EE.JavaSE_11` constant | **Yes** — and this was the arm expected to vary, since jdeps runs from the invoking JDK. Both dumps 61 lines, md5 `218439af…`. Holds for the 4 modules that build (`zjsonpatch`, `kubernetes-model-common`, `kubernetes-model-core`, `openshift-model-config`) | `30-cross:14-101` (bnd), `30-cross:102-176` (moditect) |
| | *JDK 21 not measured for either arm* — outside Task 6's commands. Step that would take it: repeat Task 6 Question 1 with `SPIKE_JDK=21` | | `30-cross:182-184` |
| **Jar reproducibility** | **Reproducible.** Two independent `clean package` builds of descriptor-carrying `zjsonpatch` are byte-identical (`cmp -s` → `REPRODUCIBLE`). The root pom's `<_reproducible>true</_reproducible>` plus bnd's timestamp handling holds up with a `module-info.class` present | **Not measured.** Task 6 Question 2 ran on `spike/jpms-bnd` only. Step that would take it: check out `spike/jpms-moditect`, run `-pl zjsonpatch clean package` twice, `cmp -s` the two jars | `30-cross:186-240` |
| **Uberjar left without a descriptor — deliberate or accidental?** | **No descriptor, but ACCIDENTAL.** `uberjar/pom.xml` is `packaging=jar`, so `maven-bundle-plugin` never binds to the lifecycle and its mojo never runs at all (confirmed: no `bundle`/`moditect` goal in the build log). A structural side effect, not a deliberate skip | **No descriptor, and ACCIDENTAL — worse: the build FAILS OUTRIGHT** (`mvn exit=1`). `add-module-info` is bound unconditionally in the root pom with no packaging guard, and `uberjar/pom.xml` has no `<skip>` or override. moditect *does* attempt the shaded jar; it only fails because a dependency (`kubernetes-model-core` from `~/.m2`) cannot be named. **Nothing in the pom would stop moditect writing a split-package-violating descriptor if that naming defect were fixed** | `30-cross:246-284` (bnd), `30-cross:286-345` (moditect), `30-cross:392-400` |
| | *Why a descriptor would be wrong either way:* all 6 of `kubernetes-model-core`'s exported packages are duplicated, unrelocated, inside the primary uberjar artifact — the plain `uberjar` shade execution declares no `<relocations>`; only the separately-classified `-versioned` execution relocates. **Both arms need an explicit exclusion; neither has one today.** | | `30-cross:347-390` |
| **Upstream maintenance status** | **Active.** bnd's latest commit **2026-08-08** — one day before this document. `maven-bundle-plugin` 5.1.9 / bndlib 6.3.1 pinned here (`pom.xml:150`); newer releases exist: bndlib 6.4.0 (still Java 8+), and `maven-bundle-plugin` 6.0.2 carrying bndlib 7.0.0 — the latter **requires JDK 17 and so is blocked by the JDK 11 CI floor**. The 6.3.1 NPE is unfixed in the pinned version | **Dormant ~12.7 months.** `moditect` `pushed_at` **2025-07-20**; latest release **1.3.0.Final, 2025-07-20** — the exact version this arm uses, so there is no newer release to move to if a defect is hit. **87** open issues. Repository **not archived** | Versions in use: `pom.xml:150`, `20-mod:17`. **The cadence figures above were derived from the GitHub API on 2026-08-09, not from any spike results file**, so they are point-in-time and will drift; re-derive before quoting them later |

### The one figure measured in this task

The `register:` cost row needed a repo-wide denominator that no earlier task captured. One command:

```
$ /usr/bin/grep -rl 'osgi.serviceloader' --include=pom.xml . | LC_ALL=C sort
./extensions/certmanager/client/pom.xml
./extensions/chaosmesh/client/pom.xml
./extensions/istio/client/pom.xml
./extensions/knative/client/pom.xml
./extensions/open-cluster-management/client/pom.xml
./extensions/open-virtual-network/client/pom.xml
./extensions/tekton/client/pom.xml
./extensions/verticalpodautoscaler/client/pom.xml
./extensions/volcano/client/pom.xml
./extensions/volumesnapshot/client/pom.xml
./httpclient-jdk/pom.xml
./httpclient-jetty/pom.xml
./httpclient-okhttp/pom.xml
./httpclient-vertx-5/pom.xml
./httpclient-vertx/pom.xml
./kubernetes-client-api/pom.xml
./kubernetes-client/pom.xml
./kubernetes-model-generator/kubernetes-model-core/pom.xml
./kubernetes-model-generator/pom.xml
./openshift-client-api/pom.xml
./openshift-client/pom.xml
```

21 poms. This is a **proxy, not the answer**: it matches the namespace anywhere in the pom, so it
mixes `Provide-Capability` (which needs `register:` under bnd) with `Require-Capability` (which
does not, and which is the shape that NPEs bndlib 6.3.1). The exact per-module `register:` cost
was not measured.

## Which of bnd's wrong names self-heal, and which do not

This is **reasoning from the measured mechanism, not a measurement** — no task ever observed bnd
reading a module name off a dependency's descriptor or `Automatic-Module-Name`. It matters because
it decides how big bnd's residual correctness defect actually is, and the two kinds of wrong name
should not be lumped together.

bnd resolved `com.fasterxml.jackson.annotation` correctly *because* that jar ships a real
`module-info.class` at its root, and guessed wrong for everything whose name it could not read
there (`10-bnd:274-292`). The 19 wrong guesses on `openshift-model` therefore split:

- **fabric8 siblings** (`kubernetes-model-core`, `kubernetes-model-common`, `kubernetes-model-rbac`,
  …) were guessed wrong because the `~/.m2` jars carried neither a `module-info` nor an
  `Automatic-Module-Name` — a state that predates this spike (`10-bnd:283-286`). At full rollout
  every one of them would carry an `Automatic-Module-Name` from the central `${replace}` macro, at
  the jar root where bnd reads. **These names would very likely become correct on their own.**
- **third-party multi-release jars** (`jackson-core`, `jackson-databind`) are guessed wrong for a
  reason rollout cannot fix: their `module-info.class` lives only at `META-INF/versions/9/`, which
  bnd's classpath analysis does not read (`10-bnd:280-282`). **These do not self-heal.** They need
  either an explicit `-jpms-module-info-options …;substitute=` per affected dependency, or a bndlib
  version that reads MR jars — the untested remedy below.

So bnd's shipped-descriptor defect is narrower than the raw 19-name count suggests: an enumerable
set of third-party MR jars, centrally fixable. Two caveats. First, the self-healing half is
inference; the one measurement that would settle it is cheap — install one fabric8 sibling built
with the new manifest, rebuild a dependent, and read its `requires`. Second, the MR-jar set was
enumerated only for `openshift-model`'s classpath; the repo-wide count of MR-jar dependencies was
not measured.

## An untested remedy that could change the verdict

bnd's two worst results — `kubernetes-model-core` unbuildable, and `uses` unreachable — are the
same defect: `JPMSModuleInfoPlugin.serviceLoaderUses` in **bndlib 6.3.1**, the version embedded in
`maven-bundle-plugin` 5.1.9. Its sibling `serviceLoaderProviders` guards with `containsKey`;
`serviceLoaderUses` does not (`10-bnd:86-122`, `12-bnd:212-223`).

**Pinning a newer bndlib — e.g. 6.4.0 — as a `maven-bundle-plugin` `<dependency>` may fix that
NPE and may also fix the multi-release-jar misreads, while preserving the JDK 11 CI floor**
(6.4.0 still supports Java 8+, unlike `maven-bundle-plugin` 6.0.2, whose bndlib 7.0.0 requires
JDK 17 and is therefore blocked).

**This was never tested.** It is not a reason to prefer bnd today; it is an open option that could
change the verdict. Testing it means: add a `<dependency>` on `biz.aQute.bnd:biz.aQute.bndlib`
(6.4.0 or later Java-8-compatible release) to the root pom's `maven-bundle-plugin` declaration,
then re-run three checks against the bnd arm — (1) does `-pl kubernetes-model-generator/kubernetes-model-core
package` now succeed, (2) does adding a `filter:="(osgi.serviceloader=…)"` `Require-Capability`
to `kubernetes-client-api` now yield a `uses` clause instead of an NPE, (3) does `openshift-model`
now emit `requires com.fasterxml.jackson.core` instead of `requires jackson-core`. Half a day at
most; it decides whether bnd is a correctness-viable mechanism at all.

## Recommendation

**If converting the 9 wired `packaging=jar` modules to `packaging=bundle` — dropping the
karaf-referenced `-bundle` classifier — is acceptable:** adopt bnd, gated on testing bndlib ≥ 6.4.0.
**bnd still reaches only 68/74; the last 6 need moditect or fresh OSGi wiring.** At 6.3.1 it is
unshippable: `kubernetes-model-core` fails, `uses` is unreachable, multi-release-jar `requires`
names are wrong. If the pin fails they need per-dependency `substitute=` — enumerable and central;
bnd's other wrong names should self-heal at rollout.

**If not:** bnd caps at 59 of 74, missing all 9 artifacts consumers put on a
module path. Use moditect for those 9 — now measured to write plain `packaging=jar` main jars.
Costs: closure-wide naming (~74 properties), the exclusion list, an uberjar skip, dormant upstream.

**Strongest argument against:** bnd's defect ships. `requires jackson-core` fails at consumer
module resolution after release; moditect's fail loudly in CI. #7986 is a correctness report;
I recommend the cheaper arm.

## Everything marked "not measured"

| Cell | Step that would take it |
|---|---|
| moditect repo-wide coverage at 74-module scale | Apply Task 5's config to all 74 modules with an ordered `mvn install`; dump descriptors |
| Whether bnd reads a dependency's `Automatic-Module-Name` — i.e. whether its fabric8-sibling wrong names self-heal at rollout (currently reasoning, not measurement) | Install one fabric8 sibling built with the new manifest, rebuild a dependent, read its `requires` |
| Repo-wide count of multi-release-jar dependencies (the names that do **not** self-heal) | Enumerate `META-INF/versions/*/module-info.class` across the resolved dependency set |
| moditect `exports` leak on a module whose `osgi.export` excludes packages | Install `kubernetes-client-api` with a descriptor, rebuild `kubernetes-client`, diff `exports` against `osgi.export` |
| moditect nested `HttpClient$Factory` in a real moditect-authored descriptor | Install `kubernetes-client-api` with a descriptor, rebuild `httpclient-jdk`, dump |
| moditect jar reproducibility | On `spike/jpms-moditect`: `-pl zjsonpatch clean package` twice, `cmp -s` the jars |
| JDK 21 stability, both arms | Repeat Task 6 Question 1 with `SPIKE_JDK=21` |
| Exact per-module `register:` cost under bnd | Count poms whose `osgi.provide-capability` (not `require-capability`) names `osgi.serviceloader` |
| bnd behaviour against a real physical split package | Run bnd over two jars that physically share a package |
| Runtime `ServiceLoader` resolution from a real module path, either arm | Build a module-path consumer and resolve the service — Phase 6 work, out of scope for the whole spike (`30-cross:419-421`, `12-bnd:302-308`) |

## Revision note

This document was first written when three cells above read "not measured". A follow-up
(`spike/jpms-moditect` commit `d6da51c856`, recorded at `20-mod:659-791`) closed them: moditect
**does** write into a `packaging=jar` main jar; its `module-info.class` is **major 53**, matching
bnd; and its module is **`open`, verified in the bytecode**. The upstream-maintenance figures were
separately re-derived from the GitHub API on 2026-08-09 rather than carried from a summary.

**The recommendation was re-derived against the closed cells and lands in the same place, in both
branches of the condition.** What changed is confidence, not direction: branch 2 no longer needs
its hedge on moditect's `packaging=jar` capability, and branch 1 is slightly stronger because
separating self-healing from non-self-healing wrong names narrows bnd's shipped defect to an
enumerable, centrally-fixable set. Nothing in the new evidence favours one arm over the other on
correctness — class-file version and `open` turned out to be parity, not a differentiator.
