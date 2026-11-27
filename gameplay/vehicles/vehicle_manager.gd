class_name VehicleManager
extends Node3D

## Donos dos veículos do mundo.
##
## Os carros nascem como filhos da raiz de atores (e não deste nó), porque é
## essa raiz que o FloatingOrigin desloca. O manager só decide quando e onde.

var terrain: TerrainService = null
var floating: FloatingOrigin = null
var actor_parent: Node3D = null
var max_vehicles: int = 8
var default_profile: DrivingProfile = null

var _vehicles: Array[Vehicle] = []
var _wetness: float = 0.0
var _spawn_counter: int = 0


func setup(sector_terrain: TerrainService, origin: FloatingOrigin, parent: Node3D) -> void:
	terrain = sector_terrain
	floating = origin
	actor_parent = parent
	if default_profile == null:
		default_profile = DrivingProfile.new()


## Perfil vindo do preset de qualidade. Aplica aos carros vivos também:
## trocar de perfil gráfico não deixa os carros discordando do preset.
func apply_preset(preset: Dictionary) -> void:
	default_profile = DrivingProfile.from_preset(preset)
	for vehicle in _vehicles:
		if is_instance_valid(vehicle):
			vehicle.apply_drive_profile(default_profile)


func _parent() -> Node3D:
	return actor_parent if actor_parent != null else self


func spawn_at(metric: Vector2, heading: float = 0.0, color: Color = Color(0.72, 0.16, 0.14)) -> Vehicle:
	if terrain == null or floating == null:
		return null
	if _vehicles.size() >= max_vehicles:
		return null
	var vehicle := Vehicle.new()
	vehicle.terrain = terrain
	vehicle.floating = floating
	vehicle.spawn_metric = metric
	vehicle.body_color = color
	if default_profile != null:
		vehicle.apply_drive_profile(default_profile)
	var height := terrain.height_at(metric) + 1.4
	vehicle.position = floating.metric_to_local(metric, height)
	vehicle.rotation.y = heading
	_parent().add_child(vehicle)
	vehicle.apply_wetness(_wetness)
	_vehicles.append(vehicle)
	_spawn_counter += 1
	return vehicle


## Spawn de conveniência: um carro parado ao lado do jogador.
func spawn_near(player_position: Vector3, offset: Vector3) -> Vehicle:
	if floating == null:
		return null
	var metric := floating.local_to_metric(player_position + offset)
	var heading := fposmod(float(_spawn_counter) * 1.7, TAU)
	return spawn_at(metric, heading, _color_for(_spawn_counter))


func _color_for(index: int) -> Color:
	var palette := [
		Color(0.72, 0.16, 0.14),
		Color(0.16, 0.28, 0.52),
		Color(0.82, 0.82, 0.80),
		Color(0.20, 0.44, 0.30),
		Color(0.28, 0.28, 0.30),
		Color(0.86, 0.68, 0.20),
	]
	return palette[index % palette.size()]


func nearest(local_position: Vector3, radius: float) -> Vehicle:
	var best: Vehicle = null
	var best_distance := radius
	for vehicle in _vehicles:
		if not is_instance_valid(vehicle):
			continue
		if vehicle.driver != null:
			continue
		var distance := vehicle.global_position.distance_to(local_position)
		if distance < best_distance:
			best_distance = distance
			best = vehicle
	return best


func all_vehicles() -> Array[Vehicle]:
	return _vehicles


func set_wetness(value: float) -> void:
	_wetness = clampf(value, 0.0, 1.0)
	for vehicle in _vehicles:
		if is_instance_valid(vehicle):
			vehicle.apply_wetness(_wetness)


func count() -> int:
	return _vehicles.size()


func remove_invalid() -> void:
	var kept: Array[Vehicle] = []
	for vehicle in _vehicles:
		if is_instance_valid(vehicle):
			kept.append(vehicle)
	_vehicles = kept
