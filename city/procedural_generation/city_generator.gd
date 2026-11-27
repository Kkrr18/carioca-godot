class_name CityGenerator
extends RefCounted

## Gerador urbano determinístico.
##
## A regra que mantém a cidade coerente entre setores: ruas nascem de uma
## RETICULADA GLOBAL. Um nó da reticulação é posicionado por um hash dos seus
## índices inteiros, então o setor A e o setor B calculam exatamente o mesmo nó
## e as vias se encontram na fronteira sem costura, sem precisar de arquivo de
## ligação nem de correção manual.
##
## Três escalas de reticulação, como no plano:
##   arterial   2112 m  rodovias e eixos estruturantes
##   collector   704 m  vias de bairro
##   local       176 m  quadras

const LOCAL_SPACING := 176.0
const COLLECTOR_SPACING := 704.0
const ARTERIAL_SPACING := 2112.0

const LOCAL_JITTER := 26.0
const COLLECTOR_JITTER := 60.0
const ARTERIAL_JITTER := 120.0

const DENSITY_LOCAL := 0.32
const DENSITY_COLLECTOR := 0.12


static func build_payload(coord: Vector2i, seed_value: int = 20170) -> Dictionary:
	var origin := SectorGrid.sector_origin(coord)
	var center := SectorGrid.sector_center(coord)
	var density := MunicipalityIndex.density_at(center)
	var payload := {
		"version": WorldSchema.SECTOR_SCHEMA_VERSION,
		"grid": [coord.x, coord.y],
		"origin": [origin.x, origin.y],
		"id": MunicipalityIndex.id_for(coord),
		"source": "procedural",
		"density": density,
		"urban": density >= DENSITY_LOCAL,
		"roads": [],
		"buildings": [],
		"water": [],
		"trees": [],
		"props": [],
	}
	var roads: Array = build_roads_only(coord, seed_value, density)
	payload["roads"] = roads

	var buildings: Array = []
	var props: Array = []
	if density >= DENSITY_LOCAL * 0.7:
		_add_lots(buildings, roads, origin, density, seed_value)
		_add_street_props(props, roads, origin, density, seed_value)
	payload["buildings"] = buildings
	payload["props"] = props
	payload["trees"] = _scatter_trees(roads, origin, density, coord, seed_value)
	return payload


## Só as vias de um setor, sem lotes, prédios ou vegetação.
##
## Existe para a camada urbana da Etapa 3: ao montar a rede de um setor é preciso
## as ruas dos oito vizinhos para as quadras da fronteira fecharem. Pedir o
## payload inteiro de nove setores só para ler as vias custaria geração de lote
## e de prédio que seria jogada fora.
##
## `density` negativo faz consultar `MunicipalityIndex`; quem já calculou passa o
## valor para não repetir a consulta.
static func build_roads_only(coord: Vector2i, seed_value: int = 20170, density: float = -1.0) -> Array:
	var origin := SectorGrid.sector_origin(coord)
	var bounds := Rect2(origin, Vector2(SectorGrid.SECTOR_SIZE, SectorGrid.SECTOR_SIZE))
	var local_density := density
	if local_density < 0.0:
		local_density = MunicipalityIndex.density_at(SectorGrid.sector_center(coord))
	var roads: Array = []
	_append_lattice(roads, bounds, origin, local_density, ARTERIAL_SPACING, ARTERIAL_JITTER, WorldSchema.ROAD_ARTERIAL, 0.0, 1001 + seed_value)
	if local_density >= DENSITY_COLLECTOR:
		_append_lattice(roads, bounds, origin, local_density, COLLECTOR_SPACING, COLLECTOR_JITTER, WorldSchema.ROAD_COLLECTOR, DENSITY_COLLECTOR, 2002 + seed_value)
	if local_density >= DENSITY_LOCAL:
		_append_lattice(roads, bounds, origin, local_density, LOCAL_SPACING, LOCAL_JITTER, WorldSchema.ROAD_LOCAL, DENSITY_LOCAL, 3003 + seed_value)
	return roads


static func _node_metric(i: int, j: int, spacing: float, jitter: float, salt: int) -> Vector2:
	var x := float(i) * spacing + Deterministic.rand_signed(i, j, salt) * jitter
	var y := float(j) * spacing + Deterministic.rand_signed(i, j, salt + 17) * jitter
	return Vector2(x, y)


