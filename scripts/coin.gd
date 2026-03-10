extends Area2D

@export var value: int = 1
var _collected: bool = false
@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return

	if _collected:
		return

	if body == null:
		return
	if not body.is_in_group("player"):
		return
	if not body.has_method("add_coins_server"):
		return

	_collected = true

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	if is_instance_valid(_shape):
		_shape.set_deferred("disabled", true)

	body.add_coins_server(value)

	rpc("_rpc_collect")
	_rpc_collect()

@rpc("call_local", "reliable")
func _rpc_collect() -> void:
	queue_free()
