class_name RoadNetwork
extends RefCounted

## Grafo plano das vias de um recorte, no espaço métrico global.
##
## É o que transforma uma lista de polilinhas (do gerador procedural, do extrato
## OSM ou do traçado esquemático) em algo sobre o qual dá para construir quadra:
## vértices únicos, arestas sem cruzamento no meio, grau de cada nó e distância
## a qualquer eixo de via.
##
## Duas decisões que sustentam a qualidade da cidade:
##
## 1. **Cruzamentos viram nós.** Um segmento que passa por cima de outro é
##    cortado no ponto de interseção. Sem isso a extração de quadras enxerga uma
##    rua atravessando a quadra e o resultado é uma quadra atravessada por
##    asfalto.
##
## 2. **Nós são unificados por proximidade** (`MERGE_TOLERANCE`). Coordenadas de
##    fontes diferentes nunca coincidem no último bit; sem a fusão, duas ruas que
##    se encontram na esquina não fecham face nenhuma e o quarteirão não nasce.

const MERGE_TOLERANCE := 0.6
const MIN_EDGE_LENGTH := 1.2
const INDEX_CELL := 32.0

## Posições dos nós, em metros (easting, northing).
var nodes: PackedVector2Array = PackedVector2Array()

## Arestas: { "a": int, "b": int, "width": float, "road_class": String, "id": String }
var edges: Array = []

var _adjacency: Dictionary = {}
var _lookup: Dictionary = {}
var _index: Dictionary = {}
var _index_ready: bool = false


# --- construção --------------------------------------------------------------


static func _to_metric(point: Variant, origin: Vector2) -> Vector2:
	var pair: Array = point
	return origin + Vector2(float(pair[0]), -float(pair[1]))


## A partir de vias no formato do payload (pontos locais ao setor).
static func from_payload_roads(roads: Array, origin: Vector2) -> RoadNetwork:
	var raw: Array = []
	for entry in roads:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var road: Dictionary = entry
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var width := float(road.get("width", 6.0))
		var road_class := str(road.get("class", WorldSchema.ROAD_LOCAL))
		var road_id := str(road.get("id", "r"))
		for i in range(points.size() - 1):
			var pair_a: Variant = points[i]
			var pair_b: Variant = points[i + 1]
			if typeof(pair_a) != TYPE_ARRAY or typeof(pair_b) != TYPE_ARRAY:
				continue
			var a := _to_metric(pair_a, origin)
			var b := _to_metric(pair_b, origin)
			raw.append({
				"a": a,
				"b": b,
				"width": width,
				"road_class": road_class,
				"id": "%s|%d" % [road_id, i],
			})
	return from_segments(raw)


## A partir de segmentos já em espaço métrico.
## `segments`: [{ "a": Vector2, "b": Vector2, "width": float, "road_class": String, "id": String }]
static func from_segments(segments: Array) -> RoadNetwork:
	var network := RoadNetwork.new()
	network._build(segments)
	return network


func _build(segments: Array) -> void:
	var valid: Array = []
	for entry in segments:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var segment: Dictionary = entry
		var a: Vector2 = segment.get("a", Vector2.ZERO)
		var b: Vector2 = segment.get("b", Vector2.ZERO)
		if a.distance_to(b) < MIN_EDGE_LENGTH:
			continue
		valid.append(segment)

	var cuts: Array = []
	cuts.resize(valid.size())
	for i in range(valid.size()):
		cuts[i] = []

	# Cruzamentos: cada par é testado uma vez. Vale a pena o O(n²) — n raramente
	# passa de algumas centenas num setor, e nenhuma estrutura espacial
	# melhoraria a legibilidade disto.
	for i in range(valid.size()):
		var first: Dictionary = valid[i]
		var a1: Vector2 = first["a"]
		var b1: Vector2 = first["b"]
		for j in range(i + 1, valid.size()):
			var second: Dictionary = valid[j]
			var a2: Vector2 = second["a"]
			var b2: Vector2 = second["b"]
			var hit := PolygonUtils.segment_intersection(a1, b1, a2, b2)
			if not bool(hit.get("hit", false)):
				continue
			var t := float(hit["t"])
			var u := float(hit["u"])
			if t > 1.0e-4 and t < 1.0 - 1.0e-4:
				(cuts[i] as Array).append(t)
			if u > 1.0e-4 and u < 1.0 - 1.0e-4:
				(cuts[j] as Array).append(u)

	for i in range(valid.size()):
		var segment: Dictionary = valid[i]
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var width := float(segment.get("width", 6.0))
		var road_class := str(segment.get("road_class", WorldSchema.ROAD_LOCAL))
		var road_id := str(segment.get("id", ""))
		var stations: Array = cuts[i]
		stations.append(0.0)
		stations.append(1.0)
		stations.sort()
		var previous_node := _node_id(a)
		var previous_t := 0.0
		for k in range(1, stations.size()):
			var t := float(stations[k])
			if t - previous_t < 1.0e-4:
				continue
			var point := a.lerp(b, t)
			var node := _node_id(point)
			if node != previous_node:
				_add_edge(previous_node, node, width, road_class, "%s#%d" % [road_id, k])
			previous_node = node
			previous_t = t


func _node_id(point: Vector2) -> int:
	var cx := floori(point.x / MERGE_TOLERANCE)
	var cy := floori(point.y / MERGE_TOLERANCE)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key := "%d:%d" % [cx + dx, cy + dy]
			var bucket: Array = _lookup.get(key, [])
			for index in bucket:
				if (nodes[index] as Vector2).distance_to(point) <= MERGE_TOLERANCE:
					return int(index)
	var id := nodes.size()
	nodes.append(point)
	var home := "%d:%d" % [cx, cy]
	if _lookup.has(home):
		(_lookup[home] as Array).append(id)
	else:
		_lookup[home] = [id]
	return id


