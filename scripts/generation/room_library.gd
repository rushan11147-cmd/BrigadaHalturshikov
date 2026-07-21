class_name RoomLibrary
extends RefCounted
## Каталог комнат из res://data/rooms/*.tres

const FOLDER := "res://data/rooms"

var _rooms: Array[RoomDef] = []


func load_all() -> void:
	_rooms.clear()
	var loaded := ContentLibrary.load_resources(FOLDER, func(r): return r is RoomDef)
	for res in loaded:
		_rooms.append(res as RoomDef)
	print("[RoomLibrary] Загружено комнат: %d" % _rooms.size())


func all_rooms() -> Array[RoomDef]:
	return _rooms


func get_by_id(id: StringName) -> RoomDef:
	for room in _rooms:
		if room.id == id:
			return room
	return null


func filter(rank: int, required_tags: PackedStringArray = [], exclude_tags: PackedStringArray = []) -> Array[RoomDef]:
	var out: Array[RoomDef] = []
	for room in _rooms:
		if room.min_difficulty_rank > rank:
			continue
		if not _has_all_tags(room, required_tags):
			continue
		if _has_any_tag(room, exclude_tags):
			continue
		out.append(room)
	return out


func pick(rank: int, rng: RandomNumberGenerator, required_tags: PackedStringArray = []) -> RoomDef:
	var pool := filter(rank, required_tags)
	if pool.is_empty():
		pool = filter(rank)
	return ContentLibrary.pick_weighted(pool, func(r: RoomDef): return r.weight, rng) as RoomDef


func _has_all_tags(room: RoomDef, tags: PackedStringArray) -> bool:
	for tag in tags:
		if not tag in room.tags:
			return false
	return true


func _has_any_tag(room: RoomDef, tags: PackedStringArray) -> bool:
	for tag in tags:
		if tag in room.tags:
			return true
	return false
