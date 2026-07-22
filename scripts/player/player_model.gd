extends Node3D
## PlayerModel — визуал Food Worker (J-Toastie) + анимации.
## Вешается на Player как дочерний узел Model.

const MODEL_SCENE := preload("res://assets/models/player/food_worker.glb")

@export var model_scale: float = 0.45
@export var yaw_offset_deg: float = 180.0
@export var hide_for_local_fps: bool = true

var _anim: AnimationPlayer
var _model_root: Node3D
var _current: StringName = &""
## Смещение корня, чтобы геометрический центр был в (0,0,0).
var _center_offset_y: float = -0.4
var _half_extent: float = 0.45
var _ball_mode: bool = false


func _ready() -> void:
	_model_root = MODEL_SCENE.instantiate() as Node3D
	_model_root.name = "FoodWorker"
	_model_root.scale = Vector3.ONE * model_scale
	_model_root.rotation_degrees.y = yaw_offset_deg
	add_child(_model_root)
	_measure_bounds.call_deferred()

	_anim = _model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		_anim.active = true
		_play(&"Armature|Idle")

	var player := get_parent() as CharacterBody3D
	if hide_for_local_fps and player != null and player.is_multiplayer_authority():
		_set_meshes_visible(false)


func _measure_bounds() -> void:
	if _model_root == null or not is_inside_tree():
		return
	var aabb := AABB()
	var first := true
	for mi in _model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		if mesh_i.mesh == null:
			continue
		# AABB в пространстве Model (уже с scale).
		var xf: Transform3D = global_transform.affine_inverse() * mesh_i.global_transform
		var local_aabb := _transform_aabb(xf, mesh_i.mesh.get_aabb())
		if first:
			aabb = local_aabb
			first = false
		else:
			aabb = aabb.merge(local_aabb)
	if first:
		_center_offset_y = -0.42
		_half_extent = 0.48
		return
	var center_y := aabb.position.y + aabb.size.y * 0.5
	_center_offset_y = -center_y
	_half_extent = clampf(
		maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5,
		0.35,
		0.62
	)
	if _ball_mode:
		_model_root.position.y = _center_offset_y


func _transform_aabb(xf: Transform3D, aabb: AABB) -> AABB:
	var out := AABB(xf * aabb.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(xf * aabb.get_endpoint(i))
	return out


func get_ball_radius() -> float:
	return _half_extent + 0.08


## Центрируем меш — кручение как мячик без закапывания в пол.
func set_ball_mode(enabled: bool) -> void:
	_ball_mode = enabled
	if _model_root == null:
		return
	if enabled:
		_model_root.position.y = _center_offset_y
	else:
		_model_root.position.y = 0.0


func _physics_process(_delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if player == null or _anim == null:
		return
	if _ball_mode:
		return

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


func set_body_visible(vis: bool) -> void:
	if _model_root != null:
		_set_meshes_visible(vis)
