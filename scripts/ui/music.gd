# ============================================================================
# Music — terrain themes on the map, a town theme in towns (HoMM style).
# Each theme is a playlist (data MUSIC.THEMES): when a track ends the next
# one from the same playlist starts. Checks which screen/terrain is active and
# crossfades when the theme changes.
# ============================================================================
extends Node

var cur := ""          # current theme
var cur_track := ""    # track id playing now
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
		p.finished.connect(func(): if p == _players[_active]: _next_track())

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
			return "battle:" + D.MUSIC.TERRAIN.get(bs.b.terrain_id, "path")
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
	return "menu"

## the track ids a theme plays ("battle:<theme>" = that theme plus the battle tracks)
func playlist(theme: String) -> Array:
	var TH: Dictionary = D.MUSIC.get("THEMES", {})
	var out := []
	if theme.begins_with("battle:"):
		out = (TH.get(theme.substr(7), []) as Array) + (TH.get("battle", []) as Array)
	else:
		out = (TH.get(theme, [theme]) as Array).duplicate()
	return out.filter(func(t): return D.MUSIC.TRACKS.has(t))

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
			s.loop = false     # playlists move on when a track ends
		_streams[id] = s
	return _streams[id]

## a track from the theme's playlist, not the one that just played (when there is a choice)
func _pick(theme: String) -> String:
	var pl := playlist(theme)
	if pl.is_empty(): return ""
	if pl.size() > 1: pl.erase(cur_track)
	return pl[randi() % pl.size()]

func play(theme: String) -> void:
	var id := _pick(theme)
	if id == "":
		return
	var old: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var p: AudioStreamPlayer = _players[_active]
	cur = theme
	cur_track = id
	if old.playing:
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -80.0, 1.5)
		tw.tween_callback(old.stop)
	p.stream = _stream(id)
	p.volume_db = -60
	p.play()
	var tw2 := create_tween()
	tw2.tween_property(p, "volume_db", target_db(), 1.8)

## the playing track ended: start the next one from the same playlist
func _next_track() -> void:
	var id := _pick(cur)
	if id == "": return
	var p: AudioStreamPlayer = _players[_active]
	cur_track = id
	p.stream = _stream(id)
	p.volume_db = target_db()
	p.play()

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
	if cur_track == "": return ""
	var T: Dictionary = D.MUSIC.TRACKS[cur_track]
	return T.name + ((" — " + T.credit) if T.has("credit") else "")

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
	var items := []
	for st in Sfx.STYLES: items.append([st, "⚒ " + Sfx.STYLES[st][0]])
	items.append(["off", "⚒ Off"])
	var sfx := UI.option(items, Sfx.style if Sfx.on else "off", func(v): Sfx.set_style(v))
	sfx.add_theme_font_size_override("font_size", 12)
	UI.tip(sfx, "Button sound")
	return UI.hbox([btn, sl, sfx], 4)
