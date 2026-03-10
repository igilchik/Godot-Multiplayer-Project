extends CharacterBody2D

@export var speed: float = 220.0
@export var max_hp: int = 100
@export var pip_size: int = 25
@export var sync_rate_hz: float = 60.0
@export var attack_duration: float = 0.18
@export var hit_flash_time: float = 0.12
@export var melee_tip_distance: float = 24.0
@export var melee_hit_radius: float = 10.0
@export var melee_blade_length: float = 22.0
@export var peer_id: int = 1

const SWORD_DAMAGES := [10, 15, 20, 30]
const SWORD_UPGRADE_COST := [10, 15, 25]

signal hp_changed(pips: int, max_pips: int)
signal coins_changed(total: int)
signal weapon_state_changed(level: int, damage: int, next_cost: int, is_max: bool, can_upgrade: bool)
signal died()
signal total_coins_changed(total: int)

@onready var visual: Node2D = $Visual


var body: AnimatedSprite2D = null
var anim_sword: Node = null
var slash: AnimatedSprite2D = null
var hand_pivot: Node2D = null
var hit_pivot: Node2D = null
var sword: Node2D = null
var sword_hitbox: Area2D = null
var sword_hit_shape: CollisionShape2D = null
var hurtbox: Area2D = null
var cam: Camera2D = null

var hp: int
var is_dead: bool = false
var is_attacking: bool = false
var _attack_down_next: bool = true
var _attack_tip_world: Vector2 = Vector2.ZERO
var _attack_forward: Vector2 = Vector2.RIGHT
var _prev_attack_tip_world: Vector2 = Vector2.ZERO
var _prev_attack_forward: Vector2 = Vector2.RIGHT

var coins: int = 0
var total_coins_collected: int = 0
var sword_level: int = 0
var sword_damage: int = 10

var net_dir: Vector2 = Vector2.ZERO
var aim_to: Vector2 = Vector2.RIGHT
var aim_angle: float = 0.0
var net_aim_angle: float = 0.0
var target_aim_angle: float = 0.0
var facing_x: int = 1
var target_facing_x: int = 1

var target_pos: Vector2
var target_vel: Vector2
var _sync_accum: float = 0.0

var _attack_hit_ids: Dictionary = {}

var match_over: bool = false



func _enter_tree() -> void:
	if name.begins_with("Player_"):
		peer_id = int(name.get_slice("_", 1))
		set_multiplayer_authority(peer_id)

func _ready() -> void:
	add_to_group("player")
	_resolve_nodes()

	hp = max_hp
	coins = 0
	total_coins_collected = 0
	sword_level = 0
	sword_damage = SWORD_DAMAGES[sword_level]

	_emit_hp_changed()
	coins_changed.emit(coins)
	total_coins_changed.emit(total_coins_collected)
	emit_weapon_state()

	if body and body.sprite_frames and body.sprite_frames.has_animation("idle"):
		body.play("idle")

	if slash:
		slash.visible = false

	if sword_hitbox:
		sword_hitbox.set_deferred("monitoring", false)
		sword_hitbox.set_deferred("monitorable", true)

	if sword_hit_shape:
		sword_hit_shape.set_deferred("disabled", true)

	cam = get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.enabled = is_multiplayer_authority()
		if is_multiplayer_authority():
			cam.make_current()

	target_pos = global_position
	target_vel = Vector2.ZERO
	target_aim_angle = net_aim_angle
	target_facing_x = facing_x

	var net := get_node_or_null("/root/Network")
	if net != null and net.has_signal("match_results"):
		net.match_results.connect(_on_match_results)

func set_spawn_state(pos: Vector2) -> void:
	global_position = pos
	target_pos = pos
	target_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	net_dir = Vector2.ZERO
	match_over = false
	is_dead = false
	is_attacking = false

func _on_match_results(_winner_name: String, _winner_coins: int) -> void:
	match_over = true
	velocity = Vector2.ZERO
	net_dir = Vector2.ZERO

	if multiplayer.is_server():
		move_and_slide()


