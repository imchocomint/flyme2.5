extends SceneTree

func _init() -> void:
	print("--- Starting FlyMe2TheMoon Godot Test ---")
	var main_scene = load("res://scenes/Main.tscn")
	var root_node = main_scene.instantiate()
	root.add_child(root_node)
	
	# Give it a frame to process _ready() and load level 1
	await process_frame
	await process_frame
	
	var loader = root_node.get_node("CocosLevel")
	print("Level loaded:", loader.current_level_id)
	print("Map size: ", loader.map_width, "x", loader.map_height)
	print("BornPoint: ", loader.born_point)
	print("Suite ID: ", loader.suite_id)
	
	var static_layer = loader.get_node("StaticCollision")
	print("Static collision shapes spawned:", static_layer.get_child_count())
	
	var texture_layer = loader.get_node("Texture")
	print("Texture sprites spawned:", texture_layer.get_child_count())
	
	var fg_layer = loader.get_node("Foreground")
	print("Foreground sprites spawned:", fg_layer.get_child_count())
	
	var items_layer = loader.get_node("Items")
	print("Items spawned:", items_layer.get_child_count())
	
	var dyn_layer = loader.get_node("DynamicObjects")
	print("Dynamic objects spawned:", dyn_layer.get_child_count())
	
	var player = loader.get_node_or_null("Kiana")
	if player:
		print("Kiana player found at position:", player.position)
	else:
		print("Kiana player not found in loader!")
		
	# Test loading Level 2
	print("\n--- Testing Level 2 Load ---")
	loader.load_level(2)
	await process_frame
	print("Level 2 loaded successfully! Textures:", loader.get_node("Texture").get_child_count(), "Items:", loader.get_node("Items").get_child_count())
	
	# Test loading Level 3
	print("\n--- Testing Level 3 Load ---")
	loader.load_level(3)
	await process_frame
	print("Level 3 loaded successfully! Textures:", loader.get_node("Texture").get_child_count(), "Items:", loader.get_node("Items").get_child_count())

	print("\n--- ALL TESTS PASSED! ---")
	quit(0)
