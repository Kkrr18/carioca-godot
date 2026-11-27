extends SceneTree

## Importa um extrato .osm para dados de setor do CARIOCA.
##
##   godot --headless --script res://tools/map_importer/import_osm.gd -- \
##       --input=data/geographic/osm/guapimirim.osm \
##       --bbox=-22.75,-43.15,-22.45,-42.85
##
## Sem --bbox, usa os limites do estado. O resultado vai para
## data/geographic/sectors/<REGIÃO>/<MUNICÍPIO>/<gx>_<gy>.json e passa a ter
## prioridade sobre o gerador procedural naquele setor — importado vence.
##
## Escrever em res:// funciona rodando do editor ou da linha de comando com o
## projeto aberto, que é o caso de uso desta ferramenta.

const DATA_ROOT := "res://data/geographic/sectors"


func _initialize() -> void:
	var input := ""
	var bbox_text := ""
	var dry_run := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--input="):
			input = argument.substr(8)
		elif argument.begins_with("--bbox="):
			bbox_text = argument.substr(7)
		elif argument == "--dry-run":
			dry_run = true

	if input.is_empty():
		print("uso: godot --headless --script res://tools/map_importer/import_osm.gd -- --input=arquivo.osm [--bbox=minLat,minLon,maxLat,maxLon] [--dry-run]")
		quit(1)
		return

	MunicipalityIndex.ensure_loaded()
	var bounds := _bounds_from(bbox_text)
	print("Lendo %s ..." % input)
	var parsed: Dictionary = OsmParser.parse_file(input, bounds)
	var features: Array = parsed.get("features", [])
	print("  nós: %d   vias: %d   feições úteis: %d" % [
		int(parsed.get("node_count", 0)),
		int(parsed.get("way_count", 0)),
		features.size(),
	])
	for warning in parsed.get("warnings", []):
		print("  aviso: %s" % warning)

	var sectors: Dictionary = _bucket(features)
	print("  setores gerados: %d" % sectors.size())
	if dry_run:
		_report(sectors)
		quit(0)
		return

	var written := 0
	for coord in sectors.keys():
		var payload: Dictionary = sectors[coord]
		if SectorRepository.save_payload(coord, payload):
			written += 1
	print("  setores gravados: %d (primeiro em %s)" % [written, DATA_ROOT])
	quit(0 if written == sectors.size() else 1)


func _bounds_from(text: String) -> Rect2:
	if text.is_empty():
		var state := MunicipalityIndex.state_bounds()
		return Rect2(
			Vector2(float(state["min_lon"]), float(state["min_lat"])),
			Vector2(float(state["max_lon"]) - float(state["min_lon"]), float(state["max_lat"]) - float(state["min_lat"]))
		)
	var parts := text.split(",")
	if parts.size() != 4:
		push_warning("bbox inválida, usando limites do estado")
		return _bounds_from("")
	var min_lat := float(parts[0])
	var min_lon := float(parts[1])
	var max_lat := float(parts[2])
	var max_lon := float(parts[3])
	return Rect2(Vector2(min_lon, min_lat), Vector2(max_lon - min_lon, max_lat - min_lat))