## Posição métrica de um nó da reticulação a partir da própria chave.
## É a função que prova o invariante do gerador: a chave carrega tudo o que é
## preciso para reconstruir o ponto no mundo, então dois setores nunca discordam
## sobre onde uma via termina.
static func node_metric(lattice: String, i: int, j: int, seed_value: int = 20170) -> Vector2:
	match lattice:
		WorldSchema.ROAD_ARTERIAL:
			return _node_metric(i, j, ARTERIAL_SPACING, ARTERIAL_JITTER, 1001 + seed_value)
		WorldSchema.ROAD_COLLECTOR:
			return _node_metric(i, j, COLLECTOR_SPACING, COLLECTOR_JITTER, 2002 + seed_value)
		_:
			return _node_metric(i, j, LOCAL_SPACING, LOCAL_JITTER, 3003 + seed_value)


static func _to_local(metric: Vector2, origin: Vector2) -> Vector2:
	var d := metric - origin
	return Vector2(d.x, -d.y)


static func _mid_inside(a: Vector2, b: Vector2, bounds: Rect2) -> bool:
	return bounds.has_point((a + b) * 0.5)


static func _append_lattice(roads: Array, bounds: Rect2, origin: Vector2, density: float, spacing: float, jitter: float, road_class: String, density_gate: float, salt: int) -> void:
	if density < density_gate:
		return
	var i0 := floori(bounds.position.x / spacing) - 1
	var i1 := floori(bounds.end.x / spacing) + 1
	var j0 := floori(bounds.position.y / spacing) - 1
	var j1 := floori(bounds.end.y / spacing) + 1
	var width := WorldSchema.width_for(road_class)
	var lattice := road_class
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := _node_metric(i, j, spacing, jitter, salt)
			if i < i1:
				var q := _node_metric(i + 1, j, spacing, jitter, salt)
				if _mid_inside(p, q, bounds):
					roads.append(_road(p, q, origin, road_class, width, lattice,
						Deterministic.node_key(lattice, i, j),
						Deterministic.node_key(lattice, i + 1, j)))
			if j < j1:
				var r := _node_metric(i, j + 1, spacing, jitter, salt)
				if _mid_inside(p, r, bounds):
					roads.append(_road(p, r, origin, road_class, width, lattice,
						Deterministic.node_key(lattice, i, j),
						Deterministic.node_key(lattice, i, j + 1)))


static func _road(a: Vector2, b: Vector2, origin: Vector2, road_class: String, width: float, lattice: String, node_a: String, node_b: String) -> Dictionary:
	var la := _to_local(a, origin)
	var lb := _to_local(b, origin)
	return {
		"id": "%s|%s" % [node_a, node_b],
		"class": road_class,
		"width": width,
		"lattice": lattice,
		"nodes": [node_a, node_b],
		"points": [[la.x, la.y], [lb.x, lb.y]],
	}


## Lotes alinhados à via: cada segmento de rua local gera até dois lotes por
## lado, com recuo, testada e gabarito coerentes com a densidade do bairro.
static func _add_lots(buildings: Array, roads: Array, origin: Vector2, density: float, seed_value: int) -> void:
	for road_index in range(roads.size()):
		var road: Dictionary = roads[road_index]
		if str(road.get("class", "")) != WorldSchema.ROAD_LOCAL:
			continue
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var a := Vector2(float(points[0][0]), float(points[0][1]))
		var b := Vector2(float(points[1][0]), float(points[1][1]))
		var segment := b - a
		var length := segment.length()
		if length < 12.0:
			continue
		var dir := segment / length
		var normal := Vector2(-dir.y, dir.x)
		var road_width := float(road.get("width", 6.0))
		var slots := maxi(1, int(length / 22.0))
		for slot in range(slots):
			var t := (float(slot) + 0.5) / float(slots)
			var along := a.lerp(b, t)
			for side_index in range(2):
				var side := 1.0 if side_index == 1 else -1.0
				var lot_salt := Deterministic.hash3(road_index, slot, side_index, seed_value)
				if Deterministic.rand01(road_index * 2 + side_index, slot, seed_value + 5) > 0.82:
					continue
				if Deterministic.rand01(lot_salt, slot, seed_value + 9) < 0.08 * (1.0 - density):
					continue
				var front := Deterministic.rand_range(lot_salt, slot, 9.0, 17.0, seed_value + 21)
				var depth := Deterministic.rand_range(lot_salt, slot, 9.0, 15.0, seed_value + 33)
				var setback := 3.0 + (1.0 - density) * 6.0
				var offset := road_width * 0.5 + setback + depth * 0.5
				var center := along + normal * side * offset
				var levels := _levels_for(density, lot_salt, seed_value)
				var height := float(levels) * 3.15
				var angle := atan2(dir.y, dir.x)
				var kind := _kind_for(density, lot_salt)
				var door := along + normal * side * (road_width * 0.5 + setback)
				buildings.append({
					"id": "b%d_%d_%d" % [road_index, slot, side_index],
					"center": [center.x, center.y],
					"size": [front, depth],
					"angle": angle,
					"levels": levels,
					"height": height,
					"kind": kind,
					"door": [door.x, door.y],
				})


