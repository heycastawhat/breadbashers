extends Node3D


@export var item_id: StringName = &"chocolate"
@export var pickup_distance := 2.0
@export var spin_speed := 80.0
@export var bob_height := 0.25
@export var bob_speed := 1.0
@export var drop_gravity := 12.0
@export var floor_offset := 0.08

@onready var pivot: Node3D = $SpinPivot
@onready var visual: Node3D = $Cube
@onready var pickup_area: Area3D = $PickupArea
@onready var collision_body: StaticBody3D = $Cube/StaticBody3D
@onready var collision_shape: CollisionShape3D = $Cube/StaticBody3D/CollisionShape3D

var _start_y := 0.0
var _time := 0.0
var _interact_was_pressed := false
var _held_mode := false
var _falling := false
var _fall_velocity := 0.0


func _ready() -> void:
	_start_y = position.y
	_set_world_collision(true)


func _process(delta: float) -> void:
	if _held_mode:
		return

	_time += delta
	visual.rotate_y(deg_to_rad(spin_speed) * delta)

	if _falling:
		_apply_drop_gravity(delta)
		return

	position.y = _start_y + sin(_time * bob_speed) * bob_height

	var interact_pressed := _interact_pressed()
	var player := get_tree().get_first_node_in_group("player")
	if player and _is_player_close(player) and interact_pressed and not _interact_was_pressed:
		if player.has_method("add_item"):
			player.add_item(item_id, 1)
			queue_free()
			return

	_interact_was_pressed = interact_pressed


func _on_pickup_area_body_entered(body: Node3D) -> void:
	pass


func _on_pickup_area_body_exited(body: Node3D) -> void:
	pass


func _interact_pressed() -> bool:
	if InputMap.has_action("interact"):
		return Input.is_action_pressed("interact")
	return Input.is_physical_key_pressed(KEY_E)


func set_held_mode(value: bool) -> void:
	_held_mode = value
	_interact_was_pressed = false
	pickup_area.monitoring = not value
	pickup_area.monitorable = not value
	_set_world_collision(not value)

	if value:
		position = Vector3.ZERO
		rotation = Vector3.ZERO
		pivot.rotation = Vector3.ZERO
		visual.rotation = Vector3.ZERO
	else:
		_start_y = position.y


func begin_drop() -> void:
	set_held_mode(false)
	_falling = true
	_fall_velocity = 0.0


func _is_player_close(player: Node3D) -> bool:
	return global_position.distance_to(player.global_position) <= pickup_distance


func _apply_drop_gravity(delta: float) -> void:
	var from := global_position
	_fall_velocity += drop_gravity * delta
	var to := from + Vector3.DOWN * _fall_velocity * delta

	var query := PhysicsRayQueryParameters3D.create(from, to + Vector3.DOWN * floor_offset)
	query.exclude = [collision_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit:
		global_position = hit["position"] + Vector3.UP * floor_offset
		_start_y = position.y
		_falling = false
		return

	global_position = to


func _set_world_collision(enabled: bool) -> void:
	collision_shape.disabled = not enabled
