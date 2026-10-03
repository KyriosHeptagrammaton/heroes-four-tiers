# ============================================================================
# Sfx — UI sound effects. Buttons play a heavy stone "ba-DOOM" or a rock knock when
# pressed (style selectable); checkboxes and drop-downs a lighter stone tick.
# Button sounds are built from Kenney's CC0 packs by tools/build_kenney_sfx.py;
# the tick is synthesised by tools/make_sfx.py.
# ============================================================================
extends Node

var on := true
var vol := 0.7
var style := "stone"
var cheers := true
var _cheer: Array = []
var _cheer_pool: Array = []
var _cheer_next := 0
const STYLES := {"stone": ["Stone", 3], "pick": ["Rock knock", 3]}
var _sets := {}
var _tick: AudioStream
var _pool: Array = []
var _next := 0
var _last_ms := -1000
const CFG_PATH := "user://settings.cfg"

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		on = cf.get_value("sfx", "on", true)
		vol = cf.get_value("sfx", "vol", 0.7)
		style = cf.get_value("sfx", "style", "stone")
		cheers = cf.get_value("sfx", "cheers", true)
	if not STYLES.has(style): style = "stone"
	for st in STYLES:
		_sets[st] = []
		for i in STYLES[st][1]:
			_sets[st].append(load("res://sfx/button_%s_%d.ogg" % [st, i + 1]))
	_tick = load("res://sfx/stone_tick.wav")
	for i in 3:
		_cheer.append(load("res://sfx/cheer_%d.ogg" % (i + 1)))
	for i in 8:
		var cp := AudioStreamPlayer.new()
		add_child(cp)
		_cheer_pool.append(cp)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if not n is BaseButton or n.has_meta("silent"):
		return
	var light: bool = n is CheckBox or n is CheckButton or n is OptionButton
	n.button_down.connect(func(): play_tick() if light else play_slab())

func _play(stream: AudioStream, pitch: float, db: float = 0.0) -> void:
	if not on or stream == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(maxf(vol, 0.0001)) + db
	p.play()

func play_slab() -> void:
	# rapid double-clicks don't stack into a rumble
	var now := Time.get_ticks_msec()
	var db := -6.0 if now - _last_ms < 120 else 0.0
	_last_ms = now
	var set: Array = _sets[style]
	_play(set[randi() % set.size()], randf_range(0.97, 1.03), db)

## a crowd cheer for a critical (maximum) roll; several can overlap
func play_cheer() -> void:
	if not cheers or _cheer.is_empty():
		return
	var p: AudioStreamPlayer = _cheer_pool[_cheer_next]
	_cheer_next = (_cheer_next + 1) % _cheer_pool.size()
	p.stream = _cheer[randi() % _cheer.size()]
	p.pitch_scale = randf_range(0.94, 1.07)
	p.volume_db = linear_to_db(maxf(vol, 0.0001)) - 2.0
	p.play()

func play_tick() -> void:
	_play(_tick, randf_range(0.95, 1.08))

func save() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)
	cf.set_value("sfx", "on", on)
	cf.set_value("sfx", "vol", vol)
	cf.set_value("sfx", "style", style)
	cf.set_value("sfx", "cheers", cheers)
	cf.save(CFG_PATH)

func toggle() -> void:
	on = not on
	save()

func set_style(s: String) -> void:
	if s == "off":
		on = false
	else:
		on = true
		style = s
	save()
	play_slab()
