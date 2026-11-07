extends AnimatedSprite2D

const Ball = preload("res://scripts/ball.gd")
const SETTINGS_PATH: String = "user://settings.cfg"
const CONTROL_ACTIONS = ["move_left", "move_right", "move_up", "move_down", "jump", "receive", "spike", "block", "dive"]
const CONTROL_LABELS = ["Move left", "Move right", "Move up", "Move down", "Jump", "Pass / air tip", "Spike / serve", "Jump-block (near net)", "Dive + direction"]
const DEFAULT_KEYS = [
	[KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE, KEY_K, KEY_L, KEY_J, KEY_SHIFT],
	[KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_BACKSPACE]
]
const CHARACTER_NAMES = ["Classic", "Red", "Blue", "Gold", "Purple", "Charcoal", "Orange"]
const CHARACTER_FOLDERS = [
	"res://assets/BVA2", "res://assets/players/p1", "res://assets/players/p2",
	"res://assets/players/p3", "res://assets/players/p4", "res://assets/players/p5",
	"res://assets/players/p6"
]


@export var speed: float = 110.0
@export var input_prefix: String = ""
# Bounds use the player's feet as the position, with room for the sprite at each side.
@export var court_bounds: Rect2 = Rect2(34, 155, 142, 255)
@export var jump_speed: float = 300.0
@export var gravity: float = 550.0
@export var ball: Ball

# Frame numbers start at zero. X is forward reach; Y is height above the feet.
@export_range(0, 30) var spike_contact_frame: int = 1
@export var spike_hand_offset: Vector2 = Vector2(12, 38)

@export_range(0, 30) var block_start_frame: int = 5
@export_range(0, 30) var block_end_frame: int = 8
@export var block_hand_offset: Vector2 = Vector2(8, 42)

@export_range(0, 30) var receive_contact_frame: int = 1
@export var receive_hand_offset: Vector2 = Vector2(12, 18)
@export_range(0.1, 3.0) var receive_charge_time: float = 1.0
@export var pass_speed: float = 120.0

@export var dive_speed: float = 150.0
@export_range(0.1, 1.0) var dive_duration: float = 0.32
@export_range(0.1, 1.0) var dive_recovery: float = 0.22
@export_range(0, 30) var dive_start_frame: int = 3
@export_range(0, 30) var dive_end_frame: int = 10
@export var dive_hand_offset: Vector2 = Vector2(18, 7)

@export var side: Ball.Side = Ball.Side.LEFT

var controls_enabled: bool = true
var height_above_ground: float = 0.0
var vertical_speed: float = 0.0
var is_jumping: bool = false
var has_spiked: bool = false
var spike_hit: bool = false
var is_tipping: bool = false
var has_blocked: bool = false
var block_hit: bool = false
var is_receiving: bool = false
var receive_hit: bool = false
var receive_hold_time: float = 0.0
var jump_queued: bool = false
var is_diving: bool = false
var dive_hit: bool = false
var dive_elapsed: float = 0.0
var dive_direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	frame_changed.connect(_on_frame_changed)
	animation_finished.connect(_on_animation_finished)


func action(control: String) -> StringName:
	return StringName(input_prefix + control)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or is_diving:
		return
	if event.is_action_pressed(action("dive")) and not is_jumping:
		var direction := Input.get_vector(action("move_left"), action("move_right"), action("move_up"), action("move_down"))
		if direction != Vector2.ZERO:
			_start_dive(direction)
	elif event.is_action_pressed(action("jump")) and not is_jumping:
		if not get_parent().can_jump(self):
			return
		if is_receiving and not receive_hit:
			jump_queued = true
		else:
			_start_jump()
	elif is_jumping and not has_spiked and not has_blocked \
			and (event.is_action_pressed(action("spike")) or event.is_action_pressed(action("receive"))):
		if event.is_action_pressed(action("receive")) and ball.serve_pending:
			return
		is_tipping = event.is_action_pressed(action("receive"))
		get_parent().spend_stamina(self, get_parent().tip_cost if is_tipping else get_parent().spike_cost)
		flip_h = side == Ball.Side.RIGHT
		has_spiked = true
		spike_hit = false
		play("spike")
		# Starting at frame zero may not emit frame_changed if the old frame was zero.
		_on_frame_changed()
	elif event.is_action_pressed(action("block")) and not has_blocked and not has_spiked and _can_start_block():
		if not is_jumping and not _start_jump():
			return
		get_parent().spend_stamina(self, get_parent().block_cost)
		has_blocked = true
		block_hit = false
		flip_h = side == Ball.Side.RIGHT
		play("block")
		_on_frame_changed()
	elif event.is_action_pressed(action("receive")) and not is_jumping and not is_receiving:
		is_receiving = true
		receive_hit = false
		receive_hold_time = 0.0
		play("receive")
		_on_frame_changed()


