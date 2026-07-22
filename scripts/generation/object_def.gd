class_name ObjectDef
extends Resource
## Описание предмета/мебели. Новый .tres в data/objects/ — предмет в пуле спавна.

@export var id: StringName = &"object"
@export var display_name: String = "Предмет"
@export var scene: PackedScene
## Теги: furniture, clutter, job_item, heavy…
@export var tags: PackedStringArray = []
@export var spawn_weight: float = 1.0
@export var min_difficulty_rank: int = 0
## Случайный yaw при спавне (если маркер без face_yaw).
@export var random_yaw: bool = true
## Размер слота: small | large | any
@export var slot_size: StringName = &"small"
