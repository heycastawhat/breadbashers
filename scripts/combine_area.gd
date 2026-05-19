extends Area3D

const COMBINED_ITEM_SCENE := preload("res://scenes/Chocolate.tscn")
const CHOCBREAD_SCENE := preload("res://scenes/chocbread.tscn")

const CHOCOLATE_ITEM_IDS := [&"chocolate"]
const BREAD_ITEM_IDS := [&"bread"]

@export var required_item_count := 2
@export var combined_item_id: StringName = &"combined_chocolate"
@export var combined_item_scale := 0.22
@export var chocbread_item_id: StringName = &"chocbread"
@export var chocbread_item_scale := 0.22
@export var scan_interval := 0.15

var _items: Array = []
var _combine_queued := false
var _scan_time := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_scan_time -= delta
	if _scan_time > 0.0:
		return

	_scan_time = scan_interval
	_scan_for_items()


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


func _scan_for_items() -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	if root == null:
		return

	_keep_items_inside_area()
	_collect_items_inside(root)
	_queue_combine_if_ready()


func _keep_items_inside_area() -> void:
	var kept_items: Array = []
	for item in _items:
		if _is_valid_combinable_item(item) and _is_item_inside_area(item):
			kept_items.append(item)
	_items = kept_items


func _keep_valid_items() -> void:
	var kept_items: Array = []
	for item in _items:
		if _is_valid_combinable_item(item):
			kept_items.append(item)
	_items = kept_items


func _collect_items_inside(node: Node) -> void:
	if node != self and node is Node3D and node.has_method("can_combine"):
		var item := node as Node3D
		if item.can_combine() and _is_item_inside_area(item) and not _items.has(item):
			_items.append(item)

	for child in node.get_children():
		_collect_items_inside(child)


func _queue_combine_if_ready() -> void:
	_keep_valid_items()
	if _combine_queued or _items.size() < required_item_count:
		return

	_combine_queued = true
	_combine_items.call_deferred()


func _combine_items() -> void:
	_combine_queued = false
	_keep_valid_items()
	if _items.size() < required_item_count:
		return

	var recipe := _find_recipe()
	var ingredients: Array = []
	for item in recipe["ingredients"]:
		if not _is_valid_combinable_item(item):
			return
		ingredients.append(item)
	var spawn_position := Vector3.ZERO
	for item in ingredients:
		spawn_position += item.global_position
	spawn_position /= float(ingredients.size())

	for item in ingredients:
		_items.erase(item)
		if item.has_method("mark_combined"):
			item.mark_combined()
		item.queue_free()

	var result_scene := recipe["scene"] as PackedScene
	var combined_item := result_scene.instantiate() as Node3D
	var target_parent := get_tree().current_scene
	if target_parent == null:
		target_parent = get_parent()
	target_parent.add_child(combined_item)
	combined_item.global_position = spawn_position
	combined_item.scale = Vector3.ONE * float(recipe["scale"])
	combined_item.set("item_id", recipe["item_id"])

	if combined_item.has_method("begin_drop"):
		combined_item.begin_drop()


func _find_recipe() -> Dictionary:
	var chocolate := _find_item_by_id(CHOCOLATE_ITEM_IDS)
	var bread := _find_item_by_id(BREAD_ITEM_IDS)
	if chocolate != null and bread != null:
		return {
			"ingredients": [chocolate, bread],
			"scene": CHOCBREAD_SCENE,
			"item_id": chocbread_item_id,
			"scale": chocbread_item_scale,
		}

	return {
		"ingredients": _items.slice(0, required_item_count),
		"scene": COMBINED_ITEM_SCENE,
		"item_id": combined_item_id,
		"scale": combined_item_scale,
	}


func _find_item_by_id(item_ids: Array) -> Node3D:
	for item in _items:
		if _is_valid_combinable_item(item) and item_ids.has(_get_item_id(item)):
			return item as Node3D
	return null


func _get_item_id(item) -> StringName:
	if not is_instance_valid(item):
		return StringName()

	var value = item.get("item_id")
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return StringName()


func _find_combinable_item(node: Node) -> Node3D:
	var current := node
	while current != null and current != get_tree().current_scene:
		if current is Node3D and current.has_method("can_combine") and current.can_combine():
			return current
		current = current.get_parent()

	return null


func _is_valid_combinable_item(item) -> bool:
	return (
		is_instance_valid(item)
		and item is Node3D
		and item.has_method("can_combine")
		and item.can_combine()
	)


func _is_item_inside_area(item) -> bool:
	if not is_instance_valid(item):
		return false
	if not item is Node3D:
		return false
	var item_node := item as Node3D

	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		return false

	var local_position := shape_node.global_transform.affine_inverse() * item_node.global_position
	var shape := shape_node.shape
	if shape is BoxShape3D:
		var extents := (shape as BoxShape3D).size * 0.5
		return (
			absf(local_position.x) <= extents.x
			and absf(local_position.y) <= extents.y
			and absf(local_position.z) <= extents.z
		)
	if shape is SphereShape3D:
		return local_position.length() <= (shape as SphereShape3D).radius

	return shape_node.global_position.distance_to(item_node.global_position) <= 2.0
