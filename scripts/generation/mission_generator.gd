class_name MissionGenerator
extends RefCounted
## Собирает MissionPlan из data/missions + DifficultyDef.

const FOLDER := "res://data/missions"

var _missions: Array[MissionDef] = []


func load_all() -> void:
	_missions.clear()
	var loaded := ContentLibrary.load_resources(FOLDER, func(r): return r is MissionDef)
	for res in loaded:
		_missions.append(res as MissionDef)
	print("[MissionGenerator] Шаблонов миссий: %d" % _missions.size())


func generate(difficulty: DifficultyDef, rng: RandomNumberGenerator) -> MissionPlan:
	var plan := MissionPlan.new()
	plan.difficulty_id = difficulty.id if difficulty else &"normal"

	var def: MissionDef = null
	if not _missions.is_empty():
		def = ContentLibrary.pick_weighted(
			_missions, func(m: MissionDef): return m.weight, rng
		) as MissionDef

	var rank := difficulty.rank if difficulty else 1
	if def != null:
		plan.mission_id = def.id
		plan.title = def.display_name
		plan.description = def.description
		plan.item_tag = def.item_tag
		plan.item_count = maxi(
			1,
			int(round(def.base_item_count + def.items_mult_per_rank * rank))
			+ (difficulty.mission_item_bonus if difficulty else 0)
		)
		plan.time_limit = maxf(
			20.0,
			def.base_time_limit + def.time_mult_per_rank * rank
			+ (difficulty.mission_time_bonus if difficulty else 0.0)
		)
	else:
		# Фоллбек, если папка миссий пуста.
		plan.mission_id = &"deliver_boxes"
		plan.title = "Переезд"
		plan.description = "Затащи коробки в зону сдачи."
		plan.item_tag = &"job_item"
		plan.item_count = 3 + rank
		plan.time_limit = 70.0 - rank * 5.0

	print("[MissionGenerator] %s — %d шт. / %.0f сек." % [
		plan.title, plan.item_count, plan.time_limit
	])
	return plan
