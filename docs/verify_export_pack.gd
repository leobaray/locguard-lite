# Runs inside the artifact under test and reports what that artifact can show a
# player. Same script in two roles: run from the project directory it reports on
# the editor-side project, run from a .pck (`--main-pack game.pck`) it reports on
# the exported game, and nothing else changes. The shell driver
# (verify_export_pack.sh) compares the two.
#
# Prints one block per run. LG_END is the gate: a run that did not reach it
# measured nothing, and the driver reports that as an error, never as a pass.
extends Node

func _ready() -> void:
	var locale: String = "pt"
	if OS.has_environment("LGLOCALE"):
		locale = OS.get_environment("LGLOCALE")
	TranslationServer.set_locale(locale)
	print("LG_CASE ", OS.get_environment("LGCASE"))
	print("LG_LOCALE_ASKED ", locale)
	print("LG_LOCALE_GOT ", TranslationServer.get_locale())
	print("LG_SEES ", tr("GREET"))
	print("LG_LOADED ", ",".join(TranslationServer.get_loaded_locales()))
	# What the player's build actually carries, asked of the running filesystem:
	# res:// is the pack when there is one, the project directory when there is not.
	print("LG_HAS_EN ", FileAccess.file_exists("res://strings.en.translation"))
	print("LG_HAS_PT ", FileAccess.file_exists("res://strings.pt.translation"))
	print("LG_HAS_CSV ", FileAccess.file_exists("res://strings.csv"))
	print("LG_END")
	get_tree().quit()
