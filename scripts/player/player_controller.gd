extends CharacterBody3D
## PlayerController — третье лицо; комичные падения от стен и предметов.

const SPEED := 5.0
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const PUSH_FORCE := 5.5
const PITCH_MIN := -70.0
const PITCH_MAX := 55.0

## Пороги по скорости ДО столкновения (после move_and_slide уже поздно).
const WALL_FALL_SPEED := 3.4
const OBJECT_FALL_SPEED := 2.9
const FALL_DURATION := 1.5
const HIT_COOLDOWN := 0.9
## Как быстро заваливается модель (меньше = плавнее).
const FALL_POSE_SPEED := 2.2

enum FallStyle { SIDE, FORWARD, BACK, TUMBLE, SPRAWL }

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var grab_carry: Node3D = $CameraPivot/SpringArm3D/Camera3D/GrabCarry
@onready var model: Node3D = $Model

var _pitch: float = -20.0
var _stun_left: float = 0.0
var _fallen: bool = false
var _hit_cooldown: float = 0.0
var _model_base_rotation: Vector3 = Vector3.ZERO
var _fall_side: float = 1.0
var _camera_punch: float = 0.0
var _fall_blend: float = 0.0
var _fall_style: FallStyle = FallStyle.SIDE
var _tumble_spin: float = 0.0


func _ready() -> void:
	var is_local := is_multiplayer_authority()
	camera.current = is_local
	set_process_input(is_local)
	set_physics_process(true)
	camera_pivot.rotation_degrees.x = _pitch
	spring_arm.add_excluded_object(get_rid())
	if model != null:
		_model_base_rotation = model.rotation

	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if get_tree().paused:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var look_mul := 0.3 if _fallen else 1.0

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY * look_mul)
		_pitch = clampf(
			_pitch - event.relative.y * MOUSE_SENSITIVITY * 60.0 * look_mul,
			PITCH_MIN,
			PITCH_MAX
		)
		camera_pivot.rotation_degrees.x = _pitch


func _physics_process(delta: float) -> void:
	_hit_cooldown = maxf(_hit_cooldown - delta, 0.0)
	_stun_left = maxf(_stun_left - delta, 0.0)
	_camera_punch = move_toward(_camera_punch, 0.0, delta * 18.0)

	if not is_on_floor():
		velocity += get_gravity() * delta

	if not is_multiplayer_authority():
		move_and_slide()
		return

	if _stun_left <= 0.0 and _fallen:
		_recover_from_fall()

	var can_control := _stun_left <= 0.0 and not _fallen

	if can_control and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else SPEED
	if grab_carry != null and grab_carry.has_method("is_carrying") and grab_carry.is_carrying():
		speed *= 0.92

	if can_control:
		if direction != Vector3.ZERO:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
			velocity.z = move_toward(velocity.z, 0.0, SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)

	# Важно: скорость до слайда — иначе удар о стену «съедается».
	var pre_vel := velocity
	move_and_slide()
	_push_rigid_bodies(pre_vel)
	_check_comedy_falls(pre_vel)
	_update_stumble_pose(delta)
	camera_pivot.rotation_degrees.x = _pitch - _camera_punch


func _push_rigid_bodies(pre_vel: Vector3) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider is RigidBody3D and not (collider as RigidBody3D).freeze:
			var body := collider as RigidBody3D
			var push_dir := -col.get_normal()
			push_dir.y = 0.0
			if push_dir.length_squared() < 0.001:
				continue
			push_dir = push_dir.normalized()
			var approach := maxf(-pre_vel.dot(col.get_normal()), 0.0)
			var strength := PUSH_FORCE * (0.55 + approach * 0.25) \
				* clampf(8.0 / maxf(body.mass, 1.0), 0.12, 2.2)
			body.apply_central_impulse(push_dir * strength)
			body.apply_torque_impulse(Vector3(
				randf_range(-0.5, 0.5),
				randf_range(-0.3, 0.3),
				randf_range(-0.5, 0.5)
			) * clampf(approach * 0.2, 0.0, 1.2))


func _check_comedy_falls(pre_vel: Vector3) -> void:
	if _hit_cooldown > 0.0 or _fallen:
		return

	var best_closing := 0.0
	var best_normal := Vector3.ZERO
	var hit_object := false
	var hit_heavy := false

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider == null:
			continue

		var normal := col.get_normal()
		# Пол не считаем.
		if normal.y > 0.55:
			continue

		var closing := maxf(-pre_vel.dot(normal), 0.0)

		if collider is RigidBody3D:
			var body := collider as RigidBody3D
			var toward := global_position - body.global_position
			if toward.length_squared() > 0.01:
				closing = maxf(closing, body.linear_velocity.dot(toward.normalized()))
			# Даже лёгкий разгон в мебель — уже повод упасть.
			if body.mass >= 8.0:
				closing += 0.6
			if body.mass >= 40.0:
				hit_heavy = true
				closing += 1.2
			hit_object = true
		else:
			# Стена / статика: нужен заметный влёт.
			pass

		if closing > best_closing:
			best_closing = closing
			best_normal = normal

	if best_normal == Vector3.ZERO:
		return

	var need := OBJECT_FALL_SPEED if hit_object else WALL_FALL_SPEED
	# С грузом неуклюжее — падаем легче.
	if grab_carry != null and grab_carry.has_method("is_carrying") and grab_carry.is_carrying():
		need *= 0.75
	if hit_heavy:
		need *= 0.7

	if best_closing < need:
		return

	var knock := best_normal * (1.4 + best_closing * 0.35) \
		+ Vector3.UP * (0.9 + best_closing * 0.12)
	_apply_fall(knock, best_closing, best_normal)


