extends CharacterBody3D

@export var walk_speed := 6.0
@export var turn_speed := 8.0
@export var wander_min := Vector2(-34.0, -22.0)
@export var wander_max := Vector2(12.0, 20.0)
@export var target_reached_distance := 1.2
@export var bonk_stun_time := 4
@export var bonk_force := 18.0

@export_group("Facing")
@export var face_negative_z := true

@export_group("Animation")
@export var walk_freq := 8.0
@export var walk_bob_height := 0.1
@export var walk_sway_degrees := 4.0
@export var walk_pitch_degrees := 2.5
@export var idle_bob_freq := 1.4
@export var idle_bob_height := 0.1
@export var bonk_tilt_degrees := 18.0
@export var bonk_spin_degrees := 380.0
@export var animation_smoothing := 14.0

var _target := Vector3.ZERO
var _stun_time := 0.0
var _knockback := Vector3.ZERO
var _walk_phase := 0.0
var _idle_phase := 0.0
var _bonk_phase := 0.0
var _visual_base_position := Vector3.ZERO
var _visual_base_rotation := Vector3.ZERO
var _spawn_position := Vector3.ZERO

@onready var _visual: Node3D = $Ch23_nonPBR
@onready var _honk_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
var _honk_sound := preload("res://assets/Honk1.mp3")


func _ready() -> void:
	add_to_group("enemy")
	_visual_base_position = _visual.position
	_visual_base_rotation = _visual.rotation
	_idle_phase = randf() * TAU
	_spawn_position = global_position
	_pick_new_target()
	add_child(_honk_player)
	_honk_player.stream = _honk_sound

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_honk_player.play()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _stun_time > 0.0:
		_stun_time = maxf(_stun_time - delta, 0.0)
		_knockback = _knockback.move_toward(Vector3.ZERO, 12.0 * delta)
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		move_and_slide()
		_animate_bonk(delta)
		return

	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() <= target_reached_distance:
		_pick_new_target()
		to_target = _target - global_position
		to_target.y = 0.0

	var move_dir := to_target.normalized()
	velocity.x = move_dir.x * walk_speed
	velocity.z = move_dir.z * walk_speed

	if move_dir != Vector3.ZERO:
		var target_yaw: float
		if face_negative_z:
			target_yaw = atan2(-move_dir.x, -move_dir.z)
		else:
			target_yaw = atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

	move_and_slide()
	if get_slide_collision_count() > 0:
		_pick_new_target()

	_animate_walk(delta)


func bonk(from_position: Vector3) -> void:
	var away := global_position - from_position
	away.y = 0.0
	if away == Vector3.ZERO:
		away = global_transform.basis.z
	_knockback = away.normalized() * bonk_force
	_stun_time = bonk_stun_time
	_bonk_phase = 0.0
	_spawn_bonk_particles(from_position)


func _pick_new_target() -> void:
	_target = _spawn_position + Vector3(
		randf_range(wander_min.x, wander_max.x),
		0.0,
		randf_range(wander_min.y, wander_max.y)
	)
	_target.y = global_position.y


func _animate_walk(delta: float) -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var moving_amount := clampf(horiz_speed / maxf(walk_speed, 0.001), 0.0, 1.0)

	if moving_amount > 0.05:
		_walk_phase += delta * walk_freq * lerpf(0.65, 1.25, moving_amount)
	else:
		_idle_phase += delta * idle_bob_freq

	var step := sin(_walk_phase)
	var bob := absf(step) * walk_bob_height * moving_amount
	bob += sin(_idle_phase) * idle_bob_height * (1.0 - moving_amount)

	var target_position := _visual_base_position + Vector3.UP * bob
	var target_rotation := _visual_base_rotation
	target_rotation.x += deg_to_rad(walk_pitch_degrees) * absf(step) * moving_amount
	target_rotation.z += deg_to_rad(walk_sway_degrees) * step * moving_amount

	_apply_visual_pose(target_position, target_rotation, delta)


func _animate_bonk(delta: float) -> void:
	_bonk_phase += delta
	var stun_amount := clampf(_stun_time / maxf(bonk_stun_time, 0.001), 0.0, 1.0)
	var spin := deg_to_rad(bonk_spin_degrees) * _bonk_phase
	var tilt := deg_to_rad(bonk_tilt_degrees) * stun_amount

	var target_position := _visual_base_position + Vector3.UP * (0.08 * stun_amount)
	var target_rotation := _visual_base_rotation + Vector3(tilt, spin, -tilt * 0.5)
	_apply_visual_pose(target_position, target_rotation, delta)


func _apply_visual_pose(target_position: Vector3, target_rotation: Vector3, delta: float) -> void:
	var t := clampf(delta * animation_smoothing, 0.0, 1.0)
	_visual.position = _visual.position.lerp(target_position, t)
	_visual.rotation.x = lerp_angle(_visual.rotation.x, target_rotation.x, t)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_rotation.y, t)
	_visual.rotation.z = lerp_angle(_visual.rotation.z, target_rotation.z, t)


func _spawn_bonk_particles(from_position: Vector3) -> void:
	var away := global_position - from_position
	away.y = 0.0
	if away == Vector3.ZERO:
		away = global_transform.basis.z
	var hit_direction := away.normalized()
	var burst_position := global_position + Vector3.UP * 0.55 - hit_direction * 0.28

	var particles := CPUParticles3D.new()
	particles.amount = 36
	particles.lifetime = 0.34
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.12
	particles.direction = (away.normalized() + Vector3.UP * 0.65).normalized()
	particles.spread = 50.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 5.2
	particles.gravity = Vector3(0.0, -8.0, 0.0)
	particles.scale_amount_min = 0.05
	particles.scale_amount_max = 0.14
	particles.color = Color(1.0, 0.74, 0.22, 1.0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	particles.mesh = mesh
	get_tree().current_scene.add_child(particles)
	particles.global_position = burst_position
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	_spawn_hit_sparks(burst_position, hit_direction)

func _spawn_hit_sparks(burst_position: Vector3, hit_direction: Vector3) -> void:
	var container := Node3D.new()
	get_tree().current_scene.add_child(container)
	container.global_position = burst_position

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.78, 0.16, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.05, 1.0)
	material.emission_energy_multiplier = 1.8
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for i in range(14):
		var spark := MeshInstance3D.new()
		var spark_mesh := BoxMesh.new()
		spark_mesh.size = Vector3(0.08, 0.08, 0.08) * randf_range(0.7, 1.35)
		spark.mesh = spark_mesh
		spark.material_override = material
		container.add_child(spark)

		var spread := Vector3(randf_range(-0.8, 0.8), randf_range(0.2, 1.0), randf_range(-0.8, 0.8))
		var spark_dir := (hit_direction * randf_range(0.6, 1.2) + spread).normalized()
		var distance := randf_range(0.45, 1.15)
		var tween := spark.create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", spark_dir * distance, randf_range(0.22, 0.38))
		tween.tween_property(spark, "scale", Vector3.ZERO, 0.34)
		tween.tween_property(spark, "rotation", Vector3(randf(), randf(), randf()) * TAU, 0.34)

	await get_tree().create_timer(0.42).timeout
	container.queue_free()
