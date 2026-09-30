extends RefCounted
# Integration adaptation of the archived audit_strong.gd, not a new benchmark claim.
# Required engine patch: clone_view constructor uses explicit seed:1.
const PRESETS := {"medium": {"samples": 2, "horizon": 16}, "hard": {"samples": 4, "horizon": 24}}
var snapshot: Battle
var candidates: Array = []
var totals: Array = []
var best: Dictionary = {}
var done := true
var reason := "not_started"
var simulations := 0
var completed_samples := 0
var sample_index := 0
var candidate_index := 0
var samples := 4
var horizon := 24
var decision_index := 0
var last_score := -INF

# Only supports ordinary no-commander, non-siege stack decisions.
# Hero UNITS (the promoted stack state) are supported; commander records are not.
func unsupported_reason(b: Battle) -> String:
	if b.over != null: return "battle_over"
	if b.pre_combat: return "pre_combat"
	if b.probe: return "probe_battle"
	if b.wall != null: return "siege"
	for sd in b.sides:
		if sd.hero != null or sd.hs != null: return "commander_present"
	if b.current_stack() == null: return "not_stack_turn"
	return ""

func clone_sim(b: Battle, planning_seed: int) -> Battle:
	var c := b.clone_view()
	c.probe = false
	c.rng = Rng.new(planning_seed)
	c.log = []
	return c

func baseline(b: Battle) -> Dictionary:
	var saved_rng := b.rng.get_state()
	var d := CombatAI.decide(b, b.current_stack())
	b.rng.set_state(saved_rng)
	return d

# begin/advance operate on a private snapshot. No reads of live RNG state.
# Return false means caller must use unchanged CombatAI.step(live_battle).
func begin(b: Battle, tick: int, difficulty: String = "hard") -> bool:
	done = true
	best = {}
	candidates = []
	totals = []
	simulations = 0
	completed_samples = 0
	sample_index = 0
	candidate_index = 0
	last_score = -INF
	snapshot = null
	reason = unsupported_reason(b)
	if reason != "": return false
	if not PRESETS.has(difficulty):
		reason = "unknown_difficulty"
		return false
	samples = PRESETS[difficulty].samples
	horizon = PRESETS[difficulty].horizon
	decision_index = maxi(0, tick)
	snapshot = clone_sim(b, 1)
	best = baseline(snapshot)
	candidates = legal(snapshot)
	candidates.push_front(best.duplicate(true))
	totals.resize(candidates.size())
	totals.fill(0.0)
	done = false
	reason = "searching"
	return true

# One bounded simulation (root move plus horizon continuation actions).
# A full sweep evaluates every candidate with a common independent seed.
# Partial sweeps never affect the published best action.
func advance() -> bool:
	if done: return true
	var c := clone_sim(snapshot, 9871 + decision_index * 7919 + sample_index * 104729)
	var err = do_act(c, candidates[candidate_index])
	if err != null:
		done = true
		reason = "illegal_candidate"
		return true
	for step_n in horizon:
		if c.over != null or c.current() == null: break
		var d := baseline(c)
		if do_act(c, d) != null:
			done = true
			reason = "illegal_continuation"
			return true
	totals[candidate_index] += eval_state(c, snapshot.current_stack().side)
	simulations += 1
	candidate_index += 1
	if candidate_index == candidates.size():
		completed_samples += 1
		var selected := 0
		for i in range(1, candidates.size()):
			if totals[i] > totals[selected] + 0.00001: selected = i
		best = candidates[selected].duplicate(true)
		last_score = totals[selected] / completed_samples
		candidate_index = 0
		sample_index += 1
		if sample_index == samples:
			done = true
			reason = "complete"
	return done

func cancel() -> void:
	done = true
	reason = "cancelled"

func result() -> Dictionary:
	return {"action": best.duplicate(true), "reason": reason, "complete": reason == "complete", "completed_samples": completed_samples, "simulations": simulations, "score": last_score}

# For headless tests/offline use. Zero deadline means deterministic full budget.
# Wall-clock cutoffs vary by machine. Never apply the result to a changed turn.
func decide(b: Battle, tick: int, difficulty: String = "hard", max_msec: int = 0) -> Dictionary:
	if not begin(b, tick, difficulty): return result()
	var start := Time.get_ticks_msec()
	while not done:
		if max_msec > 0 and Time.get_ticks_msec() - start >= max_msec:
			done = true
			reason = "timeout"
			break
		advance()
	return result()

func legal(b: Battle) -> Array:
	var a = b.current_stack()
	if a == null: return []
	var out := []
	for t in b.enemies_of(a):
		if b.check_rally(a,t) == null: out.append({"action":"rally", "target":t.id})
		if b.check_attack(a, t) == null: out.append({"action":"attack", "target":t.id})
		if b.check_engage(a, t) == null: out.append({"action":"engage", "target":t.id})
		if b.check_deny(a, t) == null:
			for i in b.deny_options(a, t).size(): out.append({"action":"deny", "target":t.id, "opt":i})
	for t in b.allies_of(a):
		if b.check_guard(a, t) == null: out.append({"action":"guard", "target":t.id})
		if b.check_rally(a, t) == null: out.append({"action":"rally", "target":t.id})
	if b.check_fallback(a) == null: out.append({"action":"fallback"})
	if b.can_wait(a): out.append({"action":"wait"})
	out.append({"action":"seek"})
	out.append({"action":"retaliate"})
	return out

func do_act(b: Battle, d: Dictionary):
	return b.act(d.action, d.get("target", null), d.get("opt", null))

func eval_state(b: Battle, side: int) -> float:
	if b.over != null:
		if b.over.winner == side: return 1000.0
		if b.over.winner == 1-side: return -1000.0
		return 0.0
	var amounts := [0.0,0.0]
	for st in b.stacks:
		if st.count > 0: amounts[st.side] += st.count * CombatAI.value_of(st)
	return 100.0 * (amounts[side]-amounts[1-side]) / maxf(1.0, amounts[0]+amounts[1])

