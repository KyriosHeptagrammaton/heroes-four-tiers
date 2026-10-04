extends RefCounted
var failed := false
func check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok: failed = true
func run(root) -> void:
	Main.boot()
	for id in D.MUSIC.TRACKS:
		var s = load("res://" + D.MUSIC.TRACKS[id].file)
		check(s != null and s.get_length() > 30, "track loads: %s (%.0fs)" % [id, s.get_length() if s else 0.0])
	check(Music.playlist("battle:water") == ["water", "driving", "epic"], "battle on water: water playlist + battle track (%s)" % [Music.playlist("battle:water")])
	Music.play("town")
	var first: String = Music.cur_track
	check(first in ["town", "canon"], "town plays a town track (%s)" % first)
	Music._players[Music._active].finished.emit()
	check(Music.cur_track in ["town", "canon"] and Music.cur_track != first, "when it ends the other town track starts (%s)" % Music.cur_track)
	Music.play("woods")
	var w: String = Music.cur_track
	Music._players[Music._active].finished.emit()
	check(Music.cur_track == "woods", "single-track playlist repeats")
	print("now playing: ", Music.now_playing())
	# design flags screen opens
	UI.screen("menu")
	var mm = load("res://scripts/ui/main_menu.gd")
	print("music_check ", "FAILED" if failed else "OK")