func _pick_fall_style() -> FallStyle:
	var roll := randi() % 5
	match roll:
		0:
			return FallStyle.SIDE
		1:
			return FallStyle.FORWARD
		2:
			return FallStyle.BACK
		3:
			return FallStyle.TUMBLE
		_:
			return FallStyle.SPRAWL


func _apply_fall(knock: Vector3, impact: float, hit_normal: Vector3) -> void:
	_hit_cooldown = HIT_COOLDOWN
	_fallen = true
	_fall_blend = 0.0
	_tumble_spin = 0.0
	_fall_style = _pick_fall_style()
	_fall_side = 1.0 if randf() > 0.5 else -1.0
	_stun_left = FALL_DURATION + clampf(impact * 0.06, 0.0, 0.35)
	if _fall_style == FallStyle.TUMBLE:
		_stun_left += 0.35
	_camera_punch = 4.0 + impact * 0.6

	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	match _fall_style:
		FallStyle.SIDE:
			knock += right * _fall_side * randf_range(0.5, 1.1)
		FallStyle.FORWARD:
			# Носом вперёд/в стену.
			knock += -forward * randf_range(0.25, 0.7) + Vector3.UP * 0.15
			knock += right * _fall_side * randf_range(0.05, 0.25)
		FallStyle.BACK:
			# Отлёт на пятую точку.
			knock = hit_normal * randf_range(0.5, 1.0) + Vector3.UP * randf_range(0.6, 1.0)
			knock += -forward * randf_range(0.6, 1.2)
			knock += right * _fall_side * randf_range(0.1, 0.4)
		FallStyle.TUMBLE:
			knock += -forward * randf_range(0.8, 1.4) + Vector3.UP * randf_range(1.0, 1.6)
			knock += right * _fall_side * randf_range(0.2, 0.7)
		FallStyle.SPRAWL:
			knock += right * _fall_side * randf_range(0.3, 0.9)
			knock += -forward * randf_range(-0.5, 0.7) + Vector3.UP * 0.35

	velocity.x = velocity.x * 0.25 + knock.x
	velocity.z = velocity.z * 0.25 + knock.z
	velocity.y = maxf(velocity.y, knock.y)

	if grab_carry != null and grab_carry.has_method("force_drop"):
		grab_carry.force_drop(knock * 0.45 + Vector3.UP * 0.8)

	var names: PackedStringArray = [
		"на бок", "носом в пол", "на спину", "кувырок", "каракатицей"
	]
	var style_name: String = names[_fall_style]
	print("[Player] Ой, %s (удар %.1f)" % [style_name, impact])


func _recover_from_fall() -> void:
	_fallen = false
	_stun_left = 0.25
	_camera_punch = 0.0
	_fall_blend = 0.0
	_tumble_spin = 0.0


func _fall_target_rotation(t: float) -> Vector3:
	# t 0..1 — насколько уже «лежит».
	match _fall_style:
		FallStyle.SIDE:
			return Vector3(
				lerpf(0.1, 0.35, t),
				0.0,
				lerpf(0.2, 1.1, t) * _fall_side
			)
		FallStyle.FORWARD:
			return Vector3(
				lerpf(0.25, 1.25, t),
				lerpf(0.0, 0.15 * _fall_side, t),
				lerpf(0.0, 0.2 * _fall_side, t)
			)
		FallStyle.BACK:
			return Vector3(
				lerpf(-0.2, -1.15, t),
				lerpf(0.0, -0.1 * _fall_side, t),
				lerpf(0.0, 0.25 * _fall_side, t)
			)
		FallStyle.TUMBLE:
			# Кувырок вперёд + кривой докрут на бок.
			var spin := _tumble_spin
			return Vector3(
				spin,
				sin(spin * 0.7) * 0.35 * _fall_side,
				sin(spin * 0.45) * 0.55 * _fall_side
			)
		FallStyle.SPRAWL:
			return Vector3(
				lerpf(0.15, 0.85, t),
				lerpf(0.0, 0.55 * _fall_side, t),
				lerpf(0.15, 0.95 * _fall_side, t)
			)
	return Vector3.ZERO


func _update_stumble_pose(delta: float) -> void:
	if model == null:
		return
	if _fallen:
		_fall_blend = minf(_fall_blend + delta * FALL_POSE_SPEED, 1.0)
		var t := _fall_blend * _fall_blend
		if _fall_style == FallStyle.TUMBLE:
			# Нелепый кувырок, потом долежать.
			if _fall_blend < 0.85:
				_tumble_spin += delta * lerpf(7.5, 3.0, _fall_blend)
			else:
				_tumble_spin = lerpf(_tumble_spin, TAU + 0.4, clampf(delta * 4.0, 0.0, 1.0))
		var target := _fall_target_rotation(t)
		var follow := 7.0 if _fall_style == FallStyle.TUMBLE else 5.5
		model.rotation.x = lerpf(model.rotation.x, target.x, clampf(delta * follow, 0.0, 1.0))
		model.rotation.y = lerpf(model.rotation.y, _model_base_rotation.y + target.y, clampf(delta * 5.0, 0.0, 1.0))
		model.rotation.z = lerpf(model.rotation.z, target.z, clampf(delta * follow, 0.0, 1.0))
	else:
		_fall_blend = maxf(_fall_blend - delta * 3.0, 0.0)
		model.rotation.x = lerpf(model.rotation.x, _model_base_rotation.x, clampf(delta * 5.0, 0.0, 1.0))
		model.rotation.y = lerpf(model.rotation.y, _model_base_rotation.y, clampf(delta * 5.0, 0.0, 1.0))
		model.rotation.z = lerpf(model.rotation.z, _model_base_rotation.z, clampf(delta * 5.0, 0.0, 1.0))
