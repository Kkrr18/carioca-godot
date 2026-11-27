class_name UrbanProps
extends RefCounted

## Mobiliário urbano: poste, placa, semáforo, lixeira, banco, abrigo de ônibus,
## caixa de infraestrutura — mais sinalização horizontal.
##
## A regra é a mesma do resto da camada urbana: **posição derivada da geometria
## da via**, nunca sorteada sobre a área.
##
## - Poste: caminha ao longo de uma aresta, alternando de lado, com espaçamento
##   por classe de via, a uma folga fixa do meio-fio.
## - Semáforo: só em nó de grau 3 ou mais em que pelo menos uma via seja
##   coletora ou arterial. Dois por cruzamento, em lados opostos.
## - Placa: perto de cruzamento e ao longo de arterial.
## - Lixeira: ao lado da porta de estabelecimento comercial.
## - Banco e abrigo: em espaço aberto e em trecho de arterial.
## - Caixa de infraestrutura: nas quinas de quadra.
## - Faixa de pedestre e marcação de eixo: no cruzamento e ao longo da pista.
##
## Todo objeto é rejeitado se cair no asfalto. A folga é conferida contra a
## metade da pista de cada via, então via larga empurra o objeto mais para fora
## da calçada — que é o comportamento correto.

const CURB_OFFSET := 0.65
const SIGNAL_OFFSET := 1.35
const BIN_OFFSET := 1.1


## `context`: { "network", "blocks", "parcels", "buildings", "config",
## "seed_value", "coord", "rect", "open_spaces" }
static func plan(context: Dictionary) -> Dictionary:
	var config: UrbanConfig = context.get("config", UrbanConfig.active())
	var network: RoadNetwork = context.get("network")
	var rect: Rect2 = context.get("rect", Rect2())
	var seed_value := int(context.get("seed_value", 20170))
	var coord: Vector2i = context.get("coord", Vector2i.ZERO)
	var out := _empty_result()
	if network == null or config.prop_density <= 0.0:
		return out

	var budget := config.max_props_per_sector
	_plan_lights(out, network, rect, config, coord, seed_value, budget)
	_plan_crossings(out, network, rect, config, coord, seed_value, budget)
	_plan_signs(out, network, rect, config, coord, seed_value, budget)
	_plan_bins(out, context, rect, config, seed_value, budget)
	_plan_open_space_furniture(out, context, rect, config, seed_value, budget)
	_plan_shelters(out, network, rect, config, coord, seed_value, budget)
	_plan_utility_boxes(out, context, rect, config, seed_value, budget)
	_plan_lane_markings(out, network, rect, config)
	return out


static func _empty_result() -> Dictionary:
	var out := {}
	for type in UrbanSchema.PROP_TYPES:
		out[type] = []
	out[UrbanSchema.PROP_CROSSWALK] = []
	out[UrbanSchema.PROP_LANE_MARKING] = []
	return out


static func _on_sidewalk(point: Vector2, network: RoadNetwork, rect: Rect2, margin: float) -> bool:
	if not rect.has_point(point):
		return false
	if network == null:
		return true
	return network.clearance_to_road(point) >= margin


static func _plan_lights(out: Dictionary, network: RoadNetwork, rect: Rect2, config: UrbanConfig, coord: Vector2i, seed_value: int, budget: int) -> void:
	var lights: Array = out[UrbanSchema.PROP_LIGHT]
	for edge in network.edges:
		if lights.size() >= budget:
			return
		var a := network.node_position(int(edge["a"]))
		var b := network.node_position(int(edge["b"]))
		var length := a.distance_to(b)
		if length < 12.0:
			continue
		var width := float(edge["width"])
		var road_class := str(edge["road_class"])
		var spacing := config.light_spacing_local
		match road_class:
			WorldSchema.ROAD_ARTERIAL:
				spacing = config.light_spacing_arterial
			WorldSchema.ROAD_COLLECTOR:
				spacing = config.light_spacing_collector
		var count := maxi(1, int(length / spacing))
		var direction := (b - a) / length
		var normal := Vector2(-direction.y, direction.x)
		var offset := width * 0.5 + CURB_OFFSET + config.sidewalk_width * 0.35
		# A rede inclui as ruas do entorno: sem o corte, o laço percorreria vias de
		# outros setores só para rejeitar cada posição no fim.
		if not PolygonUtils.bounds(PackedVector2Array([a, b])).grow(offset + 4.0).intersects(rect):
			continue
		for i in range(count):
			var t := (float(i) + 0.5) / float(count)
			var side := 1.0 if (i + int(edge["a"])) % 2 == 0 else -1.0
			var point := a.lerp(b, t) + normal * (offset * side)
			if not _on_sidewalk(point, network, rect, CURB_OFFSET):
				continue
			if Deterministic.rand01(coord.x + i, coord.y + int(edge["b"]), seed_value + 307) > config.prop_density:
				continue
			lights.append({
				"pos": point,
				"rot": atan2(direction.y, direction.x),
				"scale": 1.0,
			})
			if lights.size() >= budget:
				return


