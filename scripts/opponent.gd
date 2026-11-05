extends AnimatedSprite2D

# Simple computer player for the right side: run under the ball and pass it back.
const Ball = preload("res://scripts/ball.gd")

@export var speed: float = 90.0
@export var court_bounds: Rect2 = Rect2(224, 155, 142, 255)
@export var ball: Ball
@export_range(0, 30) var receive_contact_frame: int = 1
@export var receive_hand_offset: Vector2 = Vector2(12, 18)
# Passes land somewhere inside this part of the left court.
@export var pass_target_area: Rect2 = Rect2(50, 170, 120, 220)

var controls_enabled: bool = false
var home_position: Vector2
var is_receiving: bool = false
var receive_hit: bool = false


func _ready() -> void:
	home_position = position
	animation_finished.connect(_on_animation_finished)


func reset_for_serve(ground_position: Vector2) -> void:
	position = ground_position
	is_receiving = false
	receive_hit = false
	flip_h = true
	play("idle")


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if controls_enabled and not is_receiving:
		var target := home_position
		if _ball_is_ours():
			# Stand so the hands, not the feet, end up under the ball.
			target = ball.predict_landing() + Vector2(receive_hand_offset.x, 0)
		if position.distance_to(target) > 2.0:
			direction = position.direction_to(target)
	position += direction * speed * delta
	position = position.clamp(court_bounds.position, court_bounds.end)

	if not is_receiving:
		play("idle" if direction == Vector2.ZERO else "run")
		if controls_enabled and _ball_is_ours() and ball.vertical_speed < 0.0 \
				and ball.height_above_ground < 40.0 \
				and ball.global_position.distance_to(_hand_position()) < ball.receive_reach:
			is_receiving = true
			receive_hit = false
			play("receive")

	if is_receiving and not receive_hit and frame >= receive_contact_frame:
		receive_hit = ball.try_receive(_hand_position(), receive_hand_offset.y,
			Ball.Side.RIGHT, 1.0, _pass_velocity())
		# Wait at the contact pose until the ball arrives or the rally ends.
		if not receive_hit and _ball_is_ours():
			pause()
		elif not is_playing():
			play("receive")

	var frame_height := sprite_frames.get_frame_texture(animation, frame).get_height()
	offset.y = -frame_height / 2.0


func _ball_is_ours() -> bool:
	if not is_instance_valid(ball) or not ball.rally_active:
		return false
	if ball.last_touch == Ball.Side.RIGHT:
		return false
	return ball.position.x > ball.net_x or ball.velocity.x > 0.0


func _hand_position() -> Vector2:
	return global_position + Vector2(-receive_hand_offset.x, 0)


func _pass_velocity() -> Vector2:
	var target := Vector2(
		randf_range(pass_target_area.position.x, pass_target_area.end.x),
		randf_range(pass_target_area.position.y, pass_target_area.end.y))
	var air_time := ball.seconds_to_ground(ball.height_above_ground, ball.receive_speed(1.0))
	return (target - ball.global_position) / air_time


func _on_animation_finished() -> void:
	if animation == &"receive":
		is_receiving = false
