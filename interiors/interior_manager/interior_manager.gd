class_name InteriorManager
extends Node3D

## Gerencia o dentro e o fora.
##
## O interior não substitui o mundo: ele fica 500 m abaixo dele. O jogador é
## teleportado para lá e o streaming é congelado enquanto ele está dentro, o que
## economiza o custo mais caro do jogo justamente quando não há mundo a mostrar.
## Ao sair, o jogador volta à porta exata de onde entrou.
##
## É por isso que interiores não precisam de cena separada, de carregamento de
## nível nem de reinício de sistemas: é um teleporte com três sistemas pausados.

signal entered(interior_id: String)
signal exited()

const INTERIOR_ORIGIN := Vector3(0.0, -500.0, 0.0)
const SPAWN_OFFSET := Vector3(2.5, 1.1, 2.4)

var player: Player = null
var floating: FloatingOrigin = null
var streaming: SectorStreamingManager = null
var traffic: TrafficManager = null
var pedestrians: PedestrianManager = null
var audio: AudioManager = null

var _inside: bool = false
var _return_position: Vector3 = Vector3.ZERO
var _return_vehicle: Vehicle = null
var _root: Node3D = null
var _doors_by_sector: Dictionary = {}
var _current_id: String = ""


func setup(world_player: Player, origin: FloatingOrigin, streamer: SectorStreamingManager) -> void:
	player = world_player
	floating = origin
	streaming = streamer
	_ensure_built()
	if streaming != null:
		streaming.sector_built.connect(_on_sector_built)
		streaming.sector_dropped.connect(_on_sector_dropped)


func _ensure_built() -> void:
	if _root != null:
		return
	_root = ApartmentBuilder.build()
	_root.position = INTERIOR_ORIGIN
	add_child(_root)


func is_inside() -> bool:
	return _inside


func _on_sector_built(coord: Vector2i) -> void:
	var instance := streaming.loaded_sector(coord)
	if instance == null:
		return
	_doors_by_sector[coord] = instance.door_positions(SectorGrid.sector_origin(coord))


func _on_sector_dropped(coord: Vector2i) -> void:
	_doors_by_sector.erase(coord)


## Porta mais próxima em espaço métrico. Chamado pelo jogador ao apertar E.
func find_nearby_door(metric: Vector2, radius: float) -> Dictionary:
	if _inside:
		return {}
	var best: Dictionary = {}
	var best_distance := radius
	for coord in _doors_by_sector.keys():
		var doors: Array = _doors_by_sector[coord]
		for door in doors:
			var door_metric: Vector2 = door["metric"]
			var distance := door_metric.distance_to(metric)
			if distance < best_distance:
				best_distance = distance
				best = door
	return best


func enter(door: Dictionary) -> void:
	if _inside or player == null:
		return
	_ensure_built()
	_inside = true
	_current_id = "%s_%d" % [str(door.get("building_id", "?")), int(Time.get_ticks_msec())]
	_return_position = player.global_position
	_return_vehicle = player.current_vehicle if player.current_vehicle != null else null

	if streaming != null:
		streaming.enabled = false
	if traffic != null:
		traffic.set_physics_process(false)
	if pedestrians != null:
		pedestrians.set_physics_process(false)
	if audio != null:
		audio.set_mode("interior")

	player.teleport_to_local(INTERIOR_ORIGIN + SPAWN_OFFSET)
	if player.camera_rig != null:
		player.camera_rig.yaw = PI
	entered.emit(_current_id)
	CariocaBus.get_instance().interior_entered.emit(_current_id)


func exit() -> void:
	if not _inside:
		return
	_inside = false
	if streaming != null:
		streaming.enabled = true
	if traffic != null:
		traffic.set_physics_process(true)
	if pedestrians != null:
		pedestrians.set_physics_process(true)
	if audio != null:
		audio.set_mode("street")
	if player != null:
		player.teleport_to_local(_return_position + Vector3(0.0, 0.4, 0.0))
	exited.emit()
	CariocaBus.get_instance().interior_exited.emit()


func exit_point_local() -> Vector3:
	return INTERIOR_ORIGIN + ApartmentBuilder.EXIT_POINT


func door_count() -> int:
	var total := 0
	for coord in _doors_by_sector.keys():
		total += (_doors_by_sector[coord] as Array).size()
	return total
