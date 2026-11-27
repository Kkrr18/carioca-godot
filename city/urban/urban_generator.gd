class_name UrbanGenerator
extends RefCounted

## Orquestrador da geração urbana.
##
## Transforma um setor em cidade: fonte de ruas -> rede -> quadras -> lotes ->
## edificações -> mobiliário -> vegetação, num payload só.
##
## **A prioridade das fontes de rua é a decisão mais importante daqui:**
##
##   1. payload de setor gravado (extrato OSM importado) — geometria real;
##   2. traçado esquemático em `data/geographic/urban` — estimativa declarada;
##   3. reticulação procedural da Etapa 1 — sem dado externo.
##
## As três passam pelo mesmo pipeline. Trocar de fonte não muda uma linha de
## quadra, lote ou prédio; muda de onde veio a rua.
##
## **A costura entre setores** é resolvida montando a rede com um recorte maior
## que o setor (as ruas dos oito vizinhos). Cada quadra pertence ao setor que
## contém o seu centroide e é gerada por inteiro, então não existe quarteirão
## cortado ao meio com metade em cada lado.
##
## **A compatibilidade com a Etapa 2 é aditiva.** O payload mantém todas as
## chaves antigas (`roads`, `buildings` com center/size/angle/height/kind/door,
## `trees`, `props`, `water`) e acrescenta `blocks`, `parcels`, `vegetation`,
## `street_objects`, `landmarks`, `provenance` e `urban_v3`. Trânsito, pedestres,
## minimapa, porta de interior e `validate_sectors` continuam lendo o que já
## liam.
##
## **Setor rural continua barato**: sem dado externo e abaixo da densidade
## mínima, devolve exatamente o payload da Etapa 2.

const NETWORK_MARGIN := 640.0


