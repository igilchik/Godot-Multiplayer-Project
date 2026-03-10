extends Node

signal status_changed(text: String)
signal lobby_players_changed(lines: String)
signal match_results(winner_name: String, winner_coins: int)

var is_host := false
var my_name := "Player"
var server_ip := "127.0.0.1"
var server_port := 7778
var player_names: Dictionary = {}
var _connect_watchdog_timer: SceneTreeTimer = null
var _join_started_at_ms: int = 0
var rematch_votes: Dictionary = {}
var current_game_scene_path: String = "res://scenes/game.tscn"
var current_menu_scene_path: String = "res://scenes/main_menu.tscn"

@export var main_menu_scene_path: String = "res://scenes/main_menu.tscn"
@export var game_scene_path: String = "res://scenes/game.tscn"


func _ready() -> void:
	call_deferred("_move_to_root_and_init")

func _move_to_root_and_init() -> void:
	var tree := get_tree()
	if tree == null:
		return

	var root := tree.root
	if root == null:
		return

	if get_parent() != root:
		var old_parent := get_parent()
		if old_parent != null:
			old_parent.remove_child(self)

		root.add_child(self)
		name = "Network"

	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(nickname: String, port: int) -> void:
	is_host = true
	my_name = nickname
	server_port = port

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 4)
	if err != OK:
		emit_signal("status_changed", "Failed to host: %s" % err)
		return

	multiplayer.multiplayer_peer = peer
	_net_debug("HOST: peer set")
	player_names.clear()
	rematch_votes.clear()
	player_names[multiplayer.get_unique_id()] = my_name

	emit_signal("status_changed", "Hosting on port %d" % port)
	_emit_lobby_list()

func _net_debug(where: String) -> void:
	var peer := multiplayer.multiplayer_peer
	var status_txt := "NO_PEER"
	var my_id := 0

	if peer:
		var s := peer.get_connection_status()
		match s:
			MultiplayerPeer.CONNECTION_DISCONNECTED:
				status_txt = "DISCONNECTED"
			MultiplayerPeer.CONNECTION_CONNECTING:
				status_txt = "CONNECTING"
			MultiplayerPeer.CONNECTION_CONNECTED:
				status_txt = "CONNECTED"
			_:
				status_txt = "UNKNOWN(%s)" % s

		my_id = multiplayer.get_unique_id()

	print("[NET] %s | is_server=%s | my_id=%s | status=%s | ip=%s | port=%s"
		% [where, multiplayer.is_server(), my_id, status_txt, server_ip, server_port])

func join(nickname: String, ip: String, port: int) -> void:
	is_host = false
	my_name = nickname
	server_ip = ip.strip_edges()
	server_port = port

	if server_ip == "" or server_port <= 0:
		emit_signal("status_changed", "IP/Port is empty")
		return

	if server_ip == "127.0.0.1" or server_ip.to_lower() == "localhost":
		emit_signal("status_changed", "⚠️ 127.0.0.1 = this PC. For LAN use host's 192.168.x.x")

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(server_ip, server_port)
	if err != OK:
		emit_signal("status_changed", "Failed to connect: %s" % err)
		return

	multiplayer.multiplayer_peer = peer
	_join_started_at_ms = Time.get_ticks_msec()

	emit_signal("status_changed", "Connecting to %s:%d..." % [server_ip, server_port])
	_net_debug("JOIN: peer set")

	if _connect_watchdog_timer:
		_connect_watchdog_timer = null

	_connect_watchdog_timer = get_tree().create_timer(4.0)
	_connect_watchdog_timer.timeout.connect(func():
		if multiplayer.multiplayer_peer != peer:
			return

		var st := peer.get_connection_status()
		if st != MultiplayerPeer.CONNECTION_CONNECTED:
			_net_debug("WATCHDOG: not connected in time")
			emit_signal("status_changed", "❌ Not connected (timeout). Check IP/Port/Firewall.")
			leave()
	)

func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	player_names.clear()
	rematch_votes.clear()
	is_host = false
	emit_signal("status_changed", "Disconnected")

func start_match() -> void:
	if not multiplayer.is_server():
		return
	rpc("_rpc_load_game")
	_rpc_load_game()

@rpc("call_local")
func _rpc_load_game() -> void:
	get_tree().change_scene_to_file(game_scene_path)




