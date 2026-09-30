extends RefCounted
# Local audit only: no changes to combat rules. No commanders, thus copied hero
# objects are absent. Planning samples use fresh RNG states, never future live RNG.
var actions_used := {}
var simulations := 0
var search_samples := 3
var horizon := 36
var matrix_roster := false

func clone_sim(b: Battle, seed_n: int) -> Battle:
	var c := b.clone_view()
	c.probe = false
	c.rng = Rng.new(seed_n)
	c.log = []
	return c

func legal(b: Battle) -> Array:
	var a = b.current_stack()
	if a == null: return []
	var out := []
	for t in b.enemies_of(a):
		if b.check_rally(a,t) == null: out.append({"action":"rally", "target":t.id})
		if b.check_attack(a, t) == null: out.append({"action":"attack", "target":t.id})
		if b.check_engage(a, t) == null: out.append({"action":"engage", "target":t.id})
		if b.check_deny(a, t) == null:
			for i in b.deny_options(a, t).size(): out.append({"action":"deny", "target":t.id, "opt":i})
	for t in b.allies_of(a):
		if b.check_guard(a, t) == null: out.append({"action":"guard", "target":t.id})
		if b.check_rally(a, t) == null: out.append({"action":"rally", "target":t.id})
	if b.check_fallback(a) == null: out.append({"action":"fallback"})
	if b.can_wait(a): out.append({"action":"wait"})
	out.append({"action":"seek"})
	out.append({"action":"retaliate"})
	return out

func do_act(b: Battle, d: Dictionary):
	return b.act(d.action, d.get("target", null), d.get("opt", null))

func greedy(b: Battle) -> Dictionary:
	var a = b.current_stack()
	var best := {"action":"seek"}
	var val := -INF
	for t in b.enemies_of(a):
		if b.check_attack(a,t) != null: continue
		var h := b.expected_hit(a,t)
		var sc: float = (h.removed + h.frac * t.count * 0.5) * CombatAI.value_of(t)
		if sc > val:
			val = sc
			best = {"action":"attack", "target":t.id}
	return best

func eval_state(b: Battle, side: int) -> float:
	if b.over != null:
		if b.over.winner == side: return 1000.0
		if b.over.winner == 1-side: return -1000.0
		return 0.0
	var amounts := [0.0,0.0]
	for st in b.stacks:
		if st.count > 0: amounts[st.side] += st.count * CombatAI.value_of(st)
	return 100.0 * (amounts[side]-amounts[1-side]) / maxf(1.0, amounts[0]+amounts[1])

func rollout(b: Battle, tick: int, follow: String, omit_rally: bool = false) -> Dictionary:
	var a = b.current_stack()
	var cand := legal(b)
	# Put baseline first so equal-value actions do not introduce pointless changes.
	var saved_rng := b.rng.get_state()
	var base := CombatAI.decide(b,a)
	b.rng.set_state(saved_rng)
	cand.push_front(base)
	if omit_rally: cand = cand.filter(func(d): return d.action != "rally")
	var best := base
	var best_score := -INF
	for d in cand:
		var total := 0.0
		for sample in search_samples:
			# Independent of live battle seed: no clairvoyance about combat rolls.
			var c := clone_sim(b, 9871 + tick*7919 + sample*104729)
			var err = do_act(c,d)
			assert(err == null, "illegal search action")
			for step_n in horizon:
				if c.over != null: break
				var e = c.current()
				if e == null: break
				if follow == "greedy":
					var sr := c.rng.get_state()
					var gd := greedy(c)
					c.rng.set_state(sr)
					do_act(c,gd)
				else:
					var sr := c.rng.get_state()
					var cd := CombatAI.decide(c,c.current_stack())
					c.rng.set_state(sr)
					do_act(c,cd)
			total += eval_state(c,a.side)
			simulations += 1
		if total > best_score + 0.00001:
			best_score = total
			best = d
	return best

func step_policy(b: Battle, policy: String, tick: int) -> void:
	if b.pre_combat:
		b.end_pre_combat()
		return
	var saved_rng := b.rng.get_state()
	var d: Dictionary
	if policy == "rollout": d = rollout(b,tick,"builtin")
	elif policy == "rollout_no_rally": d = rollout(b,tick,"builtin",true)
	elif policy == "counter_greedy": d = rollout(b,tick,"greedy")
	elif policy == "greedy": d = greedy(b)
	else: d = CombatAI.decide(b,b.current_stack())
	b.rng.set_state(saved_rng)
	var key: String = policy + ":" + d.action
	actions_used[key] = actions_used.get(key,0)+1
	var err = do_act(b,d)
	assert(err == null, str(err))

func army(f: String, shape: int) -> Array:
	if shape == 0 and matrix_roster:
		return [{"key":Units.key(f,1),"count":24},{"key":Units.key(f,2),"count":12},{"key":Units.key(f,3),"count":8},{"key":Units.key(f,4),"count":4}]
	if shape == 0:
		return [{"key":Units.key(f,1),"count":20},{"key":Units.key(f,2),"count":10},{"key":Units.key(f,3),"count":5},{"key":Units.key(f,4),"count":2}]
	return [{"key":Units.key(f,1,1,"r"),"count":14},{"key":Units.key(f,2,1,""),"count":8},{"key":Units.key(f,3,1,"m"),"count":4}]

