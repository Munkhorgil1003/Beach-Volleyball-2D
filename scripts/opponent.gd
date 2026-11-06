extends AnimatedSprite2D

# Shared by the teammate and both opponents. Match assigns one receiver per team.
const Ball = preload("res://scripts/ball.gd")
enum Action { CHASE, RECEIVE, JUMP, SPIKE, BLOCK }

@export var side: Ball.Side = Ball.Side.RIGHT
@export var speed: float = 110.0
@export var court_bounds: Rect2 = Rect2(224, 155, 142, 255)
@export var ball: Ball
@export_range(0, 30) var receive_contact_frame: int = 1
@export var receive_hand_offset: Vector2 = Vector2(12, 18)
@export var jump_speed: float = 300.0
@export var gravity: float = 550.0
@export_range(0, 30) var spike_contact_frame: int = 1
@export var spike_hand_offset: Vector2 = Vector2(12, 38)
@export_range(0.0, 1.0) var soft_return_chance: float = 0.25
@export_range(0.0, 1.0) var set_charge: float = 0.65
@export_range(0.0, 1.0) var reaction_delay: float = 0.0
@export_range(0.0, 1.0) var block_reaction_delay: float = 0.08
@export var block_jump_speed: float = 260.0
@export var block_hand_offset: Vector2 = Vector2(8, 42)
@export_range(0, 30) var block_start_frame: int = 5
@export_range(0, 30) var block_end_frame: int = 8

@onready var normal_speed: float = speed
@onready var normal_soft_return_chance: float = soft_return_chance
@onready var normal_reaction_delay: float = reaction_delay
@onready var normal_block_reaction_delay: float = block_reaction_delay

var controls_enabled: bool = false
var home_position: Vector2
var action: Action = Action.CHASE
var height_above_ground: float = 0.0
var vertical_speed: float = 0.0
var spike_hit: bool = false
var block_hit: bool = false
var soft_return: bool = false
var receive_velocity: Vector2 = Vector2.ZERO
var attack_position: Vector2
var reaction_time_left: float = 0.0
var observed_hitter: Node = null
var observed_touches: int = -1


func _ready() -> void:
	home_position = position
	frame_changed.connect(_check_contact)
	animation_finished.connect(_on_animation_finished)


func reset_for_serve(ground_position: Vector2) -> void:
	position = ground_position
	action = Action.CHASE
	height_above_ground = 0.0
	vertical_speed = 0.0
	spike_hit = false
	block_hit = false
	soft_return = false
	receive_velocity = Vector2.ZERO
	reaction_time_left = 0.0
	observed_hitter = null
	observed_touches = -1
	flip_h = side == Ball.Side.RIGHT
	stop()
	play("idle")
	_update_height()


func apply_difficulty(level: int) -> void:
	speed = normal_speed
	soft_return_chance = normal_soft_return_chance
	reaction_delay = normal_reaction_delay
	block_reaction_delay = normal_block_reaction_delay
	if level == 0:
		speed *= 0.75
		soft_return_chance = 0.65
		reaction_delay = maxf(normal_reaction_delay, 0.2)
		block_reaction_delay = maxf(normal_block_reaction_delay, 0.22)
	elif level == 2:
		speed *= 1.25
		soft_return_chance = 0.1
		reaction_delay = normal_reaction_delay * 0.5
		block_reaction_delay = normal_block_reaction_delay * 0.25


