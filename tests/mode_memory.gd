extends RefCounted
var failed := false
# The action a stack used is re-selected when its next turn comes round.
func run(root) -> void:
	Main.boot()
	var sb = UI.screen("sandbox")
	sb.open()
	var b = Battle.new(sb.battle_opts(7))
	var bs = UI.screen("battle")
	bs.ai_delay = 999.0
	bs.start(b, func(_b): pass)
	var me = null
	for i in 200:
		if b.over != null: break
		var a = b.turn_stack()
		if a != null and bs.human_turn() and b.current().type != "hero":
			for t in b.enemies_of(a):
				if b.check_engage(a, t) == null:
					me = a; break
			if me != null:
				bs.pick_action("engage")
				for t in b.enemies_of(a):
					var before: int = b.log.size()
					bs.do_act("engage", t.id)
					if b.log.size() != before: break
				break
		CombatAI.step(b); bs.render()
	print("acted with ", me.name if me != null else "nobody", " mode now ", bs.mode)
	var ok := me != null and bs.mode == null
	var got = "never"
	for i in 400:
		if b.over != null: break
		var a = b.turn_stack()
		if a != null and a.id == me.id and bs.human_turn() and b.current().type != "hero":
			got = bs.mode; break
		CombatAI.step(b); bs.render()
	print("next turn mode: ", got)
	ok = ok and got == "engage"
	print("mode_memory ", "OK" if ok else "FAILED")
	failed = not ok
