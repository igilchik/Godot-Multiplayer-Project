extends Node

@export var player_scene: PackedScene

@onready var players_root: Node = $"../Players"
@onready var spawn_root: Node = $"../SpawnPoints"

func _ready() -> void:
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		_respawn_all()

func _get_spawn_positions() -> Array[Vector2]:
	var arr: Array[Vector2] = []
	for c in spawn_root.get_children():
		if c is Marker2D:
			arr.append((c as Marker2D).global_position)
	return arr

@rpc("authority", "call_local", "reliable")
func _rpc_spawn_player(peer_id: int, pos: Vector2) -> void:
	if players_root.has_node("Player_%d" % peer_id):
		return

	if player_scene == null:
		push_error("SpawnManager: player_scene is null")
		return

	var p := player_scene.instantiate()
	p.name = "Player_%d" % peer_id
	p.set_multiplayer_authority(peer_id)

	players_root.add_child(p)

	if p.has_method("set_spawn_state"):
		p.set_spawn_state(pos)
	else:
		p.global_position = pos

func _on_peer_connected(_id: int) -> void:
	_respawn_all()

func _respawn_all() -> void:
	for c in players_root.get_children():
		c.queue_free()

	await get_tree().process_frame

	var spawn_positions := _get_spawn_positions()
	if spawn_positions.is_empty():
		push_error("SpawnManager: Нет Marker2D в SpawnPoints!")
		return

	var ids: Array[int] = [1]
	for id in multiplayer.get_peers():
		ids.append(id)
	ids.sort()

	print("SpawnManager: respawn ids = ", ids)

	for i in range(ids.size()):
		var pid := ids[i]
		var pos := spawn_positions[min(i, spawn_positions.size() - 1)]
		rpc("_rpc_spawn_player", pid, pos)
