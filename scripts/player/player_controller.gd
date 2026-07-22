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
const FALL_DURATION := 1.15
const HIT_COOLDOWN := 0.75
const BALL_RADIUS := 0.55
const BALL_BOUNCE := 0.38
const BALL_FRICTION := 4.5
const BALL_SPIN_DAMP := 1.6
const BALL_SPIN_SCALE := 0.85

enum FallStyle { SIDE, FORWARD, BACK, TUMBLE, SPRAWL }

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var grab_carry: Node3D = $CameraPivot/SpringArm3D/Camera3D/GrabCarry
@onready var model: Node3D = $Model
@onready var body_collision: CollisionShape3D = $CollisionShape3D

var _pitch: float = -20.0
var _stun_left: float = 0.0
var _fallen: bool = false
var _hit_cooldown: float = 0.0
var _model_base_rotation: Vector3 = Vector3.ZERO
var _model_base_position: Vector3 = Vector3.ZERO
var _fall_side: float = 1.0
var _camera_punch: float = 0.0
var _fall_blend: float = 0.0
var _fall_style: FallStyle = FallStyle.SIDE
var _tumble_spin: float = 0.0
var _stand_shape: Shape3D
var _stand_shape_pos: Vector3 = Vector3(0.0, 0.9, 0.0)
var _ball_shape: SphereShape3D
var _ball_spin: Vector3 = Vector3.ZERO
var _style_spin: Vector3 = Vector3.ZERO
var _active_ball_radius: float = BALL_RADIUS


func _ready() -> void:
	var is_local := is_multiplayer_authority()
	camera.current = is_local
	set_process_input(is_local)
	set_physics_process(true)
	camera_pivot.rotation_degrees.x = _pitch
	spring_arm.add_excluded_object(get_rid())
	if model != null:
		_model_base_rotation = model.rotation
		_model_base_position = model.position
	if body_collision != null:
		_stand_shape = body_collision.shape
		_stand_shape_pos = body_collision.position
	_ball_shape = SphereShape3D.new()
	_ball_shape.radius = BALL_RADIUS

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
	elif _fallen:
		# Как мячик: катится, трение слабое.
		velocity.x = move_toward(velocity.x, 0.0, BALL_FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, BALL_FRICTION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)

	# Важно: скорость до слайда — иначе удар о стену «съедается».
	var pre_vel := velocity
	move_and_slide()
	if _fallen:
		_bounce_like_ball(pre_vel)
	else:
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

	var knock := best_normal * (1.0 + best_closing * 0.25) \
		+ Vector3.UP * (0.65 + best_closing * 0.08)
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
		_stun_left += 0.4
	_camera_punch = 3.0 + impact * 0.4
	_active_ball_radius = BALL_RADIUS
	if model != null and model.has_method("get_ball_radius"):
		_active_ball_radius = maxf(BALL_RADIUS, model.get_ball_radius())
	if model != null and model.has_method("set_ball_mode"):
		model.set_ball_mode(true)
	_set_ball_collision(true)
	_ball_spin = _initial_ball_spin()
	_style_spin = _ball_spin * 0.28

	var right := global_transform.basis.x
	var forward := -global_transform.basis.z
	match _fall_style:
		FallStyle.SIDE:
			knock += right * _fall_side * randf_range(0.4, 0.8)
		FallStyle.FORWARD:
			knock += -forward * randf_range(0.2, 0.55) + Vector3.UP * 0.1
			knock += right * _fall_side * randf_range(0.04, 0.18)
		FallStyle.BACK:
			knock = hit_normal * randf_range(0.4, 0.75) + Vector3.UP * randf_range(0.45, 0.75)
			knock += -forward * randf_range(0.45, 0.9)
			knock += right * _fall_side * randf_range(0.08, 0.3)
		FallStyle.TUMBLE:
			knock += -forward * randf_range(0.55, 1.0) + Vector3.UP * randf_range(0.8, 1.25)
			knock += right * _fall_side * randf_range(0.15, 0.5)
		FallStyle.SPRAWL:
			knock += right * _fall_side * randf_range(0.25, 0.65)
			knock += -forward * randf_range(-0.35, 0.5) + Vector3.UP * 0.4

	velocity.x = velocity.x * 0.35 + knock.x
	velocity.z = velocity.z * 0.35 + knock.z
	velocity.y = maxf(velocity.y * 0.25 + knock.y, 1.25 + impact * 0.1)

	if grab_carry != null and grab_carry.has_method("force_drop"):
		grab_carry.force_drop(knock * 0.45 + Vector3.UP * 0.8)

	var names: PackedStringArray = [
		"на бок", "носом в пол", "на спину", "кувырок", "каракатицей"
	]
	var style_name: String = names[_fall_style]
	print("[Player] Ой, %s (удар %.1f)" % [style_name, impact])


