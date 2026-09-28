extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var b := Battle.new({"seed": 9, "sides": [
		{"name": "A", "ai": true, "stacks": [{"key": "alpha.1.0.", "count": 18}]},
		{"name": "B", "ai": true, "stacks": [{"key": "beta.1.0.", "count": 18}]}]})
	var n := 0
	while b.over == null and n < 5000:
		CombatAI.step(b); n += 1
	var crits := b.events.filter(func(e): return e.type == "crit").size()
	var logmax := b.log.filter(func(l): return "(max roll" in l.t or "(crit roll" in l.t).size()
	print("crit events ", crits, " log max/crit lines ", logmax, " cheer streams ", Sfx._cheer.map(func(s): return s != null))
	failed = crits != logmax
