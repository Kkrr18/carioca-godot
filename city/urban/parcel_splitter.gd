class_name ParcelSplitter
extends RefCounted

## Divide uma quadra em lotes.
##
## Guilhotina em duas direções, que é como loteamento de verdade se organiza:
##
##   1. A quadra é fatiada **paralelamente à via principal**, em faixas de
##      largura variável (a testada do lote).
##   2. Cada faixa é cortada **perpendicularmente**, separando o lote de frente
##      do lote de fundo. Quadra funda recebe duas fileiras; quadra rasa recebe
##      uma.
##   3. Se a faixa encosta numa via perpendicular (quadra de esquina), o canto
##      vira um lote próprio, com a frente para essa outra via.
##
## Tudo sai de recorte de meia-reta sobre o polígono real da quadra, então lote de
## quadra triangular é triangular. E como cada lote nasce de uma fatia disjunta,
## **dois lotes nunca se sobrepõem** — não é uma checagem, é uma propriedade da
## construção.
##
## A frente do lote não é inferida da fatia: depois de formado o polígono do
## lote, procuramos a aresta com menor folga até o asfalto e a orientamos com a
## normal para dentro do lote. Lote de esquina acaba com a frente certa na rua
## que de fato o atende.

const ROW_FRONT := "frente"
const ROW_BACK := "fundo"
const ROW_CORNER := "esquina"


## Devolve os lotes de uma quadra, com polígonos em espaço métrico global.
static func split(block: Dictionary, network: RoadNetwork, config: UrbanConfig, seed_value: int) -> Array:
	var parcels: Array = []
	var poly: PackedVector2Array = block.get("poly", PackedVector2Array())
	if poly.size() < 3:
		return parcels
	if PolygonUtils.area(poly) < config.parcel_min_area:
		return parcels

	var frontage: Array = block.get("frontage", [])
	if frontage.is_empty():
		return parcels

	var primary := _longest(frontage)
	var u: Vector2 = primary["dir"]
	var n: Vector2 = Vector2(-u.y, u.x)
	if not _normal_points_inside(poly, primary["a"], n):
		u = -u
		n = -n

	var secondary := _secondary_frontage(frontage, u)
	var block_centroid: Vector2 = block.get("centroid", Vector2.ZERO)
	var salt := Deterministic.hash2(int(block_centroid.x), int(block_centroid.y), seed_value)

	var along := PolygonUtils.project_range(poly, u)
	var widths := _strip_widths(along.y - along.x, config, salt)
	var cursor := along.x
	for strip_index in range(widths.size()):
		var width: float = widths[strip_index]
		var strip := PolygonUtils.clip_slab(poly, u, cursor, cursor + width)
		cursor += width
		if strip.size() < 3:
			continue
		if PolygonUtils.area(strip) < config.parcel_min_area * 0.5:
			continue

		var remaining := strip
		if not secondary.is_empty():
			var cut := _corner_parcel(strip, secondary, network, config, salt, strip_index)
			if not cut.is_empty():
				if not cut["parcel"].is_empty():
					parcels.append(cut["parcel"])
				if cut["remaining"].size() >= 3:
					remaining = cut["remaining"]
				else:
					continue

		var across := PolygonUtils.project_range(remaining, n)
		var depth := Deterministic.rand_range(salt, strip_index, config.parcel_depth_min, config.parcel_depth_max, seed_value + 31) * config.parcel_scale
		var available := across.y - across.x
		depth = clampf(depth, config.parcel_depth_min, maxf(available, config.parcel_depth_min))
		if available <= depth + 4.0:
			# Quadra rasa: uma fileira só.
			_append_parcel(parcels, remaining, network, config, ROW_FRONT)
		else:
			var front := PolygonUtils.clip_slab(remaining, n, across.x, across.x + depth)
			var back := PolygonUtils.clip_slab(remaining, n, across.x + depth, across.y)
			_append_parcel(parcels, front, network, config, ROW_FRONT)
			_append_parcel(parcels, back, network, config, ROW_BACK)

	parcels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2 = a["centroid"]
		var pb: Vector2 = b["centroid"]
		if absf(pa.x - pb.x) > 0.001:
			return pa.x < pb.x
		return pa.y < pb.y)
	for i in range(parcels.size()):
		(parcels[i] as Dictionary)["id"] = "L%02d" % i
	return parcels


