class_name LevelGenerator
extends Node
## Собирает квартиру из RoomLibrary + мебель из ObjectLibrary + миссию.
##
## Расширение без кода:
##   data/rooms/*.tres · data/objects/*.tres · data/missions/*.tres
##   data/difficulties/*.tres · data/events/*.tres

signal generation_finished(plan: MissionPlan)
signal status_message(text: String)

const DELIVERY_ZONE_SCENE := preload("res://scenes/world/DeliveryZone.tscn")

@export var level_root_path: NodePath = NodePath("../GeneratedLevel")
@export var seed_override: int = -1

var rooms: RoomLibrary = RoomLibrary.new()
var objects: ObjectLibrary = ObjectLibrary.new()
var missions: MissionGenerator = MissionGenerator.new()
var events: EventLibrary = EventLibrary.new()
var difficulties: DifficultyLibrary = DifficultyLibrary.new()

var _rng := RandomNumberGenerator.new()
var _plan: MissionPlan
var _difficulty: DifficultyDef
var _spawned_rooms: Array[Node3D] = []
var player_spawn_global: Vector3 = Vector3.ZERO
var delivery_zone: Area3D = null


func _ready() -> void:
	rooms.load_all()
	objects.load_all()
	missions.load_all()
	events.load_all()
	difficulties.load_all()


func get_plan() -> MissionPlan:
	return _plan


func get_difficulty() -> DifficultyDef:
	return _difficulty


func get_event_library() -> EventLibrary:
	return events


func generate(difficulty_id: StringName = &"") -> MissionPlan:
	_difficulty = difficulties.get_by_id(
		difficulty_id if difficulty_id != &"" else GameSession.difficulty_id
	)
	if _difficulty == null:
		_difficulty = _make_fallback_difficulty()

	var seed_value := seed_override
	if seed_value < 0:
		seed_value = GameSession.level_seed
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system())
	_rng.seed = seed_value
	GameSession.last_seed = seed_value

	_plan = missions.generate(_difficulty, _rng)
	var root := _get_level_root()
	_clear_children(root)
	_spawned_rooms.clear()
	delivery_zone = null

	var room_defs := _pick_room_sequence()
	_build_rooms(root, room_defs)
	_populate_furniture()
	_spawn_job_items()
	_place_delivery_zone()

	generation_finished.emit(_plan)
	status_message.emit("%s · %s" % [_difficulty.display_name, _plan.title])
	print("[LevelGenerator] seed=%d rooms=%d items=%d" % [
		seed_value, _spawned_rooms.size(), _plan.item_count
	])
	return _plan


func _pick_room_sequence() -> Array[RoomDef]:
	var count := maxi(_difficulty.room_count, 1)
	var sequence: Array[RoomDef] = []

	var start := rooms.pick(_difficulty.rank, _rng, PackedStringArray(["start"]))
	if start == null:
		start = rooms.pick(_difficulty.rank, _rng)
	if start != null:
		sequence.append(start)

	while sequence.size() < count - 1:
		var mid := rooms.pick(_difficulty.rank, _rng, PackedStringArray([]))
		# Избегаем дублирования start/delivery в середине, если есть выбор.
		if mid != null:
			sequence.append(mid)
		else:
			break

	if sequence.size() < count:
		var end := rooms.pick(_difficulty.rank, _rng, PackedStringArray(["delivery"]))
		if end == null:
			end = rooms.pick(_difficulty.rank, _rng)
		if end != null:
			sequence.append(end)

	# Гарантия хотя бы одной комнаты.
	if sequence.is_empty():
		var fallback := RoomDef.new()
		fallback.id = &"fallback"
		fallback.display_name = "Комната"
		fallback.tags = PackedStringArray(["start", "delivery"])
		fallback.furniture_slots = 5
		sequence.append(fallback)
	return sequence


func _build_rooms(root: Node3D, defs: Array[RoomDef]) -> void:
	var cursor_x := 0.0
	player_spawn_global = Vector3.ZERO

	# Одна ширина/глубина на всю квартиру — иначе на стыках дыры в небо.
	var cell := Vector3(8.0, 3.0, 8.0)
	for def in defs:
		cell.x = maxf(cell.x, def.size.x)
		cell.y = maxf(cell.y, def.size.y)
		cell.z = maxf(cell.z, def.size.z)

	for i in defs.size():
		var def := defs[i]
		var door_neg := i > 0
		var door_pos := i < defs.size() - 1
		var room := _instance_room(def, cell, door_neg, door_pos)
		room.position = Vector3(cursor_x, 0.0, 0.0)
		root.add_child(room)
		_spawned_rooms.append(room)

		var spawn := room.find_child("PlayerSpawn", true, false) as Marker3D
		if spawn != null and (i == 0 or player_spawn_global == Vector3.ZERO):
			player_spawn_global = spawn.global_position

		cursor_x += cell.x


