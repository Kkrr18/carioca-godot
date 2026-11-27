extends SceneTree

## Inspetor da camada urbana.
##
##   godot --headless --path . --script res://tools/urban_tools/urban_inspector.gd -- \
##       --center=GUAPI --radius=1 [--json=relatorio.json] [--quiet]
##
## Gera os setores da área e responde às perguntas que quebram uma cidade
## procedural, uma por uma:
##
##   - há quadra sem lote, ou lote fora da quadra?
##   - há dois lotes ocupando o mesmo chão?
##   - há prédio fora do próprio lote, ou em cima do asfalto?
##   - há identificador repetido (o duplicado que o streaming produziria)?
##   - há construção incompatível com o relevo (encosta íngreme)?
##   - qual fonte de rua foi usada, e com que licença?
##
## Sai com código 1 quando encontra erro — serve para integração contínua, como
## o `validate_sectors.gd` da Etapa 2.

const MAX_REPORTED := 12
const STEEP_DEGREES := 22.0

var _problems: Array[String] = []
var _warnings: Array[String] = []


func _initialize() -> void:
	var center_code := "GUAPI"
	var radius := 1
	var json_path := ""
	var quiet := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--center="):
			center_code = argument.substr(9)
		elif argument.begins_with("--radius="):
			radius = int(argument.substr(9))
		elif argument.begins_with("--json="):
			json_path = argument.substr(7)
		elif argument == "--quiet":
			quiet = true

	MunicipalityIndex.ensure_loaded()
	UrbanConfig.set_active_from_preset(QualityProfile.get_preset("pc_medium"))
	var center := MunicipalityIndex.center_of(center_code)
	if center == Vector2.ZERO:
		print("município desconhecido: %s" % center_code)
		quit(1)
		return
	var coord := SectorGrid.sector_of(center)
	var coords := SectorGrid.sectors_in_radius(coord, maxi(radius, 0))

	print("")
	print("=== CARIOCA — inspetor urbano ===")
	print("centro: %s (%s)   setores: %d" % [
		center_code,
		GeoCoordinateSystem.format_lat_lon(
			GeoCoordinateSystem.metric_to_geographic(center).x,
			GeoCoordinateSystem.metric_to_geographic(center).y),
		coords.size(),
	])
	print("")

	var terrain := TerrainService.new(20170)
	var totals := {
		"blocks": 0,
		"parcels": 0,
		"buildings": 0,
		"trees": 0,
		"props": 0,
	}
	var seen_ids := {}
	var sources := {}
	var landmarks := {}
	var report: Array = []

	for target in coords:
		var payload := UrbanGenerator.build_payload(target, 20170)
		var origin := SectorGrid.sector_origin(target)
		var entry := {
			"grid": SectorGrid.key(target),
			"id": str(payload.get("id", "")),
			"urban": bool(payload.get("urban_v3", false)),
			"source": str(payload.get("urban_source", payload.get("source", ""))),
			"blocks": (payload.get("blocks", []) as Array).size(),
			"parcels": (payload.get("parcels", []) as Array).size(),
			"buildings": (payload.get("buildings", []) as Array).size(),
		}
		sources[entry["source"]] = int(sources.get(entry["source"], 0)) + 1
		totals["blocks"] += int(entry["blocks"])
		totals["parcels"] += int(entry["parcels"])
		totals["buildings"] += int(entry["buildings"])
		totals["trees"] += (payload.get("vegetation", {}).get("trees", []) as Array).size()
		for key in (payload.get("street_objects", {}) as Dictionary).keys():
			totals["props"] += ((payload.get("street_objects", {}) as Dictionary)[key] as Array).size()
		for landmark in payload.get("landmarks", []):
			if typeof(landmark) != TYPE_DICTIONARY:
				continue
			landmarks[str((landmark as Dictionary).get("id", ""))] = str((landmark as Dictionary).get("confidence", ""))
		_inspect_sector(payload, origin, terrain, seen_ids, entry)
		report.append(entry)

	print("setores urbanos: %d/%d   quadras %d   lotes %d   prédios %d   árvores %d   mobiliário %d" % [
		_count_urban(report), coords.size(),
		totals["blocks"], totals["parcels"], totals["buildings"], totals["trees"], totals["props"],
	])
	var source_parts := PackedStringArray()
	for key in sources.keys():
		source_parts.append("%s (%d)" % [str(key), int(sources[key])])
	print("fontes de rua: %s" % ", ".join(source_parts))
	print("pontos de referência no recorte: %d" % landmarks.size())
	for id in landmarks.keys():
		print("  %s — confiança %s" % [str(id), str(landmarks[id])])

	print("")
	print("atribuição:")
	for line in StreetFramework.attribution_text().split("\n"):
		print("  %s" % line)
	for line in LandmarkRegistry.attribution_text().split("\n"):
		print("  %s" % line)

	_report(_problems, "ERRO")
	_report(_warnings, "AVISO")
	print("")
	print("Resultado: %d erros, %d avisos" % [_problems.size(), _warnings.size()])

	if not json_path.is_empty():
		var file := FileAccess.open(json_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({
				"center": center_code,
				"radius": radius,
				"sectors": report,
				"totals": totals,
				"sources": sources,
				"problems": _problems,
				"warnings": _warnings,
			}, "  "))
			file.close()
			if not quiet:
				print("relatório gravado em %s" % json_path)

	quit(0 if _problems.is_empty() else 1)


