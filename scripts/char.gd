extends CharacterBody3D

const CHOCOLATE_SCENE := preload("res://scenes/Chocolate.tscn")
const BREAD_SCENE := preload("res://scenes/bread1.tscn")
const CHOCBREAD_SCENE := preload("res://scenes/chocbread.tscn")
const MILK_SCENE := preload("res://rawmodels/Standard Milk.glb")
const PICKUP_ITEM_SCRIPT := preload("res://scripts/spin.gd")
const TITLE_SCENE := "res://scenes/control.tscn"

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
@export var milk_explosion_count := 10
@export var milk_explosion_radius := 7.0
@export var milk_explosion_force := 22.0
@export var milk_diarrhea_duration := 4.0
@export var milk_diarrhea_force := 34.0
@export var milk_diarrhea_splat_interval := 0.08
@export var shit_puddle_acceleration_multiplier := 0.2
@export var shit_puddle_deceleration_multiplier := 0.04
@export var cola_rocket_up_speed := 42.0
@export var cola_rocket_forward_speed := 26.0

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
var _last_pickup_frame := -1
var _goose_base_position := Vector3.ZERO
var _goose_base_rotation := Vector3.ZERO
var _goose_anim_time := 0.0
var _goose_animation_player: AnimationPlayer = null
var _goose_idle_animation := StringName()
var _goose_walk_animation := StringName()
var _goose_jump_animation := StringName()
var _milk_exploded := false
var _milk_diarrhea_time := 0.0
var _milk_diarrhea_splat_time := 0.0
var _cola_rocket_active := false
var _cola_rocket_light: OmniLight3D = null
var _cola_flame_outer: MeshInstance3D = null
var _cola_flame_inner: MeshInstance3D = null


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
	if _cola_rocket_active:
		_update_cola_rocket(delta)
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if _jump_pressed() and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := _get_move_input()
	var move_dir := _get_move_direction(input_dir)
	var speed := sprint_speed if _sprint_pressed() else move_speed
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var on_slippery_puddle := is_on_floor() and _is_on_slippery_puddle()

	if move_dir != Vector3.ZERO:
		var target_velocity := move_dir * speed
		var accel := acceleration if is_on_floor() else air_acceleration
		if on_slippery_puddle:
			accel *= shit_puddle_acceleration_multiplier
		horizontal_velocity = horizontal_velocity.move_toward(target_velocity, accel * delta)
	else:
		var current_deceleration := deceleration
		if on_slippery_puddle:
			current_deceleration *= shit_puddle_deceleration_multiplier
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, current_deceleration * delta)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	_update_milk_diarrhea(delta)
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


func add_item(item_id: StringName, amount: int = 1) -> bool:
	var pickup_frame := Engine.get_process_frames()
	if _last_pickup_frame == pickup_frame:
		return false

	_last_pickup_frame = pickup_frame
	inventory[item_id] = inventory.get(item_id, 0) + amount
	if item_id == &"cola":
		_start_cola_rocket()
		return true

	if item_id == &"milk" and inventory[item_id] >= milk_explosion_count:
		_start_milk_diarrhea()
		_explode_from_milk_overload()
		return true
	elif item_id == &"milk":
		_start_milk_diarrhea()

	if held_item == null and _get_held_item_scene(item_id) != null:
		_spawn_held_item(item_id)

	return true


func get_item_count(item_id: StringName) -> int:
	return inventory.get(item_id, 0)


func _start_milk_diarrhea() -> void:
	_milk_diarrhea_time = milk_diarrhea_duration
	_milk_diarrhea_splat_time = 0.0
	_spawn_milk_diarrhea_blast()


func _update_milk_diarrhea(delta: float) -> void:
	if _milk_diarrhea_time <= 0.0:
		return

	_milk_diarrhea_time = maxf(_milk_diarrhea_time - delta, 0.0)
	_apply_milk_diarrhea_firehose_force(delta)
	_spawn_milk_diarrhea_spray()
	_milk_diarrhea_splat_time -= delta
	if _milk_diarrhea_splat_time <= 0.0:
		_milk_diarrhea_splat_time = milk_diarrhea_splat_interval
		_spawn_milk_diarrhea_splat()


