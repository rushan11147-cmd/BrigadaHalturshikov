extends Node
## JobManager — заказ: перенеси N предметов в зону за T секунд.

signal job_started(goal: int, time_limit: float)
signal progress_changed(delivered: int, goal: int)
signal time_changed(seconds_left: float)
signal job_won(delivered: int, time_left: float)
signal job_lost(delivered: int)
signal status_message(text: String)

@export var goal_count: int = 3
@export var time_limit: float = 60.0

var _delivered: int = 0
var _time_left: float = 60.0
var _running: bool = false
var _finished: bool = false


func _ready() -> void:
	set_process(false)


func configure(plan) -> void:
	if plan == null:
		return
	goal_count = plan.item_count
	time_limit = plan.time_limit


func start_job() -> void:
	_delivered = 0
	_time_left = time_limit
	_running = true
	_finished = false
	set_process(true)
	job_started.emit(goal_count, time_limit)
	progress_changed.emit(_delivered, goal_count)
	time_changed.emit(_time_left)
	status_message.emit("Заказ: сдайте %d шт. в зелёную зону!" % goal_count)
	print("[Job] Старт: %d шт. / %.0f сек." % [goal_count, time_limit])


func push_status(text: String) -> void:
	status_message.emit(text)


func add_time(delta_sec: float) -> void:
	if _finished:
		return
	_time_left = maxf(_time_left + delta_sec, 0.0)
	time_changed.emit(_time_left)
	if _time_left <= 0.0:
		_fail()


func restart_job() -> void:
	get_tree().reload_current_scene()


func register_delivery_zone(zone: Node) -> void:
	if zone != null and zone.has_signal("item_delivered"):
		if not zone.item_delivered.is_connected(_on_item_delivered):
			zone.item_delivered.connect(_on_item_delivered)


func _process(delta: float) -> void:
	if not _running or _finished:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	time_changed.emit(_time_left)
	if _time_left <= 0.0:
		_fail()


func _on_item_delivered(_item) -> void:
	if _finished or not _running:
		return
	_delivered += 1
	progress_changed.emit(_delivered, goal_count)
	status_message.emit("Сдано %d / %d" % [_delivered, goal_count])
	if _delivered >= goal_count:
		_win()


func _win() -> void:
	_finished = true
	_running = false
	job_won.emit(_delivered, _time_left)
	status_message.emit("ГОТОВО! Бригада справилась. R — ещё раз")
	print("[Job] Победа! Осталось %.1f сек." % _time_left)


func _fail() -> void:
	_finished = true
	_running = false
	job_lost.emit(_delivered)
	status_message.emit("Время вышло! Сдано %d/%d. R — заново" % [_delivered, goal_count])
	print("[Job] Провал.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_job"):
		restart_job()
