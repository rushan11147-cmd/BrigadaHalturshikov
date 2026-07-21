class_name ObjectLibrary
extends RefCounted
## Каталог предметов из res://data/objects/*.tres

const FOLDER := "res://data/objects"

var _objects: Array[ObjectDef] = []


func load_all() -> void:
	_objects.clear()
	var loaded := ContentLibrary.load_resources(FOLDER, func(r): return r is ObjectDef)
	for res in loaded:
		_objects.append(res as ObjectDef)
	print("[ObjectLibrary] Загружено объектов: %d" % _objects.size())


func all_objects() -> Array[ObjectDef]:
	return _objects


func get_by_id(id: StringName) -> ObjectDef:
	for obj in _objects:
		if obj.id == id:
			return obj
	return null


func filter(rank: int, required_tags: PackedStringArray = []) -> Array[ObjectDef]:
	var out: Array[ObjectDef] = []
	for obj in _objects:
		if obj.scene == null:
			continue
		if obj.min_difficulty_rank > rank:
			continue
		if not required_tags.is_empty():
			var ok := false
			for tag in required_tags:
				if tag in obj.tags:
					ok = true
					break
			if not ok:
				continue
		out.append(obj)
	return out


func pick(rank: int, rng: RandomNumberGenerator, required_tags: PackedStringArray = []) -> ObjectDef:
	var pool := filter(rank, required_tags)
	if pool.is_empty():
		return null
	return ContentLibrary.pick_weighted(pool, func(o: ObjectDef): return o.spawn_weight, rng) as ObjectDef


func instantiate(def: ObjectDef, rng: RandomNumberGenerator = null) -> Node3D:
	if def == null or def.scene == null:
		return null
	var node := def.scene.instantiate() as Node3D
	if node == null:
		return null
	if def.random_yaw and rng != null:
		node.rotate_y(deg_to_rad(rng.randf_range(0.0, 360.0)))
	return node
