extends Node

var players: Dictionary = {}
var coins: Dictionary = {}
var alive: Dictionary = {}
var match_started: bool = false
var match_finished: bool = false
var match_duration_sec: float = 0.0


func _ready() -> void:
	if multiplayer.is_server():
		call_deferred("_server_bootstrap")

func _server_bootstrap() -> void:
	if not multiplayer.is_server():
		return

	await get_tree().process_frame
	await get_tree().process_frame

	_register_existing_players()
	_start_match_rules()

func _register_existing_players() -> void:
	if not multiplayer.is_server():
		return

	players.clear()
	coins.clear()
	alive.clear()

	var scene := get_tree().current_scene
	if scene == null:
		push_error("MatchManager: current_scene is null.")
		return

	var players_root := scene.get_node_or_null("Players")
	if players_root == null:
		push_error("MatchManager: Node 'Players' not found.")
		return

	for child in players_root.get_children():
		_try_register_player(child)

func _try_register_player(p: Node) -> void:
	if not multiplayer.is_server():
		return
	if p == null:
		return
	if not is_instance_valid(p):
		return
	if not p.has_signal("died"):
		return
	if not p.has_method("get"):
		return

	var peer_value = p.get("peer_id")
	if peer_value == null:
		return

	var id: int = int(peer_value)

	players[id] = p
	alive[id] = true

	var total_coin_value = p.get("total_coins_collected")
	if total_coin_value == null:
		coins[id] = 0
	else:
		coins[id] = int(total_coin_value)

	if p.has_signal("total_coins_changed"):
		var on_total_coins_changed := func(total: int) -> void:
			if multiplayer.is_server() and not match_finished:
				coins[id] = int(total)

		p.total_coins_changed.connect(on_total_coins_changed)

	var on_died := func() -> void:
		if not multiplayer.is_server():
			return
		if match_finished:
			return

		alive[id] = false
		_check_last_survivor()

	p.died.connect(on_died)

func _start_match_rules() -> void:
	if not multiplayer.is_server():
		return
	if match_started:
		return

	var count := players.size()
	if count <= 0:
		push_error("MatchManager: no players registered.")
		return

	match_started = true
	match_finished = false

	if count == 1:
		match_duration_sec = 120.0
	else:
		match_duration_sec = 180.0

	print("MatchManager: players=", count, " duration=", match_duration_sec)

	call_deferred("_run_match_timer")

func _run_match_timer() -> void:
	await get_tree().create_timer(match_duration_sec).timeout

	if not multiplayer.is_server():
		return
	if match_finished:
		return

	_finish_by_timeout()

func _check_last_survivor() -> void:
	if not multiplayer.is_server():
		return
	if match_finished:
		return

	var alive_ids := _get_alive_ids()
	if alive_ids.size() == 1:
		var winner_id: int = alive_ids[0]
		var winner_coins: int = int(coins.get(winner_id, 0))
		_finish_match(winner_id, winner_coins)

func _finish_by_timeout() -> void:
	if not multiplayer.is_server():
		return
	if match_finished:
		return

	var alive_ids := _get_alive_ids()

	if alive_ids.size() == 1:
		var winner_id: int = alive_ids[0]
		var winner_coins: int = int(coins.get(winner_id, 0))
		_finish_match(winner_id, winner_coins)
		return

	var candidate_ids: Array[int] = alive_ids
	if candidate_ids.is_empty():
		for id in players.keys():
			candidate_ids.append(int(id))

	if candidate_ids.is_empty():
		push_error("MatchManager: no candidates for timeout winner.")
		return

	var best_id: int = candidate_ids[0]
	var best_coins: int = int(coins.get(best_id, 0))

	for id in candidate_ids:
		var c: int = int(coins.get(id, 0))
		if c > best_coins:
			best_coins = c
			best_id = int(id)

	_finish_match(best_id, best_coins)

func _finish_match(winner_id: int, winner_coins: int) -> void:
	if not multiplayer.is_server():
		return
	if match_finished:
		return

	match_finished = true

	var winner_name: String = _resolve_player_name(winner_id)

	var net := get_node_or_null("/root/Network")
	if net == null:
		push_error("MatchManager: /root/Network not found.")
		return

	if net.has_method("show_results_all"):
		net.show_results_all(winner_name, winner_coins)
	else:
		push_error("MatchManager: Network has no show_results_all().")

func _resolve_player_name(peer_id: int) -> String:
	var net := get_node_or_null("/root/Network")
	if net == null:
		return "Player"

	if net.has_method("get_player_name"):
		return str(net.get_player_name(peer_id))

	var names = net.get("player_names")
	if names is Dictionary:
		return str(names.get(peer_id, "Player"))

	return "Player"

func _get_alive_ids() -> Array[int]:
	var arr: Array[int] = []
	for id in alive.keys():
		if alive[id] == true:
			arr.append(int(id))
	return arr
