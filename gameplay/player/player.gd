class_name Player
extends CharacterBody3D

## Jogador em terceira pessoa.
##
## Todas as entradas passam por `read_move_input()`, que junta teclado e toque.
## Assim o controle do carro usa exatamente a mesma leitura do controle a pé —
## é o que permite "W acelera" e "arrastar o analógico para cima acelera" sem
## duplicar regra em dois lugares.

signal entered_vehicle(vehicle: Vehicle)
signal exited_vehicle(vehicle: Vehicle)

const WALK_SPEED := 4.2
const RUN_SPEED := 7.8
const ACCELERATION := 14.0
const AIR_CONTROL := 2.2
const JUMP_SPEED := 5.4
const GRAVITY := 20.0
const INTERACT_COOLDOWN := 0.35
const VEHICLE_RADIUS := 4.5
const DOOR_RADIUS := 4.5

var camera_rig: PlayerCamera = null
var touch_controls: TouchControls = null
var vehicle_manager: VehicleManager = null
var interior_manager: InteriorManager = null
var floating: FloatingOrigin = null
var terrain: TerrainService = null

var current_vehicle: Vehicle = null
var can_move: bool = true
var sprinting: bool = false

var _jump_requested: bool = false
var _jump_held: bool = false
var _interact_cooldown: float = 0.0
var _body_mesh: MeshInstance3D = null


func _ready() -> void:
	up_direction = Vector3.UP
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.6
	collision_layer = 2
	collision_mask = 1
	_build_body()


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)

	_body_mesh = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.36
	mesh.height = 1.8
	mesh.radial_segments = 12
	mesh.rings = 4
	_body_mesh.mesh = mesh
	_body_mesh.position = Vector3(0.0, 0.9, 0.0)
	_body_mesh.material_override = MaterialLibrary.pedestrian(Color(0.18, 0.31, 0.52))
	add_child(_body_mesh)

	# Marca de frente: sem modelo animado, sem ela não dá para saber para onde
	# o personagem está virado.
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.18, 0.18, 0.26)
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, 1.42, -0.34)
	nose.material_override = MaterialLibrary.pedestrian(Color(0.92, 0.76, 0.35))
	add_child(nose)


func _physics_process(delta: float) -> void:
	_interact_cooldown = maxf(_interact_cooldown - delta, 0.0)
	_update_jump_latch()
	if current_vehicle != null:
		_pin_to_vehicle()
		return
	if not can_move:
		velocity = Vector3.ZERO
		return

	var input := read_move_input()
	var yaw := camera_rig.yaw() if camera_rig != null else 0.0
	var direction := Vector3(input.x, 0.0, -input.y).rotated(Vector3.UP, yaw)
	var magnitude := clampf(input.length(), 0.0, 1.0)
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()

	var base_speed := RUN_SPEED if sprinting else WALK_SPEED
	var target := direction * base_speed * magnitude
	var accel := ACCELERATION if is_on_floor() else AIR_CONTROL
	velocity.x = move_toward(velocity.x, target.x, accel * delta * 6.0)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * 6.0)

	if is_on_floor():
		if _jump_requested:
			velocity.y = JUMP_SPEED
			_jump_requested = false
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()
	_face_direction(direction, delta)


func _update_jump_latch() -> void:
	var jump_pressed := Input.is_key_pressed(KEY_SPACE)
	if touch_controls != null and touch_controls.consume_jump():
		jump_pressed = true
	if jump_pressed and not _jump_held:
		_jump_requested = true
	_jump_held = jump_pressed


func _face_direction(direction: Vector3, delta: float) -> void:
	if current_vehicle != null:
		return
	if direction.length_squared() < 0.01:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 12.0, 0.0, 1.0))


func _pin_to_vehicle() -> void:
	if current_vehicle == null:
		return
	velocity = Vector3.ZERO
	global_position = current_vehicle.global_position + Vector3.UP * 0.6


## Entrada unificada: teclado e analógico virtual, o maior valor vence.
func read_move_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	sprinting = Input.is_key_pressed(KEY_SHIFT)
	if touch_controls != null and touch_controls.visible_controls:
		if touch_controls.move_vector.length() > input.length():
			input = touch_controls.move_vector
	if input.length() > 1.0:
		input = input.normalized()
	return input


func try_interact() -> void:
	if _interact_cooldown > 0.0:
		return
	_interact_cooldown = INTERACT_COOLDOWN
	if current_vehicle != null:
		exit_vehicle()
		return
	if interior_manager != null and interior_manager.is_inside():
		interior_manager.exit()
		return
	if vehicle_manager != null:
		var vehicle := vehicle_manager.nearest(global_position, VEHICLE_RADIUS)
		if vehicle != null:
			enter_vehicle(vehicle)
			return
	if interior_manager != null and floating != null:
		var door := interior_manager.find_nearby_door(floating.viewer_metric(), DOOR_RADIUS)
		if not door.is_empty():
			interior_manager.enter(door)


func enter_vehicle(vehicle: Vehicle) -> void:
	if vehicle == null or current_vehicle != null:
		return
	current_vehicle = vehicle
	vehicle.set_driver(self)
	visible = false
	can_move = false
	if camera_rig != null:
		camera_rig.set_target(vehicle)
	entered_vehicle.emit(vehicle)
	CariocaBus.get_instance().vehicle_entered.emit(vehicle)


func exit_vehicle() -> void:
	var vehicle := current_vehicle
	if vehicle == null:
		return
	current_vehicle = null
	vehicle.clear_driver()
	visible = true
	can_move = true
	if camera_rig != null:
		camera_rig.set_target(self)
	var side := vehicle.global_transform.basis.x.normalized()
	var exit_position := vehicle.global_position + side * 2.3 + Vector3.UP * 1.2
	global_position = exit_position
	velocity = Vector3.ZERO
	exited_vehicle.emit(vehicle)
	CariocaBus.get_instance().vehicle_exited.emit(vehicle)


## Teleporte usado ao sair de um interior e no reset (R).
func teleport_to_local(local_position: Vector3) -> void:
	global_position = local_position
	velocity = Vector3.ZERO


func metric_position() -> Vector2:
	if floating == null:
		return Vector2.ZERO
	return floating.local_to_metric(position)


## Altura do solo no ponto atual, usada para alinhar câmera e NPCs.
func ground_height() -> float:
	if terrain == null:
		return position.y
	return terrain.height_at(metric_position())
