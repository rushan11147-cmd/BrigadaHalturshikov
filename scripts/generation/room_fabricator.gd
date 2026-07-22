class_name RoomFabricator
extends RefCounted
## Собирает комнату-бокс. Двери только на указанных сторонах (±X).

const WALL_THICK := 0.25
const WALL_INSET := 0.85
const DOOR_W := 1.6
const DOOR_H := 2.2
## Лёгкий нахлёст кусков стены, чтобы не было щелей.
const SEAM := 0.02


static func fabricate(
	def: RoomDef,
	door_neg_x: bool = false,
	door_pos_x: bool = false
) -> Node3D:
	var root := Node3D.new()
	root.name = str(def.id)

	var size := def.size
	var half := size * 0.5

	_add_box(root, "Floor", Vector3(size.x, 0.2, size.z), Vector3(0, -0.1, 0), def.floor_color, true)

	# Глухие стены ±Z всегда.
	_add_solid_wall(root, "WallNegZ", Vector3(size.x + SEAM, size.y, WALL_THICK), Vector3(0, size.y * 0.5, -half.z), def.wall_color)
	_add_solid_wall(root, "WallPosZ", Vector3(size.x + SEAM, size.y, WALL_THICK), Vector3(0, size.y * 0.5, half.z), def.wall_color)

	# ±X: либо глухая, либо проём внутрь квартиры.
	if door_neg_x:
		_add_door_wall(root, "WallNegX", size, Vector3(-half.x, 0, 0), def.wall_color)
	else:
		_add_solid_wall(root, "WallNegX", Vector3(WALL_THICK, size.y, size.z + SEAM), Vector3(-half.x, size.y * 0.5, 0), def.wall_color)

	if door_pos_x:
		_add_door_wall(root, "WallPosX", size, Vector3(half.x, 0, 0), def.wall_color)
	else:
		_add_solid_wall(root, "WallPosX", Vector3(WALL_THICK, size.y, size.z + SEAM), Vector3(half.x, size.y * 0.5, 0), def.wall_color)

	var player_spawn := Marker3D.new()
	player_spawn.name = "PlayerSpawn"
	player_spawn.position = Vector3(0.0, 0.1, half.z * 0.25)
	root.add_child(player_spawn)

	var delivery := Marker3D.new()
	delivery.name = "DeliveryAnchor"
	delivery.position = Vector3(0.0, 0.05, -half.z * 0.35)
	root.add_child(delivery)

	_add_furniture_layout(root, size, half, def.furniture_slots)
	_add_job_pile_markers(root, half)

	return root


## Проём в стене вдоль Z (стена на ±X): два косяка + перемычка + порог.
static func _add_door_wall(parent: Node3D, wall_name: String, room_size: Vector3, wall_origin: Vector3, color: Color) -> void:
	var half_z := room_size.z * 0.5
	var side_len := (room_size.z - DOOR_W) * 0.5 + SEAM
	var x := wall_origin.x

	# Косяки (полные по высоте).
	if side_len > 0.05:
		var panel := Vector3(WALL_THICK, room_size.y, side_len)
		_add_solid_wall(parent, wall_name + "L", panel, Vector3(x, room_size.y * 0.5, -(DOOR_W * 0.5 + side_len * 0.5 - SEAM * 0.5)), color)
		_add_solid_wall(parent, wall_name + "R", panel, Vector3(x, room_size.y * 0.5, (DOOR_W * 0.5 + side_len * 0.5 - SEAM * 0.5)), color)

	# Перемычка над дверью.
	var lintel_h := maxf(room_size.y - DOOR_H, 0.35)
	var lintel := Vector3(WALL_THICK, lintel_h + SEAM, DOOR_W + SEAM * 2.0)
	_add_solid_wall(
		parent,
		wall_name + "Lintel",
		lintel,
		Vector3(x, DOOR_H + lintel_h * 0.5, 0.0),
		color
	)


static func _add_solid_wall(parent: Node3D, wall_name: String, size: Vector3, pos: Vector3, color: Color) -> void:
	_add_box(parent, wall_name, size, pos, color, true)


static func _add_furniture_layout(root: Node3D, size: Vector3, half: Vector3, slots: int) -> void:
	var layouts: Array[Dictionary] = []
	var door_clear := DOOR_W * 0.5 + 0.55

	# Крупное у задней стены: диван или шкаф (один слот).
	layouts.append({
		"pos": Vector3(0.0, 0.05, -half.z + WALL_INSET),
		"yaw": 0.0,
		"size": &"large",
	})
	# Второй large у угла задней стены — часто шкаф.
	if size.x >= 7.5:
		layouts.append({
			"pos": Vector3(-half.x + WALL_INSET + 0.5, 0.05, -half.z + WALL_INSET),
			"yaw": 0.0,
			"size": &"large",
		})

	var z_back := -half.z + WALL_INSET
	var z_front := half.z - WALL_INSET
	var x_left := -half.x + WALL_INSET + 0.15
	var x_right := half.x - WALL_INSET - 0.15
	var smalls: Array[Dictionary] = [
		{"pos": Vector3(x_left, 0.05, z_back), "yaw": 45.0},
		{"pos": Vector3(x_right, 0.05, z_back), "yaw": -45.0},
		{"pos": Vector3(-1.2, 0.05, z_back), "yaw": 0.0},
		{"pos": Vector3(1.2, 0.05, z_back), "yaw": 0.0},
		{"pos": Vector3(x_left, 0.05, z_front), "yaw": 135.0},
		{"pos": Vector3(x_right, 0.05, z_front), "yaw": -135.0},
	]

	if half.z > door_clear + 1.0:
		smalls.append({"pos": Vector3(x_left, 0.05, -door_clear - 0.4), "yaw": 90.0})
		smalls.append({"pos": Vector3(x_right, 0.05, -door_clear - 0.4), "yaw": -90.0})
		smalls.append({"pos": Vector3(x_left, 0.05, door_clear + 0.4), "yaw": 90.0})
		smalls.append({"pos": Vector3(x_right, 0.05, door_clear + 0.4), "yaw": -90.0})

	var max_small := maxi(slots - 1, 2)
	for i in mini(smalls.size(), max_small):
		var s: Dictionary = smalls[i]
		if absf(s.pos.x) > half.x - 1.1 and absf(s.pos.z) < door_clear:
			continue
		layouts.append({"pos": s.pos, "yaw": s.yaw, "size": &"small"})

	var idx := 0
	for layout in layouts:
		var m := Marker3D.new()
		m.name = "FurnitureSpawn_%d" % idx
		m.add_to_group("furniture_spawn")
		m.position = layout.pos
		m.set_meta("slot_size", layout.size)
		m.set_meta("face_yaw", layout.yaw)
		root.add_child(m)
		idx += 1


static func _add_job_pile_markers(root: Node3D, half: Vector3) -> void:
	var base := Vector3(half.x * 0.35, 0.05, half.z * 0.35)
	var offsets := [
		Vector3(0, 0, 0),
		Vector3(0.6, 0, 0),
		Vector3(0, 0, 0.6),
		Vector3(0.6, 0, 0.6),
		Vector3(0.3, 0, 0.3),
		Vector3(1.0, 0, 0.2),
	]
	for i in offsets.size():
		var m := Marker3D.new()
		m.name = "JobSpawn_%d" % i
		m.add_to_group("job_spawn")
		m.position = base + offsets[i]
		m.set_meta("slot_size", &"job")
		m.set_meta("face_yaw", 0.0)
		root.add_child(m)


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
