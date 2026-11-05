extends Control

@onready var play_button: Button = $Buttons/PlayButton
@onready var controls_button: Button = $Buttons/ControlsButton
@onready var quit_button: Button = $Buttons/QuitButton
@onready var controls_text: Label = $ControlsText


func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	controls_text.hide()
	play_button.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_controls_pressed() -> void:
	controls_text.visible = not controls_text.visible


func _on_quit_pressed() -> void:
	get_tree().quit()