func run(_root) -> void:
	Battle._full = false
	var shard_n := maxi(1,int(OS.get_environment("AUDIT_SHARDS")))
	var shard_i := int(OS.get_environment("AUDIT_SHARD"))
	var n := int(OS.get_environment("AUDIT_SEEDS"))
	if n <= 0: n = 4
	var pol: String = OS.get_environment("AUDIT_POLICY")
	if pol == "": pol = "rollout"
	var opponent: String = OS.get_environment("AUDIT_OPPONENT")
	if opponent == "": opponent = "builtin"
	var h := int(OS.get_environment("AUDIT_HORIZON"))
	if h > 0: horizon = h
	var samp := int(OS.get_environment("AUDIT_SAMPLES"))
	if samp > 0: search_samples = samp
	var cross: String = OS.get_environment("AUDIT_CROSS")
	matrix_roster = cross != ""
	var records := []
	var resume_keys := {}
	var resume_path: String = OS.get_environment("AUDIT_RESUME_LOG")
	if resume_path != "":
		var fh := FileAccess.open(resume_path,FileAccess.READ)
		while not fh.eof_reached():
			var line := fh.get_line()
			if line.begins_with("AUDIT_RESULT "):
				var prior = JSON.parse_string(line.substr(13))
				records.append(prior)
				resume_keys[str(prior.faction)+":"+str(int(prior.shape))+":"+str(int(prior.seed))+":"+str(int(prior.challenger_side))] = true
	var resumed_records: int = records.size()
	var started := Time.get_ticks_msec()
	# Validate clone-as-simulator on an actual legal path with matched RNG states.
	var check := Battle.new({"seed":71,"sides":[{"stacks":army("alpha",1)},{"stacks":army("beta",1)}]})
	if check.pre_combat: check.end_pre_combat()
	for z in 24:
		if check.over != null: break
		var c := clone_sim(check,check.rng.get_state())
		CombatAI.step(check)
		CombatAI.step(c)
		assert(JSON.stringify(check.summary()) == JSON.stringify(c.summary()),"clone summary mismatch")
		assert(JSON.stringify(check.queue) == JSON.stringify(c.queue),"clone queue mismatch")
		assert(check.rng.get_state() == c.rng.get_state(),"clone RNG mismatch")
	print("AUDIT_CLONE_CHECK passed")
	var seed_offset := int(OS.get_environment("AUDIT_SEED_OFFSET"))
	var only_fac: String = OS.get_environment("AUDIT_FACTION")
	var only_shape: String = OS.get_environment("AUDIT_SHAPE")
	var factions: Array = ["gamma"] if cross != "" else ["alpha","beta","gamma","delta"]
	if only_fac != "": factions = [only_fac]
	for faction in factions:
		for shape in (1 if cross != "" else 2):
			if only_shape != "" and shape != int(only_shape): continue
			for i in n:
				if i % shard_n != shard_i: continue
				for challenger_side in 2:
					if resume_keys.has(str(faction)+":"+str(shape)+":"+str(101+(i+seed_offset)*7919)+":"+str(challenger_side)): continue
					var cfg := {"seed":101+(i+seed_offset)*7919,"terrain":"field","time":"dawn","weather":"clear","sides":[{"faction":faction,"stacks":army(faction,shape)},{"faction":faction,"stacks":army(faction,shape)}]}
					if cross != "":
						cfg.sides[1-challenger_side] = {"faction":cross,"stacks":army(cross,shape)}
					var b := Battle.new(cfg)
					var tick := 0
					while b.over == null and tick < 1500:
						var e = b.current()
						if e == null: break
						step_policy(b,pol if e.side == challenger_side else opponent,tick)
						tick += 1
					var rec := {"faction":faction,"opponent_faction":cross if cross != "" else faction,"shape":shape,"seed":cfg.seed,"challenger_side":challenger_side,"challenger":pol,"opponent":opponent,"over":b.over,"round":b.round_n,"decisions":tick,"value":eval_state(b,challenger_side)}
					records.append(rec)
					print("AUDIT_RESULT ",JSON.stringify(rec))
	var output := {"engine":"Godot 4.3", "commit":"26d4cdc0436c740cae6a2524bdfd057789f247a7", "rng_isolation":true,"resumed_records":resumed_records,"action_simulation_runtime_counters_exclude_resumed":resumed_records>0,"full_threshold":false,"hero_present":false,"policy":pol,"opponent":opponent,"horizon":horizon,"samples":search_samples,"independent_seed_blocks_per_scenario":n,"records":records,"actions":actions_used,"simulations":simulations,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0}
	var dest := "/workspace/shared/heroes-four-tiers-audit/experiments/"+pol+"_vs_"+opponent+"_"+str(n)+("_gamma_vs_"+cross if cross != "" else "")+("_"+only_fac+"_shape"+only_shape+"_offset"+str(seed_offset) if only_fac != "" else "")+("_shard"+str(shard_i) if shard_n > 1 else "")+".json"
	FileAccess.open(dest,FileAccess.WRITE).store_string(JSON.stringify(output,"  "))
	print("AUDIT_DONE ",dest," seconds ",output.elapsed_seconds)
