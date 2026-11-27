class_name LandmarkRegistry
extends RefCounted

## Pontos de referência individuais — o que diferencia um lugar de outro.
##
## O sistema é **dado, não código**: novos locais entram acrescentando um JSON em
## `data/geographic/landmarks/`, sem tocar no gerador urbano, na malha nem nos
## testes. Cada ponto traz os campos que a honestidade exige:
##
##   confidence   alta / media / baixa — quão confiável é a posição
##   sources      de onde veio a informação
##   honesty      uma frase dizendo o que aquele dado é e o que não é
##
## Nenhum ponto de referência é declarado "reproduzido fielmente": o que a massa
## descreve é um volume (largura, profundidade, altura, giro), não uma fachada.
## Quem desenha o modelo final é a próxima etapa; aqui o edifício genérico que
## ocupa o lugar é marcado com `landmark_id` e `confidence`, e o inspetor mostra
## os dois.
##
## Acesso de duas threads ao mesmo tempo (a geração de payload roda nas workers do
## streaming), por isso o carregamento é protegido por cadeado e acontece uma vez.

const DATA_DIR := "res://data/geographic/landmarks"

static var _loaded: bool = false
static var _lock := Mutex.new()
static var _datasets: Array = []
static var _landmarks: Array = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	_lock.lock()
	if _loaded:
		_lock.unlock()
		return
	_loaded = true
	_datasets.clear()
	_landmarks.clear()
	var files := _json_files(DATA_DIR)
	for path in files:
		var dataset := _load_dataset(path)
		if dataset.is_empty():
			continue
		_datasets.append(dataset)
		for raw in dataset.get("landmarks", []):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var entry := _normalise(raw, dataset)
			if not entry.is_empty():
				_landmarks.append(entry)
	_lock.unlock()


static func reload() -> void:
	_lock.lock()
	_loaded = false
	_datasets.clear()
	_landmarks.clear()
	_lock.unlock()
	ensure_loaded()


static func count() -> int:
	ensure_loaded()
	return _landmarks.size()


static func all() -> Array:
	ensure_loaded()
	return _landmarks


## Pontos de referência cujo raio de influência alcança o retângulo.
static func for_rect(rect: Rect2) -> Array:
	ensure_loaded()
	var out: Array = []
	for entry in _landmarks:
		if str(entry.get("role", "")) == UrbanSchema.ROLE_BARRIER:
			continue
		var point: Vector2 = entry["point"]
		var radius := float(entry.get("radius_m", 20.0))
		if rect.grow(radius).has_point(point):
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("radius_m", 0.0)) > float(b.get("radius_m", 0.0)))
	return out


## Barreiras (rio, ferrovia, faixa non aedificandi) que cruzam o retângulo.
static func barriers_for_rect(rect: Rect2) -> Array:
	ensure_loaded()
	var out: Array = []
	for entry in _landmarks:
		if str(entry.get("role", "")) != UrbanSchema.ROLE_BARRIER:
			continue
		var polyline: PackedVector2Array = entry.get("polyline", PackedVector2Array())
		if polyline.size() < 2:
			continue
		var bounds := Rect2(polyline[0], Vector2.ZERO)
		for point in polyline:
			bounds = bounds.expand(point)
		if bounds.grow(float(entry.get("width_m", 4.0))).intersects(rect):
			out.append(entry)
	return out


## Áreas em que não se constrói: barreira mais o afastamento declarado.
static func protected_polygons(rect: Rect2, buffer: float) -> Array:
	ensure_loaded()
	var out: Array = []
	for entry in _landmarks:
		var role := str(entry.get("role", ""))
		var polyline: PackedVector2Array = entry.get("polyline", PackedVector2Array())
		if role != UrbanSchema.ROLE_BARRIER or polyline.size() < 2:
			continue
		var width := float(entry.get("width_m", 4.0)) * 0.5 + buffer + float(entry.get("protected_buffer_m", 0.0))
		for i in range(polyline.size() - 1):
			var a := polyline[i]
			var b := polyline[i + 1]
			var direction := (b - a).normalized()
			var normal := Vector2(-direction.y, direction.x) * width
			var strip := PackedVector2Array([a + normal, b + normal, b - normal, a - normal])
			if not PolygonUtils.bounds(strip).intersects(rect):
				continue
			out.append({"id": str(entry.get("id", "")), "poly": strip})
	return out


