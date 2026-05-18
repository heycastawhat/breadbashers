extends Node3D


@export var item_id: StringName = &"chocolate"
@export var pickup_distance := 2.0
@export var spin_speed := 80.0
@export var bob_height := 0.25
@export var bob_speed := 1.0

@onready var pivot: Node3D = $SpinPivot
@onready var pickup_area: Area3D = $PickupArea

var _start_y := 0.0
var _time := 0.0
var _interact_was_pressed := false
var _held_mode := false


func _ready() -> void:
	_start_y = position.y


func _process(delta: float) -> void:
	if _held_mode:
		return

	_time += delta
	pivot.rotate_y(deg_to_rad(spin_speed) * delta)
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

	if value:
		position = Vector3.ZERO
		rotation = Vector3.ZERO
		pivot.rotation = Vector3.ZERO
	else:
		_start_y = position.y


func _is_player_close(player: Node3D) -> bool:
	return global_position.distance_to(player.global_position) <= pickup_distance
