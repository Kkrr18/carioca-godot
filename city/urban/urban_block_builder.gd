class_name UrbanBlockBuilder
extends RefCounted

## Extrai quadras da rede de ruas.
##
## O método é o de grafo plano, não o de "retângulo a cada N metros": as ruas
## viram arestas, os cruzamentos viram nós, e cada face fechada do grafo **é** um
## quarteirão. É o que faz uma rua diagonal, uma quadra triangular ou um loteamento
## irregular produzirem quadras com a mesma forma da rua — em vez de uma grade de
## retângulos que ignora o traçado.
##
## Como a face é percorrida: para cada meia-aresta (u→v) ainda não visitada, anda-
## se escolhendo sempre a saída de menor giro anti-horário em relação à direção de
## chegada, excluída a volta. Esse é o percurso que mantém a face à esquerda:
## faces internas saem em sentido anti-horário (área positiva) e a face externa
## sai em sentido horário (área negativa, descartada).
##
## Depois da face, vem o recuo: cada aresta da quadra é recuada pela metade da
## pista da via correspondente mais a calçada. O resultado é a **área edificável**
## da quadra — a frente de lote é medida a partir dela, então nenhum lote encosta
## no asfalto.
##
## Quadras de fronteira: uma face que atravessa o limite do setor pertence ao
## setor que contém o seu centroide e é gerada por inteiro, com as vias do
## entorno (o gerador monta a rede com um recorte maior). É o que evita a costura
## no meio da rua e a quadra duplicada na fronteira.

const MAX_FACE_STEPS := 8192

## Folga para decidir se uma aresta da quadra ainda está de frente para a rua.
const FRONTAGE_TOLERANCE := 1.2


## Devolve as quadras cujo centroide cai em `sector_rect`.
## Cada quadra: { "poly": PackedVector2Array, "area", "centroid", "frontage",
## "corner", "bounds", "street_area" } — tudo em espaço métrico global.
static func build(network: RoadNetwork, config: UrbanConfig, sector_rect: Rect2) -> Array:
	var blocks: Array = []
	if network == null or network.edge_count() == 0:
		return blocks
	var claim := sector_rect.grow(-0.01)
	var overflow := sector_rect.grow(config.border_overflow_limit)
	for face in extract_faces(network):
		var centroid := PolygonUtils.centroid(face)
		if not claim.has_point(centroid):
			# A face pertence ao setor vizinho. Cada uma é reivindicada uma vez só,
			# então dois setores nunca geram a mesma quadra.
			continue
		if not overflow.has_point(centroid):
			continue
		var block := _make_block(face, network, config)
		if block.is_empty():
			continue
		blocks.append(block)

	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2 = a["centroid"]
		var pb: Vector2 = b["centroid"]
		if absf(pa.x - pb.x) > 0.001:
			return pa.x < pb.x
		return pa.y < pb.y)
	for i in range(blocks.size()):
		(blocks[i] as Dictionary)["id"] = "Q%03d" % i
	return blocks


## Todas as faces fechadas de área positiva. Exposta porque a ferramenta de
## inspeção desenha exatamente o que o gerador enxerga.
static func extract_faces(network: RoadNetwork) -> Array:
	var faces: Array = []
	var visited: Dictionary = {}
	for edge in network.edges:
		var a := int(edge["a"])
		var b := int(edge["b"])
		for start in [Vector2i(a, b), Vector2i(b, a)]:
			var key := "%d>%d" % [start.x, start.y]
			if visited.has(key):
				continue
			visited[key] = true
			var path := _walk_face(network, int(start.x), int(start.y), visited)
			if path.size() < 3:
				continue
			var poly := PackedVector2Array()
			for node in path:
				poly.append(network.node_position(int(node)))
			poly = PolygonUtils.clean(poly, 0.05)
			if poly.size() < 3:
				continue
			if PolygonUtils.signed_area(poly) <= 1.0e-3:
				continue
			faces.append(poly)
	return faces


