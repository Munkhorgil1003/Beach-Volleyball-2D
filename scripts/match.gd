extends Node2D

const Ball = preload("res://scripts/ball.gd")
enum State { WAITING_FOR_SERVE, RALLY, POINT, GAME_OVER }

@export var court_bounds: Rect2 = Rect2(16, 145, 368, 270)
@export var point_pause: float = 1.2
@export var winning_score: int = 7
@export var toss_height: float = 160.0
@export var toss_speed: float = 160.0
@export var ai_serve_delay: float = 1.0

@onready var ball = $Ball
@onready var player_left = $PlayerLeft
@onready var player_right = $PlayerRight
@onready var left_start: Vector2 = player_left.position
@onready var right_start: Vector2 = player_right.position
@onready var left_score_label: Label = $Scoreboard/LeftScore
@onready var right_score_label: Label = $Scoreboard/RightScore
@onready var status_label: Label = $Scoreboard/Status
@onready var landing_marker: Sprite2D = $LandingMarker
@onready var popup: Panel = $Scoreboard/Popup
@onready var popup_title: Label = $Scoreboard/Popup/Box/Title
@onready var resume_button: Button = $Scoreboard/Popup/Box/ResumeButton
@onready var restart_button: Button = $Scoreboard/Popup/Box/RestartButton
@onready var menu_button: Button = $Scoreboard/Popup/Box/MenuButton

var scores: Array[int] = [0, 0]
var serving_side: int = Ball.Side.LEFT
var state: State = State.WAITING_FOR_SERVE
var point_time_left: float = 0.0
var serve_time_left: float = 0.0


func _ready() -> void:
	ball.landed.connect(_on_ball_landed)
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	_update_scores()
	_prepare_serve()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and state != State.GAME_OVER:
		_show_popup("Paused", true)
		get_tree().paused = true
		get_viewport().set_input_as_handled()
	elif state == State.WAITING_FOR_SERVE and serving_side == Ball.Side.LEFT \
			and event.is_action_pressed("serve"):
		_start_serve()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Show where the ball will come down so it is easier to get under it.
	landing_marker.visible = state == State.RALLY and ball.height_above_ground > 0.0
	if landing_marker.visible:
		landing_marker.position = ball.predict_landing()

	if state == State.POINT:
		point_time_left -= delta
		if point_time_left <= 0.0:
			_prepare_serve()
	elif state == State.WAITING_FOR_SERVE and serving_side == Ball.Side.RIGHT:
		serve_time_left -= delta
		if serve_time_left <= 0.0:
			_start_serve()


func _prepare_serve() -> void:
	state = State.WAITING_FOR_SERVE
	player_left.controls_enabled = false
	player_left.reset_for_serve(left_start)
	player_right.controls_enabled = false
	player_right.reset_for_serve(right_start)
	serve_time_left = ai_serve_delay
	var serve_position := left_start + Vector2(26, -2)
	if serving_side == Ball.Side.RIGHT:
		serve_position = right_start + Vector2(-26, -2)
	ball.prepare_serve(serve_position, serving_side)
	var server := "LEFT" if serving_side == Ball.Side.LEFT else "RIGHT"
	status_label.text = "%s serves · Enter to start" % server
	if serving_side == Ball.Side.RIGHT:
		status_label.text = "RIGHT serves · get ready"


func _start_serve() -> void:
	state = State.RALLY
	player_left.controls_enabled = true
	player_right.controls_enabled = true
	if serving_side == Ball.Side.LEFT:
		ball.serve(Vector2.ZERO, toss_height, toss_speed)
	else:
		ball.serve(Vector2(randf_range(-220, -120), randf_range(-40, 40)), 60.0, 200.0)
	status_label.text = "K: receive · hold ←/→ to pass · Space: jump · L: spike"


func _on_ball_landed(ground_position: Vector2, last_touch: int) -> void:
	if state != State.RALLY:
		return
	# A ball touching a boundary line is in, including its radius.
	var closest_point := ground_position.clamp(court_bounds.position, court_bounds.end)
	var inside := ground_position.distance_squared_to(closest_point) <= Ball.RADIUS * Ball.RADIUS
	var winner := Ball.Side.RIGHT if ground_position.x < ball.net_x else Ball.Side.LEFT
	if not inside:
		winner = Ball.Side.RIGHT if last_touch == Ball.Side.LEFT else Ball.Side.LEFT
	scores[winner] += 1
	serving_side = winner
	_update_scores()
	var team := "LEFT" if winner == Ball.Side.LEFT else "RIGHT"
	if scores[winner] >= winning_score:
		state = State.GAME_OVER
		player_left.controls_enabled = false
		player_right.controls_enabled = false
		status_label.text = ""
		_show_popup("%s wins!" % team, false)
		return
	state = State.POINT
	point_time_left = point_pause
	player_left.controls_enabled = false
	player_right.controls_enabled = false
	var reason := "Ball down" if inside else "Out"
	status_label.text = "%s · %s wins the point" % [reason, team]


func _update_scores() -> void:
	left_score_label.text = "LEFT  %d" % scores[Ball.Side.LEFT]
	right_score_label.text = "RIGHT  %d" % scores[Ball.Side.RIGHT]


func _show_popup(title: String, can_resume: bool) -> void:
	popup_title.text = title
	resume_button.visible = can_resume
	popup.show()
	if can_resume:
		resume_button.grab_focus()
	else:
		restart_button.grab_focus()


func _on_resume_pressed() -> void:
	popup.hide()
	get_tree().paused = false


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