func _can_start_block() -> bool:
	if not is_instance_valid(ball):
		return false
	var facing := -1.0 if side == Ball.Side.RIGHT else 1.0
	var hand_position := global_position + Vector2(block_hand_offset.x * facing, 0)
	return (global_position.x - ball.net_x) * facing <= 0.0 \
		and absf(hand_position.x - ball.net_x) <= ball.block_net_distance \
		and hand_position.y >= ball.net_span.x and hand_position.y <= ball.net_span.y


func _on_frame_changed() -> void:
	_check_contact()


func _check_contact() -> void:
	if not controls_enabled or not is_instance_valid(ball):
		return
	if is_diving:
		if dive_hit or animation != &"slide" or frame < dive_start_frame or frame > dive_end_frame:
			return
		var facing := -1.0 if flip_h else 1.0
		var hand_position := global_position + Vector2(dive_hand_offset.x * facing, 0)
		var pass_velocity: Vector2 = get_parent().pass_to_partner(self, 0.35)
		dive_hit = ball.try_receive(hand_position, dive_hand_offset.y, side, 0.35, pass_velocity, self)
		return
	if animation == &"receive" and is_receiving and controls_enabled:
		if receive_hit or frame < receive_contact_frame:
			return
		var facing := -1.0 if flip_h else 1.0
		var hand_position := global_position + Vector2(receive_hand_offset.x * facing, 0)
		var charge := clampf(receive_hold_time / receive_charge_time, 0.0, 1.0)
		var pass_velocity: Vector2 = get_parent().pass_to_partner(self, charge)
		var next_touch: int = ball.team_touches + 1 if ball.contact_team == side else 1
		# Early contacts pass/set to our partner; directional returns are third-touch only.
		if next_touch == 3 and Input.get_axis(action("move_left"), action("move_right")) != 0.0:
			pass_velocity = Vector2(Input.get_axis(action("move_left"), action("move_right")) * pass_speed, 0)
		receive_hit = ball.try_receive(hand_position, receive_hand_offset.y, side, charge,
			pass_velocity, self)
		if receive_hit:
			if not jump_queued or not _start_jump():
				play("receive")
		return
	if animation == &"block" and is_jumping and has_blocked and is_playing():
		if block_hit or frame < block_start_frame or frame > block_end_frame:
			return
		var facing := -1.0 if side == Ball.Side.RIGHT else 1.0
		var hand_position := global_position + Vector2(block_hand_offset.x * facing, 0)
		block_hit = ball.try_block(hand_position, height_above_ground + block_hand_offset.y, side, self)
		return
	if animation != &"spike" or not is_jumping or not has_spiked or not is_playing():
		return
	if spike_hit or frame < spike_contact_frame:
		return

	var facing := -1.0 if flip_h else 1.0
	var hand_ground_position := global_position + Vector2(spike_hand_offset.x * facing, 0)
	var hand_height := height_above_ground + spike_hand_offset.y
	spike_hit = ball.try_spike(hand_ground_position, hand_height, facing, side, self,
		get_parent().stamina_factor(self), is_tipping)


func _start_jump() -> bool:
	jump_queued = false
	if not get_parent().can_jump(self):
		return false
	get_parent().spend_stamina(self, get_parent().jump_cost)
	is_tipping = false
	is_receiving = false
	is_jumping = true
	vertical_speed = jump_speed
	play("jump")
	return true


func _start_dive(direction: Vector2) -> void:
	get_parent().spend_stamina(self, get_parent().dive_cost)
	is_receiving = false
	jump_queued = false
	is_diving = true
	dive_hit = false
	dive_elapsed = 0.0
	dive_direction = direction.normalized()
	if dive_direction.x != 0.0:
		flip_h = dive_direction.x < 0.0
	play("slide")
	_check_contact()


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
	is_tipping = false
	has_blocked = false
	block_hit = false
	is_receiving = false
	receive_hit = false
	receive_hold_time = 0.0
	jump_queued = false
	is_diving = false
	dive_hit = false
	dive_elapsed = 0.0
	dive_direction = Vector2.ZERO
	flip_h = side == Ball.Side.RIGHT
	stop()
	play("idle")
	offset.y = -sprite_frames.get_frame_texture("idle", 0).get_height() / 2.0


