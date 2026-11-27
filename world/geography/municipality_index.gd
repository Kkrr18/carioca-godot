class_name MunicipalityIndex
extends RefCounted

## Índice geográfico do estado: municípios, regiões e densidade urbana.
##
## Os centros são aproximados (usados para rótulo de setor e para a função de
## densidade que decide onde há cidade). A malha oficial do IBGE entra na etapa
## de importação: quando ela chegar, `nearest()` passa a fazer ponto-em-polígono
## e o resto do projeto não muda, porque ninguém consulta coordenadas por conta
## própria.

const DATA_PATH := "res://data/geographic/municipalities.json"
const DENSITY_CACHE_LIMIT := 8192
const DENSITY_QUANTUM := 64.0

static var _loaded: bool = false
static var _entries: Array = []
static var _state: Dictionary = {}
static var _regions: Array = []
static var _density_cache: Dictionary = {}
## O streaming gera payloads em duas worker threads ao mesmo tempo. `_entries` é
## lido (nunca escrito) nelas; `_density_cache` é escrito, e Dictionary não é
## thread-safe — daí o cadeado. Sem ele, dois setores carregados no mesmo frame
## podem corromper a tabela e derrubar o processo.
static var _density_lock := Mutex.new()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_density_cache.clear()
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("MunicipalityIndex: dados ausentes em %s" % DATA_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MunicipalityIndex: JSON inválido em %s" % DATA_PATH)
		return
	var data: Dictionary = parsed
	_state = data.get("state", {})
	_regions = data.get("regions", [])
	_entries.clear()
	for raw in data.get("municipalities", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = raw
		var center: Array = m.get("center", [0.0, 0.0])
		if center.size() < 2:
			continue
		var lat := float(center[0])
		var lon := float(center[1])
		_entries.append({
			"code": str(m.get("code", "UNK")),
			"name": str(m.get("name", "?")),
			"region": str(m.get("region", "UNK")),
			"lat": lat,
			"lon": lon,
			"metric": CariocaProjection.forward(lat, lon),
			"urban_radius_m": float(m.get("urban_radius_m", 600.0)),
			"phase": int(m.get("phase", 0)),
		})


static func reload() -> void:
	_loaded = false
	_entries.clear()
	_regions.clear()
	_state = {}
	_density_cache.clear()
	ensure_loaded()


static func state() -> Dictionary:
	ensure_loaded()
	return _state


static func regions() -> Array:
	ensure_loaded()
	return _regions


static func count() -> int:
	ensure_loaded()
	return _entries.size()


static func all_municipalities() -> Array:
	ensure_loaded()
	return _entries


static func by_code(code: String) -> Dictionary:
	ensure_loaded()
	for m in _entries:
		if m["code"] == code:
			return m
	return {}


static func center_of(code: String) -> Vector2:
	var m := by_code(code)
	if m.is_empty():
		return CariocaProjection.forward(-22.537, -42.982)
	return m["metric"]


static func center_latlon_of(code: String) -> Vector2:
	var m := by_code(code)
	if m.is_empty():
		return Vector2(-22.537, -42.982)
	return Vector2(m["lat"], m["lon"])


## Município mais próximo de um ponto no espaço métrico.
static func nearest(metric: Vector2) -> Dictionary:
	ensure_loaded()
	if _entries.is_empty():
		return {}
	var best: Dictionary = _entries[0]
	var best_d := metric.distance_squared_to(best["metric"])
	for i in range(1, _entries.size()):
		var candidate: Dictionary = _entries[i]
		var d := metric.distance_squared_to(candidate["metric"])
		if d < best_d:
			best_d = d
			best = candidate
	var result := best.duplicate()
	result["distance_m"] = sqrt(best_d)
	return result


## Densidade urbana em [0,1]: 1 no núcleo da cidade, caindo até 0 no campo.
## É o que decide onde nascem ruas asfaltadas, prédios e onde o terreno fica
## praticamente natural.
static func density_at(metric: Vector2) -> float:
	ensure_loaded()
	if _entries.is_empty():
		return 0.35
	var cache_key := Vector2i(
		floori(metric.x / DENSITY_QUANTUM),
		floori(metric.y / DENSITY_QUANTUM)
	)
	_density_lock.lock()
	var cached: Variant = _density_cache.get(cache_key)
	_density_lock.unlock()
	if cached != null:
		return float(cached)
	var m := nearest(metric)
	var d := float(m.get("distance_m", 999999.0))
	var radius := float(m.get("urban_radius_m", 600.0))
	var value := 0.0
	if d <= radius:
		value = 1.0
	else:
		value = clampf(1.0 - (d - radius) / (radius * 2.5), 0.0, 1.0)
		value *= 0.85
	_density_lock.lock()
	if _density_cache.size() > DENSITY_CACHE_LIMIT:
		_density_cache.clear()
	_density_cache[cache_key] = value
	_density_lock.unlock()
	return value


## Identificador legível de setor, no formato pedido pelo plano:
##   RJ_METRO_GUAPI_0390_15433
static func id_for(coord: Vector2i) -> String:
	ensure_loaded()
	var m := nearest(SectorGrid.sector_center(coord))
	if m.is_empty():
		return "RJ_UNK_UNK_%d_%d" % [coord.x, coord.y]
	return "RJ_%s_%s_%04d_%05d" % [m["region"], m["code"], coord.x, coord.y]


## Limites do estado em latitude/longitude (para validação e para o minimapa
## de escala estadual).
static func state_bounds() -> Dictionary:
	ensure_loaded()
	return _state.get("bounds", {
		"min_lat": -23.37,
		"max_lat": -20.76,
		"min_lon": -44.89,
		"max_lon": -40.96,
	})


## Quantos setores de 512 m o estado cobre — número de referência do plano.
static func estimated_sector_count() -> int:
	var b := state_bounds()
	var top_left := CariocaProjection.forward(float(b["max_lat"]), float(b["min_lon"]))
	var bottom_right := CariocaProjection.forward(float(b["min_lat"]), float(b["max_lon"]))
	var width := absf(bottom_right.x - top_left.x)
	var height := absf(top_left.y - bottom_right.y)
	var cols := ceilf(width / SectorGrid.SECTOR_SIZE)
	var rows := ceilf(height / SectorGrid.SECTOR_SIZE)
	return int(cols * rows)
