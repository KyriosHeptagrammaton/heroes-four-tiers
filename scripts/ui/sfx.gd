# ============================================================================
# Sfx — UI sound effects. Every button plays a chunky stone-slab "ba-DOOM"
# when pressed (checkboxes and drop-downs a lighter stone tick). The sounds
# are synthesised by tools/make_sfx.py.
# ============================================================================
extends Node

var on := true
var vol := 0.7
var _slabs: Array = []
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
	for i in 3:
		_slabs.append(load("res://sfx/stone_button_%d.wav" % (i + 1)))
	_tick = load("res://sfx/stone_tick.wav")
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
	_play(_slabs[randi() % _slabs.size()], randf_range(0.96, 1.04), db)

func play_tick() -> void:
	_play(_tick, randf_range(0.95, 1.08))

func save() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)
	cf.set_value("sfx", "on", on)
	cf.set_value("sfx", "vol", vol)
	cf.save(CFG_PATH)

func toggle() -> void:
	on = not on
	save()
