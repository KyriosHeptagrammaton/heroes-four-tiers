# Combat search AI integration pack

For Heroes of Four Seasons (repository `heroes-four-tiers`). This is a tested integration reference, not an already integrated difficulty-menu release.

**Target:** https://github.com/KyriosHeptagrammaton/heroes-four-tiers/tree/26d4cdc0436c740cae6a2524bdfd057789f247a7
**Engine verified:** Godot 4.3 stable, `77dcf97d8`. Prepared 2026-09-30.

## Recommended starting design

- **Easy:** unchanged `CombatAI.step(b)`, including commander behavior and existing preview RNG behavior
- **Medium:** 2 sampled continuations × 16 future actions for every legal candidate
- **Hard:** 4 sampled continuations × 24 future actions for every legal candidate

These are proposed labels/budgets, not a guarantee that Hard beats Medium in every matchup. They are not minimax or optimal play: both sides are assumed to follow the existing heuristic after the candidate root action. Difficulty does not modify unit stats, grant resources, or read future live combat rolls.

## What is included

- `scripts/rules/combat_search_ai.gd`: adaptation with snapshot planning, incremental work, deterministic ties, cancellation and optional soft deadline
- `scripts/rules/combat_difficulty_adapter.gd`: synchronous dispatcher for offline/headless use; Easy and unsupported states delegate to the original AI
- `patches/clone-view-explicit-seed.patch`: required one-line engine fix preventing cloning from consuming global RNG
- `tests/`: safety, original-source equivalence, independent review, and small fresh-seed benchmark
- `reference/audit_strong.gd`: byte-for-byte original archived search harness, including its original historical output path; do not run its `run()` unchanged
- `reference/`: historical results and original archive checksum manifest
- `results/`: actual new Godot test logs and benchmark data
- `handoff.txt`: copy-paste instructions for the coding AI

## Integration into exact target

From the game repository root, copy this pack's `scripts/rules/*.gd` into `scripts/rules/` and `tests/*.gd` into `tests/`. Review and apply `patches/clone-view-explicit-seed.patch` with `git apply`. It changes only the empty clone constructor from an implicit random seed to explicit `seed: 1`. The planner replaces that dummy seed with independent planning seeds. Do not overwrite the game's native `combat_ai.gd`.

Use preloads; these scripts are RefCounted, not new autoloads. The optional synchronous adapter's API is:

```gdscript
var ai = preload("res://scripts/rules/combat_difficulty_adapter.gd").new()
ai.step(battle, "hard", decision_index) # synchronous; unsuitable for smooth UI
```

Persist a battle-scoped monotonic `decision_index` that advances once per committed decision, including opponent decisions. Do not derive it from RNG or time. Save it with the battle if replay after save/load matters. The reference tick had this meaning. Case-sensitive accepted labels are `easy`, `medium`, `hard`; unknown labels safely fall back to native in the adapter.

### UI-safe integration contract

Use `begin(battle, decision_index, difficulty)` then call `advance()` incrementally, yielding process frames between calls. `begin` returns false for unsupported states. `advance` executes one whole candidate simulation (root action plus up to horizon future actions), so it is bounded in operations but not guaranteed under a frame time. Never run the synchronous `decide()`/adapter loop on the UI thread for release integration. Profile on minimum-spec hardware; if one `advance()` is too expensive, split the simulation itself over frames. A worker thread is an alternative only after auditing Godot thread safety: the current implementation reads shared autoload data, and it has not been validated for concurrent use.

Freeze battle input while planning, but keep rendering and cancellation responsive. Hold a battle identity and monotonically incrementing state-generation token at `begin`. Before applying, require the same battle AND the same generation token; actor id alone is insufficient because actors recur. Invalidate on every game-state mutation, turn advance, load/restart, cancel, scene change and battle end. Discard stale results. Check the result reason; only `complete` or an explicitly accepted time-budget stop can be used. If an illegal candidate/continuation is reported, discard and use native fallback on the current state.

Apply once through `Battle.act(action, target, opt)`. This final authoritative rules call revalidates legality. On a non-null error, discard the plan and use native fallback. Do not retry an already successful action. UI wiring, turn tokens, save persistence and difficulty selection are deliberately left to the integrating coding AI.

### Planner API and budget semantics