static func _walk_face(network: RoadNetwork, start: int, first: int, visited: Dictionary) -> Array:
	var path: Array = [start]
	var previous := start
	var current := first
	var steps := 0
	while steps < MAX_FACE_STEPS:
		steps += 1
		path.append(current)
		var next := _next_node(network, previous, current)
		if next == -1:
			return []
		visited["%d>%d" % [current, next]] = true
		previous = current
		current = next
		if current == start:
			return path
	return []


## Saída de menor giro anti-horário em relação à direção de chegada, excluída a
## volta. Devolve -1 em beco sem saída (grau 1), o que descarta o caminho.
static func _next_node(network: RoadNetwork, previous: int, current: int) -> int:
	var incoming := network.node_position(current) - network.node_position(previous)
	if incoming.length_squared() < 1.0e-8:
		return -1
	var base := incoming.angle()
	var best := -1
	var best_turn := INF
	for neighbour_value in network.neighbours(current):
		var neighbour := int(neighbour_value)
		if neighbour == previous:
			continue
		var outgoing := network.node_position(neighbour) - network.node_position(current)
		if outgoing.length_squared() < 1.0e-8:
			continue
		var turn := wrapf(outgoing.angle() - base, 0.0, TAU)
		if turn < best_turn - 1.0e-9:
			best_turn = turn
			best = neighbour
	return best


static func _make_block(face: PackedVector2Array, network: RoadNetwork, config: UrbanConfig) -> Dictionary:
	var street_poly := PolygonUtils.to_ccw(face)
	var street_area := PolygonUtils.area(street_poly)
	if street_area < config.block_min_area or street_area > config.block_max_area:
		return {}

	var poly := street_poly
	var count := street_poly.size()
	for i in range(count):
		var a := street_poly[i]
		var b := street_poly[(i + 1) % count]
		var edge := b - a
		if edge.length_squared() < 1.0e-6:
			continue
		edge = edge.normalized()
		var inward := Vector2(-edge.y, edge.x)
		var midpoint := (a + b) * 0.5
		var width := network.nearest_width(midpoint)
		var margin := width * 0.5 + config.sidewalk_width + config.block_inset_extra
		poly = PolygonUtils.clip_half_plane(poly, inward, inward.dot(a) + margin)
		if poly.size() < 3:
			return {}

	var area := PolygonUtils.area(poly)
	if area < config.block_min_area:
		return {}

	var frontage := _frontage_edges(poly, network, config)
	return {
		"poly": poly,
		"street_poly": street_poly,
		"street_area": street_area,
		"area": area,
		"centroid": PolygonUtils.centroid(poly),
		"frontage": frontage,
		"corner": frontage.size() >= 2,
		"bounds": PolygonUtils.bounds(poly),
	}


## Arestas da quadra que ainda estão de frente para uma via, com a normal
## apontando para fora (para a rua) e a classe da via correspondente.
static func _frontage_edges(poly: PackedVector2Array, network: RoadNetwork, config: UrbanConfig) -> Array:
	var out: Array = []
	var count := poly.size()
	var expected := config.sidewalk_width + config.block_inset_extra
	for i in range(count):
		var a := poly[i]
		var b := poly[(i + 1) % count]
		var edge := b - a
		var length := edge.length()
		if length < 3.0:
			continue
		var midpoint := (a + b) * 0.5
		var clearance := network.clearance_to_road(midpoint)
		if clearance > expected + FRONTAGE_TOLERANCE:
			continue
		var direction := edge / length
		out.append({
			"a": a,
			"b": b,
			"length": length,
			"dir": direction,
			"normal": Vector2(direction.y, -direction.x),
			"road_class": str(network.nearest_edge(midpoint).get("road_class", WorldSchema.ROAD_LOCAL)),
			"road_width": network.nearest_width(midpoint),
			"clearance": clearance,
		})
	return out
