extends Node3D

const PICKUP_ITEM_SCRIPT := preload("res://scripts/spin.gd")

@export var milk_item_id: StringName = &"milk"
@export var pickup_item_id: StringName = &"milk"
@export var pickup_distance := 3.0
@export var direct_children_are_items := false


func _ready() -> void:
	make_milk_pickupable()


func make_milk_pickupable() -> void:
	for shelf_group in get_children():
		if not shelf_group is Node3D:
			continue
		if direct_children_are_items:
			_configure_milk_item(shelf_group as Node3D)
			continue

		for milk in shelf_group.get_children():
			if milk is Node3D:
				_configure_milk_item(milk as Node3D)


func _configure_milk_item(milk: Node3D) -> void:
	if not milk.has_method("can_combine"):
		milk.set_script(PICKUP_ITEM_SCRIPT)

	milk.set("item_id", pickup_item_id if pickup_item_id != StringName() else milk_item_id)
	milk.set("pickup_distance", pickup_distance)
	milk.set("visual_path", NodePath(""))
	milk.set("pickup_area_path", NodePath(""))
	milk.set("collision_body_path", NodePath(""))
	milk.set("collision_shape_path", NodePath(""))

	if milk.has_method("initialize_pickup"):
		milk.initialize_pickup()
