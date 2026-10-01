extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func mk() -> Battle:
	return Battle.new({"seed": 5, "probe": true, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("gamma", 3, 0, ""), "count": 12}, {"key": Units.key("delta", 3, 0, ""), "count": 6}, {"key": Units.key("delta", 2, 0, ""), "count": 9}]},
		{"name": "B", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}]}]})
func run(_root) -> void:
	for on in [false, true]:
		Battle._full = on
		var b := mk()
		var le = b.stacks[0]
		var ally = b.stacks[2]
		ally.phys = 0; ally.mor = 0
		b.do_rally(b.stacks[1], ally)
		print("test mode %s: Leshi start %d, Draugr rally leaves ally health damage %d" % [on, le.phys, ally.phys])
		if on: ok(le.phys == 0 and ally.phys == 0, "test mode: no Leshi buffer, no negative health damage from Draugr")
		else: ok(le.phys == -12 and ally.phys < 0, "normal: Leshi buffer and Draugr negative health damage")
	Battle._full = false
