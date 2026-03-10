extends Control

@onready var main_panel: Control = %MainMenuPanel
@onready var lobby_panel: Control = %LobbyPanel

@onready var nick_input: LineEdit = %NicknameInput
@onready var ip_input: LineEdit = %IPInput
@onready var port_input: LineEdit = %PortInput

@onready var host_btn: Button = %HostButton
@onready var join_btn: Button = %JoinButton
@onready var quit_btn: Button = %QuitButton
@onready var status_text: Label = %StatusText

@onready var players_list: Label = %PlayersList
@onready var start_match_btn: Button = %StartMatchButton
@onready var leave_btn: Button = %LeaveButton

var net: Node


func _ready() -> void:
	net = get_node("/root/Network") if has_node("/root/Network") else get_node("../Network")

	net.status_changed.connect(_on_status)
	net.lobby_players_changed.connect(_on_lobby_list)

	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	quit_btn.pressed.connect(func(): get_tree().quit())

	start_match_btn.pressed.connect(_on_start_match)
	leave_btn.pressed.connect(_on_leave)

	if ip_input.text.strip_edges() == "":
		ip_input.text = "127.0.0.1"
	if port_input.text.strip_edges() == "":
		port_input.text = "7778"

	main_panel.visible = true
	lobby_panel.visible = false


func _on_status(t: String) -> void:
	status_text.text = "Status: " + t


func _on_lobby_list(lines: String) -> void:
	players_list.text = lines
	main_panel.visible = false
	lobby_panel.visible = true


func _on_host() -> void:
	var nick := nick_input.text.strip_edges()
	if nick == "":
		nick = "Host"

	var port := int(port_input.text)
	net.host(nick, port)

	main_panel.visible = false
	lobby_panel.visible = true


func _on_join() -> void:
	var nick := nick_input.text.strip_edges()
	if nick == "":
		nick = "Client"

	var ip := ip_input.text.strip_edges()
	var port := int(port_input.text)
	net.join(nick, ip, port)

	main_panel.visible = false
	lobby_panel.visible = true


func _on_leave() -> void:
	net.leave()
	players_list.text = ""
	main_panel.visible = true
	lobby_panel.visible = false


func _on_start_match() -> void:
	net.start_match()
