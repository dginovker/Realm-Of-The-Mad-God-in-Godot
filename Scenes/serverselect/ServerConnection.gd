extends Node

const PORT := 9999
const MAX_PLAYERS := 16

func _ready():
    $HostButton.pressed.connect(host_game)
    $JoinButton.pressed.connect(join_game)

    var args = OS.get_cmdline_args()
    if "--host" in args:
        print("Auto-hosting via command-line")
        host_game()
    if not "--host" in args:
        print("Auto-joining because we're not host..")
        join_game()

func host_game():
    print("Hosting game...")
    PlayerManager.start_server()
    var peer = ENetMultiplayerPeer.new()
    var result = peer.create_server(PORT, MAX_PLAYERS)
    if result != OK:
        push_error("Failed to start server!")
        return

    multiplayer.multiplayer_peer = peer
    multiplayer.connection_failed.connect(_on_connection_failed)

    # Load the game scene after starting the server
    call_deferred("load_world_scene")

func join_game():
    print("Joining game...")
    var peer = ENetMultiplayerPeer.new()
    peer.create_client("127.0.0.1", PORT)  # Replace IP as needed
    multiplayer.multiplayer_peer = peer

    multiplayer.connected_to_server.connect(load_world_scene)
    multiplayer.connection_failed.connect(_on_connection_failed)

func load_world_scene():
    var game_scene = load("res://Scenes/world/World.tscn").instantiate()
    get_tree().root.add_child(game_scene)
    queue_free()  # remove the main menu

func _on_connection_failed():
    print("Failed to connect to server.")