- `begin(b, tick, "medium"|"hard") -> bool`: copies supported state, finds candidates, returns false with reason otherwise
- `advance() -> bool`: performs one simulation; true means done
- `result() -> Dictionary`: `action` (action/target/opt, possibly heuristic `score`), `reason`, `complete`, `completed_samples`, `simulations`, `score`
- `cancel()`: stops; no automatic application; caller must discard cancellation results
- `decide(b, tick, difficulty, max_msec=0)`: synchronous convenience; zero means full deterministic budget

Candidates remain in engine enumeration order, with native baseline first. Ties within `0.00001` favor the earlier candidate. Scores are totals before tie comparison, exactly like original reference; final diagnostic score is the average. Root duplicates are intentionally retained to match original ordering/budget. There is no candidate pruning.

Each sample evaluates every candidate with the same independent seed `9871 + tick*7919 + sample*104729`. There is no access to live battle RNG state by the planner. Continuation heuristic previews restore the simulation RNG after deciding; only actual simulated combat advances it. `probe=false` is essential for real casualty/progression effects. The seed patch also protects Godot's global RNG.

A partial candidate sweep never replaces the published best. On timeout, use the last fully evaluated sweep; before the first complete sweep, use baseline. `max_msec` is a SOFT deadline: setup happens before the timer and a whole simulation may exceed it. Deterministic replay requires full fixed budgets and unchanged engine/data; deadlines produce hardware/load-dependent choices. There is no silent equal-strength promise when a device times out. Shared mutable rules data must not change during planning.

## Supported versus fallback

Search supports ordinary non-siege stack turns with no commander records on either side. Candidate actions are legal attack, engage, deny (all options), guard, allied/enemy rally, fallback, wait when legal, seek and retaliate. Native promoted hero-unit stack state is supported. With no commanders, wait is normally unavailable because it requires Tactics; its enumeration is retained from the reference.

Search is explicitly refused for commander/hero records (`side.hero` or `side.hs`), siege/wall battles, pre-combat, probes, non-stack turns, ended battles and unknown difficulty. The adapter uses unchanged native AI for these. Thus Medium/Hard currently play identically to Easy for entire commander and siege battles. This matters for campaign coverage; do not hide it behind difficulty labels.

Why not enable commanders immediately? `clone_view` shares commander dictionaries and spells can mutate them (e.g. spellPower). A correct extension needs isolated mutable heroes, commander/precombat sequencing, casts, commands, dispel/transfer and related legality and outcome tests. No such extension is claimed here. Likewise siege wall candidates/continuations need separate validation. No fleeing search or strategic overworld AI is included. This pack does not claim broad terrain/weather/large-army balance coverage.

## Evidence and limits

The historical 128-battle comparison was **90 wins / 34 losses / 4 draws**, with 4×24 search versus an RNG-isolated version of the native heuristic, not the unchanged shipping `CombatAI.step`. Both controllers' preview RNG was restored in that audit. Original source defaults are 3×36, overridden to 4×24 in the saved experiment. Historical Delta rally ablation was 63–1 on 64 held-out battles with 2×16 search; that result is about rally access, not a direct Medium/Hard comparison.

All 33 files in the recovered original evidence archive matched its recorded SHA-256 manifest. This pack retains the original harness unchanged and separately labels the implementation adaptation. Historical results must not be presented as new benchmark results for the adaptation or literal shipping Easy.

New tests cover 32 original-choice comparisons across four factions, four successive states, both budgets; RNG/state purity, legality, deterministic repeats, partial-sweep behavior, soft timeout, cancellation and unsupported-state rejection. Independent review additionally matched eight successive Delta decisions. See `TEST_RESULTS.md` for counts, fresh benchmark results and limitations.

## Re-run with Godot 4.3

Use a writable HOME/XDG environment on restricted Linux. Import first so global script classes are registered:

```sh
godot --headless --editor --path . --import --quit
godot --headless --path . -- --test=package_search
godot --headless --path . -- --test=review_search
PACKAGE_RESULTS=/absolute/writable/benchmark.json godot --headless --path . -- --test=package_benchmark
```

The package_search and review_search tests return nonzero via the existing runner's `failed` flag. Also inspect output for script parse/runtime errors and require the explicit PACKAGE_TEST / REVIEW markers; a Godot launch alone is not a pass. The full 34,800-battle balance audit was NOT rerun for this packaging task. No upstream code was pushed, no game UI was modified and no external coding AI was contacted.
