extends Node

var peer: WebSocketMultiplayerPeer

func _ready():
    peer = WebSocketMultiplayerPeer.new()
    
    if OS.get_name() == "Web":
        # Join the server
        print("Joining as Websocket Client..")
        peer.create_client("ws://127.0.0.1:10000") # Test Local!!
        multiplayer.multiplayer_peer = peer
        #peer.create_client("wss://duck.openredsoftware.com/blobjump") # Real server!
    else:
        # We are the server
        PlayerManager.start_listening()
        peer.create_server(10000)

        multiplayer.multiplayer_peer = peer # Todo - Test what happens if I remove this then document it
    
        await get_tree().process_frame # Wait a frame so we don't change scenes during _ready
    
        var game_scene = load("res://Scenes/3dWorld/3Dworld.tscn").instantiate()
        get_tree().root.add_child(game_scene)
        PlayerManager.spawn_player(1)
        queue_free()  # remove the main menu