func request_rematch() -> void:
	if multiplayer.multiplayer_peer == null:
		push_warning("Network: request_rematch called with no multiplayer peer.")
		return

	if multiplayer.is_server():
		_server_register_rematch_vote(multiplayer.get_unique_id())
	else:
		rpc_id(1, "_server_register_rematch_vote", multiplayer.get_unique_id())

func request_main_menu() -> void:
	if multiplayer.multiplayer_peer == null:
		push_warning("Network: request_main_menu called with no multiplayer peer.")
		_go_main_menu_local()
		return

	if multiplayer.is_server():
		_server_go_main_menu()
	else:
		rpc_id(1, "_server_go_main_menu")

@rpc("any_peer", "reliable")
func _server_register_rematch_vote(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id:
		return

	rematch_votes[peer_id] = true
	print("Network: rematch vote from ", peer_id, " votes=", rematch_votes)

	var needed: Array[int] = [1]
	for id in multiplayer.get_peers():
		needed.append(id)

	for id in needed:
		if not rematch_votes.get(id, false):
			return

	_start_rematch_all()

func _start_rematch_all() -> void:
	if not multiplayer.is_server():
		return

	rematch_votes.clear()

	_rpc_load_game_scene()
	rpc("_rpc_load_game_scene")

@rpc("authority", "call_local", "reliable")
func _rpc_load_game_scene() -> void:
	get_tree().change_scene_to_file(game_scene_path)

@rpc("any_peer", "reliable")
func _server_go_main_menu() -> void:
	if not multiplayer.is_server():
		return

	rematch_votes.clear()

	if multiplayer.multiplayer_peer != null:
		rpc("_rpc_go_main_menu")

	call_deferred("_deferred_go_main_menu_host")

@rpc("authority", "reliable")
func _rpc_go_main_menu() -> void:
	_go_main_menu_local()

func _go_main_menu_local() -> void:
	leave()
	get_tree().change_scene_to_file(main_menu_scene_path)





func show_results_all(winner_name: String, winner_coins: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_show_results(winner_name, winner_coins)
	rpc("_rpc_show_results", winner_name, winner_coins)

@rpc("authority", "call_local", "reliable")
func _rpc_show_results(winner_name: String, winner_coins: int) -> void:
	emit_signal("match_results", winner_name, winner_coins)

func _on_connected_to_server() -> void:
	_net_debug("EVENT: connected_to_server")
	emit_signal("status_changed", "Connected")
	rpc_id(1, "_rpc_register_name", multiplayer.get_unique_id(), my_name)

func _on_connection_failed() -> void:
	_net_debug("EVENT: connection_failed")
	emit_signal("status_changed", "Connection failed")
	leave()

func _on_server_disconnected() -> void:
	_net_debug("EVENT: server_disconnected")
	emit_signal("status_changed", "Server disconnected")
	leave()

func _on_peer_connected(id: int) -> void:
	_net_debug("EVENT: peer_connected %d" % id)
	if multiplayer.is_server():
		emit_signal("status_changed", "Peer connected: %d" % id)

func _on_peer_disconnected(id: int) -> void:
	_net_debug("EVENT: peer_disconnected %d" % id)
	if multiplayer.is_server():
		player_names.erase(id)
		_emit_lobby_list()

@rpc("any_peer")
func _rpc_register_name(id: int, nickname: String) -> void:
	if not multiplayer.is_server():
		return
	player_names[id] = nickname
	_emit_lobby_list()

func _emit_lobby_list() -> void:
	if not multiplayer.is_server():
		return

	var ids := player_names.keys()
	ids.sort()

	var lines := ""
	for i in range(4):
		if i < ids.size():
			var pid: int = ids[i]
			var tag := " [HOST]" if pid == 1 else ""
			lines += "%d) %s%s\n" % [i + 1, player_names[pid], tag]
		else:
			lines += "%d) ---\n" % (i + 1)

	rpc("_rpc_lobby_list", lines)
	_rpc_lobby_list(lines)

@rpc("call_local")
func _rpc_lobby_list(lines: String) -> void:
	emit_signal("lobby_players_changed", lines)

func get_player_name(peer_id: int) -> String:
	if "player_names" in self:
		return str(player_names.get(peer_id, "Player"))
	return "Player"

func _deferred_go_main_menu_host() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	_go_main_menu_local()