func _count_urban(report: Array) -> int:
	var total := 0
	for entry in report:
		if bool((entry as Dictionary)["urban"]):
			total += 1
	return total


func _inspect_sector(payload: Dictionary, origin: Vector2, terrain: TerrainService, seen_ids: Dictionary, entry: Dictionary) -> void:
	var label := str(entry["grid"])
	if not bool(payload.get("urban_v3", false)):
		return

	var parcels := _metric_entries(payload.get("parcels", []), origin)
	var buildings: Array = payload.get("buildings", [])
	var footprints: Array = []

	for raw in buildings:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = raw
		var id := str(building.get("id", ""))
		if seen_ids.has(id):
			_add(_problems, "%s: identificador repetido %s" % [label, id])
		seen_ids[id] = true

		var footprint := PolygonUtils.from_array(building.get("footprint", []))
		if footprint.size() >= 3:
			var metric := PackedVector2Array()
			for point in footprint:
				metric.append(origin + Vector2(point.x, -point.y))
			footprints.append({"id": id, "poly": metric})

		var center: Array = building.get("center", [])
		if center.size() < 2:
			_add(_problems, "%s: edificação sem centro (%s)" % [label, id])
			continue
		var height := float(building.get("height", 0.0))
		if height <= 1.5 or height > 260.0:
			_add(_problems, "%s: altura implausível em %s (%.1f m)" % [label, id, height])

		var centroid := origin + Vector2(float(center[0]), -float(center[1]))
		if footprint.size() >= 3:
			for point in footprints[footprints.size() - 1]["poly"]:
				var clearance := _clearance(payload, point, origin)
				if clearance < 0.0:
					_add(_problems, "%s: edificação %s sobre a pista (%.1f m)" % [label, id, clearance])
					break
			if str(building.get("landmark_id", "")).is_empty():
				if not _inside_any_parcel(centroid, parcels):
					_add(_warnings, "%s: edificação %s sem lote correspondente" % [label, id])
		var slope := _slope_degrees(terrain, footprint, origin)
		if slope > STEEP_DEGREES:
			_add(_warnings, "%s: edificação %s em encosta de %.0f°" % [label, id, slope])

	for i in range(footprints.size()):
		for j in range(i + 1, footprints.size()):
			if PolygonUtils.polygons_overlap(footprints[i]["poly"], footprints[j]["poly"]):
				_add(_problems, "%s: edificações %s e %s se sobrepõem" % [label, str(footprints[i]["id"]), str(footprints[j]["id"])])
	for parcel in parcels:
		if float(parcel["area"]) < 1.0:
			_add(_problems, "%s: lote sem área" % label)


func _metric_entries(entries: Array, origin: Vector2) -> Array:
	var out: Array = []
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var poly := PolygonUtils.from_array(entry.get("poly", []))
		var metric := PackedVector2Array()
		for point in poly:
			metric.append(origin + Vector2(point.x, -point.y))
		out.append({
			"id": str(entry.get("id", "")),
			"poly": metric,
			"area": float(entry.get("area", PolygonUtils.area(metric))),
		})
	return out


func _inside_any_parcel(point: Vector2, parcels: Array) -> bool:
	for parcel in parcels:
		var poly: PackedVector2Array = parcel["poly"]
		if PolygonUtils.bounds(poly).grow(0.5).has_point(point) and PolygonUtils.point_in_polygon(point, poly):
			return true
	return false


func _clearance(payload: Dictionary, point: Vector2, origin: Vector2) -> float:
	# Sem reconstruir a rede: a folga é medida contra as vias do próprio payload.
	var best := INF
	for raw in payload.get("roads", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var road: Dictionary = raw
		var points: Array = road.get("points", [])
		var width := float(road.get("width", 6.0))
		for i in range(points.size() - 1):
			var a: Array = points[i]
			var b: Array = points[i + 1]
			var pa := origin + Vector2(float(a[0]), -float(a[1]))
			var pb := origin + Vector2(float(b[0]), -float(b[1]))
			best = minf(best, PolygonUtils.distance_to_segment(point, pa, pb) - width * 0.5)
	if best == INF:
		return 999.0
	return best


func _slope_degrees(terrain: TerrainService, footprint: PackedVector2Array, origin: Vector2) -> float:
	if footprint.size() < 3:
		return 0.0
	var metric := PackedVector2Array()
	for point in footprint:
		metric.append(origin + Vector2(point.x, -point.y))
	return terrain.slope_degrees(PolygonUtils.centroid(metric))


func _add(list: Array[String], message: String) -> void:
	list.append(message)


func _report(list: Array[String], kind: String) -> void:
	if list.is_empty():
		return
	print("")
	print("%s:" % kind)
	var shown := 0
	for message in list:
		if shown >= MAX_REPORTED:
			print("  … e mais %d" % (list.size() - shown))
			break
		print("  %s" % message)
		shown += 1