## Distribui as feições em setores. Vias vão para o setor do meio de cada
## segmento (a via continua no setor vizinho como outro segmento), edificações e
## água vão para o setor do centroide.
func _bucket(features: Array) -> Dictionary:
	var sectors: Dictionary = {}
	for feature in features:
		if typeof(feature) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = feature
		var points: PackedVector2Array = entry.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		var kind := str(entry.get("kind", ""))
		if kind == "road":
			for i in range(points.size() - 1):
				var a := GeoCoordinateSystem.geographic_to_metric(points[i].x, points[i].y)
				var b := GeoCoordinateSystem.geographic_to_metric(points[i + 1].x, points[i + 1].y)
				var coord := SectorGrid.sector_of((a + b) * 0.5)
				var origin := SectorGrid.sector_origin(coord)
				var payload := _payload_for(sectors, coord)
				var local_a := _to_local(a, origin)
				var local_b := _to_local(b, origin)
				(payload["roads"] as Array).append({
					"id": "osm_%s_%d" % [str(entry.get("id", "w")), i],
					"class": str(entry.get("road_class", WorldSchema.ROAD_LOCAL)),
					"width": float(entry.get("width", 6.0)),
					"lattice": "osm",
					"nodes": [_node_key(a), _node_key(b)],
					"points": [[local_a.x, local_a.y], [local_b.x, local_b.y]],
					"name": str(entry.get("name", "")),
				})
			continue

		var centroid := _centroid_metric(points)
		var coord := SectorGrid.sector_of(centroid)
		var origin := SectorGrid.sector_origin(coord)
		var payload := _payload_for(sectors, coord)
		var polygon: Array = []
		for point in points:
			var metric := GeoCoordinateSystem.geographic_to_metric(point.x, point.y)
			var local := _to_local(metric, origin)
			polygon.append([local.x, local.y])

		if kind == "building":
			(payload["buildings"] as Array).append(_building_entry(entry, polygon, sector_name_slug(coord)))
		elif kind == "water":
			(payload["water"] as Array).append({
				"id": "water_%d" % payload["water"].size(),
				"poly": polygon,
				"name": str(entry.get("name", "")),
			})
	return sectors


func _payload_for(sectors: Dictionary, coord: Vector2i) -> Dictionary:
	if sectors.has(coord):
		return sectors[coord]
	var origin := SectorGrid.sector_origin(coord)
	var payload := {
		"version": WorldSchema.SECTOR_SCHEMA_VERSION,
		"grid": [coord.x, coord.y],
		"origin": [origin.x, origin.y],
		"id": MunicipalityIndex.id_for(coord),
		"source": "osm",
		"density": MunicipalityIndex.density_at(SectorGrid.sector_center(coord)),
		"urban": true,
		"roads": [],
		"buildings": [],
		"water": [],
		"trees": [],
		"props": [],
	}
	sectors[coord] = payload
	return payload


func _building_entry(entry: Dictionary, polygon: Array, slug: String) -> Dictionary:
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for point in polygon:
		min_x = minf(min_x, float(point[0]))
		max_x = maxf(max_x, float(point[0]))
		min_y = minf(min_y, float(point[1]))
		max_y = maxf(max_y, float(point[1]))
	var size_x := maxf(max_x - min_x, 1.0)
	var size_y := maxf(max_y - min_y, 1.0)
	var center := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	var levels := maxi(int(entry.get("levels", 2)), 1)
	var height := maxf(float(entry.get("height", float(levels) * 3.15)), 2.5)
	var kind := "residential"
	if str(entry.get("building", "")) in ["commercial", "retail", "office", "industrial"]:
		kind = "commercial"
	elif str(entry.get("building", "")) in ["school", "hospital", "public", "civic"]:
		kind = "public"
	return {
		"id": "%s_%d" % [slug, int(Deterministic.hash2(int(center.x), int(center.y), 17))],
		"center": [center.x, center.y],
		"size": [size_x, size_y],
		"angle": 0.0,
		"levels": levels,
		"height": height,
		"kind": kind,
		"poly": polygon,
		"door": [center.x, center.y + size_y * 0.5],
	}


func sector_name_slug(coord: Vector2i) -> String:
	var municipality := MunicipalityIndex.nearest(SectorGrid.sector_center(coord))
	return "%s_%d_%d" % [str(municipality.get("code", "RJ")), coord.x, coord.y]


func _node_key(metric: Vector2) -> String:
	return "p:%.2f:%.2f" % [metric.x, metric.y]


func _to_local(metric: Vector2, origin: Vector2) -> Vector2:
	var delta := metric - origin
	return Vector2(delta.x, -delta.y)


func _centroid_metric(points: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in points:
		sum += GeoCoordinateSystem.geographic_to_metric(point.x, point.y)
	return sum / float(maxi(points.size(), 1))


func _report(sectors: Dictionary) -> void:
	var roads := 0
	var buildings := 0
	for coord in sectors.keys():
		var payload: Dictionary = sectors[coord]
		roads += (payload["roads"] as Array).size()
		buildings += (payload["buildings"] as Array).size()
	print("  simulação: %d vias, %d edificações em %d setores" % [roads, buildings, sectors.size()])