static func _levels_for(density: float, salt: int, seed_value: int) -> int:
	var roll := Deterministic.rand01(salt, 7, seed_value + 71)
	if density > 0.82 and roll > 0.72:
		return 14 + int(Deterministic.rand01(salt, 11, seed_value) * 12.0)
	if density > 0.55 and roll > 0.45:
		return 6 + int(Deterministic.rand01(salt, 13, seed_value) * 6.0)
	if density > 0.3:
		return 2 + int(Deterministic.rand01(salt, 17, seed_value) * 4.0)
	return 1 + int(Deterministic.rand01(salt, 19, seed_value) * 2.0)


static func _kind_for(density: float, salt: int) -> String:
	var roll := Deterministic.rand01(salt, 23, 991)
	if density > 0.6 and roll > 0.7:
		return "commercial"
	if roll < 0.09:
		return "public"
	return "residential"


static func _add_street_props(props: Array, roads: Array, origin: Vector2, density: float, seed_value: int) -> void:
	for road_index in range(roads.size()):
		var road: Dictionary = roads[road_index]
		var road_class := str(road.get("class", ""))
		if road_class == WorldSchema.ROAD_LOCAL and density < 0.45:
			continue
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var a := Vector2(float(points[0][0]), float(points[0][1]))
		var b := Vector2(float(points[1][0]), float(points[1][1]))
		var segment := b - a
		var length := segment.length()
		if length < 20.0:
			continue
		var dir := segment / length
		var normal := Vector2(-dir.y, dir.x)
		var spacing := 46.0 if road_class == WorldSchema.ROAD_ARTERIAL else 62.0
		var count := maxi(1, int(length / spacing))
		var half := float(road.get("width", 6.0)) * 0.5 + 1.2
		for i in range(count):
			var t := (float(i) + 0.5) / float(count)
			var side := 1.0 if (i + road_index) % 2 == 0 else -1.0
			var pos := a.lerp(b, t) + normal * side * half
			props.append({
				"type": "light",
				"pos": [pos.x, pos.y],
				"rot": atan2(dir.y, dir.x),
			})


static func _scatter_trees(roads: Array, origin: Vector2, density: float, coord: Vector2i, seed_value: int) -> Array:
	var out: Array = []
	if density > 0.75:
		return out
	var spacing := 26.0
	var steps := int(SectorGrid.SECTOR_SIZE / spacing)
	var probability := 0.55 * (1.0 - density)
	for gy in range(steps):
		for gx in range(steps):
			if Deterministic.rand01(coord.x * 64 + gx, coord.y * 64 + gy, seed_value + 301) > probability:
				continue
			var local := Vector2((float(gx) + 0.5) * spacing, (float(gy) + 0.5) * spacing)
			if _too_close_to_road(local, roads, 9.0):
				continue
			var scale := Deterministic.rand_range(coord.x + gx, coord.y + gy, 0.7, 1.8, seed_value + 17)
			out.append([local.x, local.y, scale])
	return out


static func _too_close_to_road(local: Vector2, roads: Array, radius: float) -> bool:
	var radius_sq := radius * radius
	for road in roads:
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var a := Vector2(float(points[0][0]), float(points[0][1]))
		var b := Vector2(float(points[1][0]), float(points[1][1]))
		if _distance_to_segment(local, a, b) < radius_sq:
			return true
	return false


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)
