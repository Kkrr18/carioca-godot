class_name Vehicle
extends VehicleBody3D

## Veículo dirigível.
##
## Usa o VehicleBody3D nativo da Godot: suspensão, atrito e tração vêm do
## servidor de física, o que é muito mais estável e barato do que reimplementar
## pneus em GDScript. O jogo só decide força de motor, freio e esterço.
##
## Física seletiva, como no plano: o carro só simula de verdade quando tem
## motorista. Estacionado, ele é um corpo parado com freio aplicado.

const MAX_ENGINE_FORCE := 1600.0
const MAX_BRAKE := 12.0
const MAX_STEER := 0.52
const REVERSE_FACTOR := 0.45
const DRY_FRICTION := 3.0
const WET_FRICTION := 1.35

var driver: Player = null
var terrain: TerrainService = null
var floating: FloatingOrigin = null
var spawn_metric: Vector2 = Vector2.ZERO
var wheel_radius: float = 0.36
var wheels: Array[VehicleWheel3D] = []
var body_color: Color = Color(0.72, 0.16, 0.14)
var wetness: float = 0.0

var _body_mesh: MeshInstance3D = null


func _ready() -> void:
	mass = 1250.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.35, 0.0)
	_build_chassis()
	_build_wheels()
	apply_wetness(0.0)


func _build_chassis() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.86, 1.05, 4.2)
	shape.shape = box
	shape.position = Vector3(0.0, 0.78, 0.0)
	add_child(shape)

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.mesh = ProceduralMeshes.car_body()
	_body_mesh.material_override = MaterialLibrary.vehicle(body_color)
	add_child(_body_mesh)


func _build_wheels() -> void:
	var positions := [
		Vector3(-0.82, 0.16, -1.32),
		Vector3(0.82, 0.16, -1.32),
		Vector3(-0.82, 0.16, 1.34),
		Vector3(0.82, 0.16, 1.34),
	]
	for i in range(4):
		var wheel := VehicleWheel3D.new()
		wheel.name = "Wheel%d" % i
		wheel.position = positions[i]
		wheel.wheel_radius = wheel_radius
		wheel.wheel_rest_length = 0.16
		wheel.wheel_friction_slip = DRY_FRICTION
		wheel.suspension_travel = 0.22
		wheel.suspension_stiffness = 36.0
		wheel.damping_compression = 0.42
		wheel.damping_relaxation = 0.58
		wheel.use_as_traction = i >= 2
		wheel.use_as_steering = i < 2
		add_child(wheel)

		var visual := MeshInstance3D.new()
		visual.mesh = ProceduralMeshes.wheel()
		visual.material_override = MaterialLibrary.prop()
		visual.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		wheel.add_child(visual)
		wheels.append(wheel)


func _physics_process(delta: float) -> void:
	if driver == null:
		engine_force = 0.0
		steering = move_toward(steering, 0.0, delta * 3.0)
		brake = MAX_BRAKE if linear_velocity.length() < 1.5 else 0.0
		return

	var input := driver.read_move_input()
	var throttle := input.y
	var steer_input := input.x
	if throttle >= 0.0:
		engine_force = throttle * MAX_ENGINE_FORCE
	else:
		engine_force = throttle * MAX_ENGINE_FORCE * REVERSE_FACTOR
	steering = move_toward(steering, steer_input * MAX_STEER, delta * 2.8)
	brake = 0.0 if absf(throttle) > 0.05 else 3.0


func set_driver(new_driver: Player) -> void:
	driver = new_driver


func clear_driver() -> void:
	driver = null
	engine_force = 0.0
	brake = MAX_BRAKE


## A chuva reduz a aderência: o clima não é só visual.
func apply_wetness(value: float) -> void:
	wetness = clampf(value, 0.0, 1.0)
	var friction := lerpf(DRY_FRICTION, WET_FRICTION, wetness)
	for wheel in wheels:
		wheel.wheel_friction_slip = friction


func metric_position() -> Vector2:
	if floating == null:
		return Vector2.ZERO
	return floating.local_to_metric(position)


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6
