extends Control


const GAME_SCENE := "res://scenes/ground.tscn"


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
