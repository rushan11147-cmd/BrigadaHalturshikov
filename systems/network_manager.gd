extends Node
## NetworkManager — заготовка сетевого слоя для 2–4 игроков.
## Autoload: доступен из любой сцены как NetworkManager.
##
## Этап 1: локальный прототип без реального лобби.
## Этап 2: host/join, лобби, синхронизация предметов.

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 4

## Сигналы для UI и геймплея.
signal server_started
signal connected_to_server
signal connection_failed
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

## peer_id локального игрока (1 = сервер / хост).
var local_peer_id: int = 1


func _ready() -> void:
	# Подписка на события мультиплеера Godot.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Создать хост (сервер + локальный игрок).
func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("Не удалось создать сервер: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	local_peer_id = multiplayer.get_unique_id()
	server_started.emit()
	print("[Network] Хост запущен на порту %d (peer=%d)" % [port, local_peer_id])
	return OK


## Подключиться к хосту как клиент.
func join_game(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Не удалось подключиться: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	print("[Network] Подключение к %s:%d..." % [address, port])
	return OK


## Отключиться и очистить peer.
func disconnect_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	local_peer_id = 1
	print("[Network] Отключено")


## Есть ли реальная сетевая сессия (не OfflineMultiplayerPeer).
func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	if peer == null:
		return false
	# В Godot 4 по умолчанию всегда стоит OfflineMultiplayerPeer.
	if peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## Локальный хост / офлайн — можно сразу менять мир без RPC на себя.
func is_authority_host() -> bool:
	return not is_online() or multiplayer.is_server()


## Пример RPC: сообщение всем игрокам (заготовка для чата / событий).
@rpc("any_peer", "reliable", "call_local")
func rpc_broadcast_message(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = local_peer_id
	print("[RPC][%d] %s" % [sender, text])


func _on_peer_connected(id: int) -> void:
	print("[Network] Игрок подключился: %d" % id)
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[Network] Игрок отключился: %d" % id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	print("[Network] Подключены к серверу (peer=%d)" % local_peer_id)
	connected_to_server.emit()


func _on_connection_failed() -> void:
	push_warning("[Network] Ошибка подключения")
	connection_failed.emit()


func _on_server_disconnected() -> void:
	push_warning("[Network] Сервер отключился")
	disconnect_game()
