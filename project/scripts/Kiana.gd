class_name Kiana
extends RigidBody2D
## Kiana player controller
##
## Controls:
##   Drag DOWN from anywhere on screen -> rocket thrusts UP
##   Drag LEFT / RIGHT -> steers LEFT / RIGHT in that direction
##   No drag / release -> falls naturally from gravity

signal died

# Physics constants from roleConfig.json (scaled by Box2D 32 px/m)
const PTM: float = 32.0
var max_thrust: float = 28.0 * PTM   # 896 px/s^2
var steer_force: float = 24.0 * PTM  # 768 px/s^2

# Maximum drag distance in pixels for 100% thrust (matches pushDistance1 in roleConfig)
const MAX_DRAG_Y: float = 55.0
const MAX_DRAG_X: float = 48.0
const DEADZONE: float = 4.0

const MAX_X_SPEED: float = 190.0
const MAX_FALL_SPEED: float = 380.0
const MAX_CLIMB_SPEED: float = -420.0

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D

var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_current: Vector2 = Vector2.ZERO
var is_dead: bool = false
var input_enabled: bool = true

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		is_dragging = false
		linear_velocity = Vector2.ZERO
		gravity_scale = 0.0
		if drag_canvas:
			drag_canvas.queue_redraw()
		if anim_sprite:
			anim_sprite.play("idle")
	else:
		gravity_scale = 1.0

# Visual drag indicator nodes (CanvasLayer ensures screen-space 1:1 cursor alignment)
var drag_layer: CanvasLayer = null
var drag_canvas: Control = null

func _ready() -> void:
	add_to_group("player")
	mass = 1.0
	linear_damp = 0.05
	angular_damp = 5.0
	lock_rotation = true
	contact_monitor = true
	max_contacts_reported = 4

	if camera:
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = 7.0
		camera.zoom = Vector2(1.6, 1.6) # authentic iPhone framing

	setup_animations()
	setup_drag_indicator()

func setup_drag_indicator() -> void:
	drag_layer = CanvasLayer.new()
	drag_layer.layer = 100
	add_child(drag_layer)

	drag_canvas = Control.new()
	drag_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_canvas.draw.connect(_on_drag_draw)
	drag_layer.add_child(drag_canvas)

func setup_animations() -> void:
	if not anim_sprite:
		return
	var frames = SpriteFrames.new()
	_add_anim(frames, "stand", "res://assets/sprites/character/charStand", 1, 5.0)
	_add_anim(frames, "idle",  "res://assets/sprites/character/charIdle",  8, 8.0)
	_add_anim(frames, "up",    "res://assets/sprites/character/charUp",    8, 12.0)
	_add_anim(frames, "down",  "res://assets/sprites/character/charDown",  8, 8.0)
	_add_anim(frames, "left",  "res://assets/sprites/character/charLeft",  8, 10.0)
	_add_anim(frames, "right", "res://assets/sprites/character/charRight", 8, 10.0)
	_add_anim(frames, "death", "res://assets/sprites/character/charDeath", 2, 4.0)
	anim_sprite.sprite_frames = frames
	anim_sprite.play("idle")

func _add_anim(sf: SpriteFrames, anim: String, base: String, count: int, fps: float) -> void:
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, true)
	for i in range(1, count + 1):
		var gp = ProjectSettings.globalize_path("%s/%03d.png" % [base, i])
		if FileAccess.file_exists(gp):
			var img = Image.load_from_file(gp)
			if img:
				sf.add_frame(anim, ImageTexture.create_from_image(img))

func _unhandled_input(event: InputEvent) -> void:
	if is_dead or not input_enabled:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			drag_start = event.position
			drag_current = event.position
		else:
			is_dragging = false
		if drag_canvas:
			drag_canvas.queue_redraw()

	elif event is InputEventMouseMotion and is_dragging:
		drag_current = event.position
		if drag_canvas:
			drag_canvas.queue_redraw()

	elif event is InputEventScreenTouch:
		if event.pressed:
			is_dragging = true
			drag_start = event.position
			drag_current = event.position
		else:
			is_dragging = false
		if drag_canvas:
			drag_canvas.queue_redraw()

	elif event is InputEventScreenDrag and is_dragging:
		drag_current = event.position
		if drag_canvas:
			drag_canvas.queue_redraw()

