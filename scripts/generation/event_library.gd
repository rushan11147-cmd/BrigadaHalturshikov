class_name EventLibrary
extends RefCounted
## Каталог событий из res://data/events/*.tres

const FOLDER := "res://data/events"

var _events: Array[EventDef] = []


func load_all() -> void:
	_events.clear()
	var loaded := ContentLibrary.load_resources(FOLDER, func(r): return r is EventDef)
	for res in loaded:
		_events.append(res as EventDef)
	print("[EventLibrary] Событий: %d" % _events.size())


func pick(rank: int, rng: RandomNumberGenerator) -> EventDef:
	var pool: Array[EventDef] = []
	for e in _events:
		if e.min_difficulty_rank <= rank:
			pool.append(e)
	if pool.is_empty():
		return null
	return ContentLibrary.pick_weighted(pool, func(e: EventDef): return e.weight, rng) as EventDef
