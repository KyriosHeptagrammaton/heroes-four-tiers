# Verification results

Date: 2026-09-30 UTC. Engine: Godot 4.3 stable official `77dcf97d8` on cloud Linux x86_64. Base source: commit `26d4cdc0436c740cae6a2524bdfd057789f247a7`.

## Recovered reference

All 33 recorded file hashes in the original evidence archive verified. `reference/audit_strong.gd` is byte-identical to the recovered original. The full original archive is also included as `reference/original-evidence.zip`; the archived script's hard-coded output location remains unchanged for provenance, so use the supplied package tests to rerun comparisons.

## Current tests

- Headless Godot4.3 editor import: passed
- Existing worldgen_selfcheck: passed (`selfcheck OK`)
- `package_search`: 206 checks, no failures; 32 exact original action comparisons (4 factions × 4 sequential positions × 2 budgets)
- `review_search`: 8 additional successive Delta decisions exactly match original4×24 search
- Easy adapter equals unchanged native step on a deterministic fixture
- Hard commander fallback equals unchanged native step on a real commander fixture
- Global RNG, complete recursively serialized live battle state and live battle RNG remain unchanged by planning
- Chosen actions accepted by Battle.act; deterministic repeats match
- Partial sweep does not replace baseline; partial later sweep does not replace completed-sweep result
- Cancellation, soft timeout and unsupported-state guards exercised
- No-commander restriction means hero mutable-record aliasing cannot be exercised by search; rejection does not validate hero search

See the raw logs for exact final counts and elapsed times. The independent review test now sets a runner failure flag until all assertions finish. Tests still require explicit success markers and no parse/runtime errors, not merely process exit zero.

## Fresh 16-battle smoke benchmark

One new seed (900001), base mixed-tier mirror armies for each of Alpha/Beta/Gamma/Delta, search on each side. Eight battles per budget, all ordinary no-commander field/dawn/clear battles. Opponent is native heuristic with preview RNG restored, as in historical audit. No deadline applied. This seed is new relative to the historical benchmark, but the same seed was used in some equivalence fixtures. This is a packaging smoke test, not an independent broad strength study.

| Budget | W/L/D | Decisions | Median ms | p95 ms | Maximum ms |
|---|---|---:|---:|---:|---:|
| Medium 2×16 | 4/3/1 | 102 | 107.95 | 274.67 | 413.96 |
| Hard 4×24 | 5/2/1 | 107 | 205.91 | 635.28 | 846.79 |

209 search decisions completed without invalid actions or live Battle RNG changes. Runtime 41.438 seconds for the benchmark process. p95 is nearest-rank. Other verification jobs shared the cloud machine during this measurement; these latencies describe this environment/load, not a minimum-spec guarantee. UI integration must use incremental work and profile the duration of one simulation; no shipping UI latency test was performed.

The sample is tiny and paired by scenario; there are not sixteen independent faction/army/seed blocks. It is not a direct Medium-vs-Hard match and cannot prove ordering. No claim of commander, siege, every terrain/weather, arbitrary mods or large-army support follows from it.

## Historical evidence, not rerun here

- Original 4×24 search vs RNG-isolated native heuristic: 90 wins, 34 losses, 4 draws across 128 battles
- Delta rally ablation 2×16: 63–1 across 64 held-out battles
- Original broad battle audits were not rerun in this packaging task

The existing shipping native step consumes preview RNG differently from the comparator above. Easy is deliberately preserved; a future direct shipping-Easy comparison must be separately run. The original preview RNG bug is not fixed by this pack. Only clone construction's global RNG side effect is fixed.

## Remaining integration acceptance work

Difficulty UI/settings/save wiring, stale-result cancellation and input locking, user-facing fallback disclosure, minimum-device responsiveness, Medium-vs-Hard benchmarks, more independent held-out seeds and compositions. For campaign difficulty, safe commander cloning and full legal spell/command/phase search are prerequisites; until then every battle containing a commander uses native AI for all turns.
