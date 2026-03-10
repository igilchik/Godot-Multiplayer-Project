extends Control

@onready var winner_value: Label = $ResultCard/Layout/WinnerPadding/WinnerRow/WinnerValue
@onready var coins_value: Label = $ResultCard/Layout/CoinsPadding/CoinsRow/CoinsValue
@onready var rematch_btn: Button = $ResultCard/Layout/ButtonsPadding/ButtonsRow/RematchButton
@onready var mainmenu_btn: Button = $ResultCard/Layout/ButtonsPadding/ButtonsRow/MainMenuButton


func _ready() -> void:
	visible = false

	var net := get_node_or_null("/root/Network")
	if net != null and net.has_signal("match_results"):
		net.match_results.connect(_on_match_results)

	rematch_btn.pressed.connect(_on_rematch_pressed)
	mainmenu_btn.pressed.connect(_on_mainmenu_pressed)

func _on_match_results(winner_name: String, winner_coins: int) -> void:
	visible = true
	winner_value.text = winner_name
	coins_value.text = str(winner_coins)

	rematch_btn.disabled = false
	mainmenu_btn.disabled = false

func _on_rematch_pressed() -> void:
	rematch_btn.disabled = true

	var net := get_node_or_null("/root/Network")
	if net == null:
		push_warning("EndMatchUI: /root/Network not found.")
		rematch_btn.disabled = false
		return

	if net.has_method("request_rematch"):
		net.request_rematch()

func _on_mainmenu_pressed() -> void:
	mainmenu_btn.disabled = true

	var net := get_node_or_null("/root/Network")
	if net == null:
		push_warning("EndMatchUI: /root/Network not found.")
		mainmenu_btn.disabled = false
		return

	if net.has_method("request_main_menu"):
		net.request_main_menu()
