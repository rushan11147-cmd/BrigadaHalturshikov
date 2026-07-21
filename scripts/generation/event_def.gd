class_name EventDef
extends Resource
## Случайное событие смены. Новый .tres в data/events/.

enum EventType {
	MESSAGE, ## Только сообщение в HUD/статус
	SPAWN_OBJECT, ## Заспавнить объект по object_id у игрока / в комнате
	IMPULSE_TAG, ## Толкнуть все объекты с тегом
	TIME_BONUS, ## Добавить/убавить время заказа
}

@export var id: StringName = &"event"
@export var display_name: String = "Событие"
@export_multiline var message: String = ""
@export var event_type: EventType = EventType.MESSAGE
@export var weight: float = 1.0
@export var min_difficulty_rank: int = 0
## Для SPAWN_OBJECT — id из ObjectLibrary.
@export var object_id: StringName = &""
## Для IMPULSE_TAG.
@export var target_tag: StringName = &"physical_object"
@export var impulse_strength: float = 6.0
## Для TIME_BONUS (может быть отрицательным).
@export var time_delta: float = 0.0
