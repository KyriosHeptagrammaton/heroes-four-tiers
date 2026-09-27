extends RefCounted
var failed := false
func run(_root) -> void:
	print(Units.resolve("beta.4.0.").name, " / ", Units.resolve("beta.4.1.m").name)
	var b := Battle.new({"seed": 5, "sides": [
		{"name": "A", "ai": true, "stacks": [{"key": "beta.4.0.", "count": 1}]},
		{"name": "B", "ai": true, "stacks": [{"key": "alpha.1.0.", "count": 10}, {"key": "alpha.3.0.", "count": 4}, {"key": "gamma.4.0.", "count": 1}]}]})
	for s in b.stacks: print(s.name, " count ", s.count, " deserters ", s.deserters)
	failed = b.stacks[3].deserters != 0 or b.stacks[1].deserters != 1
