class_name RoomFabricator
extends RefCounted
## Собирает простую комнату-бокс, если у RoomDef нет своей сцены.
## Маркеры: PlayerSpawn, DeliveryAnchor, FurnitureSpawn_*

const WALL_THICK := 0.25


static func fabricate(def: RoomDef) -> Node3D:
	var root := Node3D.new()
	root.name = str(def.id)

	var size := def.size
	var half := size * 0.5

	_add_box(root, "Floor", Vector3(size.x, 0.2, size.z), Vector3(0, -0.1, 0), def.floor_color, true)
	_add_box(root, "Ceiling", Vector3(size.x, 0.15, size.z), Vector3(0, size.y, 0), Color(0.85, 0.85, 0.82), true)

	# Стены; на +X и -X — дверные проёмы (линейная квартира).
	_add_wall_with_door(root, "WallNegZ", Vector3(size.x, size.y, WALL_THICK), Vector3(0, size.y * 0.5, -half.z), def.wall_color, false)
	_add_wall_with_door(root, "WallPosZ", Vector3(size.x, size.y, WALL_THICK), Vector3(0, size.y * 0.5, half.z), def.wall_color, false)
	_add_wall_with_door(root, "WallNegX", Vector3(WALL_THICK, size.y, size.z), Vector3(-half.x, size.y * 0.5, 0), def.wall_color, true)
	_add_wall_with_door(root, "WallPosX", Vector3(WALL_THICK, size.y, size.z), Vector3(half.x, size.y * 0.5, 0), def.wall_color, true)

	var player_spawn := Marker3D.new()
	player_spawn.name = "PlayerSpawn"
	player_spawn.position = Vector3(0.0, 0.1, half.z * 0.35)
	root.add_child(player_spawn)

	var delivery := Marker3D.new()
	delivery.name = "DeliveryAnchor"
	delivery.position = Vector3(0.0, 0.05, -half.z * 0.35)
	root.add_child(delivery)

	var slots := maxi(def.furniture_slots, 0)
	for i in slots:
		var m := Marker3D.new()
		m.name = "FurnitureSpawn_%d" % i
		m.add_to_group("furniture_spawn")
		var angle := TAU * float(i) / float(maxi(slots, 1))
		var radius := minf(size.x, size.z) * 0.28
		m.position = Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
		root.add_child(m)

	return root


static func _add_wall_with_door(
	parent: Node3D, wall_name: String, full_size: Vector3, pos: Vector3, color: Color, doorway: bool
) -> void:
	if not doorway:
		_add_box(parent, wall_name, full_size, pos, color, true)
		return
	# Два столба по бокам проёма ~1.4 м.
	var door_w := 1.5
	if full_size.z >= full_size.x:
		# Стена вдоль Z — режем по Z.
		var side := (full_size.z - door_w) * 0.5
		if side > 0.05:
			var s := Vector3(full_size.x, full_size.y, side)
			_add_box(parent, wall_name + "A", s, pos + Vector3(0, 0, -(door_w + side) * 0.5), color, true)
			_add_box(parent, wall_name + "B", s, pos + Vector3(0, 0, (door_w + side) * 0.5), color, true)
		# Перемычка над дверью.
		var lintel := Vector3(full_size.x, full_size.y * 0.35, door_w)
		_add_box(parent, wall_name + "Lintel", lintel, pos + Vector3(0, full_size.y * 0.325, 0), color, true)
	else:
		var side := (full_size.x - door_w) * 0.5
		if side > 0.05:
			var s := Vector3(side, full_size.y, full_size.z)
			_add_box(parent, wall_name + "A", s, pos + Vector3(-(door_w + side) * 0.5, 0, 0), color, true)
			_add_box(parent, wall_name + "B", s, pos + Vector3((door_w + side) * 0.5, 0, 0), color, true)
		var lintel := Vector3(door_w, full_size.y * 0.35, full_size.z)
		_add_box(parent, wall_name + "Lintel", lintel, pos + Vector3(0, full_size.y * 0.325, 0), color, true)


static func _add_box(
	parent: Node3D, box_name: String, size: Vector3, pos: Vector3, color: Color, static_body: bool
) -> void:
	var body: CollisionObject3D
	if static_body:
		body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
	else:
		body = AnimatableBody3D.new()
	body.name = box_name
	body.position = pos
	parent.add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh_i := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_i.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_i.material_override = mat
	body.add_child(mesh_i)
