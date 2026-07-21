extends CanvasLayer
## PauseMenu — Esc во время игры: продолжить / в меню / выход.

const MENU_SCENE := "res://ui/main_menu.tscn"

@onready var root: Control = $Root
@onready var resume_button: Button = $Root/Center/Panel/VBox/ResumeButton
@onready var menu_button: Button = $Root/Center/Panel/VBox/MenuButton
@onready var quit_button: Button = $Root/Center/Panel/VBox/QuitButton

var _paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	resume_button.pressed.connect(_resume)
	menu_button.pressed.connect(_to_menu)
	quit_button.pressed.connect(func(): get_tree().quit())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()


func _pause() -> void:
	_paused = true
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()


func _resume() -> void:
	_paused = false
	root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)
