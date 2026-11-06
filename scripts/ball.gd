extends AnimatedSprite2D

signal landed(ground_position: Vector2, last_touch: int)
signal contact_made(side: int, touches: int)
signal fault(side: int, reason: String)
signal net_hit
signal net_skimmed
# Strength runs from a soft pass (low) to a full spike (1.0).
signal struck(strength: float)

enum Side { LEFT, RIGHT }
const RADIUS: float = 5.0

# Position is on the sand; height only moves the drawing above its shadow.
@export var velocity: Vector2 = Vector2(35, 0)
@export var height_above_ground: float = 40.0
@export var vertical_speed: float = 0.0
@export_range(1.0, 2000.0) var gravity: float = 550.0
@export_range(0.0, 0.95) var bounce_strength: float = 0.45
@export_range(1.0, 1000.0) var ground_friction: float = 140.0
@export_range(1.0, 100.0) var spike_reach: float = 44.0
@export_range(1.0, 100.0) var spike_height_reach: float = 40.0
@export var spike_speed: float = 260.0
@export var spike_downward_speed: float = 220.0
@export var spike_upward_speed: float = 220.0
# Player-to-ball ground offset needed to reach the strongest angle.
@export_range(1.0, 100.0) var spike_position_range: float = 32.0
@export_range(0.0, 60.0) var spike_side_angle: float = 40.0
@export var serve_upward_speed: float = 260.0
@export var tip_upward_speed: float = 290.0
@export_range(15.0, 100.0) var tip_distance_past_net: float = 50.0
@export_range(1.0, 100.0) var block_reach: float = 20.0
@export_range(1.0, 100.0) var block_height_reach: float = 22.0
@export_range(1.0, 100.0) var block_net_distance: float = 32.0
@export var block_return_speed: float = 180.0
@export var block_upward_speed: float = 80.0
@export_range(1.0, 100.0) var receive_reach: float = 20.0
@export_range(1.0, 100.0) var receive_height_reach: float = 16.0
@export var receive_upward_speed: float = 260.0
@export var charged_receive_upward_speed: float = 410.0
@export var net_x: float = 200.0
@export var net_height: float = 50.0
@export var net_span: Vector2 = Vector2(145, 415)
@export_range(0.0, 1.0) var net_rebound: float = 0.2
# Clearing the net top by less than this still brushes the tape.
@export_range(0.0, 50.0) var net_skim_height: float = 8.0

var last_touch: int = Side.LEFT
var rally_active: bool = true
var contact_team: int = -1
var team_touches: int = 0
var last_hitter: Node = null
var server: Node = null
var serve_pending: bool = false
var is_service: bool = false


func _ready() -> void:
	height_above_ground = maxf(height_above_ground, 0.0)
	_update_visuals()


func prepare_serve(ground_position: Vector2, serving_side: int, serving_player: Node = null) -> void:
	contact_team = -1
	team_touches = 0
	last_hitter = null
	server = serving_player
	serve_pending = false
	is_service = false
	position = ground_position
	velocity = Vector2.ZERO
	height_above_ground = 0.0
	vertical_speed = 0.0
	last_touch = serving_side
	rally_active = false
	set_physics_process(false)
	stop()
	_update_visuals()


func serve(ground_velocity: Vector2, height: float, upward_speed: float, toss_only: bool = false) -> void:
	serve_pending = toss_only
	is_service = not toss_only
	if not toss_only:
		last_hitter = server
		contact_team = last_touch
		struck.emit(0.85)
	velocity = ground_velocity
	height_above_ground = height
	vertical_speed = upward_speed
	rally_active = true
	set_physics_process(true)
	play("spin")
	_update_visuals()


