class_name WeatherManager
extends Node

## Clima com consequência, não só com aparência.
##
## Céu limpo, chuva e neblina. A chuva muda três coisas de verdade: densidade da
## neblina, aderência dos pneus (via VehicleManager.set_wetness) e o ruído de
## ambiente do áudio. A visibilidade é reduzida pelo próprio fog do ambiente.

signal weather_changed(kind: String)

const KINDS: Array[String] = ["clear", "rain", "fog"]

var environment: WorldEnvironment = null
var camera: Camera3D = null
var vehicle_manager: VehicleManager = null
var audio: AudioManager = null

var kind: String = "clear"
var wetness: float = 0.0

var _rain: GPUParticles3D = null
var _target_wetness: float = 0.0


func setup(world_environment: WorldEnvironment, follow_camera: Camera3D) -> void:
	environment = world_environment
	camera = follow_camera
	_build_rain()
	_apply(true)


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.emitting = false
	_rain.amount = 900
	_rain.lifetime = 0.9
	_rain.visibility_aabb = AABB(Vector3(-40.0, -20.0, -40.0), Vector3(80.0, 40.0, 80.0))
	_rain.local_coords = false

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.06, -1.0, 0.02)
	process.spread = 3.0
	process.initial_velocity_min = 22.0
	process.initial_velocity_max = 30.0
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(28.0, 1.0, 28.0)
	_rain.process_material = process

	var drop := QuadMesh.new()
	drop.size = Vector2(0.03, 0.55)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.72, 0.80, 0.92, 0.45)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	drop.material = material
	_rain.draw_pass_1 = drop
	add_child(_rain)


func _process(delta: float) -> void:
	wetness = move_toward(wetness, _target_wetness, delta * 0.08)
	if vehicle_manager != null:
		vehicle_manager.set_wetness(wetness)
	if _rain != null and camera != null:
		_rain.global_position = camera.global_position + Vector3.UP * 6.0


func set_weather(new_kind: String, silent: bool = false) -> void:
	if not KINDS.has(new_kind):
		return
	kind = new_kind
	_target_wetness = 1.0 if kind == "rain" else 0.0
	_apply(silent)


func cycle() -> void:
	var index := KINDS.find(kind)
	set_weather(KINDS[(index + 1) % KINDS.size()])


func _apply(silent: bool) -> void:
	if _rain != null:
		_rain.emitting = kind == "rain"
	if audio != null:
		audio.set_mode("rain" if kind == "rain" else "street")
	if environment != null and environment.environment != null:
		var env := environment.environment
		match kind:
			"rain":
				env.fog_enabled = true
				env.fog_light_color = Color(0.52, 0.56, 0.60)
				env.fog_density = 0.0022
				env.ambient_light_energy = 0.55
			"fog":
				env.fog_enabled = true
				env.fog_light_color = Color(0.74, 0.76, 0.78)
				env.fog_density = 0.006
				env.ambient_light_energy = 0.65
			_:
				env.fog_enabled = false
				env.fog_density = 0.0
	if not silent:
		weather_changed.emit(kind)
		CariocaBus.get_instance().weather_changed.emit(kind)


func label() -> String:
	match kind:
		"rain":
			return "Chuva"
		"fog":
			return "Neblina"
		_:
			return "Céu limpo"
