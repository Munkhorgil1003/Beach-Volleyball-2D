extends AnimatedSprite2D

const Ball = preload("res://scripts/ball.gd")

@export var speed: float = 110.0
# Bounds use the player's feet as the position, with room for the sprite at each side.
@export var court_bounds: Rect2 = Rect2(34, 155, 142, 255)
@export var jump_speed: float = 300.0
@export var gravity: float = 550.0
@export var ball: Ball
# Frame numbers start at zero. X is forward reach; Y is height above the feet.
@export_range(0, 30) var spike_contact_frame: int = 1
@export var spike_hand_offset: Vector2 = Vector2(12, 38)
@export_range(0, 30) var receive_contact_frame: int = 1
@export var receive_hand_offset: Vector2 = Vector2(12, 18)
@export_range(0.1, 3.0) var receive_charge_time: float = 1.0
@export var pass_speed: float = 120.0
@export var side: Ball.Side = Ball.Side.LEFT

var controls_enabled: bool = true
var height_above_ground: float = 0.0
var vertical_speed: float = 0.0
var is_jumping: bool = false
var has_spiked: bool = false
var spike_hit: bool = false
var is_receiving: bool = false
var receive_hit: bool = false
var receive_hold_time: float = 0.0
var jump_queued: bool = false


func _ready() -> void:
	frame_changed.connect(_on_frame_changed)
	animation_finished.connect(_on_animation_finished)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event.is_action_pressed("jump") and not is_jumping:
		if is_receiving and not receive_hit:
			jump_queued = true
		else:
			_start_jump()
	elif event.is_action_pressed("spike") and is_jumping and not has_spiked:
		has_spiked = true
		spike_hit = false
		play("spike")
		# Starting at frame zero may not emit frame_changed if the old frame was zero.
		_on_frame_changed()
	elif event.is_action_pressed("receive") and not is_jumping and not is_receiving:
		is_receiving = true
		receive_hit = false
		receive_hold_time = 0.0
		play("receive")
		_on_frame_changed()


func _on_frame_changed() -> void:
	_check_contact()


func _check_contact() -> void:
	if not controls_enabled or not is_instance_valid(ball):
		return
	if animation == &"receive" and is_receiving and controls_enabled:
		if receive_hit or frame < receive_contact_frame:
			return
		var facing := -1.0 if flip_h else 1.0
		var hand_position := global_position + Vector2(receive_hand_offset.x * facing, 0)
		var charge := clampf(receive_hold_time / receive_charge_time, 0.0, 1.0)
		# Holding left or right sends the ball that way instead of straight up.
		var pass_velocity := Vector2(Input.get_axis("move_left", "move_right") * pass_speed, 0)
		receive_hit = ball.try_receive(hand_position, receive_hand_offset.y, side, charge,
			pass_velocity)
		if receive_hit:
			if jump_queued:
				_start_jump()
			else:
				play("receive")
		return
	if animation != &"spike" or not is_jumping or not has_spiked or not is_playing():
		return
	if spike_hit or frame < spike_contact_frame:
		return

	var facing := -1.0 if flip_h else 1.0
	var hand_ground_position := global_position + Vector2(spike_hand_offset.x * facing, 0)
	var hand_height := height_above_ground + spike_hand_offset.y
	spike_hit = ball.try_spike(hand_ground_position, hand_height, facing, side)


func _start_jump() -> void:
	is_receiving = false
	jump_queued = false
	is_jumping = true
	vertical_speed = jump_speed
	play("jump")


func _on_animation_finished() -> void:
	if animation == &"receive":
		is_receiving = false
		if jump_queued and controls_enabled:
			_start_jump()


func reset_for_serve(ground_position: Vector2) -> void:
	position = ground_position
	height_above_ground = 0.0
	vertical_speed = 0.0
	is_jumping = false
	has_spiked = false
	spike_hit = false
	is_receiving = false
	receive_hit = false
	receive_hold_time = 0.0
	jump_queued = false
	flip_h = side == Ball.Side.RIGHT
	stop()
	play("idle")
	offset.y = -sprite_frames.get_frame_texture("idle", 0).get_height() / 2.0


func _physics_process(delta: float) -> void:
	if controls_enabled and is_receiving and not receive_hit and Input.is_action_pressed("receive"):
		receive_hold_time = minf(receive_hold_time + delta, receive_charge_time)

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# While receiving, the arrows only aim the pass instead of walking.
	if not controls_enabled or is_receiving:
		direction = Vector2.ZERO
	position += direction * speed * delta
	position = position.clamp(court_bounds.position, court_bounds.end)

	if direction.x != 0.0 and not has_spiked and not is_receiving:
		flip_h = direction.x < 0.0

	if is_jumping:
		height_above_ground += vertical_speed * delta - 0.5 * gravity * delta * delta
		vertical_speed -= gravity * delta
		if height_above_ground <= 0.0:
			height_above_ground = 0.0
			vertical_speed = 0.0
			is_jumping = false
			has_spiked = false

	if not is_jumping and not is_receiving:
		play("idle" if direction == Vector2.ZERO else "run")

	# Check throughout the active pose, but allow only one successful hit per action.
	_check_contact()
	if is_receiving and not receive_hit and frame >= receive_contact_frame:
		if controls_enabled and Input.is_action_pressed("receive"):
			pause()
		elif not is_playing():
			play("receive")

	# Move only the drawing upward; position and the child shadow stay on the court.
	var frame_height := sprite_frames.get_frame_texture(animation, frame).get_height()
	offset.y = -frame_height / 2.0 - height_above_ground