## Ponto de entrada. Devolve o payload completo do setor.
static func build_payload(coord: Vector2i, seed_value: int = 20170, config: UrbanConfig = null) -> Dictionary:
	var active: UrbanConfig = config if config != null else UrbanConfig.active()
	var rect := SectorGrid.sector_rect(coord)
	var origin := SectorGrid.sector_origin(coord)
	var stored := _stored_payload(coord)
	var base: Dictionary = stored.duplicate(true) if not stored.is_empty() else CityGenerator.build_payload(coord, seed_value)
	var density := float(base.get("density", MunicipalityIndex.density_at(SectorGrid.sector_center(coord))))

	var source := _source_for(coord, rect, stored)
	if source == UrbanSchema.SOURCE_PROCEDURAL and density < active.urban_density_threshold:
		# Caminho barato, byte por byte igual ao da Etapa 2.
		return base

	var network := _build_network(coord, source, seed_value, stored)
	if network.edge_count() == 0:
		return base

	var sector_id := str(base.get("id", MunicipalityIndex.id_for(coord)))
	var landmarks := LandmarkRegistry.for_rect(rect)
	var open_spaces := LandmarkRegistry.open_spaces_for_rect(rect)
	var barriers := _barriers(rect)
	var reserved := _reserved_areas(rect, active, landmarks, open_spaces)

	var blocks := UrbanBlockBuilder.build(network, active, rect)
	var parcels: Array = []
	for block in blocks:
		var block_parcels := ParcelSplitter.split(block, network, active, seed_value)
		block["parcel_count"] = block_parcels.size()
		for parcel in block_parcels:
			parcel["block_id"] = str(block.get("id", ""))
			parcels.append(parcel)

	var usable: Array = []
	for parcel in parcels:
		var centroid: Vector2 = parcel.get("centroid", Vector2.ZERO)
		if _inside_any(centroid, reserved):
			continue
		usable.append(parcel)

	var real_buildings: Array = []
	var real_footprints: Array = []
	if source == UrbanSchema.SOURCE_OSM:
		for raw in base.get("buildings", []):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			real_buildings.append(raw)
			var polygon: Array = (raw as Dictionary).get("poly", [])
			if not polygon.is_empty():
				real_footprints.append(_polygon_to_metric(polygon, origin))

	var buildings: Array = []
	for landmark in landmarks:
		if buildings.size() >= active.max_buildings:
			break
		if str(landmark.get("role", "")) != UrbanSchema.ROLE_LANDMARK:
			continue
		var massing: Dictionary = landmark.get("generate", {})
		if str(massing.get("type", "")) != "building":
			continue
		var point: Vector2 = landmark.get("point", Vector2.ZERO)
		if not rect.has_point(point):
			# Pertence ao setor vizinho: gera uma vez só.
			continue
		var landmark_building := BuildingGenerator.generate_landmark(landmark, active, sector_id, seed_value)
		if not landmark_building.is_empty():
			buildings.append(landmark_building)

	var context := {
		"config": active,
		"network": network,
		"density": density,
		"seed_value": seed_value,
		"sector_id": sector_id,
	}
	for parcel in usable:
		if buildings.size() >= active.max_buildings:
			break
		var parcel_poly: PackedVector2Array = parcel.get("poly", PackedVector2Array())
		var blocked := false
		for footprint in real_footprints:
			if PolygonUtils.polygons_overlap(parcel_poly, footprint):
				blocked = true
				break
		if blocked:
			continue
		var building := BuildingGenerator.generate(parcel, context)
		if building.is_empty():
			continue
		buildings.append(building)

	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector2 = a.get("center", Vector2.ZERO)
		var cb: Vector2 = b.get("center", Vector2.ZERO)
		if absf(ca.x - cb.x) > 0.001:
			return ca.x < cb.x
		return ca.y < cb.y)
	for index in range(buildings.size()):
		var building: Dictionary = buildings[index]
		if str(building.get("id", "")).is_empty():
			building["id"] = "%s/B%03d" % [sector_id, index]
		buildings[index] = building

	var prop_context := {
		"network": network,
		"blocks": blocks,
		"parcels": usable,
		"buildings": buildings,
		"config": active,
		"seed_value": seed_value,
		"coord": coord,
		"rect": rect,
		"open_spaces": open_spaces,
	}
	var props := UrbanProps.plan(prop_context)
	var vegetation := UrbanVegetation.plan({
		"network": network,
		"blocks": blocks,
		"parcels": usable,
		"buildings": buildings,
		"config": active,
		"seed_value": seed_value,
		"coord": coord,
		"rect": rect,
		"barriers": barriers,
		"open_spaces": open_spaces,
		"props": props,
	})

	return _assemble(base, {
		"coord": coord,
		"origin": origin,
		"rect": rect,
		"source": source,
		"density": density,
		"sector_id": sector_id,
		"network": network,
		"blocks": blocks,
		"parcels": usable,
		"buildings": buildings,
		"real_buildings": real_buildings,
		"props": props,
		"vegetation": vegetation,
		"landmarks": landmarks,
		"barriers": barriers,
		"open_spaces": open_spaces,
		"config": active,
		"seed_value": seed_value,
	})


static func _source_for(coord: Vector2i, rect: Rect2, stored: Dictionary) -> String:
	if not stored.is_empty():
		# Payload já congelado por `regenerate_sector --bake`: ele mesmo declara a
		# fonte, e essa declaração sobrevive ao disco. Sem isto, um setor gerado a
		# partir do traçado esquemático voltaria rotulado como OSM depois do bake.
		var declared := str(stored.get("urban_source", ""))
		if declared == UrbanSchema.SOURCE_OSM or declared == UrbanSchema.SOURCE_ESTIMATED or declared == UrbanSchema.SOURCE_PROCEDURAL:
			return declared
		if not (stored.get("roads", []) as Array).is_empty():
			return UrbanSchema.SOURCE_OSM
	if StreetFramework.covers(rect.grow(NETWORK_MARGIN)):
		return UrbanSchema.SOURCE_ESTIMATED
	return UrbanSchema.SOURCE_PROCEDURAL