func _resolve_nodes() -> void:
	body = get_node_or_null("Visual/AnimBody") as AnimatedSprite2D

	anim_sword = get_node_or_null("Visual/AnimSword")
	if anim_sword == null:
		anim_sword = get_node_or_null("AnimSword")

	slash = get_node_or_null("Visual/HandBase/AnimSlash") as AnimatedSprite2D
	if slash == null:
		slash = get_node_or_null("AnimSlash") as AnimatedSprite2D

	hand_pivot = get_node_or_null("Visual/HandPivot") as Node2D
	if hand_pivot == null:
		hand_pivot = get_node_or_null("HandPivot") as Node2D

	hit_pivot = get_node_or_null("HitPivot") as Node2D

	sword = get_node_or_null("Visual/HandPivot/Sword") as Node2D
	if sword == null:
		sword = get_node_or_null("Sword") as Node2D

	sword_hitbox = get_node_or_null("HitPivot/SwordHitBox") as Area2D
	if sword_hitbox == null:
		sword_hitbox = get_node_or_null("SwordHitBox") as Area2D

	if sword_hitbox:
		sword_hit_shape = sword_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if not sword_hitbox.area_entered.is_connected(_on_sword_area_entered):
			sword_hitbox.area_entered.connect(_on_sword_area_entered)

	hurtbox = get_node_or_null("HurtBox") as Area2D


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if is_multiplayer_authority() and not is_dead and not match_over:
		var dir: Vector2 = Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
		).normalized()

		net_dir = dir
		aim_to = get_global_mouse_position()

		var look_dir := aim_to - global_position
		if look_dir.length() > 0.001:
			aim_angle = look_dir.angle()
			net_aim_angle = aim_angle

			if look_dir.x < -0.001:
				facing_x = -1
			elif look_dir.x > 0.001:
				facing_x = 1

		if not multiplayer.is_server():
			rpc_id(1, "_server_set_dir", dir)
			rpc_id(1, "_server_set_aim", aim_angle, facing_x)

		if Input.is_action_just_pressed("attack") and not is_attacking:
			if multiplayer.is_server():
				_server_attack(aim_to, facing_x)
			else:
				rpc_id(1, "_server_attack", aim_to, facing_x)

	if multiplayer.is_server():
		if is_dead or match_over:
			velocity = Vector2.ZERO
		else:
			velocity = net_dir * speed

		move_and_slide()

		_sync_accum += delta
		var do_sync := true
		if sync_rate_hz > 0.0:
			var step := 1.0 / sync_rate_hz
			do_sync = _sync_accum >= step
			if do_sync:
				_sync_accum = 0.0

		if do_sync:
			rpc("_rpc_sync_state", global_position, velocity, net_aim_angle, facing_x)

	if not multiplayer.is_server():
		if is_multiplayer_authority():
			if is_dead or match_over:
				velocity = Vector2.ZERO
			else:
				velocity = net_dir * speed

			move_and_slide()

			var error := global_position.distance_to(target_pos)
			if error > 24.0:
				global_position = target_pos
			elif error > 6.0:
				global_position = global_position.lerp(target_pos, 0.35)
		else:
			global_position = global_position.lerp(target_pos, 0.25)
			velocity = target_vel
			net_aim_angle = target_aim_angle
			facing_x = target_facing_x

	if multiplayer.is_server() and is_attacking:
		_apply_attack_hits_now()

	_apply_aim_visual()
	_update_body_anim()

func _update_body_anim() -> void:
	if body == null or body.sprite_frames == null:
		return

	if is_dead:
		if body.sprite_frames.has_animation("death") and body.animation != "death":
			body.play("death")
		return

	if velocity.length() > 0.01:
		if body.sprite_frames.has_animation("run") and body.animation != "run":
			body.play("run")
	else:
		if body.sprite_frames.has_animation("idle") and body.animation != "idle":
			body.play("idle")

func _apply_aim_visual() -> void:
	var current_angle: float = net_aim_angle
	var current_facing_x: int = facing_x

	if is_multiplayer_authority():
		current_angle = aim_angle

	if visual and is_instance_valid(visual):
		visual.scale.x = float(current_facing_x)

	if not is_attacking and hand_pivot and is_instance_valid(hand_pivot):
		var local_angle := current_angle
		if current_facing_x < 0:
			local_angle = PI - current_angle
		hand_pivot.rotation = wrapf(local_angle, -PI, PI)

	if sword and is_instance_valid(sword):
		sword.rotation = 0.0

	if hit_pivot and is_instance_valid(hit_pivot) and sword and is_instance_valid(sword):
		hit_pivot.global_position = sword.global_position
		hit_pivot.global_rotation = sword.global_rotation

