extends RefCounted
const Planner = preload("res://scripts/rules/combat_search_ai.gd")
const Reference = preload("res://tests/audit_strong_reference.gd")
var failed := false
func run(_root) -> void:
	Battle._full = false
	var records := []
	var latencies := {}
	var ref := Reference.new()
	var planner := Planner.new()
	var start := Time.get_ticks_msec()
	for level in ["medium", "hard"]:
		latencies[level] = []
		for faction in ["alpha", "beta", "gamma", "delta"]:
			for search_side in 2:
				var b := Battle.new({"seed": 900001, "sides": [{"stacks": ref.army(faction, 0)}, {"stacks": ref.army(faction, 0)}]})
				var tick := 0
				while b.over == null and tick < 1500:
					if b.current() == null: break
					if b.current().side == search_side:
						var before := b.rng.get_state()
						var t := Time.get_ticks_usec()
						var result := planner.decide(b, tick, level)
						latencies[level].append((Time.get_ticks_usec()-t)/1000.0)
						if not result.complete or before != b.rng.get_state() or planner.do_act(b, result.action) != null:
							failed = true
							print("FAIL benchmark")
							return
					else: ref.step_policy(b, "builtin", tick)
					tick += 1
				var rec := {"level": level, "faction": faction, "seed": 900001, "search_side": search_side, "over": b.over, "ticks": tick}
				records.append(rec)
				print("BENCHMARK_BATTLE ", JSON.stringify(rec))
	var output := {"engine": Engine.get_version_info().string, "records": records, "latencies_ms": latencies, "seconds": (Time.get_ticks_msec()-start)/1000.0, "failed": failed, "seed_note": "New 900001 seed; one base-roster mirrored scenario per faction, both sides; not a strength guarantee"}
	FileAccess.open(OS.get_environment("PACKAGE_RESULTS"), FileAccess.WRITE).store_string(JSON.stringify(output, "  "))
	print("BENCHMARK_DONE ", output.seconds)
