extends RefCounted
var failed := true
func run(_root) -> void:
	Battle._full = false
	var Search = load("res://scripts/rules/combat_search_ai.gd")
	var original = load("res://tests/review_original_search.gd").new()
	original.search_samples = 4
	original.horizon = 24
	var b := Battle.new({"seed":71,"sides":[{"stacks":original.army("delta",0)},{"stacks":original.army("delta",0)}]})
	var verified := 0
	for tick in 8:
		if b.over != null: break
		var saved_rng := b.rng.get_state()
		var summary := JSON.stringify(b.summary())
		seed(7191)
		var expected_global := randi()
		seed(7191)
		var search = Search.new()
		var got: Dictionary = search.decide(b,tick,"hard")
		assert(randi() == expected_global,"planner consumes global RNG")
		assert(b.rng.get_state() == saved_rng,"planner consumes live battle RNG")
		assert(JSON.stringify(b.summary()) == summary,"planner mutates live summary")
		var want: Dictionary = original.rollout(b,tick,"builtin")
		assert(JSON.stringify(got.action) == JSON.stringify(want), "hard differs from archived 4x24")
		assert(b.act(got.action.action,got.action.get("target"),got.action.get("opt")) == null)
		verified += 1
	failed = false
	print("REVIEW_SEARCH_PASS original_hard_parity_and_rng_states=",verified)
