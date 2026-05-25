extends CharacterBody3D

const CHOCOLATE_SCENE := preload("res://scenes/Chocolate.tscn")
const BREAD_SCENE := preload("res://scenes/bread1.tscn")
const CHOCBREAD_SCENE := preload("res://scenes/chocbread.tscn")

@export var move_speed := 10.0
@export var sprint_speed := 15.0
@export var acceleration := 20.0
@export var air_acceleration := 12.0
@export var deceleration := 22.0
@export var jump_velocity := 7
@export var mouse_sensitivity := 0.003
@export var min_pitch_degrees := -80.0
@export var max_pitch_degrees := 80.0
@export var goose_step_frequency := 9.0
@export var goose_bob_height := 0.045
@export var goose_waddle_degrees := 7.0
@export var goose_pitch_degrees := 3.0
@export var goose_yaw_degrees := 2.0
@export var goose_idle_breath_height := 0.01
@export var held_item_world_scale := 0.12
@export var bread_weapon_world_scale := 0.32
@export var weapon_swing_duration := 0.28
@export var weapon_hit_distance := 3.2

@onready var pivot: Node3D = $CameraPivot
@onready var goose_visual: Node3D = $goose

var inventory: Dictionary[StringName, int] = {}
var held_item: Node3D = null
var held_item_id: StringName = StringName()
var held_item_anchor: Node3D = null
var _pitch := 0.0
var _jump_was_pressed := false
var _drop_was_pressed := false
var _attack_was_pressed := false
var _weapon_swing_time := 0.0
var _weapon_hit_done := false
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
	held_item_anchor = _get_or_create_held_item_anchor()
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

	var attack_pressed := _attack_pressed()
	if attack_pressed and not _attack_was_pressed and _is_weapon_item(held_item_id):
		_start_weapon_swing()
	_attack_was_pressed = attack_pressed
	_update_weapon_swing(delta)


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
	if held_item == null and _get_held_item_scene(item_id) != null:
		_spawn_held_item(item_id)


func get_item_count(item_id: StringName) -> int:
	return inventory.get(item_id, 0)


func _get_or_create_held_item_anchor() -> Node3D:
	var anchor := goose_visual.get_node_or_null("HeldItemAnchor") as Node3D
	if anchor != null:
		return anchor

	anchor = get_node_or_null("HeldItemAnchor") as Node3D
	if anchor != null:
		var saved_global_transform := anchor.global_transform
		remove_child(anchor)
		goose_visual.add_child(anchor)
		anchor.global_transform = saved_global_transform
		return anchor

	anchor = Node3D.new()
	anchor.name = "HeldItemAnchor"
	goose_visual.add_child(anchor)
	anchor.position = Vector3(0.0868386, 3.48, -1.55)
	return anchor


func _get_held_item_local_scale() -> float:
	var anchor_scale := held_item_anchor.global_transform.basis.get_scale()
	var parent_scale := (anchor_scale.x + anchor_scale.y + anchor_scale.z) / 3.0
	var target_world_scale := _get_held_item_world_scale(held_item_id)
	if is_zero_approx(parent_scale):
		return target_world_scale
	return target_world_scale / parent_scale


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
	var swing_progress := _get_weapon_swing_progress()
	var swing_arc := sin(swing_progress * PI)
	yaw += deg_to_rad(swing_arc * 16.0)
	roll += deg_to_rad(-swing_arc * 8.0)

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


func _spawn_held_item(item_id: StringName) -> void:
	if held_item_anchor == null:
		held_item_anchor = _get_or_create_held_item_anchor()

	var item_scene := _get_held_item_scene(item_id)
	if item_scene == null:
		return

	held_item_id = item_id
	held_item = item_scene.instantiate()
	held_item.set("top_level", false)
	held_item_anchor.add_child(held_item)

	if held_item.has_method("set_held_mode"):
		held_item.set_held_mode(true)

	held_item.position = Vector3.ZERO
	held_item.rotation_degrees = _get_held_item_rotation(item_id)
	held_item.scale = Vector3.ONE * _get_held_item_local_scale()
	_configure_held_item_visual(item_id)


func _drop_held_item() -> void:
	if held_item_id == StringName() or inventory.get(held_item_id, 0) <= 0 or held_item == null:
		return

	var dropped_item_id := held_item_id
	inventory[dropped_item_id] -= 1
	if inventory[dropped_item_id] <= 0:
		inventory.erase(dropped_item_id)

	held_item_anchor.remove_child(held_item)
	get_tree().current_scene.add_child(held_item)
	held_item.global_position = global_position + (-global_transform.basis.z * 1.5) + Vector3.UP * 0.5
	held_item.rotation = Vector3.ZERO
	held_item.scale = Vector3.ONE * _get_held_item_world_scale(dropped_item_id)

	if held_item.has_method("begin_drop"):
		held_item.begin_drop()
	elif held_item.has_method("set_held_mode"):
		held_item.set_held_mode(false)

	held_item = null
	held_item_id = StringName()
	_weapon_swing_time = 0.0


