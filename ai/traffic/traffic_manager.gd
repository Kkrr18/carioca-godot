class_name TrafficManager
extends Node3D

## Trânsito simplificado.
##
## Não é um simulador de fluxo: cada agente percorre uma aresta do grafo, desvia
## para a faixa da direita, freia para carro à frente e para no semáforo. Ao
## chegar ao nó, escolhe qualquer aresta que saia dali — o que produz o efeito
## de trânsito circulando sem custo de pathfinding por agente.
##
## Densidade é limitada por perfil gráfico, e só existe trânsito perto do
## jogador: fora do raio carregado não há agente nenhum.

const GRAPH_REBUILD_INTERVAL := 1.5
const MAX_LIGHT_NODES := 72
const LIGHT_CYCLE := 24.0
const SPAWN_DISTANCE := 260.0
const DESPAWN_DISTANCE := 420.0

var floating: FloatingOrigin = null
var streaming: SectorStreamingManager = null
var terrain: TerrainService = null
var actor_parent: Node3D = null
var player: Node3D = null
var max_vehicles: int = 12

var graph := RoadGraph.new()
var agents: Array = []

var _rebuild_timer: float = 0.0
var _light_nodes: Dictionary = {}
var _green_material: StandardMaterial3D = null
var _red_material: StandardMaterial3D = null
var _clock: float = 0.0


func setup(sector_floating: FloatingOrigin, streamer: SectorStreamingManager, sector_terrain: TerrainService, parent: Node3D, player_node: Node3D) -> void:
	floating = sector_floating
	streaming = streamer
	terrain = sector_terrain
	actor_parent = parent
	player = player_node
	_green_material = _make_emissive(Color(0.15, 0.95, 0.35))
	_red_material = _make_emissive(Color(0.95, 0.16, 0.12))


