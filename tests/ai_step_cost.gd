extends RefCounted
var failed := false
func run(_root) -> void:
	var P = load("res://scripts/rules/combat_search_ai.gd")
	var pl = P.new()
	var opts := {"seed": 4242, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}, {"key": Units.key("alpha", 2, 0, ""), "count": 9}, {"key": Units.key("alpha", 3, 0, ""), "count": 6}]},
		{"name": "B", "stacks": [{"key": Units.key("beta", 1, 0, ""), "count": 18}, {"key": Units.key("beta", 2, 0, ""), "count": 9}, {"key": Units.key("beta", 3, 0, ""), "count": 6}]}]}
	var b := Battle.new(opts)
	var costs := []
	var clone_costs := []
	for dec in 6:
		if b.over != null or b.current_stack() == null: break
		var t := Time.get_ticks_usec()
		var c := b.clone_view()
		clone_costs.append((Time.get_ticks_usec() - t) / 1000.0)
		pl.begin(b, dec, "medium")
		pl.horizon = 8
		print("decision ", dec, " candidates ", pl.candidates.size())
		while not pl.done:
			var t2 := Time.get_ticks_usec()
			pl.advance()
			costs.append((Time.get_ticks_usec() - t2) / 1000.0)
		b.act(pl.result().action.action, pl.result().action.get("target"), pl.result().action.get("opt"))
	costs.sort()
	print("advance ms: median ", costs[costs.size()/2], " p95 ", costs[int(costs.size()*0.95)], " max ", costs.back(), " n ", costs.size())
	print("clone_view ms: ", clone_costs)
