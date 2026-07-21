extends Control
## MainMenu — стартовый экран + выбор сложности.

const GAME_SCENE := "res://scenes/Main.tscn"

@onready var play_button: Button = $Center/Panel/VBox/PlayButton
@onready var controls_button: Button = $Center/Panel/VBox/ControlsButton
@onready var quit_button: Button = $Center/Panel/VBox/QuitButton
@onready var controls_panel: PanelContainer = $ControlsPanel
@onready var back_button: Button = $ControlsPanel/Margin/VBox/BackButton
@onready var subtitle: Label = $Center/Panel/VBox/Subtitle
@onready var difficulty_option: OptionButton = $Center/Panel/VBox/DifficultyOption
@onready var difficulty_blurb: Label = $Center/Panel/VBox/DifficultyBlurb

var _diff_lib := DifficultyLibrary.new()
var _diffs: Array[DifficultyDef] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	controls_panel.visible = false
	play_button.pressed.connect(_on_play)
	controls_button.pressed.connect(_on_controls)
	quit_button.pressed.connect(_on_quit)
	back_button.pressed.connect(_on_back)
	difficulty_option.item_selected.connect(_on_difficulty_selected)

	_diff_lib.load_all()
	_diffs = _diff_lib.all()
	difficulty_option.clear()
	var selected := 0
	for i in _diffs.size():
		var d := _diffs[i]
		difficulty_option.add_item(d.display_name, i)
		difficulty_option.set_item_metadata(i, d.id)
		if d.id == GameSession.difficulty_id:
			selected = i
	if _diffs.is_empty():
		difficulty_option.add_item("Обычная", 0)
		difficulty_option.set_item_metadata(0, &"normal")
	difficulty_option.select(selected)
	_on_difficulty_selected(selected)

	play_button.grab_focus()
	_pulse_subtitle()


func _pulse_subtitle() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(subtitle, "modulate:a", 0.55, 1.2)
	tween.tween_property(subtitle, "modulate:a", 1.0, 1.2)


func _on_difficulty_selected(index: int) -> void:
	var id: StringName = difficulty_option.get_item_metadata(index)
	GameSession.set_difficulty(id)
	GameSession.randomize_seed()
	if index >= 0 and index < _diffs.size():
		difficulty_blurb.text = _diffs[index].blurb
	else:
		difficulty_blurb.text = ""


func _on_play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_controls() -> void:
	controls_panel.visible = true
	back_button.grab_focus()


func _on_back() -> void:
	controls_panel.visible = false
	controls_button.grab_focus()


func _on_quit() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if controls_panel.visible:
			_on_back()
		else:
			_on_quit()