func _physics_process(delta: float) -> void:
	if height_above_ground > 0.0 or vertical_speed > 0.0:
		height_above_ground += vertical_speed * delta - 0.5 * gravity * delta * delta
		vertical_speed -= gravity * delta
		if height_above_ground <= 0.0:
			height_above_ground = 0.0
			vertical_speed = 0.0
			action = Action.CHASE
	if not controls_enabled or not is_instance_valid(ball) or not ball.rally_active:
		action = Action.CHASE
		if height_above_ground == 0.0:
			play("idle")
		_update_height()
		get_parent().update_stamina(self, delta, false, height_above_ground > 0.0)
		return

	var match_node = get_parent()
	var blocker = match_node.blocker_for(side)
	var receiver = match_node.receiver_for(side)
	if observed_hitter != ball.last_hitter or observed_touches != ball.team_touches:
		observed_hitter = ball.last_hitter
		observed_touches = ball.team_touches
		reaction_time_left = reaction_delay
		if blocker == self:
			reaction_time_left = maxf(reaction_time_left, block_reaction_delay)
	reaction_time_left = maxf(reaction_time_left - delta, 0.0)
	if reaction_time_left > 0.0:
		receiver = null
	var third_touch: bool = ball.contact_team == side and ball.team_touches == 2
	var use_soft_return: bool = soft_return or (action == Action.CHASE and not match_node.can_jump(self))
	var direction := 1.0 if side == Ball.Side.LEFT else -1.0
	var target := home_position
	if blocker == self:
		target = match_node.block_target_for(side) if reaction_time_left <= 0.0 else position
	elif blocker != null:
		# The other defender stays deep until the actual attack is coming to our side.
		var landing_here: bool = (ball.predict_landing().x - ball.net_x) * direction < 0.0
		if receiver == self and landing_here:
			target = ball.predict_at_height(13.0) - Vector2(direction * receive_hand_offset.x, 0)
		else:
			target = Vector2(ball.net_x - direction * 110.0, match_node.block_target_for(side).y)
	elif receiver == self:
		target = ball.predict_at_height(90.0 if third_touch and not use_soft_return else 13.0)
		target.x -= direction * receive_hand_offset.x
	elif ball.contact_team == side and ball.last_hitter == self and ball.team_touches == 1:
		target = Vector2(ball.net_x - direction * 52.0, position.y)
	if action == Action.RECEIVE or action == Action.SPIKE or action == Action.BLOCK:
		target = position
	var previous := position
	position = position.move_toward(target.clamp(court_bounds.position, court_bounds.end),
		speed * match_node.stamina_factor(self) * delta)

	if action == Action.CHASE:
		play("idle" if position.is_equal_approx(previous) else "run")
		if blocker == self and match_node.can_jump(self) and reaction_time_left <= 0.0 and _can_start_block():
			action = Action.BLOCK
			block_hit = false
			vertical_speed = block_jump_speed
			flip_h = side == Ball.Side.RIGHT
			match_node.spend_stamina(self, match_node.jump_cost + match_node.block_cost)
			play("block")
		elif receiver == self and not ball.serve_pending:
			if third_touch and not use_soft_return and match_node.can_jump(self) \
					and ball.vertical_speed <= 100 and ball.height_above_ground > 38 \
					and ball.global_position.distance_to(_hand_position()) <= ball.spike_reach:
				action = Action.JUMP
				match_node.spend_stamina(self, match_node.jump_cost)
				vertical_speed = jump_speed
				play("jump")
			elif ball.vertical_speed < 0 and ball.height_above_ground < 40 \
					and ball.global_position.distance_to(_hand_position()) <= ball.receive_reach:
				receive_velocity = match_node.pass_to_partner(self, set_charge)
				action = Action.RECEIVE
				play("receive")
	elif action == Action.JUMP and receiver == self and height_above_ground >= 35 \
			and ball.vertical_speed < 0 and ball.global_position.distance_to(_hand_position()) <= ball.spike_reach \
			and absf(ball.height_above_ground + Ball.RADIUS - height_above_ground - spike_hand_offset.y) <= ball.spike_height_reach * 0.75:
		action = Action.SPIKE
		match_node.spend_stamina(self, match_node.spike_cost)
		spike_hit = false
		play("spike")
	_check_contact()
	if action == Action.BLOCK and frame >= block_end_frame:
		# Hold the raised-hands pose until landing; do not repeat the jump or contact.
		set_frame_and_progress(block_end_frame, 0.0)
		pause()
	if action == Action.RECEIVE and frame >= receive_contact_frame:
		if receiver == self:
			pause()
		else:
			action = Action.CHASE
	_update_height()
	# Waiting ready at the net is still defending, rather than resting between attacks.
	match_node.update_stamina(self, delta, not position.is_equal_approx(previous), action != Action.CHASE or blocker == self)


