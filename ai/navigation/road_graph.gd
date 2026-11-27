class_name RoadGraph
extends RefCounted

## Grafo de vias construído a partir dos payloads carregados.
##
## Conectividade vem das CHAVES DE NÓ do gerador (lattice:i:j), não de
## coincidência de float. Duas vias de setores diferentes que terminam no mesmo
## nó da reticulação compartilham a mesma chave por construção, então o trânsito
## atravessa a fronteira do setor sem nenhuma tabela de ligação.
##
## Para dados vindos do OpenStreetMap, onde não existe reticulação, a chave é
## derivada da coordenada arredondada a 10 cm — suficiente para nós que o
## próprio OSM compartilha entre vias.

var roads: Array = []
var by_node: Dictionary = {}


func clear() -> void:
	roads.clear()
	by_node.clear()


func rebuild(payloads: Dictionary) -> void:
	clear()
	for coord in payloads:
		var payload: Dictionary = payloads[coord]
		if typeof(payload) != TYPE_DICTIONARY:
			continue
		var origin := SectorGrid.sector_origin(coord)
		for raw in payload.get("roads", []):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var road: Dictionary = raw
			var points: Array = road.get("points", [])
			if points.size() < 2:
				continue
			var a_local := Vector2(float(points[0][0]), float(points[0][1]))
			var b_local := Vector2(float(points[1][0]), float(points[1][1]))
			var a := origin + Vector2(a_local.x, -a_local.y)
			var b := origin + Vector2(b_local.x, -b_local.y)
			if a.distance_squared_to(b) < 1.0:
				continue
			var nodes: Array = road.get("nodes", [])
			var node_a := str(nodes[0]) if nodes.size() > 0 else _fallback_key(a)
			var node_b := str(nodes[1]) if nodes.size() > 1 else _fallback_key(b)
			var index := roads.size()
			roads.append({
				"a": a,
				"b": b,
				"node_a": node_a,
				"node_b": node_b,
				"width": float(road.get("width", 6.0)),
				"class": str(road.get("class", WorldSchema.ROAD_LOCAL)),
				"cell": coord,
			})
			_link(node_a, index)
			_link(node_b, index)


func _fallback_key(metric: Vector2) -> String:
	return "p:%.1f:%.1f" % [metric.x, metric.y]


func _link(node_key: String, index: int) -> void:
	if by_node.has(node_key):
		var list: Array = by_node[node_key]
		list.append(index)
	else:
		by_node[node_key] = [index]


func edge_count() -> int:
	return roads.size()


func node_count() -> int:
	return by_node.size()


func road(index: int) -> Dictionary:
	if index < 0 or index >= roads.size():
		return {}
	return roads[index]


func outgoing(node_key: String) -> Array:
	return by_node.get(node_key, [])


func degree(node_key: String) -> int:
	return outgoing(node_key).size()


## Nós onde três ou mais vias se encontram: candidatos a semáforo.
func intersections() -> Array:
	var out: Array = []
	for node_key in by_node.keys():
		if degree(node_key) >= 3:
			out.append(node_key)
	return out


func node_metric(node_key: String) -> Vector2:
	var list := outgoing(node_key)
	if list.is_empty():
		return Vector2.ZERO
	var index: int = list[0]
	var road_entry: Dictionary = roads[index]
	if road_entry["node_a"] == node_key:
		return road_entry["a"]
	return road_entry["b"]


## Aresta mais próxima de um ponto — usada para posicionar carros e pedestres
## dentro do mundo carregado.
func nearest_road(metric: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for i in range(roads.size()):
		var entry: Dictionary = roads[i]
		var a: Vector2 = entry["a"]
		var b: Vector2 = entry["b"]
		var ab := b - a
		var length_sq := ab.length_squared()
		if length_sq < 0.001:
			continue
		var t := clampf((metric - a).dot(ab) / length_sq, 0.0, 1.0)
		var distance := metric.distance_squared_to(a + ab * t)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func road_heading(index: int) -> Vector2:
	var entry := road(index)
	if entry.is_empty():
		return Vector2.RIGHT
	return (entry["b"] - entry["a"]).normalized()
