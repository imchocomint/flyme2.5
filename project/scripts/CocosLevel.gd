class_name CocosLevel
extends Node2D

signal level_loaded(level_id: int)
signal role_reached_moon
signal role_died
signal item_collected(item_type: int, position: Vector2)

@export var current_level_id: int = 1
@export var player_scene: PackedScene

var map_width: float = 960.0
var map_height: float = 1440.0
var suite_id: int = 1
var born_point: Vector2 = Vector2.ZERO

var edge_data: Dictionary = {}
var player_instance: Node2D = null
var texture_cache: Dictionary = {}

# Layer containers with explicit z-index separation
var layer_sky: Node2D
var layer_background: Node2D
var layer_farground: Node2D
var layer_static: StaticBody2D
var layer_texture: Node2D
var layer_dynamic: Node2D
var layer_items: Node2D
var layer_foreground: Node2D

# ── Bootstrap ────────────────────────────────────────────────────────

func _ready() -> void:
	load_edge_data()
	setup_layer_containers()
	if current_level_id > 0:
		load_level(current_level_id)

func load_edge_data() -> void:
	var file = FileAccess.open("res://data/edge_data.json", FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			edge_data = parsed
		file.close()

func setup_layer_containers() -> void:
	for c in get_children():
		c.queue_free()

	layer_sky        = _make_layer("SkyGradient",    -400)
	layer_background = _make_layer("Background",     -300)
	layer_farground  = _make_layer("Farground",      -200)

	layer_static = StaticBody2D.new()
	layer_static.name = "StaticCollision"
	layer_static.collision_layer = 2
	layer_static.collision_mask = 1
	layer_static.z_index = -100
	add_child(layer_static)

	layer_texture    = _make_layer("Texture",          0)
	layer_dynamic    = _make_layer("DynamicObjects",   100)
	layer_items      = _make_layer("Items",            200)
	layer_foreground = _make_layer("Foreground",       300)

func _make_layer(n: String, z: int) -> Node2D:
	var nd = Node2D.new()
	nd.name = n
	nd.z_index = z
	add_child(nd)
	return nd

# ── Level load ───────────────────────────────────────────────────────

func clear_level() -> void:
	texture_cache.clear()
	for container in [layer_sky, layer_background, layer_farground, layer_static,
			layer_texture, layer_dynamic, layer_items, layer_foreground]:
		if container:
			for child in container.get_children():
				container.remove_child(child)
				child.queue_free()
	if player_instance and is_instance_valid(player_instance):
		remove_child(player_instance)
		player_instance.queue_free()
		player_instance = null

func load_level(level_id: int) -> bool:
	clear_level()
	current_level_id = level_id
	var xml_path = "res://data/levels/Level_%03d.xml" % level_id
	if not FileAccess.file_exists(xml_path):
		push_error("Level XML not found: " + xml_path)
		return false

	var parser = XMLParser.new()
	if parser.open(xml_path) != OK:
		push_error("Failed to parse XML: " + xml_path)
		return false

	var cur_layer_name := ""
	var cur_layer_type := -1
	var cur_layer_w := 960.0
	var cur_layer_h := 1440.0
	suite_id = 1

	var layer_objs: Dictionary = {}

	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var tag = parser.get_node_name()

		if tag == "Map":
			if parser.has_attribute("Width"):
				map_width = parser.get_named_attribute_value("Width").to_float()
			if parser.has_attribute("Height"):
				map_height = parser.get_named_attribute_value("Height").to_float()
		elif tag == "Suite":
			if parser.has_attribute("ID"):
				suite_id = parser.get_named_attribute_value("ID").to_int()
		elif tag == "BornPoint":
			var bx = parser.get_named_attribute_value("X").to_float()
			var by = parser.get_named_attribute_value("Y").to_float()
			born_point = Vector2(bx, map_height - by)
		elif tag == "Layer":
			cur_layer_name = parser.get_named_attribute_value_safe("Name")
			cur_layer_type = parser.get_named_attribute_value_safe("Type").to_int()
			cur_layer_w = parser.get_named_attribute_value_safe("Width").to_float()
			cur_layer_h = parser.get_named_attribute_value_safe("Height").to_float()
			if cur_layer_w == 0: cur_layer_w = map_width
			if cur_layer_h == 0: cur_layer_h = map_height
		elif tag == "Obj":
			var obj_info = {
				"x": parser.get_named_attribute_value_safe("X").to_float(),
				"y": parser.get_named_attribute_value_safe("Y").to_float(),
				"seq": parser.get_named_attribute_value_safe("SeqID").to_int(),
				"rot": parser.get_named_attribute_value_safe("Rotation").to_float(),
				"flip_x": parser.get_named_attribute_value_safe("IsXFlipped").to_lower() == "true",
				"flip_y": parser.get_named_attribute_value_safe("IsYFlipped").to_lower() == "true",
				"depth": parser.get_named_attribute_value_safe("Depth").to_int(),
				"lname": cur_layer_name,
				"ltype": cur_layer_type,
				"lw": cur_layer_w,
				"lh": cur_layer_h,
			}
			if not layer_objs.has(cur_layer_type):
				layer_objs[cur_layer_type] = []
			layer_objs[cur_layer_type].append(obj_info)

	# 1. Spawn sky gradient behind the level
	_create_sky_gradient()

	# 2. Sort each layer's objects by Depth, then spawn in order
	for ltype in layer_objs:
		var objs: Array = layer_objs[ltype]
		objs.sort_custom(func(a, b): return a["depth"] < b["depth"])
		for o in objs:
			_spawn_object(o)

	# 3. Spawn player at BornPoint
	spawn_player()
	level_loaded.emit(level_id)
	return true

func _create_sky_gradient() -> void:
	var top_color: Color
	var bottom_color: Color

	match suite_id:
		1: # Forest
			top_color = Color(0.24, 0.58, 0.85)
			bottom_color = Color(0.08, 0.18, 0.14)
		2: # Twilight
			top_color = Color(0.42, 0.22, 0.55)
			bottom_color = Color(0.12, 0.08, 0.20)
		3: # Crystal / Ice (Level 1)
			top_color = Color(0.29, 0.60, 0.84)
			bottom_color = Color(0.06, 0.10, 0.20)
		4: # Desert / Sunset
			top_color = Color(0.85, 0.55, 0.32)
			bottom_color = Color(0.22, 0.10, 0.08)
		_:
			top_color = Color(0.25, 0.50, 0.80)
			bottom_color = Color(0.05, 0.08, 0.15)

	var poly = Polygon2D.new()
	poly.name = "Sky"
	poly.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(map_width, 0),
		Vector2(map_width, map_height),
		Vector2(0, map_height)
	])
	poly.vertex_colors = PackedColorArray([
		top_color,
		top_color,
		bottom_color,
		bottom_color
	])
	layer_sky.add_child(poly)

