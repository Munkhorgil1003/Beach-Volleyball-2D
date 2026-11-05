extends Node2D

const Ball = preload("res://scripts/ball.gd")
enum State { WAITING_FOR_SERVE, RALLY, POINT }

@export var court_bounds: Rect2 = Rect2(16, 145, 368, 270)
@export var point_pause: float = 1.2
@export var toss_height: float = 160.0
@export var toss_speed: float = 160.0

@onready var ball = $Ball
@onready var player_left = $PlayerLeft
@onready var player_right = $PlayerRight
@onready var left_start: Vector2 = player_left.position
@onready var right_start: Vector2 = player_right.position
@onready var left_score_label: Label = $Scoreboard/LeftScore
@onready var right_score_label: Label = $Scoreboard/RightScore
@onready var status_label: Label = $Scoreboard/Status

var scores: Array[int] = [0, 0]
var serving_side: int = Ball.Side.LEFT
var state: State = State.WAITING_FOR_SERVE
var point_time_left: float = 0.0


func _ready() -> void:
	ball.landed.connect(_on_ball_landed)
	_update_scores()
	_prepare_serve()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.WAITING_FOR_SERVE and event.is_action_pressed("serve"):
		_start_serve()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state == State.POINT:
		point_time_left -= delta
		if point_time_left <= 0.0:
			_prepare_serve()


func _prepare_serve() -> void:
	state = State.WAITING_FOR_SERVE
	player_left.controls_enabled = false
	player_left.reset_for_serve(left_start)
	player_right.position = right_start
	player_right.play("idle")
	var serve_position := left_start + Vector2(26, -2)
	if serving_side == Ball.Side.RIGHT:
		serve_position = right_start + Vector2(-26, -2)
	ball.prepare_serve(serve_position, serving_side)
	var server := "LEFT" if serving_side == Ball.Side.LEFT else "RIGHT"
	status_label.text = "%s serves · Enter to start" % server


func _start_serve() -> void:
	state = State.RALLY
	player_left.controls_enabled = true
	if serving_side == Ball.Side.LEFT:
		ball.serve(Vector2.ZERO, toss_height, toss_speed)
	else:
		# A straight serve until the right player's rally AI is added.
		ball.serve(Vector2(-140, 0), 60.0, 200.0)
	status_label.text = "Hold K: receive · Space: jump · L: spike"


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
	state = State.POINT
	point_time_left = point_pause
	player_left.controls_enabled = false
	var team := "LEFT" if winner == Ball.Side.LEFT else "RIGHT"
	var reason := "Ball down" if inside else "Out"
	status_label.text = "%s · %s wins the point" % [reason, team]
	_update_scores()


func _update_scores() -> void:
	left_score_label.text = "LEFT  %d" % scores[Ball.Side.LEFT]
	right_score_label.text = "RIGHT  %d" % scores[Ball.Side.RIGHT]