func _drop_pressed() -> bool:
	if InputMap.has_action("drop"):
		return Input.is_action_pressed("drop")
	return Input.is_physical_key_pressed(KEY_Q)


func _attack_pressed() -> bool:
	if InputMap.has_action("attack"):
		return Input.is_action_pressed("attack")
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _start_weapon_swing() -> void:
	_weapon_swing_time = weapon_swing_duration
	_weapon_hit_done = false


func _update_weapon_swing(delta: float) -> void:
	if held_item == null or not _is_weapon_item(held_item_id):
		return

	if _weapon_swing_time <= 0.0:
		held_item.rotation_degrees = _get_held_item_rotation(held_item_id)
		return

	_weapon_swing_time = maxf(_weapon_swing_time - delta, 0.0)
	var progress := 1.0 - (_weapon_swing_time / weapon_swing_duration)
	var swing_yaw := sin(progress * PI) * 90.0
	held_item.rotation_degrees = _get_held_item_rotation(held_item_id) + Vector3(0.0, swing_yaw, 0.0)
	_check_weapon_hit(progress)


func _get_weapon_swing_progress() -> float:
	if _weapon_swing_time <= 0.0 or weapon_swing_duration <= 0.0:
		return 0.0
	return 1.0 - (_weapon_swing_time / weapon_swing_duration)


func _check_weapon_hit(progress: float) -> void:
	if _weapon_hit_done or progress < 0.22 or progress > 0.78:
		return

	var from := held_item_anchor.global_position
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var arc_dir := (forward + right * sin(progress * PI) * 0.75).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + arc_dir * weapon_hit_distance)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	_weapon_hit_done = true
	var bonk_target := _find_bonk_target(hit.get("collider"))
	if bonk_target != null:
		bonk_target.bonk(global_position)
	_spawn_particle_burst(hit["position"], Color(1.0, 0.68, 0.28, 1.0))


func _find_bonk_target(node: Object) -> Node:
	var current := node as Node
	while current != null:
		if current.has_method("bonk"):
			return current
		current = current.get_parent()
	return null


func _spawn_particle_burst(burst_position: Vector3, color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 24
	particles.lifetime = 0.28
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.12
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 1.5
	particles.initial_velocity_max = 4.0
	particles.gravity = Vector3(0.0, -7.0, 0.0)
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.12
	particles.color = color
	get_tree().current_scene.add_child(particles)
	particles.global_position = burst_position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _get_held_item_scene(item_id: StringName) -> PackedScene:
	match item_id:
		&"chocolate", &"combined_chocolate":
			return CHOCOLATE_SCENE
		&"bread":
			return BREAD_SCENE
		&"chocbread":
			return CHOCBREAD_SCENE
		_:
			return null


func _get_held_item_world_scale(item_id: StringName) -> float:
	if _is_weapon_item(item_id):
		return bread_weapon_world_scale
	return held_item_world_scale


func _get_held_item_rotation(item_id: StringName) -> Vector3:
	if _is_weapon_item(item_id):
		return Vector3(0.0, 0.0, 0.0)
	return Vector3.ZERO


func _configure_held_item_visual(item_id: StringName) -> void:
	if held_item == null:
		return

	if item_id == &"bread":
		var bread_visual := held_item.get_node_or_null("Sketchfab_model") as Node3D
		if bread_visual != null:
			bread_visual.position = Vector3(2.02, 0.0, 0.0)
		return

	if item_id == &"chocbread":
		var bread_visual := held_item.get_node_or_null("Sketchfab_Scene") as Node3D
		if bread_visual != null:
			bread_visual.transform = Transform3D(
				Vector3(0.07, 0.0, 0.0),
				Vector3(0.0, -3.059797e-09, 0.07),
				Vector3(0.0, -0.07, -3.059797e-09),
				Vector3(2.02, 0.0, 0.0)
			)
		var chocolate_visual := held_item.get_node_or_null("Cube") as Node3D
		if chocolate_visual != null:
			chocolate_visual.transform = Transform3D(
				Vector3(-7.3870035e-09, -0.098994955, 0.09899494),
				Vector3(0.14, -6.119594e-09, 4.327206e-09),
				Vector3(1.2674091e-09, 0.09899494, 0.098994955),
				Vector3(3.25, -0.30, 0.25)
			)


func _is_weapon_item(item_id: StringName) -> bool:
	return item_id == &"bread" or item_id == &"chocbread"
