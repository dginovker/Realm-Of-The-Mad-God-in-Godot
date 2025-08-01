extends CharacterBody3D

# Spawn is managed by MobMultiplayerSpawner

@export var speed = 2.0
@export var shoot_cooldown = 1.0
@export var wander_range = 100.0
@export var debug = true
@export var health = 100
@export var loot_table = {
    "health_potion": 1,
    "tier_0_sword": 0.5
}

var players_in_range = []
var wander_direction = Vector3.ZERO
var wander_timer = 0.0
var shoot_timer = 0.0
var wander_center: Vector3
var is_paused = false
var pause_timer = 0.0

func _enter_tree():
    $MultiplayerSynchronizer.add_visibility_filter(_visibility_filter)
    $MultiplayerSynchronizer.update_visibility()

func _visibility_filter(other_p: int) -> bool:
    return PlayerManager.map_players.get(other_p, false)
    
func _ready():
    # Server has authority over all mobs
    set_multiplayer_authority(1)  # 1 = server ID

    # Only server runs mob logic
    if not is_multiplayer_authority():
        return
        
    wander_center = global_position
    _new_wander_direction()
    $AggressionArea.body_entered.connect(_on_player_entered)
    $AggressionArea.body_exited.connect(_on_player_exited)

func _physics_process(delta):
    # Only server processes mob AI and movement
    if not is_multiplayer_authority():
        return

    shoot_timer -= delta
    pause_timer -= delta
    velocity.y -= 1000

    var target_player: Player3D = _get_nearest_player()
    if target_player:
        wander_center = global_position
        _chase_player(target_player, delta)
    else:
        _wander(delta)

    move_and_slide()

func _chase_player(player: Player3D, _delta):
    var direction: Vector3 = (player.global_position - global_position).normalized()
    direction.y = 0
    velocity = direction * speed

    if shoot_timer <= 0:
        shoot_at_player(player)
        shoot_timer = shoot_cooldown

func shoot_at_player(player):
    var bullet_direction: Vector3 = (player.global_position - global_position).normalized()
    var bullet_pos = global_position
    bullet_pos.y = 2
    var bullet_type: Bullet = Bullet.new('tier_0_bullet.png', bullet_pos, bullet_direction, 2**1)
    get_tree().get_first_node_in_group("bullet_spawner").spawn_bullet(bullet_type)

func _wander(delta):
    wander_timer -= delta

    if is_paused:
        velocity = Vector3.ZERO
        if pause_timer <= 0:
            is_paused = false
            _new_wander_direction()
        return

    if wander_timer <= 0 or global_position.distance_to(wander_center) > wander_range:
        _new_wander_direction()

    assert(wander_direction.y == 0)
    velocity = wander_direction * speed * 0.5

func _new_wander_direction():
    # Chance to pause instead of moving
    if randf() < 0.7:
        is_paused = true
        pause_timer = randf_range(1.0, 2.5)
        return

    # Choose direction that stays within wander range
    var attempts = 0
    while attempts < 10:
        wander_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
        var test_position = global_position + wander_direction * speed * 0.5 * 2.0
        if test_position.distance_to(wander_center) <= wander_range:
            break
        attempts += 1

    wander_timer = randf_range(1.0, 3.0)

func _get_nearest_player():
    # Clean up invalid players first
    players_in_range = players_in_range.filter(func(p): return is_instance_valid(p))

    if players_in_range.is_empty():
        return null

    var nearest = players_in_range[0]
    var nearest_distance = global_position.distance_squared_to(nearest.global_position)

    for player in players_in_range:
        var distance = global_position.distance_squared_to(player.global_position)
        if distance < nearest_distance:
            nearest = player
            nearest_distance = distance

    return nearest

func _on_player_entered(body):
    if body.is_in_group("players") and not players_in_range.has(body):
        players_in_range.append(body)

func _on_player_exited(body):
    if body.is_in_group("players"):
        players_in_range.erase(body)

func take_damage(amount):
    assert(multiplayer.is_server(), "Client is somehow deciding how much damage mobs take")
    if health < 0:
        return

    if not multiplayer.is_server():
        return

    health -= amount
    if health < 0:
        handle_death.rpc()


@rpc("any_peer", "call_local", "reliable")
func handle_death():
    # Disable the mob immediately
    set_physics_process(false)
    set_process(false)
    $CollisionShape3D.set_deferred("disabled", true)
    $Sprite3D.visible = false  # Hide the sprite but keep the node

    if multiplayer.is_server():
        call_deferred("roll_loot_drops")
        # I love race conditions
        await get_tree().create_timer(5).timeout
        queue_free()

func roll_loot_drops():
    # Only server should roll loot
    if not multiplayer.is_server():
        return

    var dropped_items: Array[String] = []

    # Roll each item in the loot table
    for item_name in loot_table:
        var chance: float = loot_table[item_name]
        if randf() <= chance:
            dropped_items.append(item_name)

    # If we have items to drop, spawn a loot bag
    if not dropped_items.is_empty():
        spawn_loot_bag(dropped_items)

func spawn_loot_bag(items: Array[String]):
    assert(multiplayer.is_server(), "Somehow trying to spawn lootbag even though we're not the server!")
    var loot_bag_data = {
        "position": global_position,
        "items": items
    }

    var loot_spawner: LootSpawner = get_tree().get_first_node_in_group("loot_spawners")
    loot_spawner.spawn_loot_bag(loot_bag_data)
