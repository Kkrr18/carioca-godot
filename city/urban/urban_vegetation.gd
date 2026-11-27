class_name UrbanVegetation
extends RefCounted

## Vegetação urbana: árvore de calçada, árvore de quintal, arbusto de lote vazio,
## gramado de praça.
##
## A distribuição não é aleatória sobre a área — é derivada da cidade:
##
## - **Calçada**: árvores nascem ao longo das vias, na faixa da calçada, com
##   espaçamento próprio por classe de via. Nunca no asfalto.
## - **Quintal**: lote com edificação pequena em relação à área ganha árvore no
##   fundo, que é onde ela cabe.
## - **Lote vazio**: vira vegetação de terreno baldio — arbusto e árvore esparsa.
## - **Área pública**: espaço aberto recebe árvore de praça e gramado.
## - **Barreira**: faixa de rio e ferrovia é intocada, com afastamento.
##
## Toda posição passa por três rejeições antes de existir: asfalto, pegada de
## edificação e barreira. É o que faz "árvore dentro da parede" deixar de ser
## possível, em vez de improvável.

const SIDEWALK_OFFSET := 0.55
const MIN_TREE_GAP := 3.4


## `context`: { "network", "blocks", "parcels", "buildings", "config",
## "seed_value", "coord", "rect", "barriers", "open_spaces", "props" }
##
## Devolve { "trees": [...], "bushes": [...], "grass": [...] }, cada item com
## "pos" (Vector2 métrico), "scale", "rot", "species".
static func plan(context: Dictionary) -> Dictionary:
	var config: UrbanConfig = context.get("config", UrbanConfig.active())
	var network: RoadNetwork = context.get("network")
	var rect: Rect2 = context.get("rect", Rect2())
	var seed_value := int(context.get("seed_value", 20170))
	var coord: Vector2i = context.get("coord", Vector2i.ZERO)
	var result := {"trees": [], "bushes": [], "grass": []}
	if network == null or config.tree_density <= 0.0:
		return result

	var occupied := _Occupancy.new()
	occupied.network = network
	occupied.rect = rect
	occupied.config = config
	occupied.buildings = context.get("buildings", [])
	occupied.barriers = context.get("barriers", [])
	occupied.open_spaces = context.get("open_spaces", [])
	occupied.props = context.get("props", {})

	var budget := config.max_vegetation_per_sector
	_plan_street_trees(result, occupied, network, config, coord, seed_value, budget)
	_plan_yard_trees(result, occupied, context, config, coord, seed_value, budget)
	_plan_empty_lots(result, occupied, context, config, coord, seed_value, budget)
	_plan_open_spaces(result, occupied, config, coord, seed_value, budget)
	return result


# --- calçada -----------------------------------------------------------------


static func _plan_street_trees(result: Dictionary, occupied: _Occupancy, network: RoadNetwork, config: UrbanConfig, coord: Vector2i, seed_value: int, budget: int) -> void:
	var trees: Array = result["trees"]
	for edge in network.edges:
		if trees.size() >= budget:
			return
		var a := network.node_position(int(edge["a"]))
		var b := network.node_position(int(edge["b"]))
		var length := a.distance_to(b)
		if length < 10.0:
			continue
		var width := float(edge["width"])
		var direction := (b - a) / length
		var normal := Vector2(-direction.y, direction.x)
		var spacing := maxf(config.tree_spacing / maxf(config.tree_density, 0.05), 8.0)
		var count := maxi(1, int(length / spacing))
		var offset := width * 0.5 + config.sidewalk_width * 0.62
		# A rede do setor vem com as ruas do entorno; sem este corte, árvore de
		# calçada seria gerada para vias de três setores de distância e jogada fora.
		if not PolygonUtils.bounds(PackedVector2Array([a, b])).grow(offset + 4.0).intersects(occupied.rect):
			continue
		for i in range(count):
			var t := (float(i) + 0.5) / float(count)
			for side in [-1.0, 1.0]:
				var point := a.lerp(b, t) + normal * (offset * side)
				if not occupied.accepts(point, 0.6, false, 3.4):
					continue
				if Deterministic.rand01(coord.x * 977 + i, coord.y * 131 + int(side) + 7, seed_value + 211) > config.tree_density:
					continue
				trees.append(_tree_entry(point, coord, i, seed_value, side))
				if trees.size() >= budget:
					return


