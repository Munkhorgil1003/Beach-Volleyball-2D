extends AnimatedSprite2D

# Position is on the sand; height only moves the drawing above its shadow.
@export var velocity: Vector2 = Vector2(35, 0)
@export var height_above_ground: float = 40.0
@export var vertical_speed: float = 0.0
@export_range(1.0, 2000.0) var gravity: float = 550.0
@export_range(0.0, 0.95) var bounce_strength: float = 0.45
@export_range(1.0, 1000.0) var ground_friction: float = 140.0
@export_range(1.0, 100.0) var spike_reach: float = 16.0
@export_range(1.0, 100.0) var spike_height_reach: float = 16.0
@export var spike_speed: float = 260.0
@export var spike_downward_speed: float = 180.0


func _ready() -> void:
	height_above_ground = maxf(height_above_ground, 0.0)
	_update_visuals()


func try_spike(hand_ground_position: Vector2, hand_height: float, facing: float) -> bool:
	if height_above_ground <= 0.0 or facing == 0.0:
		return false
	if global_position.distance_to(hand_ground_position) > spike_reach:
		return false
	# Height measures the bottom of the ball; its center is about five pixels higher.
	if absf(height_above_ground + 5.0 - hand_height) > spike_height_reach:
		return false

	velocity = Vector2(signf(facing) * spike_speed, 0)
	vertical_speed = -spike_downward_speed
	play("spin")
	_update_visuals()
	return true


func _physics_process(delta: float) -> void:
	var previous_velocity := velocity
	if height_above_ground > 0.0 or vertical_speed != 0.0:
		height_above_ground += vertical_speed * delta - 0.5 * gravity * delta * delta
		vertical_speed -= gravity * delta
		if height_above_ground <= 0.0:
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
	_update_visuals()


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
