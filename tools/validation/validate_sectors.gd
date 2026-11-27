extends SceneTree

## Valida todos os setores gravados em disco.
##
##   godot --headless --script res://tools/validation/validate_sectors.gd
##
## Checa o que já quebrou em projetos assim antes: schema errado, coordenadas
## não finitas, geometria fora do setor, altura absurda, payload sem origem.
## Sai com código 1 quando encontra erro — é o que a integração contínua usa.

const DATA_ROOT := "res://data/geographic/sectors"
const LOCAL_LIMIT := 900.0


func _initialize() -> void:
	var files: Array[String] = []
	_collect(DATA_ROOT, files)
	if files.is_empty():
		print("nenhum setor gravado em %s (o mundo roda por procedimento)" % DATA_ROOT)
		quit(0)
		return
	print("Validando %d setores..." % files.size())
	var errors := 0
	var warnings := 0
	for path in files:
		var report := _validate(path)
		errors += int(report["errors"])
		warnings += int(report["warnings"])
		for message in report["messages"]:
			print("  %s" % message)
	print("Resultado: %d erros, %d avisos em %d arquivos" % [errors, warnings, files.size()])
	quit(0 if errors == 0 else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.ends_with(".json"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _validate(path: String) -> Dictionary:
	var messages: Array[String] = []
	var errors := 0
	var warnings := 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"errors": 1, "warnings": 0, "messages": ["%s: não abre" % path]}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"errors": 1, "warnings": 0, "messages": ["%s: JSON inválido" % path]}
	var payload: Dictionary = parsed

	if int(payload.get("version", 0)) != WorldSchema.SECTOR_SCHEMA_VERSION:
		messages.append("%s: versão %s (esperado %d)" % [path.get_file(), str(payload.get("version")), WorldSchema.SECTOR_SCHEMA_VERSION])
		errors += 1

	var grid: Array = payload.get("grid", [])
	if grid.size() != 2:
		messages.append("%s: campo grid ausente" % path.get_file())
		errors += 1

	var origin: Array = payload.get("origin", [])
	if origin.size() != 2:
		messages.append("%s: campo origin ausente" % path.get_file())
		errors += 1

	for collection in ["roads", "buildings"]:
		var items: Array = payload.get(collection, [])
		for item in items:
			if typeof(item) != TYPE_DICTIONARY:
				errors += 1
				messages.append("%s: %s com item inválido" % [path.get_file(), collection])
				continue
			var entry: Dictionary = item
			if collection == "roads":
				var points: Array = entry.get("points", [])
				if points.size() < 2:
					errors += 1
					messages.append("%s: via com menos de 2 pontos" % path.get_file())
					continue
				for point in points:
					if not _finite_point(point):
						errors += 1
						messages.append("%s: via com coordenada inválida" % path.get_file())
						break
					var local := Vector2(float(point[0]), float(point[1]))
					if absf(local.x) > LOCAL_LIMIT or absf(local.y) > LOCAL_LIMIT:
						errors += 1
						messages.append("%s: via fora do setor (%.1f, %.1f)" % [path.get_file(), local.x, local.y])
						break
			else:
				var height := float(entry.get("height", 0.0))
				if height <= 0.0 or height > 400.0:
					errors += 1
					messages.append("%s: altura implausível (%.1f m)" % [path.get_file(), height])
				var size_value = entry.get("size", [])
				if typeof(size_value) == TYPE_ARRAY and (size_value as Array).size() >= 1:
					if float((size_value as Array)[0]) <= 0.0:
						errors += 1
						messages.append("%s: edificação sem testada" % path.get_file())

	var warnings_before := warnings
	if (payload.get("buildings", []) as Array).is_empty() and str(payload.get("source", "")) == "osm":
		warnings += 1
		if warnings > warnings_before:
			messages.append("%s: setor importado sem edificações" % path.get_file())

	return {"errors": errors, "warnings": warnings, "messages": messages}


func _finite_point(point: Variant) -> bool:
	if typeof(point) != TYPE_ARRAY:
		return false
	var array: Array = point
	if array.size() < 2:
		return false
	return is_finite(float(array[0])) and is_finite(float(array[1]))