static func _tree_entry(point: Vector2, coord: Vector2i, index: int, seed_value: int, side: float) -> Dictionary:
	var roll := Deterministic.rand01(coord.x * 31 + index, coord.y * 57 + int(side), seed_value + 223)
	var species := UrbanSchema.SPECIES_TREE if roll < 0.72 else UrbanSchema.SPECIES_TREE_TALL
	return {
		"pos": point,
		"scale": 0.85 + roll * 0.75,
		"rot": roll * TAU,
		"species": species,
	}


# --- quintal e lote -----------------------------------------------------------


static func _plan_yard_trees(result: Dictionary, occupied: _Occupancy, context: Dictionary, config: UrbanConfig, coord: Vector2i, seed_value: int, budget: int) -> void:
	var trees: Array = result["trees"]
	var parcels: Array = context.get("parcels", [])
	var buildings: Array = context.get("buildings", [])
	var building_by_parcel := {}
	for raw in buildings:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = raw
		building_by_parcel[str(building.get("parcel_id", ""))] = building

	for index in range(parcels.size()):
		if trees.size() >= budget:
			return
		var parcel: Dictionary = parcels[index]
		var poly: PackedVector2Array = parcel.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var building: Dictionary = building_by_parcel.get(str(parcel.get("id", "")), {})
		var parcel_area := float(parcel.get("area", 0.0))
		var built_area := 0.0
		if not building.is_empty():
			var footprint: PackedVector2Array = building.get("footprint", PackedVector2Array())
			built_area = PolygonUtils.area(footprint)
		if parcel_area > 0.0 and built_area / parcel_area > 0.72:
			continue
		var roll := Deterministic.rand01(coord.x + index, coord.y + index * 7, seed_value + 227)
		if roll > 0.28 + config.tree_density * 0.55:
			continue
		var point := _interior_point(poly, index, coord, seed_value)
		if point == Vector2.INF:
			continue
		if not occupied.accepts(point, 0.4, true, 1.6):
			continue
		trees.append(_tree_entry(point, coord, index + 500, seed_value, 1.0))


static func _plan_empty_lots(result: Dictionary, occupied: _Occupancy, context: Dictionary, config: UrbanConfig, coord: Vector2i, seed_value: int, budget: int) -> void:
	var trees: Array = result["trees"]
	var bushes: Array = result["bushes"]
	var parcels: Array = context.get("parcels", [])
	var buildings: Array = context.get("buildings", [])
	var occupied_parcels := {}
	for raw in buildings:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		occupied_parcels[str((raw as Dictionary).get("parcel_id", ""))] = true

	for index in range(parcels.size()):
		if trees.size() >= budget:
			return
		var parcel: Dictionary = parcels[index]
		if occupied_parcels.has(str(parcel.get("id", ""))):
			continue
		var poly: PackedVector2Array = parcel.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var bushes_here := 2 + int(Deterministic.rand01(coord.x + index, coord.y, seed_value + 229) * 3.0 * config.tree_density)
		for i in range(bushes_here):
			var point := _interior_point(poly, index * 13 + i, coord, seed_value)
			if point == Vector2.INF:
				continue
			if not occupied.accepts(point, 0.3, true, 1.2):
				continue
			var leaf := Deterministic.rand01(coord.x + i, coord.y + index, seed_value + 233)
			bushes.append({
				"pos": point,
				"scale": 0.7 + leaf * 0.9,
				"rot": leaf * TAU,
				"species": UrbanSchema.SPECIES_BUSH,
			})


static func _plan_open_spaces(result: Dictionary, occupied: _Occupancy, config: UrbanConfig, coord: Vector2i, seed_value: int, budget: int) -> void:
	var trees: Array = result["trees"]
	var grass: Array = result["grass"]
	for space in occupied.open_spaces:
		var poly: PackedVector2Array = space.get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		var center: Vector2 = space.get("point", PolygonUtils.centroid(poly))
		var radius := float(space.get("radius_m", 20.0))
		var tree_count := maxi(2, int(radius / 7.0 * config.tree_density))
		for i in range(tree_count):
			if trees.size() >= budget:
				break
			var angle := TAU * float(i) / float(tree_count)
			var point := center + Vector2(cos(angle), sin(angle)) * radius * (0.35 + Deterministic.rand01(i, coord.x, seed_value + 239) * 0.55)
			if not occupied.accepts(point, 0.6, true, 2.0):
				continue
			trees.append(_tree_entry(point, coord, 900 + i, seed_value, 1.0))
		var grass_count := int(radius * 0.9 * config.tree_density)
		for i in range(grass_count):
			var angle := TAU * Deterministic.rand01(i, 3, seed_value + 241)
			var distance := radius * sqrt(Deterministic.rand01(i, 5, seed_value + 243))
			var point := center + Vector2(cos(angle), sin(angle)) * distance
			if not occupied.accepts(point, 0.2, true, 0.5):
				continue
			grass.append({
				"pos": point,
				"scale": 0.8 + Deterministic.rand01(i, 7, seed_value + 247) * 0.8,
				"rot": angle,
				"species": UrbanSchema.SPECIES_GRASS,
			})


