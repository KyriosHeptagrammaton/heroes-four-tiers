extends Control

func _ready() -> void:
	UI.setup(self)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			var t = load("res://tests/%s.gd" % a.substr(7)).new()
			await t.run(self)
			get_tree().quit(1 if ("failed" in t and t.failed) else 0)
			return
	Main.boot()
