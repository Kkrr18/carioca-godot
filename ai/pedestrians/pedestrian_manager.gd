class_name PedestrianManager
extends Node3D

## Pedestres nas calçadas.
##
## Mesmo grafo do trânsito, deslocamento lateral maior (calçada, não faixa),
## velocidade de caminhada e pausas ocasionais. NPC distante não executa
## comportamento nenhum: é removido ao sair do raio carregado.

const SPAWN_DISTANCE := 140.0
const DESPAWN_DISTANCE := 260.0
const GRAPH_REBUILD_INTERVAL := 2.0

var floating: FloatingOrigin = null
var streaming: SectorStreamingManager = null
var terrain: TerrainService = null
var actor_parent: Node3D = null
var player: Node3D = null
var max_pedestrians: int = 20

var graph := RoadGraph.new()
var agents: Array = []

var _rebuild_timer: float = 0.0
var _clock: float = 0.0


func setup(sector_floating: FloatingOrigin, streamer: SectorStreamingManager, sector_terrain: TerrainService, parent: Node3D, player_node: Node3D) -> void:
	floating = sector_floating
	streaming = streamer
	terrain = sector_terrain
	actor_parent = parent
	player = player_node


func _parent() -> Node3D:
	return actor_parent if actor_parent != null else self


func _physics_process(delta: float) -> void:
	if floating == null or streaming == null or terrain == null:
		return
	_clock += delta
	_rebuild_timer -= delta
	if _rebuild_timer <= 0.0:
		_rebuild_timer = GRAPH_REBUILD_INTERVAL
		graph.rebuild(_collect_payloads())
	_maintain(delta)
	for agent in agents:
		_step(agent, delta)


func _collect_payloads() -> Dictionary:
	var out := {}
	var coords: Array = streaming.loaded_coords()
	for coord in coords:
		var instance: SectorInstance = streaming.loaded_sector(coord)
		if instance != null and not instance.payload.is_empty():
			out[coord] = instance.payload
	return out


func _maintain(delta: float) -> void:
	var viewer := floating.viewer_metric()
	var kept: Array = []
	for agent in agents:
		var node: Node3D = agent.get("node")
		if not is_instance_valid(node):
			continue
		var metric: Vector2 = agent.get("position_metric", viewer)
		if metric.distance_to(viewer) > DESPAWN_DISTANCE:
			node.queue_free()
			continue
		kept.append(agent)
	agents = kept

	if graph.edge_count() == 0:
		return
	var wanted := clampi(max_pedestrians, 0, 96)
	var attempts := 0
	while agents.size() < wanted and attempts < wanted * 4:
		attempts += 1
		_spawn(viewer)


func _spawn(viewer: Vector2) -> void:
	var index := graph.nearest_road(viewer)
	if index < 0:
		return
	var entry := graph.road(index)
	var heading: Vector2 = (entry["b"] - entry["a"]).normalized()
	var forward := Deterministic.rand01(agents.size(), index, 5) > 0.5
	var from: Vector2 = entry["a"] if forward else entry["b"]
	var to: Vector2 = entry["b"] if forward else entry["a"]
	if from.distance_to(viewer) > SPAWN_DISTANCE:
		return
	var mesh := MeshInstance3D.new()
	mesh.mesh = ProceduralMeshes.pedestrian_body()
	mesh.material_override = MaterialLibrary.pedestrian(_cloth(agents.size()))
	_parent().add_child(mesh)
	agents.append({
		"node": mesh,
		"from": from,
		"to": to,
		"progress": 0.0,
		"speed": 1.1 + Deterministic.rand01(agents.size(), index, 37) * 0.7,
		"side": 1.0 if Deterministic.rand01(agents.size(), index, 43) > 0.5 else -1.0,
		"offset": float(entry["width"]) * 0.5 + 1.1,
		"pause": 0.0,
		"position_metric": from,
	})


func _cloth(index: int) -> Color:
	var palette := [
		Color(0.28, 0.36, 0.55),
		Color(0.62, 0.26, 0.24),
		Color(0.78, 0.75, 0.66),
		Color(0.24, 0.42, 0.34),
		Color(0.36, 0.30, 0.42),
	]
	return palette[index % palette.size()]


func _step(agent: Dictionary, delta: float) -> void:
	var from: Vector2 = agent["from"]
	var to: Vector2 = agent["to"]
	var length := maxf(from.distance_to(to), 0.01)
	var pause := float(agent["pause"])
	if pause > 0.0:
		agent["pause"] = maxf(pause - delta, 0.0)
	else:
		agent["progress"] = float(agent["progress"]) + float(agent["speed"]) * delta / length
		# Pausa ocasional em ~2% dos quadros, para não andar tudo em fila.
		if Deterministic.rand01(int(_clock * 13.0) + agents.size(), int(length), 71) > 0.998:
			agent["pause"] = 1.0 + float(agents.size() % 3)
	if float(agent["progress"]) >= 1.0:
		var back: Vector2 = agent["from"]
		agent["from"] = to
		agent["to"] = back
		agent["progress"] = 0.0
		return
	var metric := from.lerp(to, clampf(float(agent["progress"]), 0.0, 1.0))
	var direction := (to - from).normalized()
	var lateral := Vector2(-direction.y, direction.x) * float(agent["side"]) * float(agent["offset"])
	metric += lateral
	agent["position_metric"] = metric

	var node: Node3D = agent["node"]
	if not is_instance_valid(node):
		return
	var local := floating.metric_to_local(metric)
	local.y = terrain.height_at(metric) + 0.9
	node.position = local
	node.rotation.y = atan2(-direction.x, direction.y)


func agent_count() -> int:
	return agents.size()