static func _stored_payload(coord: Vector2i) -> Dictionary:
	var path := SectorRepository.path_for(coord)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var payload: Dictionary = parsed
	if int(payload.get("version", 0)) != WorldSchema.SECTOR_SCHEMA_VERSION:
		return {}
	return payload


# --- rede --------------------------------------------------------------------


static func _build_network(coord: Vector2i, source: String, seed_value: int, stored: Dictionary) -> RoadNetwork:
	var segments: Array = []
	match source:
		UrbanSchema.SOURCE_OSM:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var neighbour := Vector2i(coord.x + dx, coord.y + dy)
					var payload := stored if neighbour == coord else _stored_payload(neighbour)
					if payload.is_empty():
						continue
					_append_payload_roads(segments, payload.get("roads", []), SectorGrid.sector_origin(neighbour))
		UrbanSchema.SOURCE_ESTIMATED:
			segments = StreetFramework.roads_for_rect(SectorGrid.sector_rect(coord).grow(NETWORK_MARGIN))
		_:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var neighbour := Vector2i(coord.x + dx, coord.y + dy)
					var origin := SectorGrid.sector_origin(neighbour)
					_append_payload_roads(segments, CityGenerator.build_roads_only(neighbour, seed_value), origin)
	return RoadNetwork.from_segments(segments)


static func _append_payload_roads(segments: Array, roads: Array, origin: Vector2) -> void:
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
			var a := origin + Vector2(float(pair_a[0]), -float(pair_a[1]))
			var b := origin + Vector2(float(pair_b[0]), -float(pair_b[1]))
			segments.append({
				"a": a,
				"b": b,
				"width": width,
				"road_class": road_class,
				"id": "%s|%d" % [road_id, i],
			})


# --- apoio -------------------------------------------------------------------


static func _barriers(rect: Rect2) -> Array:
	var out: Array = []
	for entry in StreetFramework.barriers_for_rect(rect.grow(NETWORK_MARGIN)):
		out.append(entry)
	for entry in LandmarkRegistry.barriers_for_rect(rect):
		out.append(entry)
	return out


static func _reserved_areas(rect: Rect2, config: UrbanConfig, landmarks: Array, open_spaces: Array) -> Array:
	var out: Array = []
	for entry in LandmarkRegistry.protected_polygons(rect, config.barrier_buffer):
		out.append(entry)
	for landmark in landmarks:
		var role := str(landmark.get("role", ""))
		if role == UrbanSchema.ROLE_OPEN_SPACE:
			continue
		var point: Vector2 = landmark.get("point", Vector2.ZERO)
		var radius := maxf(float(landmark.get("radius_m", 18.0)), config.landmark_reserve_radius)
		out.append({"id": str(landmark.get("id", "")), "poly": _circle(point, radius, 14)})
	for space in open_spaces:
		out.append({"id": str(space.get("id", "")), "poly": space.get("poly", PackedVector2Array())})
	return out