func _check_contact() -> void:
	if not controls_enabled or not is_instance_valid(ball) or not ball.rally_active or reaction_time_left > 0.0:
		return
	if action == Action.BLOCK:
		if not block_hit and animation == &"block" and frame >= block_start_frame and frame <= block_end_frame \
				and height_above_ground > 0.0 and not ball.is_service and not ball.serve_pending:
			var direction := 1.0 if side == Ball.Side.LEFT else -1.0
			block_hit = ball.try_block(global_position + Vector2(direction * block_hand_offset.x, 0),
				height_above_ground + block_hand_offset.y, side, self)
		return
	if get_parent().receiver_for(side) != self:
		return
	if action == Action.RECEIVE and animation == &"receive" and frame >= receive_contact_frame:
		if ball.try_receive(_hand_position(), receive_hand_offset.y, side, set_charge, receive_velocity, self):
			action = Action.CHASE
			soft_return = randf() < soft_return_chance
	elif action == Action.SPIKE and animation == &"spike" and is_playing() and not spike_hit \
			and frame >= spike_contact_frame and height_above_ground > 0:
		spike_hit = ball.try_spike(_hand_position(), height_above_ground + spike_hand_offset.y,
			1.0 if side == Ball.Side.LEFT else -1.0, side, self, get_parent().stamina_factor(self))


func _can_start_block() -> bool:
	if ball.is_service or ball.serve_pending or not get_parent().can_jump(self):
		return false
	var direction := 1.0 if side == Ball.Side.LEFT else -1.0
	if (ball.position.x - ball.net_x) * direction < -Ball.RADIUS \
			or absf(global_position.x + direction * block_hand_offset.x - ball.net_x) > ball.block_net_distance \
			or absf(position.y - get_parent().block_target_for(side).y) > ball.block_reach * 0.75:
		return false
	if ball.velocity.x * direction < 0.0:
		var time_to_net: float = (ball.net_x - ball.position.x) / ball.velocity.x
		var height_at_net: float = ball.height_above_ground + ball.vertical_speed * time_to_net \
			- 0.5 * ball.gravity * time_to_net * time_to_net
		var max_hand_height := block_jump_speed * block_jump_speed / (2.0 * gravity) + block_hand_offset.y
		if time_to_net >= -0.05 and time_to_net <= 0.32 \
				and height_at_net >= ball.net_height and height_at_net <= max_hand_height + ball.block_height_reach:
			return true
	# Read the opponent's jump to get hands up before a fast spike reaches the tape.
	for attacker in get_parent().teams[1 - side]:
		if attacker.height_above_ground > 12.0 and absf(attacker.position.x - ball.net_x) <= 75.0 \
				and attacker.position.distance_to(ball.position) <= ball.spike_reach + 12.0 \
				and ball.height_above_ground >= ball.net_height \
				and ball.height_above_ground <= attacker.height_above_ground + attacker.spike_hand_offset.y + ball.spike_height_reach + 55.0:
			return true
	return false


func _hand_position() -> Vector2:
	return global_position + Vector2(receive_hand_offset.x * (1 if side == Ball.Side.LEFT else -1), 0)


func _update_height() -> void:
	var frame_height := sprite_frames.get_frame_texture(animation, frame).get_height()
	offset.y = -frame_height / 2.0 - height_above_ground


func _on_animation_finished() -> void:
	if animation == &"receive" and action == Action.RECEIVE:
		action = Action.CHASE
