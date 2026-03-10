extends Control

@onready var hearts: AnimatedSprite2D = $Hearts
@onready var coin_label: Label = $CoinHUD/CoinLabel
@onready var sword_button: TextureButton = $SwordHUD/SwordButton
@onready var sword_text: Label = $SwordHUD/SwordText
@onready var hint_label: Label = $HintLabel

var player: Node = null
var hint_tween: Tween = null
var hint_request_id: int = 0
var last_hint_key: String = ""

func _ready() -> void:
	if not sword_button.pressed.is_connected(_on_sword_button_pressed):
		sword_button.pressed.connect(_on_sword_button_pressed)

	hint_label.visible = false
	hint_label.modulate.a = 1.0

	_reset_ui()
	call_deferred("_bind_when_ready")

func _process(_delta: float) -> void:
	if player != null and not is_instance_valid(player):
		_disconnect_from_player()
		_reset_ui()
		call_deferred("_bind_when_ready")
		return

	var p := _find_local_player()
	if p != null and p != player:
		_bind_to_player(p)

func _reset_ui() -> void:
	coin_label.text = "0"
	sword_text.text = ""
	_set_sword_button_active(false)

func _bind_when_ready() -> void:
	call_deferred("_attempt_bind_async")

func _attempt_bind_async() -> void:
	if not is_inside_tree():
		return

	var tree := get_tree()
	if tree == null:
		return

	await tree.process_frame

	if not is_inside_tree():
		return

	for _i in range(30):
		if not is_inside_tree():
			return

		var p := _find_local_player()
		if p != null:
			_bind_to_player(p)
			return

		var t := get_tree()
		if t == null:
			return

		await t.create_timer(0.1).timeout

	_reset_ui()

func _find_local_player() -> Node:
	if not is_inside_tree():
		return null

	if multiplayer.multiplayer_peer == null:
		return null

	var tree := get_tree()
	if tree == null:
		return null

	var scene := tree.current_scene
	if scene == null:
		return null

	var players_root := scene.get_node_or_null("Players")
	if players_root == null:
		return null

	for c in players_root.get_children():
		if c.has_method("is_multiplayer_authority") and c.is_multiplayer_authority():
			return c

	return null

func _bind_to_player(p: Node) -> void:
	if player == p:
		return

	_disconnect_from_player()
	player = p

	if player.has_signal("hp_changed") and not player.hp_changed.is_connected(_on_hp_changed):
		player.hp_changed.connect(_on_hp_changed)

	if player.has_signal("coins_changed") and not player.coins_changed.is_connected(_on_coins_changed):
		player.coins_changed.connect(_on_coins_changed)

	if player.has_signal("weapon_state_changed") and not player.weapon_state_changed.is_connected(_on_weapon_state_changed):
		player.weapon_state_changed.connect(_on_weapon_state_changed)

	if player.has_method("force_hp_update"):
		player.call_deferred("force_hp_update")

	var c = player.get("coins")
	if c == null:
		coin_label.text = "0"
	else:
		_on_coins_changed(int(c))

	if player.has_method("emit_weapon_state"):
		player.call_deferred("emit_weapon_state")
	else:
		_set_sword_button_active(false)

func _disconnect_from_player() -> void:
	if player == null:
		return

	if player.has_signal("hp_changed") and player.hp_changed.is_connected(_on_hp_changed):
		player.hp_changed.disconnect(_on_hp_changed)

	if player.has_signal("coins_changed") and player.coins_changed.is_connected(_on_coins_changed):
		player.coins_changed.disconnect(_on_coins_changed)

	if player.has_signal("weapon_state_changed") and player.weapon_state_changed.is_connected(_on_weapon_state_changed):
		player.weapon_state_changed.disconnect(_on_weapon_state_changed)

	player = null

func _on_hp_changed(pips: int, _max_pips: int) -> void:
	var anim_name := str(pips) + "hp"
	if hearts.sprite_frames and hearts.sprite_frames.has_animation(anim_name):
		hearts.play(anim_name)

func _on_coins_changed(total: int) -> void:
	coin_label.text = str(total)

func _on_sword_button_pressed() -> void:
	if player and player.has_method("try_upgrade_sword"):
		player.try_upgrade_sword()

func _on_weapon_state_changed(level: int, damage: int, next_cost: int, is_max: bool, can_upgrade: bool) -> void:
	if is_max:
		sword_text.text = "MAX"
		_set_sword_button_active(false)
	else:
		sword_text.text = str(next_cost)
		_set_sword_button_active(can_upgrade)

	var key: String
	var text: String

	if is_max:
		key = "max"
		text = "Weapon fully upgraded!"
	else:
		key = "lvl_%d_dmg_%d_cost_%d" % [level, damage, next_cost]
		text = "Earn %d coins to upgrade" % next_cost

	if key != last_hint_key:
		last_hint_key = key
		_show_hint_for_5s(text)

func _set_sword_button_active(active: bool) -> void:
	sword_button.disabled = not active
	sword_button.modulate.a = 1.0 if active else 0.5

func _show_hint_for_5s(text: String) -> void:
	hint_request_id += 1
	var my_id := hint_request_id

	hint_label.text = text
	hint_label.visible = true
	hint_label.modulate.a = 1.0

	if hint_tween and hint_tween.is_valid():
		hint_tween.kill()

	hint_tween = create_tween()
	hint_tween.set_loops()
	hint_tween.tween_property(hint_label, "modulate:a", 0.45, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	hint_tween.tween_property(hint_label, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await get_tree().create_timer(5.0).timeout
	if my_id != hint_request_id:
		return

	hint_label.visible = false
	if hint_tween and hint_tween.is_valid():
		hint_tween.kill()
	hint_label.modulate.a = 1.0
