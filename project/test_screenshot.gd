extends SceneTree

func _init() -> void:
	print("--- Running Screenshot Test in Godot ---")
	var main_scene = load("res://scenes/Main.tscn")
	var root_node = main_scene.instantiate()
	root.add_child(root_node)
	
	# Process multiple frames for physics and rendering
	for i in range(10):
		await process_frame
		
	var img = root.get_viewport().get_texture().get_image()
	if img:
		img.save_png("godot_screenshot.png")
		print("Saved godot_screenshot.png successfully! Size:", img.get_size())
	else:
		print("Failed to get viewport image!")
		
	quit(0)