func _make_emissive(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	return material


func _parent() -> Node3D:
	return actor_parent if actor_parent != null else self


func _physics_process(delta: float) -> void:
	if floating == null or streaming == null or terrain == null:
		return
	_clock += delta
	_rebuild_timer -= delta
	if _rebuild_timer <= 0.0:
		_rebuild_timer = GRAPH_REBUILD_INTERVAL
		_rebuild_graph()
		_update_lights()
	_maintain_agents()
	for agent in agents:
		_step_agent(agent, delta)


func _rebuild_graph() -> void:
	graph.rebuild(_collect_payloads())


func _collect_payloads() -> Dictionary:
	var out := {}
	var coords: Array = streaming.loaded_coords()
	for coord in coords:
		var instance: SectorInstance = streaming.loaded_sector(coord)
		if instance != null and not instance.payload.is_empty():
			out[coord] = instance.payload
	return out


func _maintain_agents() -> void:
	if graph.edge_count() == 0:
		return
	var viewer_metric := floating.viewer_metric()
	var kept: Array = []
	for agent in agents:
		var node: Node3D = agent.get("node")
		if not is_instance_valid(node):
			continue
		var metric: Vector2 = agent.get("position_metric", viewer_metric)
		if metric.distance_to(viewer_metric) > DESPAWN_DISTANCE:
			node.queue_free()
			continue
		kept.append(agent)
	agents = kept

	var wanted := clampi(max_vehicles, 0, 48)
	var attempts := 0
	while agents.size() < wanted and attempts < wanted * 3:
		attempts += 1
		_spawn_agent(viewer_metric)


func _spawn_agent(viewer_metric: Vector2) -> void:
	var index := graph.nearest_road(viewer_metric)
	if index < 0:
		return
	var road_entry := graph.road(index)
	var heading: Vector2 = (road_entry["b"] - road_entry["a"]).normalized()
	if Deterministic.rand01(agents.size(), index, 17) > 0.5:
		heading = -heading
	var from: Vector2 = road_entry["a"] if heading.dot((road_entry["b"] - road_entry["a"]).normalized()) > 0.0 else road_entry["b"]
	var to: Vector2 = road_entry["b"] if from == road_entry["a"] else road_entry["a"]
	var from_node: String = road_entry["node_a"] if from == road_entry["a"] else road_entry["node_b"]
	var to_node: String = road_entry["node_b"] if from_node == road_entry["node_a"] else road_entry["node_a"]
	if from.distance_to(viewer_metric) > SPAWN_DISTANCE:
		return

	var mesh := MeshInstance3D.new()
	mesh.mesh = ProceduralMeshes.car_body()
	var palette_index := agents.size() % 5
	mesh.material_override = MaterialLibrary.vehicle(_palette(palette_index))
	_parent().add_child(mesh)

	agents.append({
		"node": mesh,
		"from": from,
		"to": to,
		"from_node": from_node,
		"to_node": to_node,
		"progress": 0.0,
		"speed": 7.0 + Deterministic.rand01(agents.size(), index, 29) * 6.0,
		"lane": float(road_entry["width"]) * 0.24,
		"position_metric": from,
	})


func _palette(index: int) -> Color:
	var palette := [
		Color(0.80, 0.80, 0.78),
		Color(0.16, 0.22, 0.34),
		Color(0.55, 0.14, 0.12),
		Color(0.24, 0.35, 0.28),
		Color(0.70, 0.62, 0.20),
	]
	return palette[index % palette.size()]


func _step_agent(agent: Dictionary, delta: float) -> void:
	var from: Vector2 = agent["from"]
	var to: Vector2 = agent["to"]
	var length := maxf(from.distance_to(to), 0.01)
	var speed := minf(float(agent["speed"]), _allowed_speed(agent))
	agent["progress"] = float(agent["progress"]) + speed * delta / length
	if float(agent["progress"]) >= 1.0:
		_advance_agent(agent)
		return
	var metric := from.lerp(to, clampf(float(agent["progress"]), 0.0, 1.0))
	var direction := (to - from).normalized()
	# Faixa da direita: girar o vetor de deslocamento 90° para a direita.
	var lateral := Vector2(direction.y, -direction.x) * float(agent["lane"])
	metric += lateral
	agent["position_metric"] = metric

	var node: Node3D = agent["node"]
	if not is_instance_valid(node):
		return
	var local := floating.metric_to_local(metric)
	local.y = terrain.height_at(metric) + 0.16
	node.position = local
	node.rotation.y = atan2(-direction.x, direction.y)


func _allowed_speed(agent: Dictionary) -> float:
	var base := float(agent["speed"])
	var to: Vector2 = agent["to"]
	var to_node: String = agent["to_node"]
	if _light_nodes.has(to_node):
		var direction: Vector2 = (to - agent["from"]).normalized()
		if not _is_green(to_node, direction) and agent["position_metric"].distance_to(to) < 14.0:
			return 0.0
	# Carro à frente: compara com os outros agentes num raio curto.
	var position: Vector2 = agent["position_metric"]
	var heading: Vector2 = (to - agent["from"]).normalized()
	for other in agents:
		if other == agent:
			continue
		var other_position: Vector2 = other.get("position_metric", position)
		var offset := other_position - position
		if offset.length() > 9.0:
			continue
		if offset.dot(heading) > 4.0:
			return 0.0
	return base


func _advance_agent(agent: Dictionary) -> void:
	var arrived: Vector2 = agent["to"]
	var arrived_node: String = agent["to_node"]
	var candidates := graph.outgoing(arrived_node)
	var chosen := -1
	if not candidates.is_empty():
		var start := absi(Deterministic.hash2(arrived_node.length(), agents.size(), int(arrived.x))) % candidates.size()
		for offset in range(candidates.size()):
			var index: int = candidates[(start + offset) % candidates.size()]
			var entry := graph.road(index)
			if entry.is_empty():
				continue
			if entry["node_a"] == arrived_node and entry["b"] != arrived:
				chosen = index
				break
			if entry["node_b"] == arrived_node and entry["a"] != arrived:
				chosen = index
				break
	var previous: Vector2 = agent["from"]
	if chosen < 0:
		# Beco sem saída: retorna pela mesma via.
		agent["from"] = arrived
		agent["to"] = previous
		var swap_node: String = agent["from_node"]
		agent["from_node"] = arrived_node
		agent["to_node"] = swap_node
		agent["progress"] = 0.0
		return
	var entry := graph.road(chosen)
	agent["from"] = arrived
	agent["from_node"] = arrived_node
	if entry["node_a"] == arrived_node:
		agent["to"] = entry["b"]
		agent["to_node"] = entry["node_b"]
	else:
		agent["to"] = entry["a"]
		agent["to_node"] = entry["node_a"]
	agent["lane"] = float(entry["width"]) * 0.24
	agent["progress"] = 0.0


func _update_lights() -> void:
	if graph.node_count() == 0:
		return
	var viewer := floating.viewer_metric()
	for node_key in graph.intersections():
		if _light_nodes.size() >= MAX_LIGHT_NODES and not _light_nodes.has(node_key):
			continue
		if _light_nodes.has(node_key):
			continue
		var metric := graph.node_metric(node_key)
		if metric.distance_to(viewer) > 240.0:
			continue
		_light_nodes[node_key] = _build_light(metric)
	for node_key in _light_nodes.keys():
		var head: MeshInstance3D = _light_nodes[node_key]
		if not is_instance_valid(head):
			_light_nodes.erase(node_key)
			continue
		head.material_override = _green_material if _is_green(node_key, Vector2.RIGHT) else _red_material


func _build_light(metric: Vector2) -> MeshInstance3D:
	var root := Node3D.new()
	_parent().add_child(root)
	root.position = floating.metric_to_local(metric, terrain.height_at(metric))

	var pole := MeshInstance3D.new()
	pole.mesh = ProceduralMeshes.pole()
	pole.material_override = MaterialLibrary.prop()
	pole.position = Vector3(0.0, 3.2, 0.0)
	pole.scale = Vector3(0.5, 0.55, 0.5)
	root.add_child(pole)

	var head := MeshInstance3D.new()
	head.mesh = ProceduralMeshes.traffic_light_head()
	head.position = Vector3(0.0, 3.9, 0.0)
	head.material_override = _red_material
	root.add_child(head)
	return head


## Semáforo determinístico por nó: o mesmo cruzamento tem sempre a mesma fase,
## e não é preciso manter estado de servidor por interseção.
func _is_green(node_key: String, axis: Vector2) -> bool:
	var shift := Deterministic.rand01(node_key.length(), node_key.unicode_at(0), 61) * LIGHT_CYCLE
	var phase := fposmod(_clock + shift, LIGHT_CYCLE)
	var horizontal := absf(axis.x) >= absf(axis.y)
	if horizontal:
		return phase < LIGHT_CYCLE * 0.45
	return phase > LIGHT_CYCLE * 0.5 and phase < LIGHT_CYCLE * 0.95


func active_light_count() -> int:
	return _light_nodes.size()


func agent_count() -> int:
	return agents.size()