## Ponto pseudo-aleatório dentro do polígono, por amostragem da caixa e
## verificação de contenção. Determinístico pela chave recebida.
static func _interior_point(poly: PackedVector2Array, salt: int, coord: Vector2i, seed_value: int) -> Vector2:
	var bounds := PolygonUtils.bounds(poly)
	for attempt in range(12):
		var fx := Deterministic.rand01(salt + attempt * 3, coord.x + attempt, seed_value + 251)
		var fy := Deterministic.rand01(salt + attempt * 3, coord.y + attempt, seed_value + 253)
		var point := Vector2(bounds.position.x + bounds.size.x * fx, bounds.position.y + bounds.size.y * fy)
		if PolygonUtils.point_in_polygon(point, poly):
			if PolygonUtils.distance_to_polygon(point, poly) >= 1.5:
				return point
	return Vector2.INF


# --- rejeições ---------------------------------------------------------------


## Quem decide se uma posição pode receber vegetação. Uma instância por setor,
## com os dados já separados por caixa para a verificação não custar caro.
class _Occupancy:
	var network: RoadNetwork = null
	var rect: Rect2 = Rect2()
	var config: UrbanConfig = null
	var buildings: Array = []
	var barriers: Array = []
	var open_spaces: Array = []
	var props: Dictionary = {}
	var _building_data: Array = []

	func _prepare() -> void:
		if not _building_data.is_empty():
			return
		for raw in buildings:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var building: Dictionary = raw
			var footprint: PackedVector2Array = building.get("footprint", PackedVector2Array())
			if footprint.size() < 3:
				continue
			_building_data.append({
				"poly": footprint,
				"bounds": PolygonUtils.bounds(footprint).grow(1.2),
			})

	## `road_margin` é a folga mínima até a borda do asfalto; `prop_margin` é a
	## distância mínima de um objeto de rua já planejado. Os dois são separados
	## porque árvore de calçada nasce **a poucos metros** do meio-fio de propósito:
	## usar a mesma folga para tudo acabaria com a arborização da calçada.
	##
	## `allow_outside` libera pontos fora do recorte do setor — usado só em área
	## que pertence a este setor por construção (quintal, praça).
	func accepts(point: Vector2, road_margin: float, allow_outside: bool, prop_margin: float = 1.5) -> bool:
		_prepare()
		if not allow_outside and not rect.has_point(point):
			return false
		if network != null and network.clearance_to_road(point) < road_margin:
			return false
		for entry in _building_data:
			var bounds: Rect2 = entry["bounds"]
			if not bounds.has_point(point):
				continue
			if PolygonUtils.point_in_polygon(point, entry["poly"]):
				return false
		for barrier in barriers:
			if _near_barrier(point, barrier, road_margin):
				return false
		for key in props.keys():
			var entries: Array = props[key]
			for raw in entries:
				if typeof(raw) != TYPE_DICTIONARY:
					continue
				var entry: Dictionary = raw
				var position: Vector2 = entry.get("pos", Vector2.ZERO)
				if position.distance_to(point) < prop_margin:
					return false
		return true

	func _near_barrier(point: Vector2, barrier: Dictionary, margin: float) -> bool:
		var polyline: PackedVector2Array = barrier.get("polyline", PackedVector2Array())
		if polyline.size() < 2:
			return false
		var half := float(barrier.get("width_m", 4.0)) * 0.5 + float(barrier.get("protected_buffer_m", 0.0)) + margin
		for i in range(polyline.size() - 1):
			if PolygonUtils.distance_to_segment(point, polyline[i], polyline[i + 1]) < half:
				return true
		return false
