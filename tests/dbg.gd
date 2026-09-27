extends RefCounted
func run(root) -> void:
	UI.autopilot = true
	Main.boot()
	Game.new_game({"names": ["Ann", "Bob"], "factions": ["gamma", "delta"], "cls": ["warlord", "mage"], "seed": 777})
	await root.get_tree().process_frame
	for c in [42, 43, 44, 62, 63, 64]:
		print(c, " ", World.card(c).t, " size ", World.card(c).size, " road ", World.card(c).road, " objs ", World.card(c).objs.map(func(o): return [o.type, o.x, o.y, o.get("hidden", false), o.has("guard")]))
	var h = World.heroes_of(0)[0]
	var P = World.player(0)
	h.pos = {"c": 44, "x": 2, "y": 1}
	World.compute_visible(0)
	print("army stacks ", Army.stacks(h.army), " ", h.army)
	for n in World.neighbors(0, h, h.pos):
		print("  nb ", n, " -> ", World.enterable(h, n, P), " card ", World.card(n.c).t, World.card(n.c).road, " objs ", World.card(n.c).objs.map(func(o): return [o.type, o.x, o.y]))
