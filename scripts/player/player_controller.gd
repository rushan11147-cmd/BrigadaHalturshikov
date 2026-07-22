extends CharacterBody3D
## PlayerController — третье лицо; простое живое спотыкание (без мячика).

const SPEED := 5.0
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const PUSH_FORCE := 5.5
const PITCH_MIN := -70.0
const PITCH_MAX := 55.0

const WALL_FALL_SPEED := 3.6
const OBJECT_FALL_SPEED := 3.0
const FALL_TIME := 1.0
const GETUP_IMMUNITY := 1.0

enum FallStyle { SIDE, FORWARD, BACK }

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var grab_carry: Node3D = $CameraPivot/SpringArm3D/Camera3D/GrabCarry
@onready var model: Node3D = $Model

var _pitch: float = -20.0
var _fallen: bool = false
var _fall_timer: float = 0.0
var _hit_cooldown: float = 0.0
var _model_base_rotation: Vector3 = Vector3.ZERO
var _model_base_position: Vector3 = Vector3.ZERO
var _fall_side: float = 1.0
var _fall_style: FallStyle = FallStyle.SIDE
var _lean := Vector3.ZERO
var _lean_vel := Vector3.ZERO
var _camera_punch: float = 0.0


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
	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if get_tree().paused:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var look_mul := 0.45 if _fallen else 1.0
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
	_camera_punch = move_toward(_camera_punch, 0.0, delta * 22.0)

	if not is_on_floor():
		velocity += get_gravity() * delta

	if not is_multiplayer_authority():
		move_and_slide()
		return

	if _fallen:
		_fall_timer -= delta
		if _fall_timer <= 0.0 or Input.is_action_just_pressed("jump"):
			_recover()

	var can_control := not _fallen

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
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	var pre_vel := velocity
	move_and_slide()
	if not _fallen:
		_push_rigid_bodies(pre_vel)
		_check_hits(pre_vel)
	_update_lean(delta)
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


func _check_hits(pre_vel: Vector3) -> void:
	if _hit_cooldown > 0.0:
		return

	var best_closing := 0.0
	var best_normal := Vector3.ZERO
	var hit_object := false

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() == null:
			continue
		var normal := col.get_normal()
		if normal.y > 0.55:
			continue
		var closing := maxf(-pre_vel.dot(normal), 0.0)
		if col.get_collider() is RigidBody3D:
			var body := col.get_collider() as RigidBody3D
			closing += 0.5 + minf(body.mass * 0.02, 1.0)
			hit_object = true
		if closing > best_closing:
			best_closing = closing
			best_normal = normal

	if best_normal == Vector3.ZERO:
		return

	var need := OBJECT_FALL_SPEED if hit_object else WALL_FALL_SPEED
	if grab_carry != null and grab_carry.has_method("is_carrying") and grab_carry.is_carrying():
		need *= 0.8
	if best_closing < need:
		return

	var knock := best_normal * (0.9 + best_closing * 0.2) + Vector3.UP * 0.55
	_start_fall(knock, best_closing)


func _start_fall(knock: Vector3, impact: float) -> void:
	_fallen = true
	_fall_timer = FALL_TIME
	_hit_cooldown = GETUP_IMMUNITY
	_fall_side = 1.0 if randf() > 0.5 else -1.0
	var roll := randi() % 3
	_fall_style = [FallStyle.SIDE, FallStyle.FORWARD, FallStyle.BACK][roll] as FallStyle
	_camera_punch = 2.5 + impact * 0.25

	# Импульс качания — сначала от удара, потом завал.
	match _fall_style:
		FallStyle.SIDE:
			_lean_vel = Vector3(0.8, 0.0, -2.2 * _fall_side)
		FallStyle.FORWARD:
			_lean_vel = Vector3(-2.4, 0.0, 0.4 * _fall_side)
		FallStyle.BACK:
			_lean_vel = Vector3(2.5, 0.0, 0.35 * _fall_side)

	_lean_vel *= clampf(impact / 4.0, 0.85, 1.35)
	velocity.x = velocity.x * 0.4 + knock.x
	velocity.z = velocity.z * 0.4 + knock.z
	velocity.y = maxf(velocity.y, knock.y)

	if grab_carry != null and grab_carry.has_method("force_drop"):
		grab_carry.force_drop(knock * 0.4 + Vector3.UP * 0.6)

	if model != null and model.has_method("start_stumble_sway"):
		model.start_stumble_sway(int(_fall_style), _fall_side)

	var names: PackedStringArray = ["на бок", "вперёд", "назад"]
	print("[Player] Споткнулся: %s" % names[_fall_style])


func _recover() -> void:
	_fallen = false
	_fall_timer = 0.0
	_hit_cooldown = GETUP_IMMUNITY
	_camera_punch = 0.0
	_lean_vel = -_lean * 3.0
	if model != null and model.has_method("end_stumble_sway"):
		model.end_stumble_sway()


func _update_lean(delta: float) -> void:
	if model == null:
		return

	var target := Vector3.ZERO
	if _fallen:
		var t := 1.0 - clampf(_fall_timer / FALL_TIME, 0.0, 1.0)
		# 0..0.2 качок, 0.2..0.7 завал, дальше лежит.
		var tip := smoothstep(0.15, 0.65, t)
		var settle_wobble := sin(t * 22.0) * (1.0 - tip) * 0.12
		match _fall_style:
			FallStyle.SIDE:
				target = Vector3(0.15 * tip + settle_wobble, 0.0, 1.05 * tip * _fall_side)
			FallStyle.FORWARD:
				target = Vector3(1.1 * tip + settle_wobble, 0.08 * tip * _fall_side, 0.12 * tip * _fall_side)
			FallStyle.BACK:
				target = Vector3(-1.05 * tip - settle_wobble, -0.08 * tip * _fall_side, 0.12 * tip * _fall_side)

	# Пружина — тело не щёлкает, а качается.
	var stiff := 16.0 if _fallen else 22.0
	var damp := 6.5 if _fallen else 9.0
	var force := (target - _lean) * stiff - _lean_vel * damp
	_lean_vel += force * delta
	_lean += _lean_vel * delta
	_lean.x = clampf(_lean.x, -1.2, 1.2)
	_lean.z = clampf(_lean.z, -1.2, 1.2)

	model.rotation = _model_base_rotation + _lean
	# Поднять модель при наклоне, чтобы ноги не уходили под пол.
	var lift := (absf(sin(_lean.x)) + absf(sin(_lean.z))) * 0.38
	model.position = _model_base_position + Vector3(0.0, lift, 0.0)

	if model.has_method("tick_stumble_sway"):
		model.tick_stumble_sway(delta, _fallen)
