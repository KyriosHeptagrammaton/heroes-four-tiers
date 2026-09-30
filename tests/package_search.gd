extends RefCounted
const Planner = preload("res://scripts/rules/combat_search_ai.gd")
const Reference = preload("res://tests/audit_strong_reference.gd")
var failed := false
var checks := 0
func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		print("FAIL ", label)
func serialize(v):
	if v is Object:
		var d := {}
		for p in v.get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				d[p.name] = serialize(v.get(p.name))
		return d
	if v is Array:
		return v.map(func(x): return serialize(x))
	if v is Dictionary:
		var d := {}
		for k in v: d[k] = serialize(v[k])
		return d
	return v
func config(faction: String, n: int) -> Dictionary:
	var ref := Reference.new()
	return {"seed": n, "sides": [{"stacks": ref.army(faction, 0)}, {"stacks": ref.army(faction, 0)}]}
func key(d: Dictionary) -> String:
	return str(d.get("action")) + ":" + str(d.get("target")) + ":" + str(d.get("opt"))
func run(_root) -> void:
	Battle._full = false
	var start := Time.get_ticks_msec()
	var adapter = load("res://scripts/rules/combat_difficulty_adapter.gd").new()
	var easy_a := Battle.new(config("alpha", 911))
	var easy_b := Battle.new(config("alpha", 911))
	adapter.step(easy_a, "easy", 0)
	CombatAI.step(easy_b)
	ok(serialize(easy_a) == serialize(easy_b), "Easy exactly native step")
	var hero_cfg := config("alpha", 912)
	hero_cfg.sides[0]["hero"] = Heroes.create("mage", "alpha", "Test commander", Rng.new(17))
	var hero_a := Battle.new(hero_cfg.duplicate(true))
	var hero_b := Battle.new(hero_cfg.duplicate(true))
	adapter.step(hero_a, "hard", 0)
	CombatAI.step(hero_b)
	ok(adapter.last_result.reason == "commander_present", "Hard commander fallback reason")
	ok(serialize(hero_a) == serialize(hero_b), "Hard commander fallback exactly native step")
	var planner := Planner.new()
	var ref := Reference.new()
	var parity_positions := 0
	for faction in ["alpha", "beta", "gamma", "delta"]:
		var b := Battle.new(config(faction, 900001))
		for tick in range(4):
			if b.over != null: break
			for level in ["medium", "hard"]:
				var before = serialize(b)
				seed(771)
				var expected_global := randi()
				seed(771)
				var result := planner.decide(b, tick, level)
				ok(randi() == expected_global, "global RNG purity")
				ok(serialize(b) == before, "full battle state purity")
				ok(result.complete, "completed plan")
				ref.search_samples = Planner.PRESETS[level].samples
				ref.horizon = Planner.PRESETS[level].horizon
				var expected := ref.rollout(b, tick, "builtin")
				ok(key(result.action) == key(expected), "original action parity " + faction + " " + level)
				var repeat := planner.decide(b, tick, level)
				ok(key(result.action) == key(repeat.action), "deterministic repeat")
				var c := planner.clone_sim(b, 81)
				ok(planner.do_act(c, result.action) == null, "action legal")
				parity_positions += 1
			ref.step_policy(b, "builtin", tick)
	var b := Battle.new(config("delta", 900013))
	planner.begin(b, 0)
	var base := key(planner.best)
	planner.advance()
	ok(planner.completed_samples == 0 and key(planner.best) == base, "partial sweep keeps baseline")
	planner.cancel()
	ok(planner.done and planner.reason == "cancelled", "cancel")
	planner.begin(b, 0)
	while planner.completed_samples == 0: planner.advance()
	var prior := key(planner.best)
	planner.advance()
	ok(key(planner.best) == prior, "partial second sweep keeps completed sweep")
	var timed := planner.decide(b, 0, "hard", 1)
	ok(timed.reason in ["timeout", "complete"] and not timed.action.is_empty(), "soft timeout fallback")
	b.sides[0].hero = {"spellPower": {"flame": 1}}
	var hero_before = serialize(b)
	ok(not planner.begin(b, 0) and planner.reason == "commander_present", "commander rejected")
	ok(serialize(b) == hero_before, "rejected commander unchanged")
	b.sides[0].hero = null
	b.wall = {"hp": 10}
	ok(not planner.begin(b, 0) and planner.reason == "siege", "siege rejected")
	b.wall = null
	b.pre_combat = true
	ok(not planner.begin(b, 0), "precombat rejected")
	b.pre_combat = false
	b.probe = true
	ok(not planner.begin(b, 0), "probe rejected")
	b.probe = false
	ok(not planner.begin(b, 0, "unknown"), "unknown difficulty rejected")
	b.over = {"winner": 0}
	ok(not planner.begin(b, 0), "finished rejected")
	print("PACKAGE_TEST ", JSON.stringify({"checks": checks, "failed": failed, "reference_comparisons": parity_positions, "seconds": (Time.get_ticks_msec()-start)/1000.0}))
