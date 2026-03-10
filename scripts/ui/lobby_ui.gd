extends Control

@onready var players_list: Label = $Body/PlayersList
@onready var start_btn: Button = $Footer/StartMatchButton
@onready var leave_btn: Button = $Footer/LeaveButton


func _ready() -> void:
	var net := get_node_or_null("/root/Network")
	if net == null:
		push_warning("LobbyUI: /root/Network not found.")
		return

	net.lobby_players_changed.connect(func(lines):
		players_list.text = "Players (max 4):\n" + lines
	)

	_refresh_host_ui()

	start_btn.pressed.connect(func():
		var n := get_node_or_null("/root/Network")
		if n != null:
			n.start_match()
	)

	leave_btn.pressed.connect(func():
		var n := get_node_or_null("/root/Network")
		if n != null:
			n.leave()

		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)

func _refresh_host_ui() -> void:
	var net := get_node_or_null("/root/Network")
	if net == null:
		start_btn.visible = false
		return

	if multiplayer.multiplayer_peer != null:
		start_btn.visible = multiplayer.is_server()
	else:
		# fallback
		start_btn.visible = net.is_host
	print("LobbyUI: is_host=", net.is_host, " peer=", multiplayer.multiplayer_peer != null, " is_server=", multiplayer.is_server() if multiplayer.multiplayer_peer != null else "no_peer")
