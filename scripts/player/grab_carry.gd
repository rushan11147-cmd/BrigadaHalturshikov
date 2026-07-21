extends Node3D
## GrabCarry — E: взять / мягко отпустить · ЛКМ: бросить.
## Физика предмета — в PhysicalObject.

const REACH := 4.5
const HOLD_DISTANCE := 1.9
const MAX_CARRY_MASS := 25.0
const RELEASE_PUSH := 1.2
const THROW_IMPULSE := 11.0
const PICKUP_MASK := 4

@onready var camera: Camera3D = get_parent() as Camera3D
@onready var ray: RayCast3D = $RayCast3D
@onready var hold_point: Marker3D = $HoldPoint

var _held: PhysicalObject = null
var _e_was_down: bool = false


func _ready() -> void:
	ray.target_position = Vector3(0.0, 0.0, -REACH)
	ray.collision_mask = PICKUP_MASK
	ray.enabled = true
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	hold_point.position = Vector3(0.0, -0.15, -HOLD_DISTANCE)


func _physics_process(_delta: float) -> void:
	var player := _get_player()
	if player == null or not player.is_multiplayer_authority():
		return

	if _was_interact_just_pressed():
		if _held != null and is_instance_valid(_held):
			_drop()
		else:
			_try_grab()

	# ЛКМ — сильный бросок (только если что-то несём).
	if _held != null and is_instance_valid(_held) and Input.is_action_just_pressed("throw"):
		_throw()

	if _held != null and is_instance_valid(_held):
		_held.global_transform = Transform3D(
			hold_point.global_transform.basis,
			hold_point.global_position
		)
		_held.linear_velocity = Vector3.ZERO
		_held.angular_velocity = Vector3.ZERO
	elif _held != null:
		_held = null


func _was_interact_just_pressed() -> bool:
	if Input.is_action_just_pressed("interact"):
		_e_was_down = Input.is_physical_key_pressed(KEY_E)
		return true
	var down := Input.is_physical_key_pressed(KEY_E)
	var just := down and not _e_was_down
	_e_was_down = down
	return just


func _try_grab() -> void:
	var target := _get_look_target()
	if target == null:
		return

	if not target.can_be_carried_by(MAX_CARRY_MASS):
		print("[GrabCarry] Слишком тяжело: %s (%.0f кг)" % [
			target.display_name, target.object_mass
		])
		return

	if NetworkManager.is_online() and not multiplayer.is_server():
		rpc_request_grab.rpc_id(1, target.get_path())
	else:
		_grab(target)


func _grab(obj: PhysicalObject) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	if not obj.can_be_carried_by(MAX_CARRY_MASS):
		return
	if obj.is_delivered():
		return

	obj.begin_grab(multiplayer.get_unique_id())
	obj.global_position = hold_point.global_position
	_held = obj
	print("[GrabCarry] Взяли: %s" % obj.display_name)


## Мягко отпустить (E).
func _drop() -> void:
	_release(-camera.global_transform.basis.z * RELEASE_PUSH)


## Сильно бросить (ЛКМ).
func _throw() -> void:
	var dir := -camera.global_transform.basis.z
	# Чуть вверх — смешнее дуга.
	dir = (dir + Vector3.UP * 0.25).normalized()
	var mass := _held.mass if _held else 1.0
	_release(dir * THROW_IMPULSE * clampf(mass * 0.35, 1.0, 4.0))


func _release(velocity: Vector3) -> void:
	if _held == null:
		return
	var obj := _held
	_held = null
	obj.end_grab(velocity)
	if NetworkManager.is_online() and not multiplayer.is_server():
		rpc_notify_release.rpc(obj.get_path(), obj.global_position, velocity)
	print("[GrabCarry] Отпустили: %s" % obj.display_name)


func _get_look_target() -> PhysicalObject:
	if ray.is_colliding():
		var obj := _as_physical(ray.get_collider())
		if obj:
			return obj

	if camera == null or camera.get_world_3d() == null:
		return null

	var space := camera.get_world_3d().direct_space_state
	var origin := camera.global_position
	var end := origin + (-camera.global_transform.basis.z * REACH)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = PICKUP_MASK
	query.collide_with_bodies = true
	var player := _get_player()
	if player != null:
		query.exclude = [player.get_rid()]

	var result := space.intersect_ray(query)
	if result.is_empty():
		return null
	return _as_physical(result.get("collider"))


func _as_physical(node: Variant) -> PhysicalObject:
	if node is PhysicalObject:
		return node as PhysicalObject
	if node is RigidBody3D and (node as Node).is_in_group("physical_object"):
		return node as PhysicalObject
	return null


func _get_player() -> CharacterBody3D:
	var node: Node = self
	while node != null:
		if node is CharacterBody3D:
			return node as CharacterBody3D
		node = node.get_parent()
	return null


func _resolve(path: NodePath) -> Node:
	return get_tree().root.get_node_or_null(path)


@rpc("any_peer", "reliable")
func rpc_request_grab(object_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var node := _resolve(object_path)
	if node is PhysicalObject and (node as PhysicalObject).can_be_carried_by(MAX_CARRY_MASS):
		rpc_confirm_grab.rpc_id(multiplayer.get_remote_sender_id(), object_path)


@rpc("authority", "reliable")
func rpc_confirm_grab(object_path: NodePath) -> void:
	var node := _resolve(object_path)
	if node is PhysicalObject:
		_grab(node as PhysicalObject)


@rpc("any_peer", "reliable", "call_local")
func rpc_notify_release(object_path: NodePath, pos: Vector3, vel: Vector3) -> void:
	var node := _resolve(object_path)
	if node is PhysicalObject:
		var obj := node as PhysicalObject
		if obj.is_held():
			obj.global_position = pos
			obj.end_grab(vel)
