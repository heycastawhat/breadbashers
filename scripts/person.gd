extends CharacterBody3D

@export var walk_speed := 2.0
@export var turn_speed := 8.0
@export var wander_min := Vector2(-34.0, -22.0)
@export var wander_max := Vector2(12.0, 20.0)
@export var target_reached_distance := 1.2
@export var bonk_stun_time := 0.9
@export var bonk_force := 7.0

@export_group("Facing")
# If model walks backwards flip this. Godot forward = -Z (true), model forward = +Z (false).
@export var face_negative_z := true

@export_group("Animation")
@export var walk_freq := 7.5
@export var leg_swing := 0.7
@export var arm_swing := 0.55
@export var spine_twist := 0.12
@export var hip_bob := 0.06
@export var idle_bob_freq := 1.6
@export var idle_bob_height := 0.02
@export var bonk_spin_speed := 14.0
@export var bonk_tilt_angle := 1.1
@export var pose_smoothing := 14.0

const BONE_HIPS := 0
const BONE_SPINE := 1
const BONE_HEAD := 2
const BONE_L_ARM := 3
const BONE_R_ARM := 4
const BONE_L_LEG := 5
const BONE_R_LEG := 6

# Skeleton lives in person-local space (Godot Y-up). UP always Y; the sideways
# (shoulder) axis is detected from model bounds at rig build time.
const UP_AXIS := Vector3.UP
var _side_axis := Vector3.RIGHT       # shoulder axis (used for limb swing)
var _shoulder_along_x := true         # if false, shoulder is along Z

var _target := Vector3.ZERO
var _stun_time := 0.0
var _knockback := Vector3.ZERO

@onready var _visual: Node3D = $Sketchfab_Scene
var _skeleton: Skeleton3D
var _hips_rest_pos := Vector3.ZERO
var _walk_phase := 0.0
var _idle_phase := 0.0
var _bonk_phase := 0.0

var _target_rot: Dictionary = {}
var _target_pos: Dictionary = {}


func _ready() -> void:
	add_to_group("enemy")
	_idle_phase = randf() * TAU
	_build_rig()
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
		_animate_bonk(delta)
		_apply_smoothed(delta)
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
	_apply_smoothed(delta)


func bonk(from_position: Vector3) -> void:
	var away := global_position - from_position
	away.y = 0.0
	if away == Vector3.ZERO:
		away = global_transform.basis.z
	_knockback = away.normalized() * bonk_force
	_stun_time = bonk_stun_time
	_bonk_phase = 0.0
	_spawn_bonk_particles()


func _pick_new_target() -> void:
	_target = Vector3(
		randf_range(wander_min.x, wander_max.x),
		global_position.y,
		randf_range(wander_min.y, wander_max.y)
	)

# ---------------------------------------------------------------- rig

func _build_rig() -> void:
	var parts: Array[MeshInstance3D] = []
	_collect_meshes(_visual, parts)
	if parts.is_empty():
		return

	# Centroid of each part in person-local space (Y up).
	var person_inv := global_transform.affine_inverse()
	var centroids: Array[Vector3] = []
	var min_y := INF
	var max_y := -INF
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in parts:
		var ab := p.get_aabb()
		var center_local := ab.position + ab.size * 0.5
		var c := person_inv * (p.global_transform * center_local)
		centroids.append(c)
		min_y = minf(min_y, c.y)
		max_y = maxf(max_y, c.y)
		min_x = minf(min_x, c.x)
		max_x = maxf(max_x, c.x)
		min_z = minf(min_z, c.z)
		max_z = maxf(max_z, c.z)
	var h: float = maxf(max_y - min_y, 0.001)
	var spread_x := max_x - min_x
	var spread_z := max_z - min_z
	# Shoulder axis = wider horizontal axis.
	_shoulder_along_x = spread_x >= spread_z
	_side_axis = Vector3.RIGHT if _shoulder_along_x else Vector3.FORWARD
	var w: float = maxf(spread_x if _shoulder_along_x else spread_z, 0.001)

	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)

	# Bone rest positions in person-local. Anchored to model bounds.
	var hips_y := min_y + h * 0.50
	var spine_y := min_y + h * 0.65
	var head_y := min_y + h * 0.88
	var arm_y := min_y + h * 0.70
	var leg_y := min_y + h * 0.40

	_add_bone("Hips", -1, Vector3(0, hips_y, 0))
	_add_bone("Spine", BONE_HIPS, Vector3(0, spine_y - hips_y, 0))
	_add_bone("Head", BONE_SPINE, Vector3(0, head_y - spine_y, 0))
	_add_bone("L_Arm", BONE_SPINE, _side_offset(-w * 0.30, arm_y - spine_y))
	_add_bone("R_Arm", BONE_SPINE, _side_offset(w * 0.30, arm_y - spine_y))
	_add_bone("L_Leg", BONE_HIPS, _side_offset(-w * 0.10, leg_y - hips_y))
	_add_bone("R_Leg", BONE_HIPS, _side_offset(w * 0.10, leg_y - hips_y))
	_skeleton.reset_bone_poses()
	_hips_rest_pos = _skeleton.get_bone_rest(BONE_HIPS).origin

	# Cache bone rest positions in skeleton-local (= person-local).
	var bone_world: Array[Vector3] = []
	for b in range(_skeleton.get_bone_count()):
		bone_world.append(_skeleton.get_bone_global_rest(b).origin)

	# Reparent each mesh part under its bone attachment.
	for i in parts.size():
		var p := parts[i]
		var c := centroids[i]
		var bone := _classify(c, min_y, h)
		var att := BoneAttachment3D.new()
		att.bone_idx = bone
		_skeleton.add_child(att)

		# Part transform expressed in person/skeleton-local.
		var part_in_skel := person_inv * p.global_transform
		var local_to_att := Transform3D(part_in_skel.basis, part_in_skel.origin - bone_world[bone])

		p.get_parent().remove_child(p)
		att.add_child(p)
		p.transform = local_to_att