func try_spike(hand_ground_position: Vector2, hand_height: float, facing: float,
		hitter_side: int = Side.LEFT, hitter: Node = null, power: float = 1.0, tip: bool = false) -> bool:
	if not rally_active or height_above_ground <= 0.0 or facing == 0.0:
		return false
	if tip and serve_pending:
		return false
	if global_position.distance_to(hand_ground_position) > spike_reach:
		return false
	# Height measures the bottom of the ball; its center is about five pixels higher.
	if absf(height_above_ground + RADIUS - hand_height) > spike_height_reach:
		return false
	if not is_instance_valid(hitter) or not hitter is Node2D:
		return false

	var serving := serve_pending
	var contact_offset := global_position - (hitter as Node2D).global_position
	if not _register_contact(hitter_side, hitter):
		return false
	power = clampf(power, 0.7, 1.0)
	var direction := 1.0 if hitter_side == Side.LEFT else -1.0
	if serving:
		# Keep baseline serves lifted so they can cross the whole court.
		velocity = Vector2(direction * spike_speed * power, 0)
		vertical_speed = serve_upward_speed
	elif tip:
		# A soft arc clears the hands and drops just behind the net defender.
		vertical_speed = tip_upward_speed
		var side_aim := clampf(contact_offset.y / spike_position_range, -1.0, 1.0)
		var target := Vector2(net_x + direction * tip_distance_past_net,
			clampf(global_position.y + side_aim * 40.0, net_span.x + RADIUS, net_span.y - RADIUS))
		velocity = (target - global_position) / seconds_to_ground(height_above_ground, vertical_speed)
	else:
		# Mirror X for the right team: ball in front = steep, ball behind = lofted.
		var forward_offset := clampf(contact_offset.x * direction / spike_position_range, -1.0, 1.0)
		vertical_speed = -forward_offset * (spike_downward_speed if forward_offset >= 0.0 else spike_upward_speed) * power
		# Y aims away from the player's body; ground speed stays constant on diagonals.
		var side_angle := deg_to_rad(spike_side_angle) * clampf(contact_offset.y / spike_position_range, -1.0, 1.0)
		velocity = Vector2(direction * cos(side_angle), sin(side_angle)) * spike_speed * power
	struck.emit(0.45 if tip else (0.85 if serving else power))
	play("spin")
	_update_visuals()
	return true


func try_block(hand_ground_position: Vector2, hand_height: float, blocker_side: int, hitter: Node = null) -> bool:
	if not rally_active or height_above_ground <= 0.0 or last_touch == blocker_side:
		return false
	var direction := 1.0 if blocker_side == Side.LEFT else -1.0
	if velocity.x * direction >= 0.0:
		return false
	if absf(hand_ground_position.x - net_x) > block_net_distance \
			or hand_ground_position.y < net_span.x or hand_ground_position.y > net_span.y:
		return false
	# Only block at our side of the net, with the hands above its top.
	if (global_position.x - net_x) * direction > RADIUS or hand_height < net_height:
		return false
	if global_position.distance_to(hand_ground_position) > block_reach \
			or absf(height_above_ground + RADIUS - hand_height) > block_height_reach:
		return false

	if is_service:
		_end_with_fault(blocker_side, "Blocked serve")
		return false
	if not _register_contact(blocker_side, hitter):
		return false
	velocity = Vector2(direction * block_return_speed, velocity.y * 0.35)
	vertical_speed = block_upward_speed
	struck.emit(0.7)
	play("spin")
	_update_visuals()
	return true


func try_receive(hand_ground_position: Vector2, hand_height: float,
		hitter_side: int = Side.LEFT, charge: float = 0.0,
		pass_velocity: Vector2 = Vector2.ZERO, hitter: Node = null) -> bool:
	if not rally_active or height_above_ground <= 0.0:
		return false
	if global_position.distance_to(hand_ground_position) > receive_reach:
		return false
	if absf(height_above_ground + RADIUS - hand_height) > receive_height_reach:
		return false

	if not _register_contact(hitter_side, hitter):
		return false
	velocity = pass_velocity
	vertical_speed = receive_speed(charge)
	struck.emit(lerpf(0.4, 0.55, clampf(charge, 0.0, 1.0)))
	play("spin")
	_update_visuals()
	return true


func _register_contact(hitter_side: int, hitter: Node) -> bool:
	if not rally_active or not is_instance_valid(hitter):
		return false
	if serve_pending:
		if hitter != server:
			_end_with_fault(hitter_side, "Wrong server")
			return false
		serve_pending = false
		is_service = true
		team_touches = 0
	else:
		if contact_team == hitter_side and last_hitter == hitter:
			_end_with_fault(hitter_side, "Double hit")
			return false
		if contact_team != hitter_side:
			team_touches = 0
		if team_touches >= 3:
			_end_with_fault(hitter_side, "Four touches")
			return false
		team_touches += 1
		is_service = false
	last_touch = hitter_side
	contact_team = hitter_side
	last_hitter = hitter
	contact_made.emit(hitter_side, team_touches)
	return true


