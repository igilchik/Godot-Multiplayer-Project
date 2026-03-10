extends Node

@export var players_root_path: NodePath = NodePath("../Players")
@export var bounds_origin: Vector2 = Vector2.ZERO
@export var bounds_size: Vector2 = Vector2(2048, 2048)
@export var margin: float = 8.0

var player: Node2D = null
var _bound_player_path: NodePath = NodePath("")


func _ready() -> void:
	_try_bind_local_player()


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.get_path() != _bound_player_path:
		_try_bind_local_player()
		return

	_apply_bounds()


func _try_bind_local_player() -> void:
	if not get_tree():
		return

	var scene := get_tree().current_scene
	if scene == null:
		return

	var players_root := scene.get_node_or_null(players_root_path)
	if players_root == null:
		return

	for c in players_root.get_children():
		if c is Node2D and c.has_method("is_multiplayer_authority") and c.is_multiplayer_authority():
			player = c
			_bound_player_path = player.get_path()
			return


func _apply_bounds() -> void:
	var rect := Rect2(bounds_origin, bounds_size).grow(-margin)

	var p := player.global_position
	p.x = clamp(p.x, rect.position.x, rect.position.x + rect.size.x)
	p.y = clamp(p.y, rect.position.y, rect.position.y + rect.size.y)
	player.global_position = p
