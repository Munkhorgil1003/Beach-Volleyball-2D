extends Control

const Player = preload("res://scripts/player.gd")
enum Difficulty { EASY, NORMAL, HARD }
const SETTINGS_PATH: String = Player.SETTINGS_PATH
const CONTROLS_HINT: String = "Click a binding, then press a key. Esc cancels.\nPass also tips in air; spike also serves."

var settings_path: String = SETTINGS_PATH
var selected_character: int = 0
var preview_frames: SpriteFrames
var editing_player: int = 0
var editing_bindings: int = 0
var bindings: Array = []
var pending_binding: Vector2i = Vector2i(-1, -1)
@onready var mode_selector: OptionButton = $Mode/Selector
@onready var player_selector: OptionButton = $PlayerSlot
@onready var controls_player_selector: OptionButton = $ControlsOverlay/Panel/Player
@onready var binding_rows: VBoxContainer = $ControlsOverlay/Panel/BindingRows
@onready var team_name_input: LineEdit = $TeamName/Input
@onready var character_title: Label = $CharacterTitle
@onready var character_preview: AnimatedSprite2D = $CharacterPreview
@onready var character_choices: HBoxContainer = $CharacterChoices
@onready var controls_overlay: Control = $ControlsOverlay
@onready var difficulty_selector: OptionButton = $Difficulty/Selector
@onready var play_button: Button = $Buttons/PlayButton
@onready var controls_button: Button = $Buttons/ControlsButton
@onready var quit_button: Button = $Buttons/QuitButton
@onready var controls_text: Label = $ControlsOverlay/Panel/ControlsText


