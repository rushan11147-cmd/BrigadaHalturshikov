class_name MissionDef
extends Resource
## Шаблон задания. Новый .tres в data/missions/ расширяет пул миссий.

@export var id: StringName = &"mission"
@export var display_name: String = "Заказ"
@export_multiline var description: String = "Выполните заказ."
## Тег предметов, которые нужно сдать (обычно job_item).
@export var item_tag: StringName = &"job_item"
@export var base_item_count: int = 3
@export var base_time_limit: float = 60.0
## Множители от сложности применяются в MissionGenerator.
@export var time_mult_per_rank: float = -5.0
@export var items_mult_per_rank: float = 1.0
@export var weight: float = 1.0