func _instance_room(
	def: RoomDef,
	cell_size: Vector3,
	door_neg_x: bool,
	door_pos_x: bool
) -> Node3D:
	if def.scene != null:
		var inst := def.scene.instantiate() as Node3D
		if inst != null:
			inst.name = str(def.id)
			return inst
	var sized := def.duplicate() as RoomDef
	sized.size = cell_size
	return RoomFabricator.fabricate(sized, door_neg_x, door_pos_x)


func _populate_furniture() -> void:
	var fill := _difficulty.furniture_fill
	for room in _spawned_rooms:
		var markers := _get_furniture_markers(room)
		var used_large_ids: Array[StringName] = []
		for marker in markers:
			if _rng.randf() > fill:
				continue
			var slot: StringName = &"small"
			if marker.has_meta("slot_size"):
				slot = marker.get_meta("slot_size") as StringName
			var tags := PackedStringArray(["furniture"])
			if slot == &"large":
				tags = PackedStringArray(["furniture", "heavy"])
			var def := objects.pick(_difficulty.rank, _rng, tags, slot)
			# Не ставить два одинаковых крупных подряд (два дивана).
			if slot == &"large" and def != null and def.id in used_large_ids:
				var alt := objects.pick(_difficulty.rank, _rng, tags, slot)
				if alt != null and alt.id not in used_large_ids:
					def = alt
				elif alt != null and used_large_ids.size() > 0:
					# Если альтернативы нет — пропуск второго large.
					continue
			if def == null:
				def = objects.pick(_difficulty.rank, _rng, PackedStringArray(["furniture"]), &"small")
			if def == null:
				continue
			if &"job_item" in def.tags and not (&"furniture" in def.tags):
				continue
			var yaw: Variant = null
			if marker.has_meta("face_yaw"):
				yaw = marker.get_meta("face_yaw")
			var node := objects.instantiate(def, _rng, yaw)
			if node == null:
				continue
			room.add_child(node)
			var lift := 0.02
			if def.slot_size == &"large":
				lift = 0.05
				used_large_ids.append(def.id)
			node.global_position = marker.global_position + Vector3(0, lift, 0)


func _spawn_job_items() -> void:
	if _spawned_rooms.is_empty():
		return
	var start_room := _spawned_rooms[0]
	var markers := _get_job_markers(start_room)

	for i in _plan.item_count:
		var def := objects.pick(_difficulty.rank, _rng, PackedStringArray([str(_plan.item_tag)]))
		if def == null:
			def = objects.get_by_id(&"box")
		var node := objects.instantiate(def, _rng, 0.0)
		if node == null:
			continue
		start_room.add_child(node)
		var pos: Vector3
		if i < markers.size():
			pos = markers[i].global_position + Vector3(0, 0.28, 0)
		else:
			# Запасная куча рядом со спавном.
			var spawn := start_room.find_child("PlayerSpawn", true, false) as Marker3D
			var base := start_room.global_position + Vector3(1.2, 0.28, 1.0)
			if spawn != null:
				base = spawn.global_position + Vector3(1.2, 0.28, -0.4)
			pos = base + Vector3((i % 3) * 0.6, 0.0, (i / 3) * 0.6)
		node.global_position = pos
		if node is PhysicalObject:
			(node as PhysicalObject).counts_for_job = true
			(node as PhysicalObject).add_to_group("job_item")


func _place_delivery_zone() -> void:
	if _spawned_rooms.is_empty():
		return
	var room: Node3D = _spawned_rooms[_spawned_rooms.size() - 1]
	var anchor := room.find_child("DeliveryAnchor", true, false) as Marker3D
	var zone := DELIVERY_ZONE_SCENE.instantiate() as Area3D
	room.add_child(zone)
	if anchor != null:
		zone.global_position = anchor.global_position
	else:
		zone.position = Vector3(0.0, 0.0, -1.5)
	delivery_zone = zone


func _get_level_root() -> Node3D:
	var node := get_node_or_null(level_root_path) as Node3D
	if node == null:
		node = Node3D.new()
		node.name = "GeneratedLevel"
		get_parent().add_child(node)
	return node


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()


func _get_furniture_markers(room: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in room.get_children():
		if child is Node3D and (
			child.is_in_group("furniture_spawn") or str(child.name).begins_with("FurnitureSpawn")
		):
			out.append(child as Node3D)
	return out


func _get_job_markers(room: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in room.get_children():
		if child is Node3D and (
			child.is_in_group("job_spawn") or str(child.name).begins_with("JobSpawn")
		):
			out.append(child as Node3D)
	return out


func _make_fallback_difficulty() -> DifficultyDef:
	var d := DifficultyDef.new()
	d.id = &"normal"
	d.display_name = "Обычная"
	d.rank = 1
	d.room_count = 3
	d.furniture_fill = 0.6
	return d