func _physics_process(delta: float) -> void:
	if is_dead or not input_enabled:
		return

	var thrust := Vector2.ZERO
	var has_horizontal_input := false

	# 1. Drag controls (works anywhere on screen)
	if is_dragging:
		var delta_drag = drag_current - drag_start

		# Vertical: dragging DOWN (delta_drag.y > 0) creates UPWARD thrust (negative Y)
		if delta_drag.y > DEADZONE:
			var y_ratio = clamp((delta_drag.y - DEADZONE) / MAX_DRAG_Y, 0.0, 1.0)
			# Responsive hover-to-climb ramp: immediately overcomes gravity with slight pull
			var thrust_power = lerp(320.0 * 0.85, max_thrust, y_ratio)
			thrust.y = -thrust_power

		# Horizontal: dragging LEFT -> flies RIGHT, dragging RIGHT -> flies LEFT (slingshot pull)
		if abs(delta_drag.x) > DEADZONE:
			var x_mag = (abs(delta_drag.x) - DEADZONE) / MAX_DRAG_X
			var x_ratio = clamp(x_mag, 0.0, 1.0) * (-sign(delta_drag.x))
			var target_vx = x_ratio * MAX_X_SPEED
			thrust.x = (target_vx - linear_velocity.x) * 10.0
			has_horizontal_input = true

	# 2. Keyboard fallback for PC
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		thrust.y = -max_thrust
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		thrust.x -= steer_force
		has_horizontal_input = true
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		thrust.x += steer_force
		has_horizontal_input = true

	# Extra horizontal damping when not actively steering (prevents icy coasting)
	if not has_horizontal_input:
		linear_velocity.x = move_toward(linear_velocity.x, 0.0, 280.0 * delta)

	if thrust.length() > 0:
		apply_central_force(thrust)

	# Clamp terminal velocities
	if linear_velocity.y > MAX_FALL_SPEED:
		linear_velocity.y = MAX_FALL_SPEED
	elif linear_velocity.y < MAX_CLIMB_SPEED:
		linear_velocity.y = MAX_CLIMB_SPEED

	_update_animation(thrust)

func _update_animation(thrust: Vector2) -> void:
	if not anim_sprite or is_dead:
		return

	var v = linear_velocity
	if thrust.y < -150.0:
		if thrust.x < -80.0 or v.x < -50.0:
			_set_anim("left")
		elif thrust.x > 80.0 or v.x > 50.0:
			_set_anim("right")
		else:
			_set_anim("up")
	elif abs(v.x) > 40.0:
		if v.x < 0:
			_set_anim("left")
		else:
			_set_anim("right")
	elif v.y > 60.0:
		_set_anim("down")
	elif v.length() < 30.0:
		_set_anim("idle")

func _set_anim(anim: String) -> void:
	if anim_sprite.animation != anim:
		anim_sprite.play(anim)

func _on_drag_draw() -> void:
	if not is_dragging or not drag_canvas:
		return

	var delta_drag = drag_current - drag_start
	var col_outer = Color(0.15, 0.65, 1.0, 0.3)
	var col_ring = Color(0.2, 0.8, 1.0, 0.75)
	var col_line = Color(0.3, 0.9, 1.0, 0.8)
	var col_dot = Color(1.0, 1.0, 1.0, 0.9)

	# Starting touch circle (with border ring)
	drag_canvas.draw_circle(drag_start, 28.0, col_outer)
	drag_canvas.draw_arc(drag_start, 28.0, 0, TAU, 32, col_ring, 2.0)

	# Drag line from touch origin to current cursor
	drag_canvas.draw_line(drag_start, drag_current, col_line, 3.0)

	# Active drag handle
	drag_canvas.draw_circle(drag_current, 9.0, col_ring)
	drag_canvas.draw_circle(drag_current, 5.0, col_dot)

func set_camera_bounds(map_w: float, map_h: float) -> void:
	if camera:
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = int(map_w)
		camera.limit_bottom = int(map_h)

func kill() -> void:
	if is_dead:
		return
	is_dead = true
	linear_velocity = Vector2.ZERO
	if anim_sprite:
		anim_sprite.play("death")
	died.emit()