static func _longest(frontage: Array) -> Dictionary:
	var best: Dictionary = frontage[0]
	for entry in frontage:
		var candidate: Dictionary = entry
		if float(candidate.get("length", 0.0)) > float(best.get("length", 0.0)):
			best = candidate
	return best


## Normal para dentro do polígono: o centroide precisa estar do lado positivo.
static func _normal_points_inside(poly: PackedVector2Array, edge_point: Vector2, normal: Vector2) -> bool:
	var centroid := PolygonUtils.centroid(poly)
	return normal.dot(centroid - edge_point) > 0.0


## Via perpendicular à principal — o que transforma canto de quadra em lote de
## esquina. Vazio quando a quadra não tem frente para outra direção.
static func _secondary_frontage(frontage: Array, primary_dir: Vector2) -> Dictionary:
	for entry in frontage:
		var candidate: Dictionary = entry
		var direction: Vector2 = candidate["dir"]
		if absf(direction.dot(primary_dir)) < 0.55 and float(candidate["length"]) > 8.0:
			return candidate
	return {}


## Larguras das faixas. A última absorve o resto quando sobra menos que um lote
## mínimo — melhor um lote mais largo que um caco de dois metros.
static func _strip_widths(span: float, config: UrbanConfig, salt: int) -> Array:
	var widths: Array = []
	if span <= 0.0:
		return widths
	var min_front := config.parcel_min_front * config.parcel_scale
	var max_front := maxf(config.parcel_max_front * config.parcel_scale, min_front + 0.5)
	var cursor := 0.0
	var index := 0
	var guard := 0
	while cursor < span - 0.5 and guard < 512:
		guard += 1
		var width := Deterministic.rand_range(salt, index, min_front, max_front, 7)
		if span - (cursor + width) < min_front * 0.7:
			width = span - cursor
		widths.append(width)
		cursor += width
		index += 1
	return widths


## Lote de esquina: recorta o canto da faixa que está de frente para a via
## perpendicular. Devolve { "parcel": Dictionary|{}, "remaining": PackedVector2Array }.
static func _corner_parcel(strip: PackedVector2Array, secondary: Dictionary, network: RoadNetwork, config: UrbanConfig, salt: int, strip_index: int) -> Dictionary:
	var direction: Vector2 = secondary["dir"]
	var range := PolygonUtils.project_range(strip, direction)
	var depth := config.parcel_corner_depth
	var candidates: Array = [
		{"min": range.x, "max": range.x + depth, "low": true},
		{"min": range.y - depth, "max": range.y, "low": false},
	]
	for candidate in candidates:
		var limits: Dictionary = candidate
		var low_side := bool(limits["low"])
		var slab := PolygonUtils.clip_slab(strip, direction, float(limits["min"]), float(limits["max"]))
		if slab.size() < 3:
			continue
		if PolygonUtils.area(slab) < config.parcel_min_area:
			continue
		# O canto só vale se estiver de frente para uma via de verdade: sonda a
		# borda externa da fatia, não o centro dela.
		var probe := PolygonUtils.centroid(slab)
		probe += direction * (depth * 0.5 * (1.0 if low_side else -1.0))
		if network.clearance_to_road(probe) > config.sidewalk_width + config.block_inset_extra + 2.0:
			continue
		var remainder := PackedVector2Array()
		if low_side:
			remainder = PolygonUtils.clip_half_plane(strip, direction, float(limits["max"]))
		else:
			remainder = PolygonUtils.clip_half_plane(strip, -direction, -float(limits["min"]))
		if remainder.size() < 3:
			# O canto tomaria a faixa inteira: não é canto, é a faixa.
			continue
		var parcel := _make_parcel(slab, network, config, ROW_CORNER)
		if parcel.is_empty():
			continue
		parcel["strip"] = strip_index
		return {"parcel": parcel, "remaining": remainder}
	return {"parcel": {}, "remaining": strip}