@rpc("any_peer", "unreliable")
func _server_set_dir(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return

	if is_dead or match_over:
		net_dir = Vector2.ZERO
		return

	net_dir = dir

@rpc("any_peer", "unreliable")
func _server_set_aim(angle: float, facing: int) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return

	net_aim_angle = angle
	facing_x = facing

@rpc("any_peer", "reliable")
func _server_attack(client_aim: Vector2, client_facing: int) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	var owner_id := _owner_peer_id()

	if sender != 0 and sender != owner_id:
		return

	if is_dead or is_attacking or match_over:
		return

	aim_to = client_aim
	facing_x = client_facing

	var look_dir := client_aim - global_position
	if look_dir.length() > 0.001:
		aim_angle = look_dir.angle()
		net_aim_angle = aim_angle

	var sword_anim: String = "sword_attackdown" if _attack_down_next else "sword_attackup"
	var slash_anim: String = "slash_down" if _attack_down_next else "slash_up"
	_attack_down_next = not _attack_down_next

	_start_attack_server(sword_anim, slash_anim)
	rpc("_rpc_play_attack", sword_anim, slash_anim)

@rpc("any_peer", "unreliable")
func _rpc_sync_state(pos: Vector2, vel: Vector2, synced_angle: float, synced_facing_x: int) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return

	target_pos = pos
	target_vel = vel
	target_aim_angle = synced_angle
	target_facing_x = synced_facing_x

func take_damage(amount: int) -> void:
	if multiplayer.is_server():
		_server_apply_damage(amount)
	else:
		rpc_id(1, "_server_apply_damage", amount)

@rpc("any_peer", "reliable")
func _server_apply_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if is_dead:
		return

	hp = max(hp - amount, 0)
	_emit_hp_changed()
	rpc("_rpc_set_hp", hp)
	rpc("_rpc_flash_hit")

	if hp <= 0:
		_die()

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_hp(new_hp: int) -> void:
	hp = new_hp
	_emit_hp_changed()

func _emit_hp_changed() -> void:
	var pips := int(ceil(float(hp) / float(pip_size)))
	var max_pips := int(ceil(float(max_hp) / float(pip_size)))
	hp_changed.emit(pips, max_pips)

func force_hp_update() -> void:
	_emit_hp_changed()

func _die() -> void:
	if is_dead:
		return

	is_dead = true
	net_dir = Vector2.ZERO
	velocity = Vector2.ZERO
	died.emit()
	rpc("_rpc_set_dead", true)

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_dead(v: bool) -> void:
	is_dead = v

func _set_visual_modulate(color: Color) -> void:
	if visual and is_instance_valid(visual):
		visual.modulate = color

@rpc("any_peer", "call_local", "reliable")
func _rpc_flash_hit() -> void:
	_flash_hit()

func _flash_hit() -> void:
	_set_visual_modulate(Color(1.0, 0.35, 0.35, 1.0))
	call_deferred("_flash_hit_restore")

func _flash_hit_restore() -> void:
	await get_tree().create_timer(hit_flash_time).timeout
	_set_visual_modulate(Color(1, 1, 1, 1))

func add_coins_server(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if is_dead or match_over:
		return

	coins += amount
	total_coins_collected += amount

	coins_changed.emit(coins)
	total_coins_changed.emit(total_coins_collected)

	rpc("_rpc_set_coins", coins)
	rpc("_rpc_set_total_coins", total_coins_collected)

	emit_weapon_state()

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_coins(v: int) -> void:
	coins = v
	coins_changed.emit(coins)
	emit_weapon_state()

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_total_coins(v: int) -> void:
	total_coins_collected = v
	total_coins_changed.emit(total_coins_collected)

func get_next_upgrade_cost() -> int:
	if sword_level >= SWORD_UPGRADE_COST.size():
		return -1
	return SWORD_UPGRADE_COST[sword_level]

func is_sword_max() -> bool:
	return sword_level >= SWORD_DAMAGES.size() - 1

func can_upgrade_sword() -> bool:
	if is_sword_max():
		return false
	var cost := get_next_upgrade_cost()
	return coins >= cost

func try_upgrade_sword() -> void:
	if is_dead:
		return

	if multiplayer.is_server():
		_server_upgrade_sword()
	else:
		rpc_id(1, "_server_upgrade_sword")

@rpc("any_peer", "reliable")
func _server_upgrade_sword() -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return

	if is_dead or is_sword_max():
		return

	var cost := get_next_upgrade_cost()
	if coins < cost:
		return

	coins -= cost
	sword_level += 1
	sword_damage = SWORD_DAMAGES[sword_level]

	coins_changed.emit(coins)
	rpc("_rpc_set_coins", coins)
	rpc("_rpc_set_sword_level", sword_level, sword_damage)
	emit_weapon_state()

@rpc("any_peer", "call_local", "reliable")
func _rpc_set_sword_level(level: int, damage: int) -> void:
	sword_level = level
	sword_damage = damage
	emit_weapon_state()

func emit_weapon_state() -> void:
	var is_max := is_sword_max()
	var next_cost := get_next_upgrade_cost()
	var can_up := can_upgrade_sword()
	weapon_state_changed.emit(sword_level, sword_damage, next_cost, is_max, can_up)

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_attack(sword_anim: String, slash_anim: String) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return
	if is_dead or is_attacking:
		return

	_start_attack_visual_only(sword_anim, slash_anim)


func _snap_attack_pivots_to_current_aim() -> void:
	var current_angle: float = net_aim_angle
	var current_facing_x: int = facing_x

	if is_multiplayer_authority():
		current_angle = aim_angle

	if hand_pivot and is_instance_valid(hand_pivot):
		var local_angle := current_angle
		if current_facing_x < 0:
			local_angle = PI - current_angle
		hand_pivot.rotation = wrapf(local_angle, -PI, PI)

	if sword and is_instance_valid(sword):
		sword.rotation = 0.0

	if hit_pivot and is_instance_valid(hit_pivot) and sword and is_instance_valid(sword):
		hit_pivot.global_position = sword.global_position
		hit_pivot.global_rotation = sword.global_rotation


func _snap_attack_pose() -> void:
	var current_angle: float = net_aim_angle

	if is_multiplayer_authority():
		current_angle = aim_angle

	if hand_pivot and is_instance_valid(hand_pivot):
		var local_angle := current_angle
		if facing_x < 0:
			local_angle = PI - current_angle
		hand_pivot.rotation = wrapf(local_angle, -PI, PI)

	if sword and is_instance_valid(sword):
		sword.rotation = 0.0

	if hit_pivot and is_instance_valid(hit_pivot) and sword and is_instance_valid(sword):
		hit_pivot.global_position = sword.global_position
		hit_pivot.global_rotation = sword.global_rotation

	_attack_forward = Vector2.RIGHT.rotated(hit_pivot.global_rotation).normalized()
	_attack_tip_world = hit_pivot.global_position + _attack_forward * melee_tip_distance


func _start_attack_server(sword_anim: String, slash_anim: String) -> void:
	_snap_attack_pose()
	_prev_attack_tip_world = _attack_tip_world
	_prev_attack_forward = _attack_forward

	is_attacking = true
	_attack_hit_ids.clear()

	_play_attack_visuals(sword_anim, slash_anim)

	if sword_hit_shape and is_instance_valid(sword_hit_shape):
		sword_hit_shape.disabled = false
	if sword_hitbox and is_instance_valid(sword_hitbox):
		sword_hitbox.monitoring = true

	call_deferred("_stop_attack_later", _get_attack_lifetime(sword_anim, slash_anim))

func _start_attack_visual_only(sword_anim: String, slash_anim: String) -> void:
	_snap_attack_pose()
	is_attacking = true
	_play_attack_visuals(sword_anim, slash_anim)
	call_deferred("_stop_attack_later", _get_attack_lifetime(sword_anim, slash_anim))

func _play_anim(node: Node, anim: String) -> void:
	if node == null or not is_instance_valid(node):
		return

	if node is AnimatedSprite2D:
		var s := node as AnimatedSprite2D
		if s.sprite_frames and s.sprite_frames.has_animation(anim):
			s.play(anim)
		return

	if node is AnimationPlayer:
		var ap := node as AnimationPlayer
		if ap.has_animation(anim):
			ap.play(anim)
		return

func _play_attack_visuals(sword_anim: String, slash_anim: String) -> void:
	_play_anim(anim_sword, sword_anim)

	if slash_anim == "slash_down":
		call_deferred("play_slash_down")
	else:
		call_deferred("play_slash_up")

func play_slash_down() -> void:
	if slash and is_instance_valid(slash) and slash.sprite_frames and slash.sprite_frames.has_animation("slash_down"):
		slash.visible = true
		slash.play("slash_down")

func play_slash_up() -> void:
	if slash and is_instance_valid(slash) and slash.sprite_frames and slash.sprite_frames.has_animation("slash_up"):
		slash.visible = true
		slash.play("slash_up")

func _get_slash_anim_duration(anim_name: String) -> float:
	if slash == null or not is_instance_valid(slash):
		return attack_duration
	if slash.sprite_frames == null:
		return attack_duration
	if not slash.sprite_frames.has_animation(anim_name):
		return attack_duration

	var frames: int = slash.sprite_frames.get_frame_count(anim_name)
	var fps: float = slash.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return attack_duration

	var duration: float = float(frames) / fps
	duration /= max(slash.speed_scale, 0.001)
	return max(duration, attack_duration)

func _get_sword_anim_duration(anim_name: String) -> float:
	if anim_sword is AnimationPlayer:
		var ap := anim_sword as AnimationPlayer
		if ap.has_animation(anim_name):
			return ap.get_animation(anim_name).length
	return attack_duration

func _get_attack_lifetime(sword_anim: String, slash_anim: String) -> float:
	return float(max(
		attack_duration,
		_get_sword_anim_duration(sword_anim),
		_get_slash_anim_duration(slash_anim)
	))

func _stop_attack_later(wait_time: float) -> void:
	await get_tree().create_timer(wait_time).timeout
	_stop_attack()

func _stop_attack() -> void:
	is_attacking = false
	_attack_hit_ids.clear()

	if slash and is_instance_valid(slash):
		slash.visible = false

	if multiplayer.is_server():
		if sword_hitbox and is_instance_valid(sword_hitbox):
			sword_hitbox.monitoring = false
		if sword_hit_shape and is_instance_valid(sword_hit_shape):
			sword_hit_shape.disabled = true


func _apply_attack_hits_now() -> void:
	if not multiplayer.is_server():
		return
	if not is_attacking:
		return

	var scene := get_tree().current_scene
	if scene == null:
		return

	var players_root := scene.get_node_or_null("Players")
	if players_root == null:
		return

	_snap_attack_pose()

	var blade_end_now: Vector2 = _attack_tip_world
	var blade_start_now: Vector2 = blade_end_now - _attack_forward * melee_blade_length

	var blade_end_prev: Vector2 = _prev_attack_tip_world
	var blade_start_prev: Vector2 = blade_end_prev - _prev_attack_forward * melee_blade_length

	for victim in players_root.get_children():
		if victim == null or victim == self:
			continue
		if not is_instance_valid(victim):
			continue
		if not victim.is_in_group("player"):
			continue
		if not victim.has_method("take_damage"):
			continue

		var target_id := victim.get_instance_id()
		if _attack_hit_ids.has(target_id):
			continue

		var hurt := victim.get_node_or_null("HurtBox") as Area2D
		var victim_pos: Vector2 = victim.global_position
		if hurt and is_instance_valid(hurt):
			victim_pos = hurt.global_position

		var c1 := Geometry2D.get_closest_point_to_segment(victim_pos, blade_start_prev, blade_end_prev)
		var c2 := Geometry2D.get_closest_point_to_segment(victim_pos, blade_start_now, blade_end_now)
		var c3 := Geometry2D.get_closest_point_to_segment(victim_pos, blade_start_prev, blade_start_now)
		var c4 := Geometry2D.get_closest_point_to_segment(victim_pos, blade_end_prev, blade_end_now)

		var d: float = min(
		min(victim_pos.distance_to(c1), victim_pos.distance_to(c2)),
		min(victim_pos.distance_to(c3), victim_pos.distance_to(c4))
		)

		if d <= melee_hit_radius:
			_attack_hit_ids[target_id] = true
			victim.take_damage(sword_damage)

	_prev_attack_tip_world = _attack_tip_world
	_prev_attack_forward = _attack_forward


func _on_sword_area_entered(_a: Area2D) -> void:
	pass

func _owner_peer_id() -> int:
	if name.begins_with("Player_"):
		return int(name.get_slice("_", 1))
	return int(peer_id)
