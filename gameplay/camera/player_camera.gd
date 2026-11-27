class_name PlayerCamera
extends Node3D

## Câmera em terceira pessoa com colisão.
##
## Sem SpringArm3D de propósito: o controle do braço de colisão fica explícito
## em um raio só, o que evita a ambiguidade de eixo do SpringArm e deixa a
## distância de câmera independente da orientação do jogador.

const MIN_DISTANCE := 1.2
const POSITION_LERP := 11.0
const DISTANCE_LERP := 14.0

var target: Node3D = null
var yaw: float = 0.0
var pitch: float = -0.22
var distance: float = 4.4
var height_offset: float = 1.55
var sensitivity: float = 0.0022
var touch_controls: TouchControls = null
var camera: Camera3D = null

var _current_distance: float = 4.4


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 75.0
	camera.near = 0.08
	camera.far = 2400.0
	camera.current = true
	add_child(camera)


func set_target(new_target: Node3D) -> void:
	target = new_target
	if target != null:
		global_position = target.global_position + Vector3.UP * height_offset


func _process(delta: float) -> void:
	if target == null:
		return
	var desired := target.global_position + Vector3.UP * height_offset
	global_position = global_position.lerp(desired, clampf(delta * POSITION_LERP, 0.0, 1.0))
	rotation = Vector3(pitch, yaw, 0.0)
	_consume_touch_look()
	_update_distance(delta)


func _consume_touch_look() -> void:
	if touch_controls == null:
		return
	var look := touch_controls.consume_look()
	if look.length_squared() < 0.0001:
		return
	yaw -= look.x * 0.0038
	pitch = clampf(pitch - look.y * 0.0038, deg_to_rad(-68.0), deg_to_rad(46.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		yaw -= motion.relative.x * sensitivity
		pitch = clampf(pitch - motion.relative.y * sensitivity, deg_to_rad(-68.0), deg_to_rad(46.0))


func _update_distance(delta: float) -> void:
	var wanted := distance
	var forward := global_transform.basis.z
	var from := global_position
	var to := global_position + forward * distance
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var excluded: Array[RID] = []
		var body := target as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var hit_position: Vector3 = hit["position"]
			wanted = maxf(from.distance_to(hit_position) - 0.35, MIN_DISTANCE)
	_current_distance = lerpf(_current_distance, wanted, clampf(delta * DISTANCE_LERP, 0.0, 1.0))
	camera.position = Vector3(0.0, 0.0, _current_distance)


func yaw_angle() -> float:
	return yaw


func current_distance() -> float:
	return _current_distance
