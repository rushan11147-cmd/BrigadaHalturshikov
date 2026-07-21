extends Area3D
## DeliveryZone — зелёная зона сдачи заказа.
## Срабатывает, когда PhysicalObject (job_item) лежит внутри и не в руках.

signal item_delivered(item: PhysicalObject)

@export var require_still: bool = true
@export var max_speed_to_accept: float = 2.5


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	# Ловим предметы (слой 4) и всё остальное на всякий случай.
	collision_mask = 4
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	_try_accept(body)


func _physics_process(_delta: float) -> void:
	# Пока предмет в зоне и остановился — принимаем (если кинули и катится).
	for body in get_overlapping_bodies():
		_try_accept(body)


func _try_accept(body: Node) -> void:
	if body == null or not body is PhysicalObject:
		return
	var item := body as PhysicalObject
	if item.is_delivered() or item.is_held():
		return
	if not item.counts_for_job:
		return
	if require_still and item.linear_velocity.length() > max_speed_to_accept:
		return

	item.mark_delivered()
	item_delivered.emit(item)
	print("[DeliveryZone] Сдано: %s" % item.display_name)
