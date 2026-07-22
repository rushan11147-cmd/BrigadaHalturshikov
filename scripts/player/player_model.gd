extends Node3D
## PlayerModel — визуал Food Worker (J-Toastie) + анимации.
## Вешается на Player как дочерний узел Model.

const MODEL_SCENE := preload("res://assets/models/player/food_worker.glb")

## Подгони масштаб под метры сцены (капсула ~1.8 м).
@export var model_scale: float = 0.45
## Многие GLB смотрят в +Z; у нас ход в −Z.
@export var yaw_offset_deg: float = 180.0
## В FPS прячем своё тело у локального игрока.
@export var hide_for_local_fps: bool = true

var _anim: AnimationPlayer
var _model_root: Node3D
var _current: StringName = &""


func _ready() -> void:
	_model_root = MODEL_SCENE.instantiate() as Node3D
	_model_root.name = "FoodWorker"
	_model_root.scale = Vector3.ONE * model_scale
	_model_root.rotation_degrees.y = yaw_offset_deg
	add_child(_model_root)

	_anim = _model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		_anim.active = true
		_play(&"Armature|Idle")

	var player := get_parent() as CharacterBody3D
	if hide_for_local_fps and player != null and player.is_multiplayer_authority():
		_set_meshes_visible(false)


func _physics_process(_delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if player == null or _anim == null:
		return

	# Несёт предмет — спокойный Idle/Walk (отдельной carry-анимации нет).
	var carrying := false
	var grab := player.find_child("GrabCarry", true, false)
	if grab != null and grab.has_method("is_carrying") and grab.is_carrying():
		carrying = true

	if not player.is_on_floor():
		_play(&"Armature|Jump")
		return

	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	if carrying and horizontal <= 0.4:
		_play(&"Armature|Idle")
	elif horizontal > 4.2:
		_play(&"Armature|Sprint")
	elif horizontal > 0.4:
		_play(&"Armature|Walk")
	else:
		_play(&"Armature|Idle")


func _play(anim_name: StringName) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(anim_name):
		return
	if _current == anim_name and _anim.is_playing():
		return
	_current = anim_name
	_anim.play(anim_name)


func _set_meshes_visible(vis: bool) -> void:
	for mi in _model_root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = vis


## Показать тело (для 3-го лица / отладки).
func set_body_visible(vis: bool) -> void:
	if _model_root != null:
		_set_meshes_visible(vis)
