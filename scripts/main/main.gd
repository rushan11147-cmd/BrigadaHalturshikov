extends Node3D
## Main — оболочка уровня: генерация квартиры, игрок, HUD, события.

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const HUD_SCENE := preload("res://ui/hud.tscn")
const PAUSE_SCENE := preload("res://ui/pause_menu.tscn")
const RandomEventRunnerScript := preload("res://scripts/generation/random_event_runner.gd")

@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var job_manager: Node = $JobManager
@onready var level_generator: Node = $LevelGenerator
@onready var generated_level: Node3D = $GeneratedLevel


func _ready() -> void:
	spawner.spawn_function = _spawn_player_for_peer

	var plan = level_generator.generate(GameSession.difficulty_id)
	job_manager.configure(plan)

	_spawn_local_player()

	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	hud.bind_job(job_manager)

	add_child(PAUSE_SCENE.instantiate())

	if level_generator.delivery_zone != null:
		job_manager.register_delivery_zone(level_generator.delivery_zone)

	job_manager.start_job()
	if plan != null:
		job_manager.push_status("%s — %s" % [plan.title, plan.description])

	var runner = RandomEventRunnerScript.new()
	runner.name = "RandomEventRunner"
	add_child(runner)
	runner.setup(
		level_generator.get_event_library(),
		level_generator.get_difficulty(),
		job_manager,
		generated_level,
		level_generator.objects,
		GameSession.last_seed
	)


func _spawn_local_player() -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "Player_1"
	player.add_to_group("player")
	players.add_child(player)
	player.global_position = level_generator.player_spawn_global
	player.set_multiplayer_authority(1)


func _spawn_player_for_peer(data: Variant) -> Node:
	var peer_id: int = data.get("peer_id", 1)
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "Player_%d" % peer_id
	player.add_to_group("player")
	player.set_multiplayer_authority(peer_id)
	return player


func spawn_player_networked(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	spawner.spawn({"peer_id": peer_id})
