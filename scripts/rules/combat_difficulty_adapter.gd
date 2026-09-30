extends RefCounted
# Optional SYNCHRONOUS dispatch for headless/server use.
# UI integration should drive CombatSearchAI.begin/advance over frames instead.
const Search = preload("res://scripts/rules/combat_search_ai.gd")
var planner := Search.new()
var last_result: Dictionary = {}

func step(b: Battle, difficulty: String, decision_index: int, max_msec: int = 0) -> bool:
	if difficulty == "easy":
		last_result = {"reason": "native_easy"}
		return CombatAI.step(b)
	last_result = planner.decide(b, decision_index, difficulty, max_msec)
	if last_result.reason not in ["complete", "timeout"] or last_result.action.is_empty():
		return CombatAI.step(b)
	var d: Dictionary = last_result.action
	var err = b.act(d.action, d.get("target", null), d.get("opt", null))
	if err != null:
		last_result["apply_error"] = str(err)
		return CombatAI.step(b)
	return true
