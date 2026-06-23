extends Node3D


@export var item_id: StringName = &"chocolate"
@export var pickup_distance := 2.0
@export var spin_speed := 80.0
@export var bob_height := 0.25
@export var bob_speed := 1.0
@export var drop_gravity := 12.0
@export var floor_offset := 0.08
@export var floor_hit_particles := true
@export var visual_path: NodePath = ^"Cube"
@export var pickup_area_path: NodePath = ^"PickupArea"
@export var collision_body_path: NodePath = ^"Cube/StaticBody3D"
@export var collision_shape_path: NodePath = ^"Cube/StaticBody3D/CollisionShape3D"

@onready var pivot: Node3D = get_node_or_null(^"SpinPivot") as Node3D
@onready var visual: Node3D = _get_visual_node()
@onready var pickup_area: Area3D = get_node_or_null(pickup_area_path) as Area3D
@onready var collision_body: StaticBody3D = get_node_or_null(collision_body_path) as StaticBody3D
@onready var collision_shape: CollisionShape3D = get_node_or_null(collision_shape_path) as CollisionShape3D

var _start_y := 0.0
var _time := 0.0
var _interact_was_pressed := false
var _held_mode := false
var _falling := false
var _fall_velocity := 0.0
var _combined := false


func _ready() -> void:
	_cache_nodes()
	initialize_pickup()


func initialize_pickup() -> void:
	_cache_nodes()
	_start_y = position.y
	_set_world_collision(true)
	set_process(true)


func _cache_nodes() -> void:
	pivot = get_node_or_null(^"SpinPivot") as Node3D
	visual = _get_visual_node()
	pickup_area = get_node_or_null(pickup_area_path) as Area3D
	collision_body = get_node_or_null(collision_body_path) as StaticBody3D
	collision_shape = get_node_or_null(collision_shape_path) as CollisionShape3D


func _process(delta: float) -> void:
	if _held_mode:
		return

	_time += delta

	if _falling:
		_apply_drop_gravity(delta)
		return

	position.y = _start_y + sin(_time * bob_speed) * bob_height

	var interact_pressed := _interact_pressed()
	var player := get_tree().get_first_node_in_group("player")
	if player and _is_player_close(player) and interact_pressed and not _interact_was_pressed:
		if player.has_method("add_item"):
			var pickup_accepted = player.add_item(item_id, 1)
			if pickup_accepted != false:
				_combined = true
				queue_free()
				return

	_interact_was_pressed = interact_pressed


func _on_pickup_area_body_entered(_body: Node3D) -> void:
	pass


func _on_pickup_area_body_exited(_body: Node3D) -> void:
	pass


func _interact_pressed() -> bool:
	if InputMap.has_action("interact"):
		return Input.is_action_pressed("interact")
	return Input.is_physical_key_pressed(KEY_E)


func set_held_mode(value: bool) -> void:
	_held_mode = value
	_interact_was_pressed = false
	if pickup_area != null:
		pickup_area.monitoring = not value
		pickup_area.monitorable = not value
	_set_world_collision(not value)

	if value:
		position = Vector3.ZERO
		rotation = Vector3.ZERO
		if pivot != null:
			pivot.rotation = Vector3.ZERO
		if visual != null:
			visual.rotation = Vector3.ZERO
	else:
		_start_y = position.y


func begin_drop() -> void:
	set_held_mode(false)
	_falling = true
	_fall_velocity = 0.0


func can_combine() -> bool:
	return not _held_mode and not _falling and not _combined and is_inside_tree()


func mark_combined() -> void:
	_combined = true


func _is_player_close(player: Node3D) -> bool:
	return global_position.distance_to(player.global_position) <= pickup_distance


func _apply_drop_gravity(delta: float) -> void:
	var from := global_position
	_fall_velocity += drop_gravity * delta
	var to := from + Vector3.DOWN * _fall_velocity * delta

	var query := PhysicsRayQueryParameters3D.create(from, to + Vector3.DOWN * floor_offset)
	if collision_body != null:
		query.exclude = [collision_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit:
		global_position = hit["position"] + Vector3.UP * floor_offset
		_start_y = position.y
		_falling = false
		if floor_hit_particles:
			_spawn_particle_burst(hit["position"], Color(0.95, 0.82, 0.45, 1.0))
		return

	global_position = to


func _set_world_collision(enabled: bool) -> void:
	if collision_shape != null:
		collision_shape.disabled = not enabled


func _get_visual_node() -> Node3D:
	var configured_visual := get_node_or_null(visual_path) as Node3D
	if configured_visual != null:
		return configured_visual
	return self


func _spawn_particle_burst(burst_position: Vector3, color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.35
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.08
	particles.direction = Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 3.0
	particles.gravity = Vector3(0.0, -6.0, 0.0)
	particles.scale_amount_min = 0.035
	particles.scale_amount_max = 0.09
	particles.color = color
	get_tree().current_scene.add_child(particles)
	particles.global_position = burst_position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
