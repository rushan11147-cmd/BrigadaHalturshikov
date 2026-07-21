class_name DifficultyLibrary
extends RefCounted
## Каталог сложностей из res://data/difficulties/*.tres

const FOLDER := "res://data/difficulties"

var _list: Array[DifficultyDef] = []


func load_all() -> void:
	_list.clear()
	var loaded := ContentLibrary.load_resources(FOLDER, func(r): return r is DifficultyDef)
	for res in loaded:
		_list.append(res as DifficultyDef)
	_list.sort_custom(func(a: DifficultyDef, b: DifficultyDef): return a.rank < b.rank)
	print("[DifficultyLibrary] Сложностей: %d" % _list.size())


func all() -> Array[DifficultyDef]:
	return _list


func get_by_id(id: StringName) -> DifficultyDef:
	for d in _list:
		if d.id == id:
			return d
	if not _list.is_empty():
		return _list[0]
	return null