# ── Object spawning ──────────────────────────────────────────────────

func _spawn_object(o: Dictionary) -> void:
	var ltype: int   = o["ltype"]
	var lw: float    = o["lw"]
	var lh: float    = o["lh"]
	var ox: float    = o["x"]
	var oy: float    = o["y"]
	var seq: int     = o["seq"]
	var rot: float   = o["rot"]
	var flip_x: bool = o["flip_x"]
	var flip_y: bool = o["flip_y"]

	var scale_x = map_width / lw
	var scale_y = map_height / lh
	var gx = ox * scale_x
	var gy = map_height - (oy * scale_y)

	match ltype:
		0, 1: # Background / Farground
			var prefix = "Background" if ltype == 0 else "Farground"
			var path = "res://assets/sprites/suite_%d/%s_%03d.png" % [suite_id, prefix, seq]
			var spr = _make_sprite(path, Vector2(gx, gy), rot, flip_x, flip_y)
			if spr:
				(layer_background if ltype == 0 else layer_farground).add_child(spr)

		2: # StaticObject — collision geometry
			var edge_key = str(seq)
			if edge_data.has(edge_key):
				var pts: Array = edge_data[edge_key]
				var packed = PackedVector2Array()
				for pt in pts:
					var px: float = pt[0]
					var py: float = pt[1]
					if flip_x:
						px = -px
					if flip_y:
						py = -py
					packed.append(Vector2(px, -py))
				var poly = CollisionPolygon2D.new()
				poly.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
				poly.polygon = packed
				poly.position = Vector2(gx, gy)
				poly.rotation_degrees = rot
				layer_static.add_child(poly)

		3, 6: # Texture / Foreground
			var prefix = "Texture" if ltype == 3 else "Foreground"
			var path = "res://assets/sprites/suite_%d/%s_%03d.png" % [suite_id, prefix, seq]
			var spr = _make_sprite(path, Vector2(gx, gy), rot, flip_x, flip_y)
			if spr:
				(layer_texture if ltype == 3 else layer_foreground).add_child(spr)

		4: # DynamicObject
			if seq == 101:
				_spawn_moon(ox, oy, rot, flip_x, flip_y)
			else:
				_spawn_dynamic_object(seq, ox, oy, rot, flip_x, flip_y)

		5: # Item
			_spawn_item(seq, ox, oy)

# ── Helpers ──────────────────────────────────────────────────────────

func get_texture(res_path: String) -> Texture2D:
	if texture_cache.has(res_path):
		return texture_cache[res_path]
	var gp = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(gp):
		return null
	var img = Image.load_from_file(gp)
	if img:
		var tex = ImageTexture.create_from_image(img)
		texture_cache[res_path] = tex
		return tex
	return null

