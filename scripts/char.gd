extends CharacterBody3D

const CHOCOLATE_SCENE := preload("res://scenes/Chocolate.tscn")

@export var move_speed := 6.0
@export var sprint_speed := 9.0
@export var acceleration := 18.0
@export var air_acceleration := 8.0
@export var deceleration := 22.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.003
@export var min_pitch_degrees := -80.0
@export var max_pitch_degrees := 80.0
@export var goose_step_frequency := 9.0
@export var goose_bob_height := 0.045
@export var goose_waddle_degrees := 7.0
@export var goose_pitch_degrees := 3.0
@export var goose_yaw_degrees := 2.0
@export var goose_idle_breath_height := 0.01

@onready var pivot: Node3D = $CameraPivot
@onready var held_item_anchor: Node3D = $HeldItemAnchor
@onready var goose_visual: Node3D = $goose

var inventory: Dictionary[StringName, int] = {}
var held_item: Node3D = null
var _pitch := 0.0
var _jump_was_pressed := false
var _drop_was_pressed := false
var _goose_base_position := Vector3.ZERO
var _goose_base_rotation := Vector3.ZERO
var _goose_anim_time := 0.0
var _goose_animation_player: AnimationPlayer = null
var _goose_idle_animation := StringName()
var _goose_walk_animation := StringName()
var _goose_jump_animation := StringName()


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_pitch = pivot.rotation.x
	_goose_base_position = goose_visual.position
	_goose_base_rotation = goose_visual.rotation
	_setup_goose_animation()
	add_to_group("player")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(
			_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
		pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _jump_pressed() and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := _get_move_input()
	var move_dir := _get_move_direction(input_dir)
	var speed := sprint_speed if _sprint_pressed() else move_speed
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)

	if move_dir != Vector3.ZERO:
		var target_velocity := move_dir * speed
		var accel := acceleration if is_on_floor() else air_acceleration
		horizontal_velocity = horizontal_velocity.move_toward(target_velocity, accel * delta)
	else:
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, deceleration * delta)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	move_and_slide()
	_animate_goose(delta, Vector3(velocity.x, 0.0, velocity.z).length(), not is_on_floor())
	_jump_was_pressed = Input.is_physical_key_pressed(KEY_SPACE)

	var drop_pressed := _drop_pressed()
	if held_item and drop_pressed and not _drop_was_pressed:
		_drop_held_item()
	_drop_was_pressed = drop_pressed


func _get_move_input() -> Vector2:
	if _has_move_actions():
		return Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var input_dir := Vector2.ZERO

	if Input.is_physical_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_dir.y += 1.0

	return input_dir.normalized()


