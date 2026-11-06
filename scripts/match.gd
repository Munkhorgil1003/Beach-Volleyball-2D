extends Node2D

const Ball = preload("res://scripts/ball.gd")
const Menu = preload("res://scripts/menu.gd")
const TEAM_COLORS = [Color("ff667a"), Color("62b4ff")]
enum State { WAITING_FOR_SERVE, RALLY, POINT, GAME_OVER }

@export var court_bounds: Rect2 = Rect2(16, 145, 368, 270)
@export var point_pause: float = 1.2
@export var winning_score: int = 21
@export var toss_height: float = 160.0
@export var toss_speed: float = 160.0
@export var ai_serve_delay: float = 1.0
@export var serve_distance_behind_line: float = 16.0

@export_category("Audio")
@export var gull_interval: Vector2 = Vector2(6.0, 15.0)

@export_category("Stamina")
@export_range(1.0, 200.0) var max_stamina: float = 100.0
@export_range(0.05, 1.0) var low_stamina_ratio: float = 0.3
@export var movement_drain: float = 4.0
@export var resting_recovery: float = 10.0
@export var between_points_recovery: float = 16.0
@export var jump_cost: float = 12.0
@export var dive_cost: float = 18.0
@export var spike_cost: float = 10.0
@export var tip_cost: float = 6.0
@export var block_cost: float = 6.0

@onready var ball = $Ball
@onready var net: AnimatedSprite2D = $Net
@onready var hit_sound: AudioStreamPlayer2D = $Ball/HitSound
@onready var whistle: AudioStreamPlayer = $Audio/Whistle
@onready var gulls: AudioStreamPlayer = $Audio/Gulls
@onready var gull_timer: Timer = $Audio/GullTimer

@onready var player_left = $PlayerLeft
@onready var player_right = $PlayerRight

@onready var teams: Array = [[$PlayerLeft, $Teammate], [$PlayerRight, $OpponentTwo]]
var starting_positions: Dictionary = {}
var starting_bounds: Dictionary = {}
var stamina: Dictionary = {}
@onready var stamina_bars: Array = [
	[$Scoreboard/Stamina/Left/You/Bar, $Scoreboard/Stamina/Left/Partner/Bar],
	[$Scoreboard/Stamina/Right/RivalOne/Bar, $Scoreboard/Stamina/Right/RivalTwo/Bar]
]

@onready var left_score_label: Label = $Scoreboard/LeftScore
@onready var right_score_label: Label = $Scoreboard/RightScore
@onready var point_banner: Control = $Scoreboard/PointBanner
@onready var point_background: Panel = $Scoreboard/PointBanner/Background
@onready var point_title: Label = $Scoreboard/PointBanner/Title
@onready var point_score: Label = $Scoreboard/PointBanner/Score
@onready var point_reason: Label = $Scoreboard/PointBanner/Reason
@onready var point_flash: ColorRect = $Scoreboard/PointFlash
var point_tween: Tween

@onready var status_label: Label = $Scoreboard/Status
@onready var landing_marker: Sprite2D = $LandingMarker
@onready var popup: Panel = $Scoreboard/Popup
@onready var popup_title: Label = $Scoreboard/Popup/Box/Title
@onready var resume_button: Button = $Scoreboard/Popup/Box/ResumeButton
@onready var restart_button: Button = $Scoreboard/Popup/Box/RestartButton
@onready var menu_button: Button = $Scoreboard/Popup/Box/MenuButton

var scores: Array[int] = [0, 0]
var serving_side: int = Ball.Side.LEFT
var server_indices: Array[int] = [0, 0]
var has_served: Array[bool] = [false, false]
var blockers: Array = [null, null]
var state: State = State.WAITING_FOR_SERVE
var point_time_left: float = 0.0
var serve_time_left: float = 0.0
var difficulty: int = Menu.Difficulty.NORMAL
var team_name: String = "LEFT"
var right_team_name: String = "RIGHT"
var local_two_player: bool = false
var human_players: Array = []


