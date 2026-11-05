extends AnimatedSprite2D

signal landed(ground_position: Vector2, last_touch: int)

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
@export var spike_downward_speed: float = 100.0
@export_range(1.0, 100.0) var receive_reach: float = 20.0
@export_range(1.0, 100.0) var receive_height_reach: float = 16.0
@export var receive_upward_speed: float = 260.0
@export var charged_receive_upward_speed: float = 410.0
@export var net_x: float = 200.0
@export var net_height: float = 50.0
@export var net_span: Vector2 = Vector2(145, 415)
@export_range(0.0, 1.0) var net_rebound: float = 0.2

var last_touch: int = Side.LEFT
var rally_active: bool = true


func _ready() -> void:
	height_above_ground = maxf(height_above_ground, 0.0)
	_update_visuals()


func prepare_serve(ground_position: Vector2, serving_side: int) -> void:
	position = ground_position
	velocity = Vector2.ZERO
	height_above_ground = 0.0
	vertical_speed = 0.0
	last_touch = serving_side
	rally_active = false
	set_physics_process(false)
	stop()
	_update_visuals()


func serve(ground_velocity: Vector2, height: float, upward_speed: float) -> void:
	velocity = ground_velocity
	height_above_ground = height
	vertical_speed = upward_speed
	rally_active = true
	set_physics_process(true)
	play("spin")
	_update_visuals()


func try_spike(hand_ground_position: Vector2, hand_height: float, facing: float,
		hitter_side: int = Side.LEFT) -> bool:
	if not rally_active or height_above_ground <= 0.0 or facing == 0.0:
		return false
	if global_position.distance_to(hand_ground_position) > spike_reach:
		return false
	# Height measures the bottom of the ball; its center is about five pixels higher.
	if absf(height_above_ground + RADIUS - hand_height) > spike_height_reach:
		return false

	last_touch = hitter_side
	velocity = Vector2(signf(facing) * spike_speed, 0)
	vertical_speed = -spike_downward_speed
	play("spin")
	_update_visuals()
	return true


func try_receive(hand_ground_position: Vector2, hand_height: float,
		hitter_side: int = Side.LEFT, charge: float = 0.0,
		pass_velocity: Vector2 = Vector2.ZERO) -> bool:
	if not rally_active or height_above_ground <= 0.0:
		return false
	if global_position.distance_to(hand_ground_position) > receive_reach:
		return false
	if absf(height_above_ground + RADIUS - hand_height) > receive_height_reach:
		return false

	last_touch = hitter_side
	velocity = pass_velocity
	vertical_speed = receive_speed(charge)
	play("spin")
	_update_visuals()
	return true


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
		if position.y >= net_span.x and position.y <= net_span.y \
				and height_above_ground <= net_height:
			position.x = net_x - direction * RADIUS
			velocity = Vector2(-velocity.x, velocity.y) * net_rebound
			vertical_speed = minf(vertical_speed, 0.0)
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
