extends Control

enum Difficulty { EASY, NORMAL, HARD }
const SETTINGS_PATH: String = "user://settings.cfg"
const DIFFICULTY_HINTS = [
	"Slower movement, delayed reactions, more soft returns.",
	"Current movement and attack balance.",
	"Faster movement, more spikes."
]

var settings_path: String = SETTINGS_PATH
@onready var difficulty_selector: OptionButton = $Difficulty/Selector
@onready var difficulty_hint: Label = $DifficultyHint
@onready var play_button: Button = $Buttons/PlayButton
@onready var controls_button: Button = $Buttons/ControlsButton
@onready var quit_button: Button = $Buttons/QuitButton
@onready var controls_text: Label = $ControlsText


func _ready() -> void:
	for title in ["Easy", "Normal", "Hard"]:
		difficulty_selector.add_item(title)
	var selected := load_difficulty(settings_path)
	difficulty_selector.select(selected)
	difficulty_hint.text = DIFFICULTY_HINTS[selected]
	get_tree().set_meta("difficulty", selected)
	difficulty_selector.item_selected.connect(_on_difficulty_selected)
	play_button.pressed.connect(_on_play_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	controls_text.hide()
	play_button.grab_focus()


func _on_play_pressed() -> void:
	_on_difficulty_selected(difficulty_selector.selected)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_difficulty_selected(index: int) -> void:
	get_tree().set_meta("difficulty", index)
	difficulty_hint.text = DIFFICULTY_HINTS[index]
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
	controls_text.visible = not controls_text.visible


func _on_quit_pressed() -> void:
	get_tree().quit()
