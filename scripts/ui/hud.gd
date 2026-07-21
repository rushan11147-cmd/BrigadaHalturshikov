extends CanvasLayer
## HUD — таймер, прогресс заказа, подсказки, прицел.

@onready var timer_label: Label = $Root/TopBar/TimerLabel
@onready var progress_label: Label = $Root/TopBar/ProgressLabel
@onready var status_label: Label = $Root/StatusLabel
@onready var help_label: Label = $Root/HelpLabel


func _ready() -> void:
	status_label.text = ""
	help_label.text = "WASD — ход · Shift — бег · E — взять/отпустить · ЛКМ — бросить · R — заново · Esc — пауза"


func bind_job(job: Node) -> void:
	if job.has_signal("time_changed"):
		job.time_changed.connect(_on_time_changed)
	if job.has_signal("progress_changed"):
		job.progress_changed.connect(_on_progress_changed)
	if job.has_signal("status_message"):
		job.status_message.connect(_on_status)
	if job.has_signal("job_won"):
		job.job_won.connect(func(_d, _t): status_label.modulate = Color(0.4, 1.0, 0.5))
	if job.has_signal("job_lost"):
		job.job_lost.connect(func(_d): status_label.modulate = Color(1.0, 0.4, 0.35))


func _on_time_changed(seconds_left: float) -> void:
	var m := int(seconds_left) / 60
	var s := int(seconds_left) % 60
	timer_label.text = "%d:%02d" % [m, s]
	if seconds_left <= 10.0:
		timer_label.modulate = Color(1.0, 0.35, 0.3)
	else:
		timer_label.modulate = Color.WHITE


func _on_progress_changed(delivered: int, goal: int) -> void:
	progress_label.text = "Коробки: %d / %d" % [delivered, goal]


func _on_status(text: String) -> void:
	status_label.text = text