static func _plan_crossings(out: Dictionary, network: RoadNetwork, rect: Rect2, config: UrbanConfig, coord: Vector2i, seed_value: int, budget: int) -> void:
	var signals: Array = out[UrbanSchema.PROP_TRAFFIC_LIGHT]
	var crosswalks: Array = out[UrbanSchema.PROP_CROSSWALK]
	var crossings := network.crossings()
	for index in range(crossings.size()):
		var crossing: Dictionary = crossings[index]
		var point: Vector2 = crossing["point"]
		if not rect.has_point(point):
			continue
		var classes: Array = crossing["classes"]
		var major := classes.has(WorldSchema.ROAD_ARTERIAL) or classes.has(WorldSchema.ROAD_COLLECTOR)
		var width := float(crossing["width"])
		var angle := _crossing_angle(network, point)
		if major and signals.size() < budget:
			var offset := width * 0.5 + SIGNAL_OFFSET
			for side in [1.0, -1.0]:
				var position := point + Vector2(cos(angle + PI * 0.5), sin(angle + PI * 0.5)) * offset * side
				if not _on_sidewalk(position, network, rect, CURB_OFFSET * 0.8):
					continue
				signals.append({
					"pos": position,
					"rot": angle,
					"scale": 1.0,
				})
		if Deterministic.rand01(coord.x + index, coord.y, seed_value + 311) < 0.9:
			crosswalks.append({
				"pos": point,
				"angle": angle,
				"length": maxf(width - 0.6, 3.0),
				"bars": clampi(int(width / 0.9), 4, 12),
			})


static func _crossing_angle(network: RoadNetwork, point: Vector2) -> float:
	var edge := network.nearest_edge(point)
	if edge.is_empty():
		return 0.0
	var a := network.node_position(int(edge["a"]))
	var b := network.node_position(int(edge["b"]))
	var direction := (b - a).normalized()
	return atan2(direction.y, direction.x)


static func _plan_signs(out: Dictionary, network: RoadNetwork, rect: Rect2, config: UrbanConfig, coord: Vector2i, seed_value: int, budget: int) -> void:
	var signs: Array = out[UrbanSchema.PROP_SIGN]
	for edge in network.edges:
		if signs.size() >= budget:
			return
		var road_class := str(edge["road_class"])
		if road_class == WorldSchema.ROAD_LOCAL:
			continue
		var a := network.node_position(int(edge["a"]))
		var b := network.node_position(int(edge["b"]))
		var length := a.distance_to(b)
		if length < 30.0:
			continue
		var direction := (b - a) / length
		var normal := Vector2(-direction.y, direction.x)
		var offset := float(edge["width"]) * 0.5 + CURB_OFFSET
		for t in [0.22, 0.68]:
			for side in [1.0, -1.0]:
				var point := a.lerp(b, t) + normal * offset * side
				if not _on_sidewalk(point, network, rect, CURB_OFFSET * 0.7):
					continue
				if Deterministic.rand01(coord.x + int(t * 100.0), coord.y + int(side), seed_value + 313) > config.prop_density:
					continue
				signs.append({
					"pos": point,
					"rot": atan2(direction.y, direction.x),
					"scale": 0.9 + Deterministic.rand01(coord.x, coord.y, seed_value + 317) * 0.3,
				})
				break


static func _plan_bins(out: Dictionary, context: Dictionary, rect: Rect2, config: UrbanConfig, seed_value: int, budget: int) -> void:
	var bins: Array = out[UrbanSchema.PROP_BIN]
	var buildings: Array = context.get("buildings", [])
	var network: RoadNetwork = context.get("network")
	for raw in buildings:
		if bins.size() >= budget:
			return
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = raw
		if str(building.get("kind", "")) == UrbanSchema.KIND_RESIDENTIAL:
			continue
		var door: Vector2 = building.get("door", Vector2.ZERO)
		var angle := float(building.get("angle", 0.0))
		var u := Vector2(cos(angle), sin(angle))
		var point := door + u * 1.6
		if not _on_sidewalk(point, network, rect, CURB_OFFSET * 0.6):
			continue
		if Deterministic.rand01(int(point.x), int(point.y), seed_value + 319) > config.prop_density:
			continue
		bins.append({"pos": point, "rot": angle, "scale": 1.0})


