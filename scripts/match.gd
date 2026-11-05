extends Node2D

const Ball = preload("res://scripts/ball.gd")
const Menu = preload("res://scripts/menu.gd")
enum State { WAITING_FOR_SERVE, RALLY, POINT, GAME_OVER }

@export var court_bounds: Rect2 = Rect2(16, 145, 368, 270)
@export var point_pause: float = 1.2
@export var winning_score: int = 21
@export var toss_height: float = 160.0
@export var toss_speed: float = 160.0
@export var ai_serve_delay: float = 1.0

@export_category("Stamina")
@export_range(1.0, 200.0) var max_stamina: float = 100.0
@export var movement_drain: float = 4.0
@export var resting_recovery: float = 10.0
@export var between_points_recovery: float = 16.0
@export var jump_cost: float = 12.0
@export var dive_cost: float = 18.0
@export var spike_cost: float = 10.0
@export var block_cost: float = 6.0

@onready var ball = $Ball
@onready var net: AnimatedSprite2D = $Net

@onready var player_left = $PlayerLeft
@onready var player_right = $PlayerRight

@onready var left_start: Vector2 = player_left.position
@onready var right_start: Vector2 = player_right.position
@onready var teams: Array = [[$PlayerLeft, $Teammate], [$PlayerRight, $OpponentTwo]]
var starting_positions: Dictionary = {}
var stamina: Dictionary = {}
@onready var stamina_bars: Array = [
	[$Scoreboard/Stamina/Left/You/Bar, $Scoreboard/Stamina/Left/Partner/Bar],
	[$Scoreboard/Stamina/Right/RivalOne/Bar, $Scoreboard/Stamina/Right/RivalTwo/Bar]
]

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
var difficulty: int = Menu.Difficulty.NORMAL


func _ready() -> void:
	difficulty = int(get_tree().get_meta("difficulty", Menu.load_difficulty()))
	for opponent in teams[Ball.Side.RIGHT]:
		opponent.apply_difficulty(difficulty)
	ball.landed.connect(_on_ball_landed)
	ball.fault.connect(_on_contact_fault)
	ball.contact_made.connect(_on_contact_made)
	ball.net_hit.connect(_on_ball_net_hit)
	for team in teams:
		for player in team:
			starting_positions[player] = player.position
			stamina[player] = max_stamina
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	_update_scores()
	_prepare_serve()
	_update_stamina_bars()


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
	_update_stamina_bars()
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


# Shared rules keep the human, teammate, and opponents on the same stamina system.
func update_stamina(player: Node, delta: float, moving: bool, busy: bool) -> void:
	if state == State.GAME_OVER or get_tree().paused:
		return
	var change := between_points_recovery
	if state == State.RALLY:
		change = -movement_drain if moving else (0.0 if busy else resting_recovery)
	stamina[player] = clampf(float(stamina[player]) + change * delta, 0.0, max_stamina)


func spend_stamina(player: Node, amount: float) -> void:
	stamina[player] = maxf(float(stamina[player]) - amount, 0.0)


func stamina_factor(player: Node) -> float:
	# Keep every action available, even when exhausted. Only the bottom 30% slows it.
	return lerpf(0.7, 1.0, clampf(float(stamina[player]) / (max_stamina * 0.3), 0.0, 1.0))


func _update_stamina_bars() -> void:
	for side in range(teams.size()):
		for index in range(teams[side].size()):
			var bar: ProgressBar = stamina_bars[side][index]
			bar.max_value = max_stamina
			bar.value = stamina[teams[side][index]]
			bar.modulate = Color(1, 0.55, 0.4) if bar.value <= max_stamina * 0.3 else Color.WHITE


func _prepare_serve() -> void:
	state = State.WAITING_FOR_SERVE
	for team in teams:
		for player in team:
			player.controls_enabled = false
			player.reset_for_serve(starting_positions[player])
	serve_time_left = ai_serve_delay
	var serve_position := left_start + Vector2(26, -2)
	if serving_side == Ball.Side.RIGHT:
		serve_position = right_start + Vector2(-26, -2)
	ball.prepare_serve(serve_position, serving_side, teams[serving_side][0])
	_update_scores()
	var server := "LEFT" if serving_side == Ball.Side.LEFT else "RIGHT"
	status_label.text = "%s serves · L to start" % server
	if serving_side == Ball.Side.RIGHT:
		status_label.text = "RIGHT serves · get ready"