static func _circle(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * float(i) / float(maxi(segments, 3))
		out.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return out


static func _inside_any(point: Vector2, areas: Array) -> bool:
	for area in areas:
		if typeof(area) != TYPE_DICTIONARY:
			continue
		var poly: PackedVector2Array = (area as Dictionary).get("poly", PackedVector2Array())
		if poly.size() < 3:
			continue
		if not PolygonUtils.bounds(poly).has_point(point):
			continue
		if PolygonUtils.point_in_polygon(point, poly):
			return true
	return false


static func _polygon_to_metric(raw: Array, origin: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pair in raw:
		if typeof(pair) != TYPE_ARRAY:
			continue
		var values: Array = pair
		if values.size() < 2:
			continue
		out.append(origin + Vector2(float(values[0]), -float(values[1])))
	return out


static func _local_point(point: Vector2, origin: Vector2) -> Array:
	return [
		snappedf(point.x - origin.x, 0.01),
		snappedf(-(point.y - origin.y), 0.01),
	]


static func _local_polygon(poly: PackedVector2Array, origin: Vector2) -> Array:
	var out: Array = []
	for point in poly:
		out.append(_local_point(point, origin))
	return out


## Espelho (x, y) -> (x, -y) inverte o sentido de giro: ângulo e rotação em
## espaço local são o negativo do ângulo métrico. Fica numa função só para não
## haver conversão de ângulo escrita à mão em outro lugar.
static func _local_angle(metric_angle: float) -> float:
	return -metric_angle


# --- montagem do payload -----------------------------------------------------


static func _assemble(base: Dictionary, data: Dictionary) -> Dictionary:
	var coord: Vector2i = data["coord"]
	var origin: Vector2 = data["origin"]
	var rect: Rect2 = data["rect"]
	var source: String = data["source"]
	var sector_id: String = data["sector_id"]
	var config: UrbanConfig = data["config"]
	var network: RoadNetwork = data["network"]
	var payload := base
	var seed_value: int = data["seed_value"]

	payload["source"] = source
	payload["urban"] = true
	payload["urban_v3"] = true
	payload["urban_version"] = UrbanSchema.URBAN_VERSION
	payload["urban_source"] = source
	payload["urban_config"] = config.describe()
	payload["seed"] = seed_value
	payload["provenance"] = _provenance(source, rect)
	payload["urban_geometry"] = {
		"sidewalk_width": snappedf(config.sidewalk_width, 0.01),
		"curb_height": snappedf(config.curb_height, 0.01),
	}

	if source == UrbanSchema.SOURCE_ESTIMATED:
		payload["roads"] = _framework_roads_local(rect, origin)

	var buildings_out: Array = []
	for raw in data.get("real_buildings", []):
		buildings_out.append(raw)
	for raw in data.get("buildings", []):
		buildings_out.append(_serialize_building(raw, origin, sector_id))
	payload["buildings"] = buildings_out

	var blocks_out: Array = []
	for block in data.get("blocks", []):
		var entry: Dictionary = block
		blocks_out.append({
			"id": str(entry.get("id", "")),
			"poly": _local_polygon(entry.get("poly", PackedVector2Array()), origin),
			"centroid": _local_point(entry.get("centroid", Vector2.ZERO), origin),
			"area": snappedf(float(entry.get("area", 0.0)), 0.01),
			"parcel_count": int(entry.get("parcel_count", 0)),
		})
	payload["blocks"] = blocks_out

	var parcels_out: Array = []
	for parcel in data.get("parcels", []):
		var entry: Dictionary = parcel
		var front: Dictionary = entry.get("front", {})
		parcels_out.append({
			"id": "%s/%s" % [sector_id, str(entry.get("id", ""))],
			"block_id": "%s/%s" % [sector_id, str(entry.get("block_id", ""))],
			"poly": _local_polygon(entry.get("poly", PackedVector2Array()), origin),
			"centroid": _local_point(entry.get("centroid", Vector2.ZERO), origin),
			"area": snappedf(float(entry.get("area", 0.0)), 0.01),
			"frontage_width": snappedf(float(entry.get("frontage_width", 0.0)), 0.01),
			"depth": snappedf(float(entry.get("depth", 0.0)), 0.01),
			"row": str(entry.get("row", "")),
			"corner": bool(entry.get("corner", false)),
			"front": {
				"a": _local_point(front.get("a", Vector2.ZERO), origin),
				"b": _local_point(front.get("b", Vector2.ZERO), origin),
				"road_class": str(front.get("road_class", WorldSchema.ROAD_LOCAL)),
				"road_width": snappedf(float(front.get("road_width", 6.0)), 0.01),
				"clearance": snappedf(float(front.get("clearance", 0.0)), 0.01),
			},
		})
	payload["parcels"] = parcels_out

	payload["street_objects"] = _serialize_props(data.get("props", {}), origin)
	payload["vegetation"] = _serialize_vegetation(data.get("vegetation", {}), origin)
	payload["props"] = []
	payload["trees"] = _legacy_trees(data.get("vegetation", {}), origin)

	var landmarks_out: Array = []
	for landmark in data.get("landmarks", []):
		var entry: Dictionary = landmark
		landmarks_out.append({
			"id": str(entry.get("id", "")),
			"name": str(entry.get("name", "")),
			"kind": str(entry.get("kind", "")),
			"role": str(entry.get("role", "")),
			"confidence": str(entry.get("confidence", "")),
			"honesty": str(entry.get("honesty", "")),
			"source": str(entry.get("source", "")),
			"license": str(entry.get("license", "")),
			"local": _local_point(entry.get("point", Vector2.ZERO), origin) if entry.has("point") else [],
			"radius_m": snappedf(float(entry.get("radius_m", 0.0)), 0.01),
		})
	payload["landmarks"] = landmarks_out

	var barriers_out: Array = []
	for barrier in data.get("barriers", []):
		var entry: Dictionary = barrier
		var polyline: PackedVector2Array = entry.get("polyline", PackedVector2Array())
		var local: Array = []
		for point in polyline:
			local.append(_local_point(point, origin))
		barriers_out.append({
			"id": str(entry.get("id", "")),
			"kind": str(entry.get("kind", "")),
			"width_m": snappedf(float(entry.get("width_m", 4.0)), 0.01),
			"points": local,
		})
	payload["barriers"] = barriers_out

	var open_out: Array = []
	for space in data.get("open_spaces", []):
		var entry: Dictionary = space
		open_out.append({
			"id": str(entry.get("id", "")),
			"name": str(entry.get("name", "")),
			"local": _local_point(entry.get("point", Vector2.ZERO), origin),
			"radius_m": snappedf(float(entry.get("radius_m", 0.0)), 0.01),
		})
	payload["open_spaces"] = open_out

	payload["urban_stats"] = {
		"blocks": blocks_out.size(),
		"parcels": parcels_out.size(),
		"buildings": buildings_out.size(),
		"generated": (data.get("buildings", []) as Array).size(),
		"trees": (data.get("vegetation", {}).get("trees", []) as Array).size(),
		"vegetation": (data.get("vegetation", {}).get("bushes", []) as Array).size(),
		"roads": network.edge_count(),
		"intersections": network.intersections().size(),
		"landmarks": landmarks_out.size(),
	}
	return payload


static func _provenance(source: String, rect: Rect2) -> Dictionary:
	var out := {
		"generator": "UrbanGenerator",
		"urban_version": UrbanSchema.URBAN_VERSION,
	}
	match source:
		UrbanSchema.SOURCE_OSM:
			out["source"] = "payload de setor importado (OpenStreetMap)"
			out["license"] = "ODbL 1.0 — © colaboradores do OpenStreetMap"
			out["confidence"] = UrbanSchema.CONFIDENCE_HIGH
			out["note"] = "geometria de rua e de edificação importada; quadras e lotes derivados dela"
		UrbanSchema.SOURCE_ESTIMATED:
			var framework := StreetFramework.provenance_for(rect)
			out["source"] = str(framework.get("source", "traçado esquemático autoral"))
			out["license"] = str(framework.get("license", "CC0-1.0"))
			out["confidence"] = str(framework.get("confidence", UrbanSchema.CONFIDENCE_LOW))
			out["note"] = str(framework.get("note", "traçado esquemático; não é dado cadastral"))
			out["dataset"] = str(framework.get("dataset", ""))
		_:
			out["source"] = "reticulação procedural determinística (Etapa 1)"
			out["license"] = "obra do próprio projeto (CC0-1.0)"
			out["confidence"] = UrbanSchema.CONFIDENCE_LOW
			out["note"] = "sem dado geográfico externo: quadras e lotes são estimativa procedural, não cadastro"
	return out


## Vias do traçado esquemático recortadas ao setor, no espaço local do payload.
static func _framework_roads_local(rect: Rect2, origin: Vector2) -> Array:
	var out: Array = []
	var segments := StreetFramework.roads_for_rect(rect.grow(2.0))
	for segment in segments:
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var la := Vector2(a.x - origin.x, -(a.y - origin.y))
		var lb := Vector2(b.x - origin.x, -(b.y - origin.y))
		out.append({
			"id": str(segment.get("id", "street")),
			"class": str(segment.get("road_class", WorldSchema.ROAD_LOCAL)),
			"width": float(segment.get("width", 6.0)),
			"lattice": "framework",
			"nodes": [
				"p:%.1f:%.1f" % [a.x, a.y],
				"p:%.1f:%.1f" % [b.x, b.y],
			],
			"points": [[snappedf(la.x, 0.01), snappedf(la.y, 0.01)], [snappedf(lb.x, 0.01), snappedf(lb.y, 0.01)]],
			"name": str(segment.get("name", "")),
		})
	return out


static func _serialize_building(building: Dictionary, origin: Vector2, sector_id: String) -> Dictionary:
	var center: Vector2 = building.get("center", Vector2.ZERO)
	var size: Vector2 = building.get("size", Vector2(10.0, 10.0))
	var angle := float(building.get("angle", 0.0))
	var u := Vector2(cos(angle), sin(angle))
	var n := Vector2(-u.y, u.x)
	var frame_origin: Vector2 = building.get("frame_origin", center - u * (size.x * 0.5) - n * (size.y * 0.5))
	var modules_out: Array = []
	for module in building.get("modules", []):
		if typeof(module) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = module
		modules_out.append({
			"type": str(entry.get("type", "")),
			"side": int(entry.get("side", 0)),
			"along": snappedf(float(entry.get("along", 0.0)), 0.01),
			"width": snappedf(float(entry.get("width", 0.0)), 0.01),
			"height": snappedf(float(entry.get("height", 0.0)), 0.01),
			"sill": snappedf(float(entry.get("sill", 0.0)), 0.01),
			"floor": int(entry.get("floor", 0)),
			"depth": snappedf(float(entry.get("depth", 0.0)), 0.01),
			"category": str(entry.get("category", "")),
			"awning": bool(entry.get("awning", false)),
		})
	var wall: Dictionary = building.get("wall", {})
	var wall_out := {}
	if not wall.is_empty():
		wall_out = {
			"height": snappedf(float(wall.get("height", 1.8)), 0.01),
			"thickness": snappedf(float(wall.get("thickness", 0.18)), 0.01),
			"gate_width": snappedf(float(wall.get("gate_width", 3.0)), 0.01),
			"gate_along": snappedf(float(wall.get("gate_along", 1.0)), 0.01),
			"span": snappedf(float(wall.get("span", 0.0)), 0.01),
		}
	return {
		"id": str(building.get("id", "")),
		"parcel_id": "%s/%s" % [sector_id, str(building.get("parcel_id", ""))],
		"block_id": "%s/%s" % [sector_id, str(building.get("block_id", ""))],
		"sector_id": sector_id,
		"kind": str(building.get("kind", UrbanSchema.KIND_RESIDENTIAL)),
		"typology": str(building.get("typology", UrbanSchema.TYPOLOGY_HOUSE_GROUND)),
		"center": _local_point(center, origin),
		"size": [snappedf(size.x, 0.01), snappedf(size.y, 0.01)],
		"angle": _local_angle(angle),
		"levels": int(building.get("levels", 1)),
		"floor_height": snappedf(float(building.get("floor_height", 3.05)), 0.01),
		"height": snappedf(float(building.get("height", 6.0)), 0.01),
		"footprint": _local_polygon(building.get("footprint", PackedVector2Array()), origin),
		"frame": {
			"origin": _local_point(frame_origin, origin),
			"dir": [snappedf(u.x, 0.0001), snappedf(-u.y, 0.0001)],
			"normal": [snappedf(n.x, 0.0001), snappedf(-n.y, 0.0001)],
			"width": snappedf(size.x, 0.01),
			"depth": snappedf(size.y, 0.01),
		},
		"lot": {
			"origin": _local_point(building.get("lot_corner", center), origin),
			"dir": [snappedf(u.x, 0.0001), snappedf(-u.y, 0.0001)],
			"normal": [snappedf(n.x, 0.0001), snappedf(-n.y, 0.0001)],
			"width": snappedf(float(building.get("lot_width", size.x)), 0.01),
		},
		"roof": building.get("roof", {}),
		"palette": building.get("palette", {}),
		"modules": modules_out,
		"wall": wall_out,
		"shopfront": building.get("shopfront", {}),
		"door": _local_point(building.get("door", center), origin),
		"entrance": _local_point(building.get("entrance", center), origin),
		"landmark_id": str(building.get("landmark_id", "")),
		"landmark_name": str(building.get("landmark_name", "")),
		"confidence": str(building.get("confidence", "")),
		"category": str(building.get("category", "")),
	}


static func _serialize_props(props: Dictionary, origin: Vector2) -> Dictionary:
	var out := {}
	for key in props.keys():
		var entries: Array = props[key]
		var serialized: Array = []
		for raw in entries:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = raw
			if entry.has("a") and entry.has("b"):
				serialized.append({
					"a": _local_point(entry["a"], origin),
					"b": _local_point(entry["b"], origin),
					"width": snappedf(float(entry.get("width", 0.12)), 0.01),
					"dashes": int(entry.get("dashes", 0)),
				})
				continue
			serialized.append({
				"pos": _local_point(entry.get("pos", Vector2.ZERO), origin),
				"rot": _local_angle(float(entry.get("rot", 0.0))),
				"scale": snappedf(float(entry.get("scale", 1.0)), 0.01),
				"angle": _local_angle(float(entry.get("angle", 0.0))),
				"length": snappedf(float(entry.get("length", 0.0)), 0.01),
				"bars": int(entry.get("bars", 0)),
			})
		out[str(key)] = serialized
	return out


static func _serialize_vegetation(vegetation: Dictionary, origin: Vector2) -> Dictionary:
	var out := {}
	for key in ["trees", "bushes", "grass"]:
		var entries: Array = vegetation.get(key, [])
		var serialized: Array = []
		for raw in entries:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = raw
			serialized.append({
				"pos": _local_point(entry.get("pos", Vector2.ZERO), origin),
				"scale": snappedf(float(entry.get("scale", 1.0)), 0.01),
				"rot": _local_angle(float(entry.get("rot", 0.0))),
				"species": int(entry.get("species", 0)),
			})
		out[key] = serialized
	return out


## Compatibilidade: até a Etapa 2, vegetação era `trees: [[x, y, escala], ...]`.
## Mantém-se o formato, agora preenchido pela camada urbana, para que minimapa,
## ferramentas e qualquer leitor antigo continuem funcionando.
static func _legacy_trees(vegetation: Dictionary, origin: Vector2) -> Array:
	var out: Array = []
	for raw in vegetation.get("trees", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var local := _local_point(entry.get("pos", Vector2.ZERO), origin)
		out.append([local[0], local[1], snappedf(float(entry.get("scale", 1.0)), 0.01)])
	return out


## Resumo do que foi gerado, para HUD, ferramentas de depuração e relatório.
static func stats(payload: Dictionary) -> Dictionary:
	return payload.get("urban_stats", {})
