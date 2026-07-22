extends Node3D
## GrabCarry — предмет перед телом; лёгкое покачивание, сброс при падении игрока.

const REACH := 4.5
const MAX_CARRY_MASS := 25.0
const RELEASE_PUSH := 1.2
const THROW_IMPULSE := 11.0
const PICKUP_MASK := 4
const HOLD_FORWARD := 0.12
const NEAR_GRAB_RADIUS := 1.35
const NEAR_GRAB_FORWARD := 1.1
## Лёгкий «живой» люфт от ускорения (не ломает перенос).
const SWAY_FROM_ACCEL := 0.018
const SWAY_MAX := 0.22

@onready var camera: Camera3D = get_parent() as Camera3D
@onready var ray: RayCast3D = $RayCast3D

var _held: PhysicalObject = null
var _e_was_down: bool = false
var _carry_point: Marker3D
var _hold_offset: Vector3 = Vector3.ZERO
var _prev_player_vel: Vector3 = Vector3.ZERO
var _sway: Vector3 = Vector3.ZERO


func _ready() -> void:
	ray.target_position = Vector3(0.0, 0.0, -REACH)
	ray.collision_mask = PICKUP_MASK
	ray.enabled = true
	ray.collide_with_areas = false
	ray.collide_with_bodies = true

	var player := _get_player()
	if player != null:
		_carry_point = player.get_node_or_null("CarryPoint") as Marker3D


func _physics_process(delta: float) -> void:
	var player := _get_player()
	if player == null or not player.is_multiplayer_authority():
		return

	if _carry_point == null:
		_carry_point = player.get_node_or_null("CarryPoint") as Marker3D

	if _was_interact_just_pressed():
		if _held != null and is_instance_valid(_held):
			_drop()
		else:
			_try_grab()

	if _held != null and is_instance_valid(_held) and Input.is_action_just_pressed("throw"):
		_throw()

	if _held != null and is_instance_valid(_held):
		_update_held_transform(player, delta)
	elif _held != null:
		_held = null

	_prev_player_vel = player.velocity


func _update_held_transform(player: CharacterBody3D, delta: float) -> void:
	if _carry_point == null or _held == null:
		return

	var basis := player.global_transform.basis
	var accel := (player.velocity - _prev_player_vel) / maxf(delta, 0.0001)
	var target_sway := -accel * SWAY_FROM_ACCEL * clampf(_held.object_mass / 10.0, 0.5, 1.6)
	target_sway.y = clampf(target_sway.y, -0.12, 0.08)
	target_sway.x = clampf(target_sway.x, -SWAY_MAX, SWAY_MAX)
	target_sway.z = clampf(target_sway.z, -SWAY_MAX, SWAY_MAX)
	_sway = _sway.lerp(target_sway, clampf(delta * 10.0, 0.0, 1.0))

	var pos := _carry_point.global_position \
		+ basis * Vector3(0.0, 0.0, -HOLD_FORWARD) \
		+ basis * _hold_offset \
		+ _sway
	var hold_basis := Basis.from_euler(Vector3(0.0, player.global_rotation.y, 0.0))
	_held.global_transform = Transform3D(hold_basis, pos)
	_held.linear_velocity = Vector3.ZERO
	_held.angular_velocity = Vector3.ZERO


func is_carrying() -> bool:
	return _held != null and is_instance_valid(_held)


## Принудительный сброс (спотыкание / падение игрока).
func force_drop(extra_velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_carrying():
		return
	_release(extra_velocity)


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
	_hold_offset = _estimate_hold_offset(obj)
	_held = obj
	_sway = Vector3.ZERO
	var player := _get_player()
	if player != null:
		_update_held_transform(player, 0.016)
	print("[GrabCarry] Взяли: %s" % obj.display_name)


func _estimate_hold_offset(obj: PhysicalObject) -> Vector3:
	var shape_node := obj.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return Vector3(0.0, -0.25, 0.0)
	return -shape_node.position


func _drop() -> void:
	var player := _get_player()
	var forward := Vector3.FORWARD
	if player != null:
		forward = -player.global_transform.basis.z
	_release(forward * RELEASE_PUSH + Vector3.UP * 0.4)


func _throw() -> void:
	var dir := -camera.global_transform.basis.z
	dir = (dir + Vector3.UP * 0.28).normalized()
	var mass := _held.mass if _held else 1.0
	_release(dir * THROW_IMPULSE * clampf(mass * 0.35, 1.0, 4.0))


func _release(velocity: Vector3) -> void:
	if _held == null:
		return
	var obj := _held
	_held = null
	_hold_offset = Vector3.ZERO
	_sway = Vector3.ZERO
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
	if not result.is_empty():
		var hit := _as_physical(result.get("collider"))
		if hit:
			return hit

	return _get_near_target(player)


func _as_physical(node: Variant) -> PhysicalObject:
	if node is PhysicalObject:
		return node as PhysicalObject
	if node is RigidBody3D and (node as Node).is_in_group("physical_object"):
		return node as PhysicalObject
	return null


func _get_near_target(player: CharacterBody3D) -> PhysicalObject:
	if player == null or player.get_world_3d() == null:
		return null
	var space := player.get_world_3d().direct_space_state
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var center := player.global_position + Vector3.UP * 0.45 + forward * NEAR_GRAB_FORWARD
	var shape := SphereShape3D.new()
	shape.radius = NEAR_GRAB_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = PICKUP_MASK
	params.collide_with_bodies = true
	params.exclude = [player.get_rid()]

	var hits := space.intersect_shape(params, 12)
	var best: PhysicalObject = null
	var best_dist := INF
	for hit in hits:
		var obj := _as_physical(hit.get("collider"))
		if obj == null or not obj.can_be_carried_by(MAX_CARRY_MASS):
			continue
		if obj.is_delivered():
			continue
		var d := player.global_position.distance_squared_to(obj.global_position)
		if d < best_dist:
			best_dist = d
			best = obj
	return best


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
