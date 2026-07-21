extends CharacterBody3D
## PlayerController — третье лицо, Food Worker + WASD / мышь / прыжок.

const SPEED := 5.0
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const PUSH_FORCE := 4.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var grab_carry: Node3D = $CameraPivot/Camera3D/GrabCarry
@onready var model: Node3D = $Model

var _pitch: float = -8.0


func _ready() -> void:
	var is_local := is_multiplayer_authority()
	camera.current = is_local
	set_process_input(is_local)
	set_physics_process(true)
	camera_pivot.rotation_degrees.x = _pitch

	if is_local:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if get_tree().paused:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY * 60.0, -60.0, 40.0)
		camera_pivot.rotation_degrees.x = _pitch


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if not is_multiplayer_authority():
		move_and_slide()
		return

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := SPRINT_SPEED if Input.is_key_pressed(KEY_SHIFT) else SPEED

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	move_and_slide()
	_push_rigid_bodies()


func _push_rigid_bodies() -> void:
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
			var strength := PUSH_FORCE * clampf(8.0 / maxf(body.mass, 1.0), 0.15, 2.0)
			body.apply_central_impulse(push_dir * strength)