func _apply_milk_diarrhea_firehose_force(delta: float) -> void:
	var forward := -_get_cola_back_direction()
	var sideways := global_transform.basis.x * randf_range(-0.85, 0.85)
	var hose_direction := (forward + sideways).normalized()
	var horizontal_force := hose_direction * milk_diarrhea_force * delta
	velocity.x += horizontal_force.x
	velocity.z += horizontal_force.z


func _spawn_milk_diarrhea_blast() -> void:
	for i in range(4):
		_spawn_milk_diarrhea_spray(2.0)


func _spawn_milk_diarrhea_spray(multiplier: float = 1.0) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = int(42 * multiplier)
	particles.lifetime = 0.85
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.24 * multiplier
	particles.direction = (_get_cola_back_direction() + Vector3.DOWN * 0.45).normalized()
	particles.spread = 95.0
	particles.initial_velocity_min = 5.0 * multiplier
	particles.initial_velocity_max = 13.0 * multiplier
	particles.gravity = Vector3(0.0, -18.0, 0.0)
	particles.scale_amount_min = 0.07 * multiplier
	particles.scale_amount_max = 0.2 * multiplier
	particles.color = Color(0.28, 0.13, 0.035, 1.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	particles.mesh = mesh
	get_tree().current_scene.add_child(particles)
	particles.global_position = _get_milk_diarrhea_position()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _spawn_milk_diarrhea_splat() -> void:
	var origin := _get_milk_diarrhea_position()
	var back := _get_cola_back_direction()
	var right := global_transform.basis.x
	origin += back * randf_range(0.4, 4.0)
	origin += right * randf_range(-2.6, 2.6)
	origin += Vector3.UP * 1.2

	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 10.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var splat := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var splat_radius := randf_range(0.18, 0.55)
	mesh.top_radius = splat_radius
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.018
	mesh.radial_segments = 14
	splat.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(randf_range(0.18, 0.32), randf_range(0.08, 0.15), randf_range(0.025, 0.055), 1.0)
	material.roughness = 0.9
	splat.material_override = material
	get_tree().current_scene.add_child(splat)
	splat.global_position = hit["position"] + Vector3.UP * 0.012
	splat.rotation.y = randf_range(0.0, TAU)
	splat.scale.x = randf_range(0.7, 1.8)
	splat.scale.z = randf_range(0.45, 1.25)
	splat.add_to_group("slippery_puddle")
	splat.set_meta("slippery_radius", splat_radius * maxf(splat.scale.x, splat.scale.z) + 0.45)


func _is_on_slippery_puddle() -> bool:
	for puddle in get_tree().get_nodes_in_group("slippery_puddle"):
		if not is_instance_valid(puddle) or not puddle is Node3D:
			continue

		var puddle_node := puddle as Node3D
		if absf(global_position.y - puddle_node.global_position.y) > 1.2:
			continue

		var radius := 0.8
		if puddle_node.has_meta("slippery_radius"):
			radius = float(puddle_node.get_meta("slippery_radius"))
		var player_position := Vector2(global_position.x, global_position.z)
		var puddle_position := Vector2(puddle_node.global_position.x, puddle_node.global_position.z)
		if player_position.distance_to(puddle_position) <= radius:
			return true

	return false


func _get_milk_diarrhea_position() -> Vector3:
	return global_position + _get_cola_back_direction() * 0.85 + Vector3.UP * 0.38


func _start_cola_rocket() -> void:
	inventory.erase(&"cola")
	_cola_rocket_active = true
	_weapon_swing_time = 0.0
	_start_cola_rocket_light()
	_spawn_cola_rocket_burst()


func _update_cola_rocket(delta: float) -> void:
	var forward := -global_transform.basis.z
	velocity = forward * cola_rocket_forward_speed + Vector3.UP * cola_rocket_up_speed
	_update_milk_diarrhea(delta)
	move_and_slide()
	_animate_goose(delta, cola_rocket_forward_speed, true)
	_update_cola_rocket_light()
	_update_cola_flame_booster()
	_spawn_cola_rocket_exhaust()
	_jump_was_pressed = Input.is_physical_key_pressed(KEY_SPACE)
	_drop_was_pressed = _drop_pressed()
	_attack_was_pressed = _attack_pressed()


func _spawn_cola_rocket_burst() -> void:
	_start_cola_flame_booster()
	var burst_position := _get_cola_exhaust_position()
	_spawn_particle_burst(burst_position, Color(0.15, 0.05, 0.02, 1.0))
	_spawn_particle_burst(burst_position, Color(1.0, 0.34, 0.02, 1.0))


func _spawn_cola_rocket_exhaust() -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 52
	particles.lifetime = 0.42
	particles.one_shot = true
	particles.explosiveness = 0.98
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.42
	particles.direction = (_get_cola_back_direction() + Vector3.DOWN * 0.25).normalized()
	particles.spread = 34.0
	particles.initial_velocity_min = 14.0
	particles.initial_velocity_max = 28.0
	particles.gravity = Vector3(0.0, -12.0, 0.0)
	particles.scale_amount_min = 0.24
	particles.scale_amount_max = 0.72
	particles.color = Color(1.0, 0.28, 0.0, 1.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	particles.mesh = mesh
	get_tree().current_scene.add_child(particles)
	particles.global_position = _get_cola_exhaust_position()
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _start_cola_rocket_light() -> void:
	_stop_cola_rocket_light()
	_cola_rocket_light = OmniLight3D.new()
	_cola_rocket_light.light_color = Color(1.0, 0.28, 0.02, 1.0)
	_cola_rocket_light.light_energy = 10.0
	_cola_rocket_light.omni_range = 9.0
	get_tree().current_scene.add_child(_cola_rocket_light)
	_update_cola_rocket_light()


func _update_cola_rocket_light() -> void:
	if _cola_rocket_light != null and is_instance_valid(_cola_rocket_light):
		_cola_rocket_light.global_position = _get_cola_exhaust_position()


func _stop_cola_rocket_light() -> void:
	if _cola_rocket_light != null and is_instance_valid(_cola_rocket_light):
		_cola_rocket_light.queue_free()
	_cola_rocket_light = null


func _start_cola_flame_booster() -> void:
	_stop_cola_flame_booster()
	_cola_flame_outer = _create_cola_flame_mesh(Color(1.0, 0.24, 0.0, 0.78))
	_cola_flame_inner = _create_cola_flame_mesh(Color(1.0, 0.9, 0.12, 0.95))
	get_tree().current_scene.add_child(_cola_flame_outer)
	get_tree().current_scene.add_child(_cola_flame_inner)
	_update_cola_flame_booster()


func _create_cola_flame_mesh(color: Color) -> MeshInstance3D:
	var flame := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	flame.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	flame.material_override = material
	return flame


func _update_cola_flame_booster() -> void:
	var exhaust_position := _get_cola_exhaust_position()
	var basis := global_transform.basis
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.03) * 0.18
	if _cola_flame_outer != null and is_instance_valid(_cola_flame_outer):
		_cola_flame_outer.global_transform = Transform3D(basis, exhaust_position + _get_cola_back_direction() * 1.15)
		_cola_flame_outer.scale = Vector3(0.85 * pulse, 0.85 * pulse, 3.2 * pulse)
	if _cola_flame_inner != null and is_instance_valid(_cola_flame_inner):
		_cola_flame_inner.global_transform = Transform3D(basis, exhaust_position + _get_cola_back_direction() * 0.78)
		_cola_flame_inner.scale = Vector3(0.38 * pulse, 0.38 * pulse, 2.2 * pulse)


func _stop_cola_flame_booster() -> void:
	if _cola_flame_outer != null and is_instance_valid(_cola_flame_outer):
		_cola_flame_outer.queue_free()
	if _cola_flame_inner != null and is_instance_valid(_cola_flame_inner):
		_cola_flame_inner.queue_free()
	_cola_flame_outer = null
	_cola_flame_inner = null


func _get_cola_exhaust_position() -> Vector3:
	return global_position + _get_cola_back_direction() * 0.9 + Vector3.UP * 0.65


func _get_cola_back_direction() -> Vector3:
	return global_transform.basis.z.normalized()


func _explode_from_milk_overload() -> void:
	if _milk_exploded:
		return

	_milk_exploded = true
	var explosion_position := global_position + Vector3.UP * 1.0
	_spawn_milk_explosion(explosion_position)
	_apply_milk_explosion_knockback(explosion_position)
	inventory.clear()

	if held_item != null:
		held_item.queue_free()
		held_item = null
		held_item_id = StringName()

	goose_visual.visible = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	set_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().create_timer(0.9).timeout.connect(_return_to_title_screen)


func _return_to_title_screen() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func _spawn_milk_explosion(explosion_position: Vector3) -> void:
	_spawn_explosion_particles(
		explosion_position,
		Color(1.0, 0.35, 0.02, 1.0),
		90,
		0.34,
		0.18,
		10.0,
		22.0,
		Vector3(0.0, -5.0, 0.0),
		0.12,
		0.32
	)
	_spawn_explosion_particles(
		explosion_position,
		Color(0.98, 0.97, 0.9, 1.0),
		220,
		0.85,
		0.45,
		6.0,
		16.0,
		Vector3(0.0, -10.0, 0.0),
		0.08,
		0.24
	)
	_spawn_explosion_particles(
		explosion_position + Vector3.UP * 0.25,
		Color(0.16, 0.14, 0.12, 0.85),
		85,
		1.15,
		0.55,
		2.0,
		7.5,
		Vector3(0.0, 1.2, 0.0),
		0.18,
		0.5
	)
	_spawn_explosion_shockwave(explosion_position)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.58, 0.18, 1.0)
	flash.light_energy = 18.0
	flash.omni_range = 13.0
	get_tree().current_scene.add_child(flash)
	flash.global_position = explosion_position
	get_tree().create_timer(0.28).timeout.connect(flash.queue_free)


