class_name StreetFramework
extends RefCounted

## Camada de ruas de um recorte urbano, vinda de dado empacotado no projeto.
##
## Existe para responder a uma pergunta prática: quando **não** há extrato OSM do
## município, de onde vêm as ruas? A rede procedural da Etapa 1 responde isso com
## uma reticulação determinística — coerente, mas que não corresponde a nenhum
## lugar. Um conjunto em `data/geographic/urban/` responde com um **traçado
## esquemático autoral, georreferenciado** ao centro do município: ruas com
## classes e larguras plausíveis, na orientação certa, cobrindo cerca de 1,8 km.
##
## O que este dado **é**: um esquema de larga escala, derivado de conhecimento
## público do núcleo urbano, para o sistema urbano ter sobre o que trabalhar.
## O que ele **não é**: levantamento, dado cadastral ou extrato do OpenStreetMap.
## Cada conjunto carrega `provenance` dizendo isso, e `attribution_text()` publica
## a origem junto com a licença.
##
## Prioridade das fontes, aplicada pelo `UrbanGenerator`:
##   1. payload de setor gravado (OSM importado) — geometria real;
##   2. este conjunto esquemático;
##   3. reticulação procedural da Etapa 1.

const DATA_DIR := "res://data/geographic/urban"

## Listagem de fallback para o export web. `DirAccess` listando `res://`
## não é confiável no build web — sem a listagem, o traçado esquemático não
## carrega e a cidade nasce sem ruas (defeito encontrado na primeira execução
## real do jogo, na web). Em desktop a listagem continua valendo, porque é
## ela que deixa um conjunto novo entrar sem tocar em código; onde ela falha
## ou não acha nada, a lista conhecida assume, por acesso direto.
const KNOWN_SHEETS: Array[String] = [
	"res://data/geographic/urban/guapimirim_centro.json",
]

## Crescimento aplicado ao retângulo ao decidir se um conjunto cobre o recorte:
## uma via que passa raspando na fronteira ainda interessa.
const EDGE_MARGIN := 60.0

static var _loaded: bool = false
static var _lock := Mutex.new()
static var _sheets: Array = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	_lock.lock()
	if _loaded:
		_lock.unlock()
		return
	_loaded = true
	_sheets.clear()
	for path in _json_files(DATA_DIR):
		var sheet := _load_sheet(path)
		if not sheet.is_empty():
			_sheets.append(sheet)
	_lock.unlock()


static func reload() -> void:
	_lock.lock()
	_loaded = false
	_sheets.clear()
	_lock.unlock()
	ensure_loaded()


## Quantos conjuntos esquemáticos carregaram — número de diagnóstico.
## 0 significa "cidade sem traçado": é o que o HUD mostra para o defeito de
## carregamento de dado ser visível, e não silencioso.
static func sheet_count() -> int:
	ensure_loaded()
	return _sheets.size()


## Conjunto esquemático que cobre o recorte, ou vazio.
static func sheet_for(rect: Rect2) -> Dictionary:
	ensure_loaded()
	for sheet in _sheets:
		var bounds: Rect2 = sheet["bounds"]
		if bounds.grow(EDGE_MARGIN).intersects(rect):
			return sheet
	return {}


static func covers(rect: Rect2) -> bool:
	return not sheet_for(rect).is_empty()


