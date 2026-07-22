extends Node3D
## PlayerModel — Food Worker + лёгкое качание конечностей при спотыкании.

const MODEL_SCENE := preload("res://assets/models/player/food_worker.glb")

@export var model_scale: float = 0.45
@export var yaw_offset_deg: float = 180.0
@export var hide_for_local_fps: bool = true

var _anim: AnimationPlayer
var _model_root: Node3D
var _skeleton: Skeleton3D
var _current: StringName = &""

var _sway: bool = false
var _sway_t: float = 0.0
var _sway_side: float = 1.0
var _sway_style: int = 0

var _bone_body: int = -1
var _bone_head: int = -1
var _bone_hand_l: int = -1
var _bone_hand_r: int = -1


func _ready() -> void:
	_model_root = MODEL_SCENE.instantiate() as Node3D
	_model_root.name = "FoodWorker"
	_model_root.scale = Vector3.ONE * model_scale
	_model_root.rotation_degrees.y = yaw_offset_deg
	add_child(_model_root)

	_skeleton = _model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton != null:
		_bone_body = _skeleton.find_bone("Body")
		_bone_head = _skeleton.find_bone("Head")
		_bone_hand_l = _skeleton.find_bone("Hand.L")
		_bone_hand_r = _skeleton.find_bone("Hand.R")

	_anim = _model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		_anim.active = true
		_play(&"Armature|Idle")

	var player := get_parent() as CharacterBody3D
	if hide_for_local_fps and player != null and player.is_multiplayer_authority():
		_set_meshes_visible(false)


func start_stumble_sway(style: int, side: float) -> void:
	_sway = true
	_sway_t = 0.0
	_sway_style = style
	_sway_side = side
	if _anim != null:
		_anim.stop()
		_anim.active = false


func tick_stumble_sway(delta: float, still_down: bool) -> void:
	if not _sway or _skeleton == null:
		return
	_sway_t += delta
	if not still_down:
		# Плавно гасим после вставания.
		_clear_bones_lerp(delta * 8.0)
		if _sway_t > 0.35:
			end_stumble_sway()
		return

	var w := sin(_sway_t * 12.0) * 0.2
	var w2 := cos(_sway_t * 9.0) * 0.15
	var tip := clampf(_sway_t / 0.55, 0.0, 1.0)

	_set_bone(_bone_body, Vector3(0.25 * tip + w, 0.1 * tip * _sway_side, 0.2 * tip * _sway_side))
	_set_bone(_bone_head, Vector3(0.35 * tip + w2 * 1.5, 0.2 * tip * _sway_side, w))
	_set_bone(_bone_hand_l, Vector3(0.3 * tip + w, -0.8 * tip + w2, -0.5 * tip))
	_set_bone(_bone_hand_r, Vector3(0.3 * tip + w2, 0.8 * tip - w, 0.5 * tip))


func end_stumble_sway() -> void:
	_sway = false
	_sway_t = 0.0
	_clear_bones()
	if _anim != null:
		_anim.active = true
		_current = &""
		_play(&"Armature|Idle")


func _set_bone(idx: int, euler: Vector3) -> void:
	if idx < 0 or _skeleton == null:
		return
	_skeleton.set_bone_pose_rotation(idx, Quaternion.from_euler(euler))


func _clear_bones() -> void:
	for idx in [_bone_body, _bone_head, _bone_hand_l, _bone_hand_r]:
		_set_bone(idx, Vector3.ZERO)


func _clear_bones_lerp(alpha: float) -> void:
	if _skeleton == null:
		return
	for idx in [_bone_body, _bone_head, _bone_hand_l, _bone_hand_r]:
		if idx < 0:
			continue
		var q := _skeleton.get_bone_pose_rotation(idx).slerp(Quaternion.IDENTITY, clampf(alpha, 0.0, 1.0))
		_skeleton.set_bone_pose_rotation(idx, q)


func _physics_process(_delta: float) -> void:
	var player := get_parent() as CharacterBody3D
	if player == null or _anim == null or not _anim.active:
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
	if _anim == null or not _anim.active:
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