func _spawn_explosion_particles(
	burst_position: Vector3,
	color: Color,
	amount: int,
	lifetime: float,
	radius: float,
	min_velocity: float,
	max_velocity: float,
	gravity: Vector3,
	min_scale: float,
	max_scale: float
) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = radius
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = min_velocity
	particles.initial_velocity_max = max_velocity
	particles.gravity = gravity
	particles.scale_amount_min = min_scale
	particles.scale_amount_max = max_scale
	particles.color = color
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	particles.mesh = mesh
	get_tree().current_scene.add_child(particles)
	particles.global_position = burst_position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _spawn_explosion_shockwave(explosion_position: Vector3) -> void:
	var shockwave := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 1.0
	shockwave.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.86, 0.35, 0.42)
	shockwave.material_override = material
	get_tree().current_scene.add_child(shockwave)
	shockwave.global_position = explosion_position
	shockwave.scale = Vector3(0.35, 0.05, 0.35)

	var tween := create_tween()
	tween.tween_property(shockwave, "scale", Vector3(milk_explosion_radius, 0.08, milk_explosion_radius), 0.22)
	tween.tween_callback(shockwave.queue_free)


func _apply_milk_explosion_knockback(explosion_position: Vector3) -> void:
	var root := get_tree().current_scene
	if root == null:
		return

	_apply_milk_explosion_knockback_to_node(root, explosion_position)