## Ruas que cruzam o recorte, já em espaço métrico global.
## Formato: [{ "a": Vector2, "b": Vector2, "width": float, "road_class": String, "id": String, "name": String }]
static func roads_for_rect(rect: Rect2) -> Array:
	var out: Array = []
	var sheet := sheet_for(rect)
	if sheet.is_empty():
		return out
	var grow := rect.grow(EDGE_MARGIN)
	var anchor: Vector2 = sheet["anchor"]
	for raw in sheet.get("streets", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var street: Dictionary = raw
		var points := _to_metric(street.get("meters", []), anchor)
		if points.size() < 2:
			continue
		var width := float(street.get("width", WorldSchema.width_for(str(street.get("class", WorldSchema.ROAD_LOCAL)))))
		var road_class := str(street.get("class", WorldSchema.ROAD_LOCAL))
		var street_id := str(street.get("id", "street"))
		var name := str(street.get("name", ""))
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			if not _segment_touches(a, b, grow):
				continue
			out.append({
				"a": a,
				"b": b,
				"width": width,
				"road_class": road_class,
				"id": "%s|%d" % [street_id, i],
				"name": name,
			})
	return out


## Barreiras do conjunto (rio, ferrovia) que cruzam o recorte.
static func barriers_for_rect(rect: Rect2) -> Array:
	var sheet := sheet_for(rect)
	if sheet.is_empty():
		return []
	var anchor: Vector2 = sheet["anchor"]
	var out: Array = []
	for raw in sheet.get("barriers", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var barrier: Dictionary = raw
		var points := _to_metric(barrier.get("meters", []), anchor)
		if points.size() < 2:
			continue
		out.append({
			"id": str(barrier.get("id", "barrier")),
			"name": str(barrier.get("name", "")),
			"kind": str(barrier.get("kind", "water")),
			"width_m": float(barrier.get("width_m", 4.0)),
			"protected_buffer_m": float(barrier.get("protected_buffer_m", 0.0)),
			"polyline": points,
		})
	return out


## Bloco de proveniência do conjunto que cobre o recorte — vai para o payload do
## setor para que a origem viaje junto com a geometria.
static func provenance_for(rect: Rect2) -> Dictionary:
	var sheet := sheet_for(rect)
	if sheet.is_empty():
		return {}
	var provenance: Dictionary = sheet.get("provenance", {}).duplicate(true)
	provenance["dataset"] = str(sheet.get("id", ""))
	return provenance


static func attribution_text() -> String:
	ensure_loaded()
	if _sheets.is_empty():
		return "nenhum traçado esquemático carregado"
	var lines: Array[String] = []
	for sheet in _sheets:
		var provenance: Dictionary = sheet.get("provenance", {})
		lines.append("%s — fonte: %s · licença: %s · confiança: %s" % [
			str(sheet.get("id", "?")),
			str(provenance.get("source", "?")),
			str(provenance.get("license", "?")),
			str(provenance.get("confidence", UrbanSchema.CONFIDENCE_LOW)),
		])
		var note := str(provenance.get("note", ""))
		if not note.is_empty():
			lines.append("  %s" % note)
	return "\n".join(lines)


# --- interno -----------------------------------------------------------------


static func _json_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.ends_with(".json"):
				out.append(dir_path.path_join(entry))
			entry = dir.get_next()
		dir.list_dir_end()
		out.sort()
	if out.is_empty():
		# Listagem indisponível (build web) ou pasta vazia: tenta os arquivos
		# conhecidos por acesso direto, que funciona em qualquer plataforma.
		for known in KNOWN_SHEETS:
			if FileAccess.file_exists(known):
				out.append(known)
	return out


static func _load_sheet(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("StreetFramework: não foi possível abrir %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("StreetFramework: JSON inválido em %s" % path)
		return {}
	var sheet: Dictionary = parsed
	var anchor_data: Dictionary = sheet.get("anchor", {})
	var anchor := MunicipalityIndex.center_of(str(anchor_data.get("municipality", "GUAPI")))
	var offset: Array = anchor_data.get("offset_m", [0.0, 0.0])
	if offset.size() >= 2:
		anchor += Vector2(float(offset[0]), float(offset[1]))
	sheet["anchor"] = anchor
	sheet["bounds"] = _bounds_of(sheet, anchor)
	sheet["path"] = path
	return sheet


static func _bounds_of(sheet: Dictionary, anchor: Vector2) -> Rect2:
	var bounds := Rect2()
	var first := true
	for key in ["streets", "barriers"]:
		for raw in sheet.get(key, []):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var points := _to_metric((raw as Dictionary).get("meters", []), anchor)
			for point in points:
				if first:
					bounds = Rect2(point, Vector2.ZERO)
					first = false
				else:
					bounds = bounds.expand(point)
	return bounds


static func _to_metric(raw: Variant, anchor: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if typeof(raw) != TYPE_ARRAY:
		return out
	for pair in raw:
		if typeof(pair) != TYPE_ARRAY:
			continue
		var values: Array = pair
		if values.size() < 2:
			continue
		out.append(anchor + Vector2(float(values[0]), float(values[1])))
	return out


static func _segment_touches(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	if not PolygonUtils.bounds(PackedVector2Array([a, b])).intersects(rect):
		return false
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for i in range(4):
		var c: Vector2 = corners[i]
		var d: Vector2 = corners[(i + 1) % 4]
		if bool(PolygonUtils.segment_intersection(a, b, c, d).get("hit", false)):
			return true
	return false
