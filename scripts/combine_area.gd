extends Area3D

const COMBINED_ITEM_SCENE := preload("res://scenes/Chocolate.tscn")

@export var required_item_count := 2
@export var combined_item_id: StringName = &"combined_chocolate"
@export var combined_item_scale := 0.22

var _items: Array[Node3D] = []
var _combine_queued := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	var item := _find_combinable_item(body)
	if item == null or _items.has(item):
		return

	_items.append(item)
	_queue_combine_if_ready()


func _on_body_exited(body: Node3D) -> void:
	var item := _find_combinable_item(body)
	if item != null:
		_items.erase(item)


func _queue_combine_if_ready() -> void:
	_items = _items.filter(_is_valid_combinable_item)
	if _combine_queued or _items.size() < required_item_count:
		return

	_combine_queued = true
	_combine_items.call_deferred()


func _combine_items() -> void:
	_combine_queued = false
	_items = _items.filter(_is_valid_combinable_item)
	if _items.size() < required_item_count:
		return

	var ingredients := _items.slice(0, required_item_count)
	var spawn_position := Vector3.ZERO
	for item in ingredients:
		spawn_position += item.global_position
	spawn_position /= float(ingredients.size())

	for item in ingredients:
		_items.erase(item)
		if item.has_method("mark_combined"):
			item.mark_combined()
		item.queue_free()

	var combined_item := COMBINED_ITEM_SCENE.instantiate() as Node3D
	var target_parent := get_tree().current_scene
	if target_parent == null:
		target_parent = get_parent()
	target_parent.add_child(combined_item)
	combined_item.global_position = spawn_position
	combined_item.scale = Vector3.ONE * combined_item_scale
	combined_item.set("item_id", combined_item_id)

	if combined_item.has_method("begin_drop"):
		combined_item.begin_drop()


func _find_combinable_item(node: Node) -> Node3D:
	var current := node
	while current != null and current != get_tree().current_scene:
		if current is Node3D and current.has_method("can_combine") and current.can_combine():
			return current
		current = current.get_parent()

	return null


func _is_valid_combinable_item(item: Node3D) -> bool:
	return is_instance_valid(item) and item.has_method("can_combine") and item.can_combine()