func _add_bone(b_name: String, parent_idx: int, offset_from_parent: Vector3) -> int:
	var idx := _skeleton.add_bone(b_name)
	if parent_idx >= 0:
		_skeleton.set_bone_parent(idx, parent_idx)
	_skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, offset_from_parent))
	return idx


func _classify(c: Vector3, min_y: float, h: float) -> int:
	var y_rel := (c.y - min_y) / h
	var s: float = c.x if _shoulder_along_x else c.z
	if y_rel > 0.82:
		return BONE_HEAD
	if y_rel > 0.55:
		if s < -0.12:
			return BONE_L_ARM
		if s > 0.12:
			return BONE_R_ARM
		return BONE_SPINE
	if y_rel > 0.35:
		return BONE_HIPS
	if s < 0.0:
		return BONE_L_LEG
	return BONE_R_LEG


func _side_offset(side_amount: float, vert: float) -> Vector3:
	if _shoulder_along_x:
		return Vector3(side_amount, vert, 0)
	return Vector3(0, vert, side_amount)


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
		return
	for c in n.get_children():
		_collect_meshes(c, out)

# ---------------------------------------------------------------- anim

func _animate_walk(delta: float) -> void:
	if _skeleton == null:
		return
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var moving := horiz_speed > 0.05
	if moving:
		_walk_phase += delta * walk_freq * clampf(horiz_speed / walk_speed, 0.4, 1.5)
		var sw := sin(_walk_phase)
		_set_target_pos(BONE_HIPS, _hips_rest_pos + UP_AXIS * (absf(sw) * hip_bob))
		_set_target_rot(BONE_L_LEG, _side_axis, sw * leg_swing)
		_set_target_rot(BONE_R_LEG, _side_axis, -sw * leg_swing)
		_set_target_rot(BONE_L_ARM, _side_axis, -sw * arm_swing)
		_set_target_rot(BONE_R_ARM, _side_axis, sw * arm_swing)
		_set_target_rot(BONE_SPINE, UP_AXIS, sw * spine_twist)
		_set_target_rot(BONE_HEAD, UP_AXIS, -sw * spine_twist * 0.5)
	else:
		_idle_phase += delta * idle_bob_freq
		var si := sin(_idle_phase)
		_set_target_pos(BONE_HIPS, _hips_rest_pos + UP_AXIS * (si * idle_bob_height))
		_set_target_rot(BONE_L_LEG, _side_axis, 0.0)
		_set_target_rot(BONE_R_LEG, _side_axis, 0.0)
		_set_target_rot(BONE_L_ARM, _side_axis, 0.0)
		_set_target_rot(BONE_R_ARM, _side_axis, 0.0)
		_set_target_rot(BONE_SPINE, UP_AXIS, 0.0)
		_set_target_rot(BONE_HEAD, UP_AXIS, 0.0)


func _animate_bonk(delta: float) -> void:
	if _skeleton == null:
		return
	_bonk_phase += delta
	var stun_t := clampf(_stun_time / bonk_stun_time, 0.0, 1.0)
	var spin := _bonk_phase * bonk_spin_speed
	var tilt := bonk_tilt_angle * stun_t
	var hips_basis := Basis(UP_AXIS, spin) * Basis(_side_axis, -tilt * 0.4)
	_target_rot[BONE_HIPS] = hips_basis.get_rotation_quaternion()
	_set_target_pos(BONE_HIPS, _hips_rest_pos + UP_AXIS * (0.12 * stun_t))
	_set_target_rot(BONE_SPINE, _side_axis, -tilt * 0.5)
	_set_target_rot(BONE_HEAD, _side_axis, -tilt * 0.7)
	_set_target_rot(BONE_L_ARM, _side_axis, tilt)
	_set_target_rot(BONE_R_ARM, _side_axis, tilt)
	_set_target_rot(BONE_L_LEG, _side_axis, -tilt * 0.3)
	_set_target_rot(BONE_R_LEG, _side_axis, -tilt * 0.3)


func _set_target_rot(idx: int, axis: Vector3, angle: float) -> void:
	_target_rot[idx] = Quaternion(axis.normalized(), angle)


func _set_target_pos(idx: int, pos: Vector3) -> void:
	_target_pos[idx] = pos


func _apply_smoothed(delta: float) -> void:
	if _skeleton == null:
		return
	var t := clampf(delta * pose_smoothing, 0.0, 1.0)
	for idx in _target_rot:
		var cur: Quaternion = _skeleton.get_bone_pose_rotation(idx)
		_skeleton.set_bone_pose_rotation(idx, cur.slerp(_target_rot[idx], t))
	for idx in _target_pos:
		var cur: Vector3 = _skeleton.get_bone_pose_position(idx)
		_skeleton.set_bone_pose_position(idx, cur.lerp(_target_pos[idx], t))


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