func _add_edge(a: int, b: int, width: float, road_class: String, id: String) -> void:
	if a == b:
		return
	var existing: Array = _adjacency.get(a, [])
	if not existing.has(b):
		existing.append(b)
		_adjacency[a] = existing
	var mirror: Array = _adjacency.get(b, [])
	if not mirror.has(a):
		mirror.append(a)
		_adjacency[b] = mirror
	edges.append({
		"a": a,
		"b": b,
		"width": width,
		"road_class": road_class,
		"id": id,
	})
	_index_ready = false


# --- consultas ---------------------------------------------------------------


func node_position(index: int) -> Vector2:
	if index < 0 or index >= nodes.size():
		return Vector2.ZERO
	return nodes[index]


func neighbours(node: int) -> Array:
	return _adjacency.get(node, [])


func degree(node: int) -> int:
	return neighbours(node).size()


func edge_count() -> int:
	return edges.size()


func node_count() -> int:
	return nodes.size()


## Nós de grau 3 ou mais: esquinas onde faz sentido nascer semáforo, placa e
## faixa de pedestre.
func intersections() -> Array:
	var out: Array = []
	for node in _adjacency.keys():
		if degree(int(node)) >= 3:
			out.append(node_position(int(node)))
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		if absf(a.x - b.x) > 0.001:
			return a.x < b.x
		return a.y < b.y)
	return out


## Pares de vias que se cruzam de fato (grau do nó >= 3), com as classes
## envolvidas. É o que decide semáforo em vez de só uma esquina de quadra.
func crossings() -> Array:
	var out: Array = []
	for node in _adjacency.keys():
		var neighbours_list: Array = neighbours(int(node))
		if neighbours_list.size() < 3:
			continue
		var classes: Array[String] = []
		var widths: Array[float] = []
		for edge in edges:
			if int(edge["a"]) == int(node) or int(edge["b"]) == int(node):
				var value := str(edge["road_class"])
				if not classes.has(value):
					classes.append(value)
				widths.append(float(edge["width"]))
		var widest := 0.0
		for width in widths:
			widest = maxf(widest, width)
		out.append({
			"point": node_position(int(node)),
			"classes": classes,
			"width": widest,
			"degree": neighbours_list.size(),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2 = a["point"]
		var pb: Vector2 = b["point"]
		if absf(pa.x - pb.x) > 0.001:
			return pa.x < pb.x
		return pa.y < pb.y)
	return out


func _ensure_index() -> void:
	if _index_ready:
		return
	_index_ready = true
	_index.clear()
	for i in range(edges.size()):
		var a := node_position(int(edges[i]["a"]))
		var b := node_position(int(edges[i]["b"]))
		var length := a.distance_to(b)
		var steps := maxi(1, int(ceil(length / (INDEX_CELL * 0.5))))
		for s in range(steps + 1):
			var point := a.lerp(b, float(s) / float(steps))
			var key := _cell_key(point)
			if _index.has(key):
				var list: Array = _index[key]
				if not list.has(i):
					list.append(i)
			else:
				_index[key] = [i]


func _cell_key(point: Vector2) -> String:
	return "%d:%d" % [floori(point.x / INDEX_CELL), floori(point.y / INDEX_CELL)]


func _candidate_edges(point: Vector2, radius: float) -> Array:
	_ensure_index()
	var out: Array = []
	var reach := maxi(1, int(ceil(radius / INDEX_CELL)))
	var cx := floori(point.x / INDEX_CELL)
	var cy := floori(point.y / INDEX_CELL)
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			var bucket: Array = _index.get("%d:%d" % [cx + dx, cy + dy], [])
			for index in bucket:
				if not out.has(index):
					out.append(index)
	return out


## Distância à borda da pista mais próxima, em metros. Zero ou negativo quer
## dizer "em cima do asfalto".
func clearance_to_road(point: Vector2) -> float:
	var best := INF
	var candidates := _candidate_edges(point, 96.0)
	if candidates.is_empty():
		candidates = []
		for i in range(edges.size()):
			candidates.append(i)
	for index in candidates:
		var edge: Dictionary = edges[index]
		var a := node_position(int(edge["a"]))
		var b := node_position(int(edge["b"]))
		var distance := PolygonUtils.distance_to_segment(point, a, b) - float(edge["width"]) * 0.5
		best = minf(best, distance)
	if best == INF:
		return 9999.0
	return best


func nearest_edge(point: Vector2) -> Dictionary:
	var best := {}
	var best_distance := INF
	for index in range(edges.size()):
		var edge: Dictionary = edges[index]
		var a := node_position(int(edge["a"]))
		var b := node_position(int(edge["b"]))
		var distance := PolygonUtils.distance_to_segment(point, a, b)
		if distance < best_distance:
			best_distance = distance
			best = edge
	if best.is_empty():
		return {}
	var result := best.duplicate()
	result["distance"] = best_distance
	return result


func nearest_width(point: Vector2) -> float:
	var edge := nearest_edge(point)
	return float(edge.get("width", 6.0))


func is_on_road(point: Vector2, margin: float = 0.0) -> bool:
	return clearance_to_road(point) <= margin


## Estatísticas para HUD, inspetor e relatório.
func stats() -> Dictionary:
	var by_class: Dictionary = {}
	for edge in edges:
		var key := str(edge["road_class"])
		by_class[key] = int(by_class.get(key, 0)) + 1
	var total_length := 0.0
	for edge in edges:
		total_length += node_position(int(edge["a"])).distance_to(node_position(int(edge["b"])))
	return {
		"nodes": nodes.size(),
		"edges": edges.size(),
		"intersections": intersections().size(),
		"length_m": total_length,
		"by_class": by_class,
	}