## Áreas abertas (praça, largo) — recebem vegetação e mobiliário, não prédio.
static func open_spaces_for_rect(rect: Rect2) -> Array:
	ensure_loaded()
	var out: Array = []
	for entry in _landmarks:
		if str(entry.get("role", "")) != UrbanSchema.ROLE_OPEN_SPACE:
			continue
		var point: Vector2 = entry.get("point", Vector2.ZERO)
		var radius := float(entry.get("radius_m", 24.0))
		if not rect.grow(radius).has_point(point):
			continue
		var out_poly := PackedVector2Array()
		var segments := 20
		for i in range(segments):
			var angle := TAU * float(i) / float(segments)
			out_poly.append(point + Vector2(cos(angle), sin(angle)) * radius)
		out.append({
			"id": str(entry.get("id", "")),
			"name": str(entry.get("name", "")),
			"poly": out_poly,
			"point": point,
			"radius_m": radius,
			"confidence": str(entry.get("confidence", UrbanSchema.CONFIDENCE_LOW)),
		})
	return out


## Texto de atribuição/licença de todos os conjuntos carregados. Vai para o
## relatório e para o comando `--attribution` das ferramentas: dado geográfico
## sem atribuição não pode ser distribuído.
static func attribution_text() -> String:
	ensure_loaded()
	if _datasets.is_empty():
		return "nenhum conjunto de pontos de referência carregado"
	var lines: Array[String] = []
	for dataset in _datasets:
		var provenance: Dictionary = dataset.get("provenance", {})
		lines.append("%s — fonte: %s · licença: %s · confiança: %s" % [
			str(dataset.get("id", "?")),
			str(provenance.get("source", "?")),
			str(provenance.get("license", "?")),
			str(provenance.get("confidence", UrbanSchema.CONFIDENCE_LOW)),
		])
		var note := str(provenance.get("note", ""))
		if not note.is_empty():
			lines.append("  %s" % note)
	return "\n".join(lines)


static func datasets() -> Array:
	ensure_loaded()
	return _datasets


# --- carregamento ------------------------------------------------------------


static func _json_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			out.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func _load_dataset(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LandmarkRegistry: não foi possível abrir %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("LandmarkRegistry: JSON inválido em %s" % path)
		return {}
	var dataset: Dictionary = parsed
	dataset["path"] = path
	return dataset


static func _normalise(raw: Dictionary, dataset: Dictionary) -> Dictionary:
	var entry := raw.duplicate(true)
	var anchor := _anchor_metric(dataset)
	if entry.has("meters"):
		var meters: Array = entry["meters"]
		if meters.size() < 2:
			return {}
		entry["point"] = anchor + Vector2(float(meters[0]), float(meters[1]))
	if entry.has("polyline_m"):
		var polyline := PackedVector2Array()
		for pair in entry["polyline_m"]:
			if typeof(pair) != TYPE_ARRAY or (pair as Array).size() < 2:
				continue
			polyline.append(anchor + Vector2(float(pair[0]), float(pair[1])))
		entry["polyline"] = polyline
	if entry.has("lat") and entry.has("lon"):
		entry["point"] = GeoCoordinateSystem.geographic_to_metric(float(entry["lat"]), float(entry["lon"]))
	if not entry.has("point") and not entry.has("polyline"):
		return {}
	entry["dataset"] = str(dataset.get("id", ""))
	if not entry.has("role"):
		entry["role"] = UrbanSchema.ROLE_LANDMARK
	if not entry.has("confidence"):
		entry["confidence"] = UrbanSchema.CONFIDENCE_LOW
	if not entry.has("radius_m"):
		entry["radius_m"] = 18.0
	var provenance: Dictionary = dataset.get("provenance", {})
	entry["license"] = str(entry.get("license", provenance.get("license", "?")))
	entry["source"] = str(entry.get("source", provenance.get("source", "?")))
	return entry


static func _anchor_metric(dataset: Dictionary) -> Vector2:
	var anchor: Dictionary = dataset.get("anchor", {})
	var code := str(anchor.get("municipality", "GUAPI"))
	var offset: Array = anchor.get("offset_m", [0.0, 0.0])
	var base := MunicipalityIndex.center_of(code)
	if offset.size() >= 2:
		base += Vector2(float(offset[0]), float(offset[1]))
	return base