func _get_move_direction(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO

	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0

	return (right * input_dir.x + forward * -input_dir.y).normalized()


func _jump_pressed() -> bool:
	if InputMap.has_action("jump"):
		return Input.is_action_just_pressed("jump")
	var pressed := Input.is_physical_key_pressed(KEY_SPACE)
	return pressed and not _jump_was_pressed


func _sprint_pressed() -> bool:
	if InputMap.has_action("sprint"):
		return Input.is_action_pressed("sprint")
	return Input.is_physical_key_pressed(KEY_SHIFT)


func _has_move_actions() -> bool:
	return (
		InputMap.has_action("move_left")
		and InputMap.has_action("move_right")
		and InputMap.has_action("move_forward")
		and InputMap.has_action("move_back")
	)


func add_item(item_id: StringName, amount: int = 1) -> void:
	inventory[item_id] = inventory.get(item_id, 0) + amount
	if item_id == &"chocolate" and held_item == null:
		_spawn_held_chocolate()


func get_item_count(item_id: StringName) -> int:
	return inventory.get(item_id, 0)


func _animate_goose(delta: float, horizontal_speed: float, airborne: bool) -> void:
	var speed_floor := maxf(sprint_speed, 0.001)
	var move_amount := clampf(horizontal_speed / speed_floor, 0.0, 1.0)
	var ground_move_amount := 0.0 if airborne else move_amount
	var step_rate := lerpf(2.0, goose_step_frequency, maxf(move_amount, 0.15))
	_goose_anim_time += delta * step_rate

	var step := sin(_goose_anim_time)
	var footfall := absf(step)
	var idle_amount := 1.0 - ground_move_amount
	var bob := footfall * goose_bob_height * ground_move_amount
	bob += sin(_goose_anim_time * 0.45) * goose_idle_breath_height * idle_amount

	var pitch := deg_to_rad(goose_pitch_degrees) * footfall * ground_move_amount
	var yaw := deg_to_rad(goose_yaw_degrees) * -step * ground_move_amount
	var roll := deg_to_rad(goose_waddle_degrees) * step * ground_move_amount

	goose_visual.position = _goose_base_position + Vector3(0.0, bob, 0.0)
	goose_visual.rotation = _goose_base_rotation + Vector3(pitch, yaw, roll)

	_update_goose_rig_animation(move_amount, airborne)


func _setup_goose_animation() -> void:
	_goose_animation_player = _find_animation_player(goose_visual)
	if _goose_animation_player == null:
		return

	var animation_list := _goose_animation_player.get_animation_list()
	for animation_name in animation_list:
		var lower_name := String(animation_name).to_lower()
		if lower_name.contains("idle"):
			_goose_idle_animation = animation_name
		elif lower_name.contains("walk"):
			_goose_walk_animation = animation_name
		elif lower_name.contains("jump"):
			_goose_jump_animation = animation_name

	if not animation_list.is_empty():
		if _goose_idle_animation == StringName():
			_goose_idle_animation = animation_list[0]
		if _goose_walk_animation == StringName():
			_goose_walk_animation = _goose_idle_animation


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found

	return null


func _update_goose_rig_animation(move_amount: float, airborne: bool) -> void:
	if _goose_animation_player == null:
		return

	if airborne and _goose_jump_animation != StringName():
		if _goose_animation_player.current_animation != _goose_jump_animation or not _goose_animation_player.is_playing():
			_goose_animation_player.play(_goose_jump_animation)
		_goose_animation_player.speed_scale = 1.0
		return

	if move_amount > 0.05:
		if _goose_walk_animation == StringName():
			return
		if _goose_animation_player.current_animation != _goose_walk_animation or not _goose_animation_player.is_playing():
			_goose_animation_player.play(_goose_walk_animation)
		_goose_animation_player.speed_scale = lerpf(0.65, 1.45, move_amount)
	else:
		if _goose_idle_animation == StringName():
			_goose_animation_player.stop(true)
			return
		if _goose_animation_player.current_animation != _goose_idle_animation or not _goose_animation_player.is_playing():
			_goose_animation_player.play(_goose_idle_animation)
		_goose_animation_player.speed_scale = 1.0


func _spawn_held_chocolate() -> void:
	held_item = CHOCOLATE_SCENE.instantiate()
	held_item.set("top_level", false)
	held_item_anchor.add_child(held_item)

	if held_item.has_method("set_held_mode"):
		held_item.set_held_mode(true)

	held_item.position = Vector3.ZERO
	held_item.rotation_degrees = Vector3.ZERO
	held_item.scale = Vector3.ONE * 0.12


func _drop_held_item() -> void:
	if inventory.get(&"chocolate", 0) <= 0 or held_item == null:
		return

	inventory[&"chocolate"] -= 1
	if inventory[&"chocolate"] <= 0:
		inventory.erase(&"chocolate")

	held_item_anchor.remove_child(held_item)
	get_tree().current_scene.add_child(held_item)
	held_item.global_position = global_position + (-global_transform.basis.z * 1.5) + Vector3.UP * 0.5
	held_item.rotation = Vector3.ZERO
	held_item.scale = Vector3.ONE * 0.12

	if held_item.has_method("begin_drop"):
		held_item.begin_drop()
	elif held_item.has_method("set_held_mode"):
		held_item.set_held_mode(false)

	held_item = null


func _drop_pressed() -> bool:
	if InputMap.has_action("drop"):
		return Input.is_action_pressed("drop")
	return Input.is_physical_key_pressed(KEY_Q)
