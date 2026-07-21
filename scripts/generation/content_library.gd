class_name ContentLibrary
extends RefCounted
## Базовая загрузка Resource из папки (без правки кода при добавлении .tres).

static func load_resources(folder: String, type_check: Callable) -> Array[Resource]:
	var result: Array[Resource] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		push_warning("[ContentLibrary] Нет папки: %s" % folder)
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var path := folder.path_join(file_name)
			var res := load(path)
			if res is Resource and type_check.call(res):
				result.append(res)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result


static func pick_weighted(items: Array, weight_of: Callable, rng: RandomNumberGenerator) -> Variant:
	if items.is_empty():
		return null
	var total := 0.0
	for item in items:
		total += maxf(float(weight_of.call(item)), 0.0)
	if total <= 0.0:
		return items[rng.randi() % items.size()]
	var roll := rng.randf() * total
	var acc := 0.0
	for item in items:
		acc += maxf(float(weight_of.call(item)), 0.0)
		if roll <= acc:
			return item
	return items.back()