func _ready() -> void:
	Menu.Player.apply_bindings(get_tree().get_meta("keybindings", Menu.Player.load_bindings()))
	local_two_player = bool(get_tree().get_meta("local_two_player", Menu.load_local_two_player()))
	human_players = [player_left]
	if local_two_player:
		_add_second_player()
		var second_profile: Dictionary = get_tree().get_meta("player_two_profile", Menu.load_profile(Menu.SETTINGS_PATH, 1))
		right_team_name = Menu.clean_team_name(second_profile.team_name, "RIGHT")
		player_right.sprite_frames = Menu.Player.frames_for_character(player_right.sprite_frames, second_profile.character)
		$Scoreboard/Stamina/Left/You/Name.text = "Player 1"
		$Scoreboard/Stamina/Right/RivalOne/Name.text = "Player 2"
		$Scoreboard/Stamina/Right/RivalTwo/Name.text = "Partner"
	var profile: Dictionary = get_tree().get_meta("player_profile", Menu.load_profile())
	team_name = Menu.clean_team_name(profile.team_name)
	player_left.sprite_frames = Menu.Player.frames_for_character(player_left.sprite_frames, profile.character)
	difficulty = int(get_tree().get_meta("difficulty", Menu.load_difficulty()))
	for side in range(teams.size()):
		for player in teams[side]:
			if not is_human(player) and (side == Ball.Side.RIGHT or local_two_player):
				player.apply_difficulty(difficulty)
	ball.landed.connect(_on_ball_landed)
	ball.fault.connect(_on_contact_fault)
	ball.net_hit.connect(_on_ball_net_hit)
	ball.net_skimmed.connect(_on_ball_net_skimmed)
	ball.struck.connect(_on_ball_struck)
	gull_timer.timeout.connect(_on_gull_timer_timeout)
	gull_timer.start(randf_range(gull_interval.x, gull_interval.y))
	for team in teams:
		for player in team:
			starting_positions[player] = player.position
			starting_bounds[player] = player.court_bounds
			stamina[player] = max_stamina
	for side in range(teams.size()):
		for bar in stamina_bars[side]:
			bar.add_theme_stylebox_override("fill", bar.get_theme_stylebox("fill").duplicate())
	left_score_label.add_theme_color_override("font_color", TEAM_COLORS[0])
	right_score_label.add_theme_color_override("font_color", TEAM_COLORS[1])
	point_background.add_theme_stylebox_override("panel", point_background.get_theme_stylebox("panel").duplicate())
	resume_button.pressed.connect(_on_resume_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	_update_scores()
	_prepare_serve()
	_update_stamina_bars()


func _add_second_player() -> void:
	# Reuse the human controller and existing art; keep the other teammate as AI.
	var original = player_right
	var second = Menu.Player.new()
	second.name = "PlayerRight"
	for property in ["position", "scale", "z_index", "sprite_frames", "offset", "modulate"]:
		second.set(property, original.get(property))
	second.side = Ball.Side.RIGHT
	second.input_prefix = "p2_"
	second.court_bounds = original.court_bounds
	second.ball = ball
	second.add_child(original.get_node("Shadow").duplicate())
	var index: int = original.get_index()
	remove_child(original)
	original.free()
	add_child(second)
	move_child(second, index)
	player_right = second
	teams[Ball.Side.RIGHT][0] = second
	human_players.append(second)


func is_human(player: Node) -> bool:
	return player in human_players


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and state != State.GAME_OVER:
		_show_popup("Paused", true)
		get_tree().paused = true
		get_viewport().set_input_as_handled()
	elif state == State.WAITING_FOR_SERVE and is_human(ball.server) \
			and event.is_action_pressed(ball.server.action("spike")):
		_start_serve()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_stamina_bars()
	if state == State.RALLY:
		# Allow the server to run in from outside without snapping onto the court.
		var bounds: Rect2 = starting_bounds[ball.server]
		if ball.server.position.x >= bounds.position.x and ball.server.position.x <= bounds.end.x:
			ball.server.court_bounds = bounds
	# Show where the ball will come down so it is easier to get under it.
	landing_marker.visible = state == State.RALLY and ball.height_above_ground > 0.0
	if landing_marker.visible:
		landing_marker.position = ball.predict_landing()

	if state == State.POINT:
		point_time_left -= delta
		if point_time_left <= 0.0:
			_prepare_serve()
	elif state == State.WAITING_FOR_SERVE and not is_human(ball.server):
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
	return lerpf(0.7, 1.0, clampf(float(stamina[player]) / (max_stamina * low_stamina_ratio), 0.0, 1.0))


func can_jump(player: Node) -> bool:
	return float(stamina[player]) > max_stamina * low_stamina_ratio \
		and float(stamina[player]) >= jump_cost


func _update_stamina_bars() -> void:
	for side in range(teams.size()):
		for index in range(teams[side].size()):
			var bar: ProgressBar = stamina_bars[side][index]
			bar.max_value = max_stamina
			bar.value = stamina[teams[side][index]]
			var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
			fill.bg_color = Color("ffd166") if bar.value <= max_stamina * low_stamina_ratio else TEAM_COLORS[side]


func _prepare_serve() -> void:
	_clear_point_celebration()
	blockers.assign([null, null])
	state = State.WAITING_FOR_SERVE
	for team in teams:
		for player in team:
			player.controls_enabled = false
			player.court_bounds = starting_bounds[player]
			player.reset_for_serve(starting_positions[player])
	serve_time_left = ai_serve_delay
	var server = teams[serving_side][server_indices[serving_side]]
	var direction := 1.0 if serving_side == Ball.Side.LEFT else -1.0
	server.position.x = court_bounds.position.x - serve_distance_behind_line if serving_side == Ball.Side.LEFT \
		else court_bounds.end.x + serve_distance_behind_line
	# Temporarily include the service area in this player's movement bounds.
	server.court_bounds = server.court_bounds.expand(server.position)
	ball.prepare_serve(server.position + Vector2(direction * 12.0, -2), serving_side, server)
	_update_scores()
	if is_human(server):
		var server_name: String = "P%d" % (server.side + 1) if local_two_player else "Your"
		status_label.text = "%s serve · %s to toss" % [server_name, Menu.Player.key_label(server.action("spike"))]
	else:
		var server_name: String = "P%d partner" % (serving_side + 1) if local_two_player else ("Partner" if serving_side == Ball.Side.LEFT else "Rival %d" % (server_indices[serving_side] + 1))
		status_label.text = "%s serves · get ready" % server_name


func _start_serve() -> void:
	state = State.RALLY
	has_served[serving_side] = true
	for team in teams:
		for player in team:
			player.controls_enabled = true
	if is_human(ball.server):
		ball.serve(Vector2.ZERO, toss_height, toss_speed, true)
	else:
		spend_stamina(ball.server, spike_cost)
		var direction := 1.0 if serving_side == Ball.Side.LEFT else -1.0
		var target := Vector2(ball.net_x + direction * randf_range(55, 135), randf_range(170, 390))
		var flight_time: float = ball.seconds_to_ground(60.0, 200.0)
		ball.serve((target - ball.position) / flight_time, 60.0, 200.0)
	var hints: Array[String] = []
	for human in human_players:
		hints.append("P%d · %s jump · %s spike · Air %s tip" % [human.side + 1,
			Menu.Player.key_label(human.action("jump")), Menu.Player.key_label(human.action("spike")),
			Menu.Player.key_label(human.action("receive"))])
	status_label.text = "\n".join(hints)


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


func _on_ball_net_hit() -> void:
	# Restart the shake so back-to-back hits still wobble the net.
	net.stop()
	net.play("shake")


func _on_ball_struck(strength: float) -> void:
	# Soft passes sound lighter and higher; spikes get the full, deeper thump.
	hit_sound.volume_db = lerpf(-10.0, 0.0, strength)
	hit_sound.pitch_scale = lerpf(1.25, 0.95, strength) * randf_range(0.95, 1.05)
	hit_sound.play()


func _on_gull_timer_timeout() -> void:
	gulls.play()
	gull_timer.start(randf_range(gull_interval.x, gull_interval.y))


func _on_ball_net_skimmed() -> void:
	# A brush over the tape should not cut short a stronger shake.
	if net.animation == &"shake" and net.is_playing():
		return
	net.stop()
	net.play("skim")


func _award_point(winner: int, reason: String) -> void:
	if state != State.RALLY:
		return
	scores[winner] += 1
	whistle.play()
	# Retain the server on a winning streak; alternate when a team wins service back.
	if winner != serving_side and has_served[winner]:
		server_indices[winner] = 1 - server_indices[winner]
	serving_side = winner
	_update_scores()
	for team in teams:
		for player in team:
			player.controls_enabled = false
	var winner_name := team_name if winner == Ball.Side.LEFT else right_team_name
	if scores[winner] >= winning_score and scores[winner] - scores[1 - winner] >= 2:
		state = State.GAME_OVER
		status_label.text = ""
		_show_popup("%s wins!" % winner_name, false)
		popup_title.add_theme_color_override("font_color", TEAM_COLORS[winner])
		_celebrate_point(winner, reason, false)
		return
	state = State.POINT
	point_time_left = point_pause
	status_label.text = ""
	_celebrate_point(winner, reason)


func _clear_point_celebration() -> void:
	if point_tween and point_tween.is_valid():
		point_tween.kill()
	point_banner.hide()
	point_flash.modulate.a = 0.0
	left_score_label.scale = Vector2.ONE
	right_score_label.scale = Vector2.ONE


func _celebrate_point(winner: int, reason: String, show_banner: bool = true) -> void:
	_clear_point_celebration()
	var color: Color = TEAM_COLORS[winner]
	var score_label: Label = left_score_label if winner == Ball.Side.LEFT else right_score_label
	score_label.pivot_offset = score_label.size * 0.5
	point_flash.color = Color(color, 0.12)
	point_flash.modulate.a = 1.0
	point_tween = create_tween().set_parallel(true)
	point_tween.tween_property(point_flash, "modulate:a", 0.0, 0.45)
	point_tween.tween_property(score_label, "scale", Vector2.ONE * 1.08, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	point_tween.tween_property(score_label, "scale", Vector2.ONE, 0.18).set_delay(0.12)
	if not show_banner:
		return
	var background := point_background.get_theme_stylebox("panel") as StyleBoxFlat
	background.bg_color = Color(color.darkened(0.75), 0.97)
	background.border_color = color
	$Scoreboard/PointBanner/Accent.color = color
	point_title.text = "POINT · %s" % (team_name if winner == Ball.Side.LEFT else right_team_name).to_upper()
	point_title.add_theme_color_override("font_color", color)
	point_score.text = "%d  :  %d" % [scores[0], scores[1]]
	point_reason.text = "%s · +1 POINT" % reason.to_upper()
	point_banner.pivot_offset = point_banner.size * 0.5
	point_banner.scale = Vector2.ONE * 0.88
	point_banner.modulate.a = 0.0
	point_banner.show()
	point_tween.tween_property(point_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	point_tween.tween_property(point_banner, "modulate:a", 1.0, 0.12)
	point_tween.tween_property(point_banner, "modulate:a", 0.0, 0.18).set_delay(maxf(point_pause - 0.22, 0.22))


func _update_scores() -> void:
	left_score_label.text = "%s %d" % [team_name, scores[0]]
	right_score_label.text = "%s %d" % [right_team_name, scores[1]]
	for label: Label in [left_score_label, right_score_label]:
		var font := label.get_theme_font("font")
		var font_size := 20
		while font_size > 10 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
			font_size -= 1
		label.add_theme_font_size_override("font_size", font_size)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


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
	var blocker := blocker_for(side)
	for player in teams[side]:
		if player == blocker:
			continue
		if ball.contact_team == side and ball.last_hitter == player:
			continue
		var distance: float = player.global_position.distance_squared_to(target)
		if distance < closest:
			closest = distance
			chosen = player
	return chosen


func block_target_for(side: int) -> Vector2:
	var direction := 1.0 if side == Ball.Side.LEFT else -1.0
	var target_y: float = ball.position.y
	if ball.velocity.x * direction < 0.0:
		var time_to_net: float = (ball.net_x - ball.position.x) / ball.velocity.x
		if time_to_net > 0.0 and time_to_net <= ball.seconds_to_ground(ball.height_above_ground, ball.vertical_speed):
			target_y += ball.velocity.y * time_to_net
	return Vector2(ball.net_x - direction * 24.0, clampf(target_y, ball.net_span.x + 16.0, ball.net_span.y - 16.0))


func blocker_for(side: int) -> Node2D:
	var direction := 1.0 if side == Ball.Side.LEFT else -1.0
	var distance_from_net: float = (ball.position.x - ball.net_x) * direction
	var landing_on_our_side: bool = (ball.predict_landing().x - ball.net_x) * direction < 0.0
	if state != State.RALLY or not ball.rally_active or ball.serve_pending or ball.is_service \
			or ball.contact_team != 1 - side or distance_from_net < -ball.block_reach - Ball.RADIUS \
			or distance_from_net > 125.0 or (ball.team_touches < 2 and not landing_on_our_side):
		blockers[side] = null
		return null
	# If the human chooses J, their teammate covers behind them instead of double-blocking.
	for human in human_players:
		if human.side == side and human.is_jumping and human.has_blocked:
			blockers[side] = human
			return human
	if is_instance_valid(blockers[side]):
		if blockers[side].height_above_ground > 0.0 or blockers[side].vertical_speed > 0.0 or can_jump(blockers[side]):
			return blockers[side]
		blockers[side] = null
	var closest: float = INF
	var target := block_target_for(side)
	for player in teams[side]:
		if is_human(player) or not player.controls_enabled or not can_jump(player):
			continue
		var distance: float = player.position.distance_squared_to(target)
		if distance < closest:
			closest = distance
			blockers[side] = player
	return blockers[side]


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
	popup_title.add_theme_color_override("font_color", Color.WHITE)
	popup_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_title.add_theme_font_size_override("font_size", 16 if title.length() > 18 else 18)
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
