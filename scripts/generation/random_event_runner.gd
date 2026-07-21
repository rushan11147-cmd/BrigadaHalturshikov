class_name RandomEventRunner
extends Node
## RandomEventRunner — периодически выбирает EventDef и применяет эффект.

signal event_fired(event: EventDef)

var _library: EventLibrary
var _difficulty: DifficultyDef
var _rng := RandomNumberGenerator.new()
var _timer: float = 20.0
var _job: Node
var _level_root: Node3D
var _objects: ObjectLibrary


func setup(
	library: EventLibrary,
	difficulty: DifficultyDef,
	job_manager: Node,
	level_root: Node3D,
	object_library: ObjectLibrary,
	seed_value: int
) -> void:
	_library = library
	_difficulty = difficulty
	_job = job_manager
	_level_root = level_root
	_objects = object_library
	_rng.seed = seed_value + 97
	_timer = _rng.randf_range(difficulty.event_interval_min, difficulty.event_interval_max)
	set_process(true)


func _process(delta: float) -> void:
	if _library == null or _difficulty == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(_difficulty.event_interval_min, _difficulty.event_interval_max)
	if _rng.randf() > _difficulty.event_chance:
		return
	var ev := _library.pick(_difficulty.rank, _rng)
	if ev != null:
		_apply(ev)


func _apply(ev: EventDef) -> void:
	event_fired.emit(ev)
	match ev.event_type:
		EventDef.EventType.MESSAGE:
			_notify(ev.message if ev.message != "" else ev.display_name)
		EventDef.EventType.SPAWN_OBJECT:
			_spawn_near_player(ev)
			_notify(ev.message if ev.message != "" else "Ой… откуда это?")
		EventDef.EventType.IMPULSE_TAG:
			_impulse_tag(ev)
			_notify(ev.message if ev.message != "" else "Что за тряска?!")
		EventDef.EventType.TIME_BONUS:
			_time_bonus(ev)
			_notify(ev.message if ev.message != "" else "Время изменилось!")
	print("[Event] %s" % ev.id)


func _notify(text: String) -> void:
	if _job != null and _job.has_method("push_status"):
		_job.push_status(text)
	elif _job != null and _job.has_signal("status_message"):
		_job.status_message.emit(text)


func _spawn_near_player(ev: EventDef) -> void:
	if _objects == null or _level_root == null:
		return
	var def := _objects.get_by_id(ev.object_id)
	if def == null:
		def = _objects.pick(_difficulty.rank, _rng, PackedStringArray(["clutter", "job_item"]))
	var node := _objects.instantiate(def, _rng)
	if node == null:
		return
	_level_root.add_child(node)
	var players := get_tree().get_nodes_in_group("player")
	var pos := _level_root.global_position + Vector3(0, 1.2, 0)
	if not players.is_empty() and players[0] is Node3D:
		pos = (players[0] as Node3D).global_position + Vector3(0, 1.5, -1.2)
	node.global_position = pos


func _impulse_tag(ev: EventDef) -> void:
	var tag := str(ev.target_tag)
	for n in get_tree().get_nodes_in_group(tag):
		if n is RigidBody3D and not (n as RigidBody3D).freeze:
			var dir := Vector3(_rng.randf_range(-1, 1), 0.4, _rng.randf_range(-1, 1)).normalized()
			(n as RigidBody3D).apply_central_impulse(dir * ev.impulse_strength * (n as RigidBody3D).mass * 0.15)


func _time_bonus(ev: EventDef) -> void:
	if _job != null and _job.has_method("add_time"):
		_job.add_time(ev.time_delta)
