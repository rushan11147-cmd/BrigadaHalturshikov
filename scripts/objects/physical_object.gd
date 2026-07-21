class_name PhysicalObject
extends RigidBody3D
## PhysicalObject — базовый физический предмет бригады.
## Физика, масса, grab/release, удары и урон. Без ввода игрока.

signal grabbed(peer_id: int)
signal released(peer_id: int)
signal damaged(amount: float, health_left: float)
signal broken

@export var object_mass: float = 5.0
@export var can_be_picked_up: bool = true
@export var max_health: float = 100.0
@export var fall_damage_speed: float = 7.0
@export var fall_damage_multiplier: float = 8.0
@export var impact_sound_speed: float = 1.2
@export var display_name: String = "Предмет"
@export var physics_mat: PhysicsMaterial
## Считается ли предмет для текущего заказа (коробки — да, диван — нет).
@export var counts_for_job: bool = false

var health: float = 100.0
var held_by_peer_id: int = -1
var _delivered: bool = false

var _impact_player: AudioStreamPlayer3D
var _last_speed: float = 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	health = max_health
	mass = maxf(object_mass, 0.1)
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	freeze = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	# Явные слои: 4 = pickup, маска видит мир/игрока/предметы.
	collision_layer = 4
	collision_mask = 1 | 2 | 4

	if physics_mat != null:
		physics_material_override = physics_mat

	add_to_group("physical_object")
	if can_be_picked_up:
		add_to_group("pickup")
	if counts_for_job:
		add_to_group("job_item")

	_mesh = _find_mesh(self)
	# add_child во время _ready родителя запрещён в Godot 4.7 — откладываем.
	_setup_impact_audio.call_deferred()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	if freeze:
		_last_speed = 0.0
		return
	_last_speed = linear_velocity.length()


func can_be_carried_by(max_carry_mass: float) -> bool:
	if not can_be_picked_up or _delivered:
		return false
	if is_held():
		return false
	return object_mass <= max_carry_mass


func is_held() -> bool:
	return held_by_peer_id != -1


func is_delivered() -> bool:
	return _delivered


## Зафиксировать сдачу в зону (больше не поднимается).
func mark_delivered() -> void:
	if _delivered:
		return
	_delivered = true
	if is_held():
		end_grab(Vector3.ZERO)
	freeze = true
	collision_layer = 4
	can_be_picked_up = false
	remove_from_group("pickup")
	add_to_group("delivered")
	if _mesh != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.85, 0.35)
		_mesh.material_override = mat


func begin_grab(peer_id: int) -> void:
	if is_held():
		return
	held_by_peer_id = peer_id
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	grabbed.emit(peer_id)


func end_grab(release_velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_held():
		return
	var peer := held_by_peer_id
	held_by_peer_id = -1
	collision_layer = 4
	freeze = false
	sleeping = false
	linear_velocity = release_velocity
	angular_velocity = Vector3.ZERO
	released.emit(peer)


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, health)
	_flash_damage()
	if health <= 0.0:
		broken.emit()
		print("[PhysicalObject] %s сломан!" % display_name)


func _on_body_entered(_body: Node) -> void:
	if is_held():
		return
	var speed := maxf(_last_speed, linear_velocity.length())
	if speed >= impact_sound_speed:
		_play_impact(speed)
	if speed >= fall_damage_speed:
		var dmg := (speed - fall_damage_speed) * fall_damage_multiplier
		apply_damage(dmg)


func _setup_impact_audio() -> void:
	if not is_inside_tree():
		return
	_impact_player = AudioStreamPlayer3D.new()
	_impact_player.name = "ImpactAudio"
	_impact_player.max_distance = 28.0
	add_child(_impact_player)
	_impact_player.stream = _make_thud_stream()


func _make_thud_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var samples := 2205
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / float(samples)
		var env := (1.0 - t) * (1.0 - t)
		var sample := sin(float(i) * 0.35) * env * 0.55
		var s16 := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s16)
	stream.data = data
	return stream


func _play_impact(speed: float) -> void:
	if _impact_player == null or not is_instance_valid(_impact_player):
		return
	if _impact_player.playing:
		return
	var intensity := clampf(speed / 12.0, 0.25, 1.0)
	_impact_player.volume_db = linear_to_db(intensity)
	_impact_player.pitch_scale = remap(intensity, 0.25, 1.0, 1.15, 0.75)
	_impact_player.play()


func _flash_damage() -> void:
	if _mesh == null:
		return
	var mat := _mesh.get_active_material(0)
	if mat == null and _mesh.mesh != null:
		mat = _mesh.mesh.surface_get_material(0)
	if mat is StandardMaterial3D:
		var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		_mesh.material_override = std
		var original := std.albedo_color
		std.albedo_color = Color(1.0, 0.25, 0.2)
		get_tree().create_timer(0.12).timeout.connect(
			func() -> void:
				if is_instance_valid(std):
					std.albedo_color = original
		)


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found:
			return found
	return null
