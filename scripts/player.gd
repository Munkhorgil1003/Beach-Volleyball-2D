extends AnimatedSprite2D

const Ball = preload("res://scripts/ball.gd")

@export var speed: float = 110.0
# Bounds use the player's feet as the position, with room for the sprite at each side.
@export var court_bounds: Rect2 = Rect2(34, 155, 142, 255)
@export var jump_speed: float = 220.0
@export var gravity: float = 550.0
@export var ball: Ball
# Frame numbers start at zero. X is forward reach; Y is height above the feet.
@export_range(0, 30) var spike_contact_frame: int = 1
@export var spike_hand_offset: Vector2 = Vector2(12, 38)

var height_above_ground: float = 0.0
var vertical_speed: float = 0.0
var is_jumping: bool = false
var has_spiked: bool = false
var spike_contact_checked: bool = false


func _ready() -> void:
	frame_changed.connect(_on_frame_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and not is_jumping:
		is_jumping = true
		vertical_speed = jump_speed
		play("jump")
	elif event.is_action_pressed("spike") and is_jumping and not has_spiked:
		has_spiked = true
		spike_contact_checked = false
		play("spike")
		# Starting at frame zero may not emit frame_changed if the old frame was zero.
		_on_frame_changed()


func _on_frame_changed() -> void:
	if animation != &"spike" or not is_jumping or not has_spiked:
		return
	if spike_contact_checked or frame < spike_contact_frame:
		return
	spike_contact_checked = true
	if not is_instance_valid(ball):
		return

	var facing := -1.0 if flip_h else 1.0
	var hand_ground_position := global_position + Vector2(spike_hand_offset.x * facing, 0)
	var hand_height := height_above_ground + spike_hand_offset.y
	ball.try_spike(hand_ground_position, hand_height, facing)


func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	position += direction * speed * delta
	position = position.clamp(court_bounds.position, court_bounds.end)

	if direction.x != 0.0 and not has_spiked:
		flip_h = direction.x < 0.0

	if is_jumping:
		height_above_ground += vertical_speed * delta - 0.5 * gravity * delta * delta
		vertical_speed -= gravity * delta
		if height_above_ground <= 0.0:
			height_above_ground = 0.0
			vertical_speed = 0.0
			is_jumping = false
			has_spiked = false

	if not is_jumping:
		play("idle" if direction == Vector2.ZERO else "run")

	# Move only the drawing upward; position and the child shadow stay on the court.
	var frame_height := sprite_frames.get_frame_texture(animation, frame).get_height()
	offset.y = -frame_height / 2.0 - height_above_ground
