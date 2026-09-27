extends RefCounted
var failed := false
func run(root) -> void:
	Main.boot()
	var b := Battle.new({"seed": 11, "sides": [
		{"name": "A", "stacks": [{"key": "alpha.1.0.", "count": 12}]},
		{"name": "B", "ai": true, "stacks": [{"key": "beta.1.0.", "count": 12}]}]})
	var bs = UI.screen("battle")
	bs.start(b, func(_x): pass)
	for i in 60:
		await root.get_tree().process_frame
		if b.turn_stack() != null and not b.sides[b.current().side].ai: break
	var a := b.turn_stack()
	var enemy = b.stacks_of(1)[0]
	var before: int = enemy.count * 1000 + enemy.mor + enemy.phys
	var n0 := b.log.size()
	bs.click_stack(enemy)
	var hit := false
	for i in range(n0, b.log.size()):
		if " hit " in b.log[i].t: hit = true
	print("acting ", a.name, " -> clicked ", enemy.name, " attacked: ", hit)
	failed = not hit
