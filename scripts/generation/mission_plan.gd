class_name MissionPlan
extends RefCounted
## Результат MissionGenerator — конкретный заказ на эту смену.

var mission_id: StringName = &""
var title: String = ""
var description: String = ""
var item_tag: StringName = &"job_item"
var item_count: int = 3
var time_limit: float = 60.0
var difficulty_id: StringName = &"normal"