func _apply_milk_explosion_knockback_to_node(node: Node, explosion_position: Vector3) -> void:
	if node != self and node is Node3D:
		var node_3d := node as Node3D
		var distance := node_3d.global_position.distance_to(explosion_position)
		if distance > 0.01 and distance <= milk_explosion_radius:
			var direction := ((node_3d.global_position - explosion_position).normalized() + Vector3.UP * 0.7).normalized()
			var strength := (1.0 - (distance / milk_explosion_radius)) * milk_explosion_force
			if node_3d is RigidBody3D:
				(node_3d as RigidBody3D).apply_impulse(direction * strength)
			elif node_3d.has_method("bonk"):
				node_3d.bonk(explosion_position)

	for child in node.get_children():
		_apply_milk_explosion_knockback_to_node(child, explosion_position)


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
	_configure_pickup_item_script(held_item, item_id)
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
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	particles.mesh = mesh
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
		&"milk":
			return MILK_SCENE
		_:
			return null


func _configure_pickup_item_script(item: Node3D, item_id: StringName) -> void:
	var added_pickup_script := false
	if not item.has_method("can_combine"):
		item.set_script(PICKUP_ITEM_SCRIPT)
		added_pickup_script = true

	item.set("item_id", item_id)
	if added_pickup_script:
		item.set("visual_path", NodePath(""))
		item.set("pickup_area_path", NodePath(""))
		item.set("collision_body_path", NodePath(""))
		item.set("collision_shape_path", NodePath(""))

	if item.has_method("initialize_pickup"):
		item.initialize_pickup()


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