## Creates sprite using Cocos2d-iphone's actual anchorPoint (0, 0) [bottom-left]
## Uses a Node2D pivot at pos with rotation_degrees = rot, and child Sprite2D positioned at top-left.
## In Cocos2d (+Y up), (0,0) is bottom-left. In Godot (+Y down), bottom-left is (0,0) and top-left is (0, -h).
## Flipping is applied via flip_h/flip_v with adjusted top-left bounds:
##   flip_x: rect x in [-w, 0] -> pos.x = -w
##   flip_y: rect y in [0, h]   -> pos.y = 0.0
func _make_sprite(path: String, pos: Vector2, rot: float, flip_x: bool, flip_y: bool) -> Node2D:
	var tex = get_texture(path)
	if not tex:
		return null

	var pivot = Node2D.new()
	pivot.position = pos
	pivot.rotation_degrees = rot

	var w = float(tex.get_width())
	var h = float(tex.get_height())

	var spr = Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.position = Vector2(-w if flip_x else 0.0, 0.0 if flip_y else -h)
	spr.flip_h = flip_x
	spr.flip_v = flip_y
	pivot.add_child(spr)
	return pivot

## Spawns dynamic objects (Spikes, springs, moving hazards, etc.)
## In Cocos2d-iphone, DynamicObject uses center positioning derived from bottom-left (ox, oy)
## and rotates around its center point.
func _spawn_dynamic_object(seq_id: int, ox: float, oy: float, rot: float, flip_x: bool, flip_y: bool) -> void:
	var path = "res://assets/sprites/dynamic/DynamicObject_%03d.png" % seq_id
	var tex = get_texture(path)
	if not tex:
		return

	var w = float(tex.get_width())
	var h = float(tex.get_height())
	var hw = w * 0.5
	var hh = h * 0.5

	var rad = deg_to_rad(rot)
	var cos_r = cos(rad)
	var sin_r = sin(rad)
	var center_x = ox + hw * cos_r - hh * sin_r
	var center_y = oy + hw * sin_r + hh * cos_r

	var gx = center_x
	var gy = map_height - center_y

	var spr = Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.position = Vector2(gx, gy)
	spr.rotation_degrees = rot
	spr.flip_h = flip_x
	spr.flip_v = flip_y
	layer_dynamic.add_child(spr)

func _spawn_moon(ox: float, oy: float, rot: float = 0.0, flip_x: bool = false, flip_y: bool = false) -> void:
	var path = "res://assets/sprites/dynamic/DynamicObject_101.png"
	var tex = get_texture(path)
	if not tex:
		return

	var w = float(tex.get_width())
	var h = float(tex.get_height())
	var hw = w * 0.5
	var hh = h * 0.5

	var rad = deg_to_rad(rot)
	var cos_r = cos(rad)
	var sin_r = sin(rad)
	var center_x = ox + hw * cos_r - hh * sin_r
	var center_y = oy + hw * sin_r + hh * cos_r

	var gx = center_x
	var gy = map_height - center_y

	var area = Area2D.new()
	area.name = "MoonGoal"
	area.position = Vector2(gx, gy)
	area.rotation_degrees = rot
	area.collision_layer = 8
	area.collision_mask = 1

	var spr = Sprite2D.new()
	spr.texture = tex
	spr.scale = Vector2(0.72, 0.72)
	spr.flip_h = flip_x
	spr.flip_v = flip_y
	spr.centered = true
	area.add_child(spr)

	var col = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 36.0
	col.shape = circle
	area.add_child(col)

	area.body_entered.connect(func(body):
		if body.is_in_group("player"):
			if player_instance and player_instance.has_method("set_input_enabled"):
				player_instance.set_input_enabled(false)
			role_reached_moon.emit()
	)
	layer_dynamic.add_child(area)

func _spawn_item(seq_id: int, ox: float, oy: float) -> void:
	var path = "res://assets/sprites/dynamic/Item_%03d.png" % seq_id
	var tex = get_texture(path)
	var w = float(tex.get_width()) if tex else 32.0
	var h = float(tex.get_height()) if tex else 32.0

	# Items in Cocos2d are centered at (ox + w/2, oy + h/2)
	var center_x = ox + w * 0.5
	var center_y = oy + h * 0.5
	var gx = center_x
	var gy = map_height - center_y

	var area = Area2D.new()
	area.name = "Item_%d" % seq_id
	area.position = Vector2(gx, gy)
	area.collision_layer = 4
	area.collision_mask = 1

	var spr = Sprite2D.new()
	if tex:
		spr.texture = tex
	spr.centered = true
	area.add_child(spr)

	var col = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 16.0
	col.shape = circle
	area.add_child(col)

	area.body_entered.connect(func(body):
		if body.is_in_group("player"):
			item_collected.emit(seq_id, Vector2(gx, gy))
			area.queue_free()
	)
	layer_items.add_child(area)

func spawn_player() -> void:
	if not player_scene:
		player_scene = load("res://scenes/Kiana.tscn")
	if player_scene:
		player_instance = player_scene.instantiate()
		player_instance.position = born_point
		player_instance.z_index = 150
		add_child(player_instance)
		if player_instance.has_method("set_camera_bounds"):
			player_instance.set_camera_bounds(map_width, map_height)
