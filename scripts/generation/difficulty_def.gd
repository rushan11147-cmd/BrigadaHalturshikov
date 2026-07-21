class_name DifficultyDef
extends Resource
## Сложность смены. Новый .tres в data/difficulties/.

@export var id: StringName = &"normal"
@export var display_name: String = "Обычная"
## Чем выше rank, тем жёстче фильтры и миссии.
@export var rank: int = 1
@export var room_count: int = 3
@export_range(0.0, 1.0) var furniture_fill: float = 0.65
@export var mission_item_bonus: int = 0
@export var mission_time_bonus: float = 0.0
@export var event_interval_min: float = 18.0
@export var event_interval_max: float = 35.0
@export_range(0.0, 1.0) var event_chance: float = 0.7
@export_multiline var blurb: String = ""
