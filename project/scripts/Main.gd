extends Node2D

@onready var level_loader: Node2D = $CocosLevel
@onready var label_level: Label = $HUD/Margin/VBox/HBox/LabelLevel
@onready var label_stars: Label = $HUD/Margin/VBox/HBox/LabelStars
@onready var label_crystals: Label = $HUD/Margin/VBox/HBox/LabelCrystals
@onready var victory_panel: PanelContainer = $HUD/VictoryPanel
@onready var audio_music: AudioStreamPlayer = $AudioStreamPlayer

var current_level: int = 1
var stars_collected: int = 0
var crystals_collected: int = 0

func _ready() -> void:
	if not check_assets_installed():
		show_missing_assets_ui()
		return

	if level_loader:
		level_loader.level_loaded.connect(_on_level_loaded)
		level_loader.role_reached_moon.connect(_on_role_reached_moon)
		level_loader.item_collected.connect(_on_item_collected)
		level_loader.role_died.connect(_on_role_died)
		level_loader.load_level(current_level)
	if victory_panel:
		victory_panel.visible = false

func check_assets_installed() -> bool:
	return FileAccess.file_exists("res://data/levels/Level_001.xml") and FileAccess.file_exists("res://data/edge_data.json")

func show_missing_assets_ui() -> void:
	var hud = $HUD
	if not hud:
		return

	var margin = hud.get_node_or_null("Margin")
	if margin:
		margin.visible = false

	var panel = PanelContainer.new()
	panel.name = "MissingDataPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 260)
	center.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	card.add_child(vbox)

	var title = Label.new()
	title.text = "Original Game Data Missing"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var desc = Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.text = "FlyMe2TheMoon proprietary assets are not bundled due to copyright.\n\nTo play:\n1. Drop 'Fly2theMoon.ipa' (or extracted app files) into 'game_data/'.\n2. Run 'setup_game_data.bat'.\n3. Click 'Retry' below."
	vbox.add_child(desc)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var btn_retry = Button.new()
	btn_retry.text = " Retry / Reload "
	btn_retry.pressed.connect(func():
		if check_assets_installed():
			get_tree().reload_current_scene()
		else:
			desc.text = "[!] Game data is still not found.\nPlease run setup_game_data.bat first!"
	)
	hbox.add_child(btn_retry)

	var btn_run = Button.new()
	btn_run.text = " Run Setup Tool "
	btn_run.pressed.connect(func():
		var root_dir = ProjectSettings.globalize_path("res://..")
		var bat_path = root_dir + "/setup_game_data.bat"
		if OS.get_name() == "Windows":
			OS.create_process("cmd.exe", ["/c", "start", "", bat_path])
		else:
			OS.create_process("python3", [root_dir + "/tools/setup_game_data.py"])
	)
	hbox.add_child(btn_run)

	hud.add_child(panel)

func _on_level_loaded(lvl_id: int) -> void:
	current_level = lvl_id
	stars_collected = 0
	crystals_collected = 0
	update_hud()
	if victory_panel:
		victory_panel.visible = false

func _on_item_collected(item_type: int, _pos: Vector2) -> void:
	if item_type == 5: # Star
		stars_collected += 1
		play_sfx("res://assets/audio/45-1.wav")
	elif item_type in [3, 4]: # Crystal
		crystals_collected += 1
		play_sfx("res://assets/audio/44-1.wav")
	update_hud()

func _on_role_reached_moon() -> void:
	play_sfx("res://assets/audio/54-1.wav")
	if level_loader and level_loader.player_instance and level_loader.player_instance.has_method("set_input_enabled"):
		level_loader.player_instance.set_input_enabled(false)
	if victory_panel:
		victory_panel.visible = true

func _on_role_died() -> void:
	play_sfx("res://assets/audio/51-2.wav")

func update_hud() -> void:
	if label_level:
		label_level.text = "Level %02d" % current_level
	if label_stars:
		label_stars.text = "★ %d" % stars_collected
	if label_crystals:
		label_crystals.text = "◆ %d" % crystals_collected

func play_sfx(path: String) -> void:
	if ResourceLoader.exists(path):
		var sfx = AudioStreamPlayer.new()
		sfx.stream = load(path)
		add_child(sfx)
		sfx.finished.connect(sfx.queue_free)
		sfx.play()

func _on_btn_prev_pressed() -> void:
	if current_level > 1:
		current_level -= 1
		level_loader.load_level(current_level)

func _on_btn_next_pressed() -> void:
	if current_level < 60:
		current_level += 1
		level_loader.load_level(current_level)

func _on_btn_restart_pressed() -> void:
	level_loader.load_level(current_level)
