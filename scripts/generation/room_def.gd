class_name RoomDef
extends Resource
## Описание модульной комнаты. Новый .tres в data/rooms/ — комната появляется в генерации.

@export var id: StringName = &"room"
@export var display_name: String = "Комната"
## Если задано — инстанс этой сцены. Иначе комната собирается процедурно по size.
@export var scene: PackedScene
@export var size: Vector3 = Vector3(8.0, 3.0, 8.0)
@export var wall_color: Color = Color(0.78, 0.74, 0.68)
@export var floor_color: Color = Color(0.45, 0.42, 0.38)
## Теги: start, delivery, living, kitchen, bedroom, hallway…
@export var tags: PackedStringArray = []
## Сколько точек мебели создать при процедурной сборке.
@export var furniture_slots: int = 6
## Вес выбора генератором.
@export var weight: float = 1.0
@export var min_difficulty_rank: int = 0