static func _plan_open_space_furniture(out: Dictionary, context: Dictionary, rect: Rect2, config: UrbanConfig, seed_value: int, budget: int) -> void:
	var benches: Array = out[UrbanSchema.PROP_BENCH]
	var spaces: Array = context.get("open_spaces", [])
	for space in spaces:
		var center: Vector2 = space.get("point", Vector2.ZERO)
		var radius := float(space.get("radius_m", 20.0))
		if not rect.has_point(center):
			continue
		var count := maxi(1, int(radius / 9.0 * config.prop_density))
		for i in range(count):
			if benches.size() >= budget:
				return
			var angle := TAU * float(i) / float(count) + 0.4
			var point := center + Vector2(cos(angle), sin(angle)) * radius * 0.55
			benches.append({
				"pos": point,
				"rot": angle + PI * 0.5,
				"scale": 1.0,
			})


static func _plan_shelters(out: Dictionary, network: RoadNetwork, rect: Rect2, config: UrbanConfig, coord: Vector2i, seed_value: int, budget: int) -> void:
	var shelters: Array = out[UrbanSchema.PROP_SHELTER]
	for edge in network.edges:
		if shelters.size() >= budget:
			return
		if str(edge["road_class"]) != WorldSchema.ROAD_ARTERIAL:
			continue
		var a := network.node_position(int(edge["a"]))
		var b := network.node_position(int(edge["b"]))
		var length := a.distance_to(b)
		if length < 90.0:
			continue
		if Deterministic.rand01(coord.x + int(edge["a"]), coord.y + int(edge["b"]), seed_value + 331) > 0.34 * config.prop_density:
			continue
		var direction := (b - a) / length
		var normal := Vector2(-direction.y, direction.x)
		var point := a.lerp(b, 0.5) + normal * (float(edge["width"]) * 0.5 + config.sidewalk_width * 0.55)
		if not _on_sidewalk(point, network, rect, CURB_OFFSET):
			continue
		shelters.append({
			"pos": point,
			"rot": atan2(direction.y, direction.x),
			"scale": 1.0,
		})


static func _plan_utility_boxes(out: Dictionary, context: Dictionary, rect: Rect2, config: UrbanConfig, seed_value: int, budget: int) -> void:
	var boxes: Array = out[UrbanSchema.PROP_UTILITY_BOX]
	var blocks: Array = context.get("blocks", [])
	var network: RoadNetwork = context.get("network")
	for block in blocks:
		if boxes.size() >= budget:
			return
		var poly: PackedVector2Array = block.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var centroid := PolygonUtils.centroid(poly)
		if not rect.has_point(centroid):
			continue
		var point := centroid.lerp(poly[0], 0.94)
		if not rect.has_point(point):
			continue
		if network != null and network.clearance_to_road(point) < CURB_OFFSET * 0.5:
			continue
		if Deterministic.rand01(int(centroid.x), int(centroid.y), seed_value + 337) > 0.6 * config.prop_density:
			continue
		boxes.append({"pos": point, "rot": 0.0, "scale": 1.0})


static func _plan_lane_markings(out: Dictionary, network: RoadNetwork, rect: Rect2, config: UrbanConfig) -> void:
	var markings: Array = out[UrbanSchema.PROP_LANE_MARKING]
	for edge in network.edges:
		var road_class := str(edge["road_class"])
		if road_class != WorldSchema.ROAD_ARTERIAL and road_class != WorldSchema.ROAD_COLLECTOR:
			continue
		var a := network.node_position(int(edge["a"]))
		var b := network.node_position(int(edge["b"]))
		var length := a.distance_to(b)
		if length < 24.0:
			continue
		var direction := (b - a) / length
		var count := int(length / 8.0)
		if count <= 0 or count > 90:
			continue
		if not PolygonUtils.bounds(PackedVector2Array([a, b])).intersects(rect):
			continue
		# Um segmento só por trecho entre cruzamentos: o construtor de malha
		# desenha as faixas com base no comprimento, não uma a uma no payload.
		markings.append({
			"a": a,
			"b": b,
			"width": 0.14 if road_class == WorldSchema.ROAD_ARTERIAL else 0.11,
			"dashes": count,
			"dir": direction,
		})


## Validação usada pelas ferramentas e pelos testes: nenhum objeto sobre o
## asfalto e nenhum fora do setor.
static func validate(props: Dictionary, network: RoadNetwork, rect: Rect2) -> Array[String]:
	var problems: Array[String] = []
	for key in props.keys():
		var entries: Array = props[key]
		for raw in entries:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = raw
			if key == UrbanSchema.PROP_LANE_MARKING:
				continue
			var point: Vector2 = entry.get("pos", Vector2.ZERO)
			if not rect.has_point(point):
				problems.append("%s fora do setor em %s" % [key, str(point)])
				continue
			if network.clearance_to_road(point) < 0.15:
				problems.append("%s sobre a pista em %s" % [key, str(point)])
	return problems
