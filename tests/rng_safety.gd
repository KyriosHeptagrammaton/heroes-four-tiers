extends RefCounted
var failed := false
func ok(c: bool, m: String) -> void:
	print(("PASS " if c else "FAIL ") + m)
	if not c: failed = true
func run(_root) -> void:
	var b := Battle.new({"seed": 77, "sides": [
		{"name": "A", "stacks": [{"key": Units.key("alpha", 1, 0, ""), "count": 18}]},
		{"name": "B", "stacks": [{"key": Units.key("beta", 1, 0, ""), "count": 18}]}]})
	var a = b.stacks[0]; var t = b.stacks[1]
	var st := b.rng.get_state()
	for i in 50:
		b.preview_numbers(a, t)
		b.expected_hit(a, t)
	ok(b.rng.get_state() == st, "hover previews never touch the battle's dice")
	seed(123); var want := randi(); seed(123)
	for i in 20: b.clone_view()
	ok(randi() == want, "replay snapshots never touch Godot's global random numbers")