func _ready() -> void:
	var profile := load_profile(settings_path)
	team_name_input.text = profile.team_name
	_make_character_choices()
	_on_character_selected(profile.character, false)
	get_tree().set_meta("player_profile", profile)
	get_tree().set_meta("player_two_profile", load_profile(settings_path, 1))
	team_name_input.text_changed.connect(_on_team_name_changed)
	for title in ["Easy", "Normal", "Hard"]:
		difficulty_selector.add_item(title)
	var selected := load_difficulty(settings_path)
	difficulty_selector.select(selected)
	get_tree().set_meta("difficulty", selected)
	difficulty_selector.item_selected.connect(_on_difficulty_selected)
	play_button.pressed.connect(_on_play_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	mode_selector.add_item("Single player")
	mode_selector.add_item("Local 2 players")
	mode_selector.select(1 if load_local_two_player(settings_path) else 0)
	for title in ["Player 1 · Red", "Player 2 · Blue"]:
		player_selector.add_item(title)
		controls_player_selector.add_item(title)
	_apply_mode()
	mode_selector.item_selected.connect(_on_mode_selected)
	player_selector.item_selected.connect(_on_player_selected)
	controls_player_selector.item_selected.connect(_on_controls_player_selected)
	_setup_bindings()
	$ControlsOverlay/Panel/Buttons/ResetButton.pressed.connect(_on_reset_keys_pressed)
	$ControlsOverlay/Panel/Buttons/CloseButton.pressed.connect(_on_controls_pressed)
	controls_overlay.hide()
	play_button.grab_focus()


func _on_play_pressed() -> void:
	team_name_input.text = clean_team_name(team_name_input.text, "LEFT" if editing_player == 0 else "RIGHT")
	_save_profile()
	_on_difficulty_selected(difficulty_selector.selected)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _apply_mode() -> void:
	var local: bool = mode_selector.selected == 1
	get_tree().set_meta("local_two_player", local)
	player_selector.visible = local
	if not local and editing_player == 1:
		player_selector.select(0)
		_on_player_selected(0)
	$ModeHint.text = "One human + AI on each team · Shared keyboard" if local else "You + AI against two AI players"
	$Difficulty/Label.text = "AI difficulty" if local else "Opponent difficulty"
	_on_character_selected(selected_character, false)


func _on_mode_selected(_index: int) -> void:
	_apply_mode()
	var settings := ConfigFile.new()
	settings.load(settings_path)
	settings.set_value("gameplay", "local_two_player", mode_selector.selected == 1)
	var result := settings.save(settings_path)
	if result != OK:
		push_warning("Could not save mode: %s" % error_string(result))


static func load_local_two_player(path: String = SETTINGS_PATH) -> bool:
	var settings := ConfigFile.new()
	settings.load(path)
	return settings.get_value("gameplay", "local_two_player", false) == true


func _on_player_selected(index: int) -> void:
	editing_player = index
	var profile := load_profile(settings_path, index)
	team_name_input.set_block_signals(true)
	team_name_input.text = profile.team_name
	team_name_input.set_block_signals(false)
	_on_character_selected(profile.character, false)


func _make_character_choices() -> void:
	preview_frames = SpriteFrames.new()
	preview_frames.remove_animation("default")
	preview_frames.add_animation("idle")
	preview_frames.set_animation_speed("idle", 8.0)
	var sheet: Texture2D = load(Player.CHARACTER_FOLDERS[0] + "/playerIdle.png")
	for index in range(sheet.get_width() / 32):
		var texture := AtlasTexture.new()
		texture.atlas = sheet
		texture.region = Rect2(index * 32, 0, 32, sheet.get_height())
		preview_frames.add_frame("idle", texture)
	var group := ButtonGroup.new()
	for index in range(Player.CHARACTER_NAMES.size()):
		var button := Button.new()
		button.custom_minimum_size = Vector2(40, 52)
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = Player.CHARACTER_NAMES[index]
		button.accessibility_name = Player.CHARACTER_NAMES[index]
		var texture := AtlasTexture.new()
		texture.atlas = load(Player.CHARACTER_FOLDERS[index] + "/playerIdle.png")
		texture.region = Rect2(0, 0, 32, sheet.get_height())
		button.icon = texture
		button.pressed.connect(_on_character_selected.bind(index))
		character_choices.add_child(button)


func _on_character_selected(index: int, save_choice: bool = true) -> void:
	selected_character = index
	for choice in range(character_choices.get_child_count()):
		character_choices.get_child(choice).set_pressed_no_signal(choice == index)
	var owner_name: String = "PLAYER %d" % (editing_player + 1) if mode_selector.selected == 1 else "YOUR CHARACTER"
	character_title.text = "%s · %s" % [owner_name, Player.CHARACTER_NAMES[index].to_upper()]
	character_preview.sprite_frames = Player.frames_for_character(preview_frames, index)
	character_preview.play("idle")
	if save_choice:
		_save_profile()


func _on_team_name_changed(_text: String) -> void:
	_save_profile()


func _save_profile() -> void:
	var profile := {"character": selected_character, "team_name": clean_team_name(team_name_input.text, "LEFT" if editing_player == 0 else "RIGHT")}
	get_tree().set_meta("player_profile" if editing_player == 0 else "player_two_profile", profile)
	var settings := ConfigFile.new()
	settings.load(settings_path)
	var section := "player" if editing_player == 0 else "player_two"
	settings.set_value(section, "character", profile.character)
	settings.set_value(section, "team_name", profile.team_name)
	var result := settings.save(settings_path)
	if result != OK:
		push_warning("Could not save player choices: %s" % error_string(result))


static func clean_team_name(value: Variant, fallback: String = "LEFT") -> String:
	if not value is String:
		return fallback
	var cleaned: String = value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(16)
	return fallback if cleaned.is_empty() else cleaned


static func load_profile(path: String = SETTINGS_PATH, slot: int = 0) -> Dictionary:
	var settings := ConfigFile.new()
	settings.load(path)
	var section := "player" if slot == 0 else "player_two"
	var default_character := 0 if slot == 0 else 2
	var character: Variant = settings.get_value(section, "character", default_character)
	if not character is int or character < 0 or character >= Player.CHARACTER_NAMES.size():
		character = default_character
	var fallback := "LEFT" if slot == 0 else "RIGHT"
	return {"character": character, "team_name": clean_team_name(settings.get_value(section, "team_name", fallback), fallback)}


func _setup_bindings() -> void:
	bindings = Player.load_bindings(settings_path)
	Player.apply_bindings(bindings)
	get_tree().set_meta("keybindings", bindings.duplicate(true))
	for index in range(Player.CONTROL_ACTIONS.size()):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = Player.CONTROL_LABELS[index]
		label.add_theme_font_size_override("font_size", 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(112, 22)
		button.theme_type_variation = &"KeyButton"
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_bind_pressed.bind(index))
		row.add_child(button)
		binding_rows.add_child(row)
	_refresh_bindings()


func _refresh_bindings() -> void:
	for index in range(Player.CONTROL_ACTIONS.size()):
		var button: Button = binding_rows.get_child(index).get_child(1)
		button.text = "Press a key…" if pending_binding == Vector2i(editing_bindings, index) else OS.get_keycode_string(bindings[editing_bindings][index])
	controls_text.text = CONTROLS_HINT
	if pending_binding.x >= 0:
		controls_text.text = "Press a key for P%d · %s\nEsc cancels" % [pending_binding.x + 1, Player.CONTROL_LABELS[pending_binding.y]]


func _on_controls_player_selected(index: int) -> void:
	editing_bindings = index
	pending_binding = Vector2i(-1, -1)
	_refresh_bindings()


func _on_bind_pressed(index: int) -> void:
	pending_binding = Vector2i(editing_bindings, index)
	_refresh_bindings()


func _save_bindings() -> void:
	Player.apply_bindings(bindings)
	get_tree().set_meta("keybindings", bindings.duplicate(true))
	var result := Player.save_bindings(bindings, settings_path)
	if result != OK:
		push_warning("Could not save keys: %s" % error_string(result))


func _on_reset_keys_pressed() -> void:
	pending_binding = Vector2i(-1, -1)
	bindings = Player.DEFAULT_KEYS.duplicate(true)
	_save_bindings()
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if not controls_overlay.visible or pending_binding.x < 0 or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_ESCAPE:
		pending_binding = Vector2i(-1, -1)
		_refresh_bindings()
		return
	if key <= 0 or OS.get_keycode_string(key).is_empty():
		return
	var old_key: int = bindings[pending_binding.x][pending_binding.y]
	for slot in range(2):
		for index in range(Player.CONTROL_ACTIONS.size()):
			if bindings[slot][index] == key:
				bindings[slot][index] = old_key
	bindings[pending_binding.x][pending_binding.y] = key
	pending_binding = Vector2i(-1, -1)
	_save_bindings()
	_refresh_bindings()


func _on_difficulty_selected(index: int) -> void:
	get_tree().set_meta("difficulty", index)
	var result := save_difficulty(index, settings_path)
	if result != OK:
		push_warning("Could not save difficulty: %s" % error_string(result))


static func load_difficulty(path: String = SETTINGS_PATH) -> int:
	var settings := ConfigFile.new()
	if settings.load(path) != OK:
		return Difficulty.NORMAL
	var value: Variant = settings.get_value("gameplay", "difficulty", Difficulty.NORMAL)
	if value is int and value >= Difficulty.EASY and value <= Difficulty.HARD:
		return value
	return Difficulty.NORMAL


static func save_difficulty(level: int, path: String = SETTINGS_PATH) -> Error:
	var settings := ConfigFile.new()
	settings.load(path)
	settings.set_value("gameplay", "difficulty", level)
	return settings.save(path)


func _on_controls_pressed() -> void:
	controls_overlay.visible = not controls_overlay.visible
	pending_binding = Vector2i(-1, -1)
	if controls_overlay.visible:
		editing_bindings = editing_player
		controls_player_selector.select(editing_bindings)
	_refresh_bindings()
	for button in [play_button, controls_button, quit_button] + character_choices.get_children():
		button.disabled = controls_overlay.visible
	difficulty_selector.disabled = controls_overlay.visible
	mode_selector.disabled = controls_overlay.visible
	player_selector.disabled = controls_overlay.visible
	team_name_input.editable = not controls_overlay.visible
	if controls_overlay.visible:
		$ControlsOverlay/Panel/Buttons/CloseButton.grab_focus()
	else:
		controls_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if controls_overlay.visible and event.is_action_pressed("ui_cancel"):
		_on_controls_pressed()
		get_viewport().set_input_as_handled()


func _on_quit_pressed() -> void:
	get_tree().quit()
