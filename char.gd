extends CharacterBody3D

const CHOCOLATE_SCENE := preload("res://Chocolate.tscn")

@export var move_speed := 6.0
@export var sprint_speed := 9.0
@export var acceleration := 18.0
@export var air_acceleration := 8.0
@export var deceleration := 22.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.003
@export var min_pitch_degrees := -80.0
@export var max_pitch_degrees := 80.0

@onready var pivot: Node3D = $CameraPivot
@onready var held_item_anchor: Node3D = $HeldItemAnchor

var inventory: Dictionary[StringName, int] = {}
var held_item: Node3D = null
var _pitch := 0.0
var _jump_was_pressed := false
var _drop_was_pressed := false


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_pitch = pivot.rotation.x
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


func _spawn_held_chocolate() -> void:
	held_item = CHOCOLATE_SCENE.instantiate()
	held_item.set("top_level", false)
	held_item_anchor.add_child(held_item)

	if held_item.has_method("set_held_mode"):
		held_item.set_held_mode(true)

	held_item.position = Vector3(0.0, -0.6, 0.0)
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
