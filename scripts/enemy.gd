extends CharacterBody3D

@export var walk_speed := 2.0
@export var turn_speed := 8.0
@export var wander_min := Vector2(-34.0, -22.0)
@export var wander_max := Vector2(12.0, 20.0)
@export var target_reached_distance := 1.2
@export var bonk_stun_time := 0.9
@export var bonk_force := 7.0

var _target := Vector3.ZERO
var _stun_time := 0.0
var _knockback := Vector3.ZERO


func _ready() -> void:
	add_to_group("enemy")
	_pick_new_target()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _stun_time > 0.0:
		_stun_time = maxf(_stun_time - delta, 0.0)
		_knockback = _knockback.move_toward(Vector3.ZERO, 12.0 * delta)
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		move_and_slide()
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
		var target_yaw := atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

	move_and_slide()
	if get_slide_collision_count() > 0:
		_pick_new_target()


func bonk(from_position: Vector3) -> void:
	var away := global_position - from_position
	away.y = 0.0
	if away == Vector3.ZERO:
		away = global_transform.basis.z
	_knockback = away.normalized() * bonk_force
	_stun_time = bonk_stun_time
	_spawn_bonk_particles()


func _pick_new_target() -> void:
	_target = Vector3(
		randf_range(wander_min.x, wander_max.x),
		global_position.y,
		randf_range(wander_min.y, wander_max.y)
	)


func _spawn_bonk_particles() -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.25
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.18
	particles.direction = Vector3.UP
	particles.spread = 70.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 3.4
	particles.gravity = Vector3(0.0, -6.0, 0.0)
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.11
	particles.color = Color(1.0, 0.35, 0.2, 1.0)
	get_tree().current_scene.add_child(particles)
	particles.global_position = global_position + Vector3.UP * 1.1
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
