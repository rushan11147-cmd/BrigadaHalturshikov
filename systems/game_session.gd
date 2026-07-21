extends Node
## GameSession — настройки смены между меню и уровнем (autoload).

var difficulty_id: StringName = &"normal"
## -1 = случайный сид при генерации.
var level_seed: int = -1
var last_seed: int = 0


func set_difficulty(id: StringName) -> void:
	difficulty_id = id
	print("[Session] Сложность: %s" % id)


func randomize_seed() -> void:
	level_seed = -1