static func _append_parcel(out: Array, poly: PackedVector2Array, network: RoadNetwork, config: UrbanConfig, row: String) -> void:
	var parcel := _make_parcel(poly, network, config, row)
	if parcel.is_empty():
		return
	out.append(parcel)


static func _make_parcel(poly: PackedVector2Array, network: RoadNetwork, config: UrbanConfig, row: String) -> Dictionary:
	var cleaned := PolygonUtils.clean(PolygonUtils.to_ccw(poly), 0.05)
	if cleaned.size() < 3:
		return {}
	var area := PolygonUtils.area(cleaned)
	if area < config.parcel_min_area:
		return {}
	var front := _front_edge(cleaned, network)
	if front.is_empty():
		return {}
	var frontage_width := float(front["width"])
	if frontage_width < config.parcel_min_front * 0.55:
		return {}
	var across := PolygonUtils.project_range(cleaned, front["normal"])
	return {
		"poly": cleaned,
		"area": area,
		"centroid": PolygonUtils.centroid(cleaned),
		"front": front,
		"frontage_width": frontage_width,
		"depth": across.y - across.x,
		"row": row,
		"corner": row == ROW_CORNER,
		"bounds": PolygonUtils.bounds(cleaned),
	}


## Aresta do lote mais próxima do asfalto, orientada com a normal para dentro.
static func _front_edge(poly: PackedVector2Array, network: RoadNetwork) -> Dictionary:
	var count := poly.size()
	var best_index := -1
	var best_clearance := INF
	for i in range(count):
		var a := poly[i]
		var b := poly[(i + 1) % count]
		if a.distance_to(b) < 2.0:
			continue
		var midpoint := (a + b) * 0.5
		var clearance := network.clearance_to_road(midpoint)
		if clearance < best_clearance:
			best_clearance = clearance
			best_index = i
	if best_index < 0:
		return {}
	var a := poly[best_index]
	var b := poly[(best_index + 1) % count]
	var direction := (b - a).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var centroid := PolygonUtils.centroid(poly)
	if normal.dot(centroid - a) < 0.0:
		# A aresta estava no sentido horário em relação à face do lote.
		var swap := a
		a = b
		b = swap
		direction = -direction
		normal = -normal
	var midpoint := (a + b) * 0.5
	var edge := network.nearest_edge(midpoint)
	return {
		"a": a,
		"b": b,
		"width": a.distance_to(b),
		"dir": direction,
		"normal": normal,
		"clearance": best_clearance,
		"road_class": str(edge.get("road_class", WorldSchema.ROAD_LOCAL)),
		"road_width": float(edge.get("width", 6.0)),
	}


## Validação usada pelas ferramentas e pelos testes: nenhum par de lotes da
## mesma quadra se sobrepõe e todos cabem na quadra.
static func validate(block: Dictionary, parcels: Array) -> Array:
	var problems: Array[String] = []
	var block_poly: PackedVector2Array = block.get("poly", PackedVector2Array())
	var block_area := PolygonUtils.area(block_poly)
	var total := 0.0
	for i in range(parcels.size()):
		var parcel: Dictionary = parcels[i]
		var poly: PackedVector2Array = parcel["poly"]
		var area := PolygonUtils.area(poly)
		total += area
		if area > block_area + 1.0:
			problems.append("lote %s maior que a quadra" % str(parcel.get("id", "?")))
		if block_area > 0.0 and not PolygonUtils.point_in_polygon(PolygonUtils.centroid(poly), block_poly):
			problems.append("lote %s fora da quadra" % str(parcel.get("id", "?")))
		for j in range(i + 1, parcels.size()):
			var other: Dictionary = parcels[j]
			if PolygonUtils.polygons_overlap(poly, other["poly"]):
				problems.append("lotes %s e %s se sobrepõem" % [str(parcel.get("id", "?")), str(other.get("id", "?"))])
	if block_area > 0.0 and total > block_area + 1.0:
		problems.append("soma dos lotes (%.1f m²) excede a quadra (%.1f m²)" % [total, block_area])
	return problems
