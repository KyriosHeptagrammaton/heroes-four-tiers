# ============================================================================
# Music — terrain themes on the map, a town theme in towns (HoMM style).
# Checks which screen/terrain is active and crossfades between tracks.
# ============================================================================
extends Node

var cur := ""
var vol := 0.6
var muted := false
var _players: Array = []
var _active := 0
var _t := 0.0
var _streams := {}
const CFG_PATH := "user://settings.cfg"

func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		vol = cf.get_value("music", "vol", 0.6)
		muted = cf.get_value("music", "muted", false)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80
		add_child(p)
		_players.append(p)

func save() -> void:
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)
	cf.set_value("music", "vol", vol)
	cf.set_value("music", "muted", muted)
	cf.save(CFG_PATH)

func target_db() -> float:
	var v := 0.0 if muted else vol
	return linear_to_db(maxf(v, 0.0001)) if v > 0 else -80.0

## which track should be playing right now?
func wanted() -> String:
	var scr: String = UI.cur_screen
	if scr == "town":
		return "town"
	if scr == "battle":
		var bs = UI.screen("battle")
		if bs and bs.b != null:
			return D.MUSIC.TERRAIN.get(bs.b.terrain_id, "path")
	if scr == "world" and Game.state != null:
		var ws = UI.screen("world")
		var h = World.hero(ws.sel_hero) if ws and ws.sel_hero != "" else null
		if h == null:
			return "path"
		var o = World.obj_at(h.pos.c, h.pos.x, h.pos.y)
		if o != null and o.type == "town":
			return "town"
		return D.MUSIC.TERRAIN.get(World.card(h.pos.c).t, "path")
	if scr == "handoff":
		return cur if cur != "" else "town"
	return "path"

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.4:
		return
	_t = 0.0
	if UI.root == null:
		return
	var w := wanted()
	if w != cur:
		play(w)

func _stream(id: String) -> AudioStream:
	if not _streams.has(id):
		var s = load("res://" + D.MUSIC.TRACKS[id].file)
		if s is AudioStreamMP3:
			s.loop = true
		_streams[id] = s
	return _streams[id]

func play(id: String) -> void:
	if not D.MUSIC.TRACKS.has(id):
		return
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var p: AudioStreamPlayer = _players[_active]
	cur = id
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -80.0, 1.5)
		tw.tween_callback(old.stop)
	p.stream = _stream(id)
	p.volume_db = -60
	p.play()
	var tw2 := create_tween()
	tw2.tween_property(p, "volume_db", target_db(), 1.8)

func set_vol(v: float) -> void:
	vol = v
	save()
	_players[_active].volume_db = target_db()

func toggle() -> void:
	muted = not muted
	save()
	var tw := create_tween()
	tw.tween_property(_players[_active], "volume_db", target_db(), 0.4)

func now_playing() -> String:
	return D.MUSIC.TRACKS[cur].name if cur != "" else ""

## small control: ♪ button + volume slider
func control() -> Control:
	var btn := UI.button("♪ off" if muted else "♪", func(): pass, "Small")
	btn.pressed.connect(func():
		toggle()
		btn.text = "♪ off" if muted else "♪")
	UI.tip(btn, func(): return "Music on/off — now playing: [b]%s[/b]" % now_playing())
	var sl := HSlider.new()
	sl.min_value = 0; sl.max_value = 100; sl.value = vol * 100
	sl.custom_minimum_size = Vector2(70, 16)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v): set_vol(v / 100.0))
	UI.tip(sl, "Music volume")
	var sfx := UI.button("⚒" if Sfx.on else "⚒ off", func(): pass, "Small")
	sfx.pressed.connect(func():
		Sfx.toggle()
		sfx.text = "⚒" if Sfx.on else "⚒ off")
	UI.tip(sfx, "Button sounds on/off")
	return UI.hbox([btn, sl, sfx], 4)