func _initial_ball_spin() -> Vector3:
	match _fall_style:
		FallStyle.SIDE:
			return Vector3(randf_range(-0.6, 0.6), 0.0, 4.2 * _fall_side)
		FallStyle.FORWARD:
			return Vector3(4.5, 0.5 * _fall_side, 0.6 * _fall_side)
		FallStyle.BACK:
			return Vector3(-4.2, -0.4 * _fall_side, 0.7 * _fall_side)
		FallStyle.TUMBLE:
			return Vector3(5.8, 1.2 * _fall_side, 1.8 * _fall_side)
		FallStyle.SPRAWL:
			return Vector3(
				randf_range(2.4, 4.0),
				3.0 * _fall_side,
				randf_range(1.8, 3.4) * _fall_side
			)
	return Vector3(3.2, 0.0, 2.0 * _fall_side)


func _set_ball_collision(enabled: bool) -> void:
	if body_collision == null:
		return
	if enabled:
		_ball_shape.radius = _active_ball_radius
		body_collision.shape = _ball_shape
		body_collision.position = Vector3(0.0, _active_ball_radius, 0.0)
		floor_snap_length = 0.05
	else:
		body_collision.shape = _stand_shape
		body_collision.position = _stand_shape_pos
		floor_snap_length = 0.2


func _bounce_like_ball(pre_vel: Vector3) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		var into := -pre_vel.dot(n)
		if into < 1.1:
			continue
		var reflected := pre_vel.bounce(n) * BALL_BOUNCE
		if n.y > 0.55:
			reflected.y = maxf(reflected.y, into * BALL_BOUNCE * 0.55)
			if reflected.y < 1.15:
				reflected.y = 0.0
		velocity = reflected
		_ball_spin += Vector3(
			randf_range(-0.6, 0.6),
			randf_range(-0.4, 0.4),
			randf_range(-0.6, 0.6)
		) * into * 0.12
		break

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length_squared() > 0.08:
		var axis := Vector3.UP.cross(horiz.normalized())
		if axis.length_squared() > 0.001:
			_ball_spin += axis * horiz.length() * 0.045


func _recover_from_fall() -> void:
	_fallen = false
	_stun_left = 0.2
	_camera_punch = 0.0
	_fall_blend = 0.0
	_tumble_spin = 0.0
	_ball_spin = Vector3.ZERO
	_style_spin = Vector3.ZERO
	_set_ball_collision(false)
	if model != null and model.has_method("set_ball_mode"):
		model.set_ball_mode(false)


func _update_stumble_pose(delta: float) -> void:
	if model == null:
		return
	if _fallen:
		_fall_blend = minf(_fall_blend + delta * 2.2, 1.0)
		# Центр сферы = центр меша — при любом повороте не уходит под пол.
		var center := _model_base_position + Vector3(0.0, _active_ball_radius, 0.0)
		model.position = model.position.lerp(center, clampf(delta * 7.0, 0.0, 1.0))

		_ball_spin = _ball_spin.lerp(Vector3.ZERO, clampf(delta * BALL_SPIN_DAMP, 0.0, 1.0))
		if _fall_blend < 0.55:
			_ball_spin += _style_spin * delta

		var spin := _ball_spin * BALL_SPIN_SCALE
		model.rotate_object_local(Vector3.RIGHT, spin.x * delta)
		model.rotate_object_local(Vector3.UP, spin.y * delta)
		model.rotate_object_local(Vector3.FORWARD, spin.z * delta)
	else:
		model.position = model.position.lerp(_model_base_position, clampf(delta * 6.0, 0.0, 1.0))
		model.rotation.x = lerpf(model.rotation.x, _model_base_rotation.x, clampf(delta * 4.5, 0.0, 1.0))
		model.rotation.y = lerpf(model.rotation.y, _model_base_rotation.y, clampf(delta * 4.5, 0.0, 1.0))
		model.rotation.z = lerpf(model.rotation.z, _model_base_rotation.z, clampf(delta * 4.5, 0.0, 1.0))