func _end_with_fault(side: int, reason: String) -> void:
	if not rally_active:
		return
	rally_active = false
	fault.emit(side, reason)


func predict_at_height(height: float) -> Vector2:
	var discriminant := vertical_speed * vertical_speed + 2.0 * gravity * (height_above_ground - height)
	if discriminant < 0.0:
		return predict_landing()
	var seconds := maxf((vertical_speed + sqrt(discriminant)) / gravity, 0.0)
	return global_position + velocity * seconds


func receive_speed(charge: float) -> float:
	return lerpf(receive_upward_speed,
		maxf(receive_upward_speed, charged_receive_upward_speed), clampf(charge, 0.0, 1.0))


# Seconds until the ball reaches the sand, starting from this height and upward speed.
func seconds_to_ground(height: float, upward_speed: float) -> float:
	return (upward_speed + sqrt(upward_speed * upward_speed + 2.0 * gravity * height)) / gravity


# Where the ball will touch the sand if nothing hits it first.
func predict_landing() -> Vector2:
	return global_position + velocity * seconds_to_ground(height_above_ground, vertical_speed)


func _physics_process(delta: float) -> void:
	var end_velocity := velocity
	if height_above_ground <= 0.0 and vertical_speed == 0.0:
		end_velocity = velocity.move_toward(Vector2.ZERO, ground_friction * delta)
	var travel := (velocity + end_velocity) * 0.5 * delta
	var direction := signf(travel.x)
	var distance_to_net := net_x - position.x
	var crosses_net := direction != 0.0 and distance_to_net * direction >= 0.0 \
		and (distance_to_net - travel.x) * direction <= 0.0

	if crosses_net:
		# Split the step at the net so even fast shots use their height at contact.
		var time_to_net := delta * clampf(distance_to_net / travel.x, 0.0, 1.0)
		_advance_motion(time_to_net)
		position.x = net_x
		var within_net := position.y >= net_span.x and position.y <= net_span.y
		if within_net and height_above_ground <= net_height:
			position.x = net_x - direction * RADIUS
			velocity = Vector2(-velocity.x, velocity.y) * net_rebound
			vertical_speed = minf(vertical_speed, 0.0)
			net_hit.emit()
		elif within_net and height_above_ground <= net_height + net_skim_height:
			net_skimmed.emit()
		_advance_motion(delta - time_to_net)
	else:
		_advance_motion(delta)
	_update_visuals()


func _advance_motion(delta: float) -> void:
	var previous_velocity := velocity
	var touched_ground := false
	var landing_position := position
	if height_above_ground > 0.0 or vertical_speed != 0.0:
		# Calculate the contact point before the bounce carries the ball farther.
		var time_to_ground := (vertical_speed + sqrt(vertical_speed * vertical_speed \
			+ 2.0 * gravity * height_above_ground)) / gravity
		height_above_ground += vertical_speed * delta - 0.5 * gravity * delta * delta
		vertical_speed -= gravity * delta
		if height_above_ground <= 0.0:
			touched_ground = true
			landing_position = position + velocity * clampf(time_to_ground, 0.0, delta)
			height_above_ground = 0.0
			vertical_speed = -vertical_speed * bounce_strength
			# Stop tiny bounces so the ball can settle instead of jittering forever.
			if vertical_speed < 20.0:
				vertical_speed = 0.0
			stop()
			play("bounce")
	else:
		velocity = velocity.move_toward(Vector2.ZERO, ground_friction * delta)

	position += (previous_velocity + velocity) * 0.5 * delta
	if touched_ground and rally_active:
		rally_active = false
		landed.emit(landing_position, last_touch)


func _update_visuals() -> void:
	if animation != &"bounce" or not is_playing():
		if height_above_ground > 0.0 or vertical_speed > 0.0:
			play("spin")
		elif velocity != Vector2.ZERO:
			play("roll")
		else:
			play("idle")

	if velocity.x != 0.0:
		flip_h = velocity.x < 0.0
	var frame_height := sprite_frames.get_frame_texture(animation, frame).get_height()
	offset.y = -frame_height / 2.0 - height_above_ground