func _start_serve() -> void:
	state = State.RALLY
	for team in teams:
		for player in team:
			player.controls_enabled = true
	if serving_side == Ball.Side.LEFT:
		ball.serve(Vector2.ZERO, toss_height, toss_speed, true)
	else:
		spend_stamina(player_right, spike_cost)
		ball.serve(Vector2(randf_range(-220, -120), randf_range(-40, 40)) * stamina_factor(player_right), 60.0, 200.0)
	status_label.text = "K: pass/set · ←/→+K: 3rd return\nShift: dive · Space: jump · J: block · L: spike"


func _on_ball_landed(ground_position: Vector2, last_touch: int) -> void:
	if state != State.RALLY:
		return
	# A ball touching a boundary line is in, including its radius.
	var closest_point := ground_position.clamp(court_bounds.position, court_bounds.end)
	var inside := ground_position.distance_squared_to(closest_point) <= Ball.RADIUS * Ball.RADIUS
	var winner := Ball.Side.RIGHT if ground_position.x < ball.net_x else Ball.Side.LEFT
	if not inside:
		winner = Ball.Side.RIGHT if last_touch == Ball.Side.LEFT else Ball.Side.LEFT
	_award_point(winner, "Ball down" if inside else "Out")


func _on_contact_fault(side: int, reason: String) -> void:
	_award_point(1 - side, reason)


func _on_contact_made(_side: int, _touches: int) -> void:
	_update_scores()


func _on_ball_net_hit() -> void:
	# Restart the shake so back-to-back hits still wobble the net.
	net.stop()
	net.play("shake")


func _award_point(winner: int, reason: String) -> void:
	if state != State.RALLY:
		return
	scores[winner] += 1
	serving_side = winner
	_update_scores()
	for team in teams:
		for player in team:
			player.controls_enabled = false
	var team_name := "LEFT" if winner == Ball.Side.LEFT else "RIGHT"
	if scores[winner] >= winning_score and scores[winner] - scores[1 - winner] >= 2:
		state = State.GAME_OVER
		status_label.text = ""
		_show_popup("%s wins!" % team_name, false)
		return
	state = State.POINT
	point_time_left = point_pause
	status_label.text = "%s · %s wins the point" % [reason, team_name]


func _update_scores() -> void:
	var left_touches: int = ball.team_touches if ball.contact_team == Ball.Side.LEFT else 0
	var right_touches: int = ball.team_touches if ball.contact_team == Ball.Side.RIGHT else 0
	left_score_label.text = "LEFT %d · %d/3" % [scores[0], left_touches]
	right_score_label.text = "RIGHT %d · %d/3" % [scores[1], right_touches]


func receiver_for(side: int) -> Node2D:
	if state != State.RALLY or not ball.rally_active:
		return null
	if ball.serve_pending:
		return ball.server if side == ball.last_touch else null
	var direction := 1.0 if side == Ball.Side.LEFT else -1.0
	if (ball.position.x - ball.net_x) * direction > Ball.RADIUS and ball.velocity.x * direction >= 0:
		return null
	var target: Vector2 = ball.predict_at_height(90.0 if ball.contact_team == side and ball.team_touches == 2 else 13.0)
	var chosen: Node2D = null
	var closest: float = INF
	for player in teams[side]:
		if ball.contact_team == side and ball.last_hitter == player:
			continue
		var distance: float = player.global_position.distance_squared_to(target)
		if distance < closest:
			closest = distance
			chosen = player
	return chosen


func pass_to_partner(hitter: Node2D, charge: float) -> Vector2:
	var side: int = hitter.side
	var direction := 1.0 if side == Ball.Side.LEFT else -1.0
	var next_touch: int = ball.team_touches + 1 if ball.contact_team == side else 1
	var upward: float = ball.receive_speed(charge)
	if next_touch >= 3:
		var target := Vector2(ball.net_x + direction * randf_range(55, 135), randf_range(170, 390))
		return (target - ball.global_position) / ball.seconds_to_ground(ball.height_above_ground, upward)
	var partner = teams[side][1] if teams[side][0] == hitter else teams[side][0]
	var target: Vector2
	var travel_time: float
	if next_touch == 1:
		target = partner.global_position + Vector2(direction * partner.receive_hand_offset.x, 0)
		travel_time = ball.seconds_to_ground(maxf(ball.height_above_ground - 13.0, 0.0), upward)
	else:
		# The third-touch attacker meets the set near the net on its way down.
		target = Vector2(ball.net_x - direction * 40.0, partner.position.y)
		travel_time = upward / ball.gravity + 0.25
	return (target - ball.global_position) / maxf(travel_time, 0.1)


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