func _physics_process(delta: float) -> void:
	var previous := position
	var movement_factor: float = get_parent().stamina_factor(self)
	if is_diving:
		var move_time := minf(delta, maxf(dive_duration - dive_elapsed, 0.0))
		dive_elapsed += delta
		if controls_enabled:
			position += dive_direction * dive_speed * movement_factor * move_time
			position = position.clamp(court_bounds.position, court_bounds.end)
		if controls_enabled and dive_elapsed < dive_duration + dive_recovery:
			_check_contact()
			_update_height()
			get_parent().update_stamina(self, delta, not position.is_equal_approx(previous), true)
			return
		is_diving = false
		play("idle")
		_update_height()
		get_parent().update_stamina(self, delta, false, true)
		return
	if controls_enabled and is_receiving and not receive_hit and Input.is_action_pressed(action("receive")):
		receive_hold_time = minf(receive_hold_time + delta, receive_charge_time)

	var direction := Input.get_vector(action("move_left"), action("move_right"), action("move_up"), action("move_down"))
	# While receiving, the arrows only aim the pass instead of walking.
	if not controls_enabled or is_receiving:
		direction = Vector2.ZERO
	position += direction * speed * movement_factor * delta
	position = position.clamp(court_bounds.position, court_bounds.end)

	if direction.x != 0.0 and not has_spiked and not has_blocked and not is_receiving:
		flip_h = direction.x < 0.0

	if is_jumping:
		height_above_ground += vertical_speed * delta - 0.5 * gravity * delta * delta
		vertical_speed -= gravity * delta
		if height_above_ground <= 0.0:
			height_above_ground = 0.0
			vertical_speed = 0.0
			is_jumping = false
			has_spiked = false
			is_tipping = false
			has_blocked = false

	if not is_jumping and not is_receiving:
		play("idle" if direction == Vector2.ZERO else "run")

	# Check throughout the active pose, but allow only one successful hit per action.
	_check_contact()
	if is_receiving and not receive_hit and frame >= receive_contact_frame:
		if controls_enabled and Input.is_action_pressed(action("receive")):
			pause()
		elif not is_playing():
			play("receive")

	_update_height()
	get_parent().update_stamina(self, delta, not position.is_equal_approx(previous), is_jumping or is_receiving)


func _update_height() -> void:
	# Move only the drawing upward; position and the child shadow stay on the court.
	var frame_height := sprite_frames.get_frame_texture(animation, frame).get_height()
	offset.y = -frame_height / 2.0 - height_above_ground


static func frames_for_character(template: SpriteFrames, character: int) -> SpriteFrames:
	if character <= 0 or character >= CHARACTER_FOLDERS.size():
		return template
	# Copy the editable frames, changing only their sheets, not timing or regions.
	var frames := template.duplicate(true) as SpriteFrames
	for animation_name in frames.get_animation_names():
		for index in range(frames.get_frame_count(animation_name)):
			var texture = frames.get_frame_texture(animation_name, index)
			if texture is AtlasTexture:
				var path: String = CHARACTER_FOLDERS[character].path_join(texture.atlas.resource_path.get_file())
				if ResourceLoader.exists(path):
					texture.atlas = load(path)
	return frames


static func load_bindings(path: String = SETTINGS_PATH) -> Array:
	var settings := ConfigFile.new()
	settings.load(path)
	var bindings: Array = DEFAULT_KEYS.duplicate(true)
	var used: Array = []
	for slot in range(2):
		for index in range(CONTROL_ACTIONS.size()):
			var key: Variant = settings.get_value("controls", "p%d_%s" % [slot + 1, CONTROL_ACTIONS[index]], DEFAULT_KEYS[slot][index])
			if not key is int or key <= 0 or key == KEY_ESCAPE or OS.get_keycode_string(key).is_empty() or key in used:
				key = DEFAULT_KEYS[slot][index]
				if key in used:
					for fallback in DEFAULT_KEYS[0] + DEFAULT_KEYS[1]:
						if not fallback in used:
							key = fallback
							break
			bindings[slot][index] = key
			used.append(key)
	return bindings


static func apply_bindings(bindings: Array) -> void:
	for slot in range(2):
		var prefix := "" if slot == 0 else "p2_"
		for index in range(CONTROL_ACTIONS.size()):
			_set_key(prefix + CONTROL_ACTIONS[index], bindings[slot][index])
		# Serve shares the spike key, including for older scene/input callers.
		_set_key(prefix + "serve", bindings[slot][CONTROL_ACTIONS.find("spike")])


static func _set_key(action_name: String, key: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	Input.action_release(action_name)
	InputMap.action_erase_events(action_name)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action_name, event)


static func save_bindings(bindings: Array, path: String = SETTINGS_PATH) -> Error:
	var settings := ConfigFile.new()
	settings.load(path)
	for slot in range(2):
		for index in range(CONTROL_ACTIONS.size()):
			settings.set_value("controls", "p%d_%s" % [slot + 1, CONTROL_ACTIONS[index]], bindings[slot][index])
	return settings.save(path)


static func key_label(action_name: StringName) -> String:
	var events := InputMap.action_get_events(action_name)
	if events.is_empty():
		return "?"
	return OS.get_keycode_string(events[0].physical_keycode)
