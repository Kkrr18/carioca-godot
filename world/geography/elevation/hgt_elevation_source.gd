class_name HGTElevationSource
extends RefCounted

## Leitor de modelos digitais de elevação no formato SRTM .hgt.
##
## Formato: grade quadrada de inteiros de 16 bits big-endian, sem cabeçalho,
## cobrindo 1° x 1° de latitude/longitude. O primeiro registro é o canto
## noroeste; o último, o sudeste. SRTM1 tem 3601 pontos por lado (1 arco de
## segundo), SRTM3 tem 1201 (3 arcos de segundo) — o tamanho do arquivo revela
## qual é.
##
## O arquivo inteiro nunca é carregado: busca por `seek` na linha necessária e
## cache das linhas mais recentes. Assim o relevo real do estado cabe em poucos
## megabytes de RAM em vez de centenas.

const VOID := -32768
const MAX_TILES := 3
const MAX_ROWS := 96


var directory: String
var _tiles: Dictionary = {}
var _missing: Dictionary = {}


func _init(dir_path: String = "res://data/geographic/elevation") -> void:
	directory = dir_path


func has_data() -> bool:
	var dir := DirAccess.open(directory)
	if dir == null:
		return false
	var found := false
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.to_lower().ends_with(".hgt"):
			found = true
			break
		file_name = dir.get_next()
	dir.list_dir_end()
	return found


## Nome do tile que contém o ponto: N22W044, S23W043, ...
static func tile_name_for(latitude: float, longitude: float) -> String:
	var lat_floor := floori(latitude)
	var lon_floor := floori(longitude)
	var ns := "N" if lat_floor >= 0 else "S"
	var ew := "E" if lon_floor >= 0 else "W"
	return "%s%02d%s%03d" % [ns, absi(lat_floor), ew, absi(lon_floor)]


## Altura em metros, ou NAN quando não há dado para o ponto.
func height_at(latitude: float, longitude: float) -> float:
	var tile := _open_tile(tile_name_for(latitude, longitude))
	if tile.is_empty():
		return NAN
	var n: int = tile["n"]
	var span := float(n - 1)
	var lat_floor := floorf(latitude)
	var lon_floor := floorf(longitude)
	var x := (longitude - lon_floor) * span
	var y := (lat_floor + 1.0 - latitude) * span
	var x0 := clampi(floori(x), 0, n - 1)
	var y0 := clampi(floori(y), 0, n - 1)
	var x1 := mini(x0 + 1, n - 1)
	var y1 := mini(y0 + 1, n - 1)
	var fx := clampf(x - float(x0), 0.0, 1.0)
	var fy := clampf(y - float(y0), 0.0, 1.0)
	var row_north := _row(tile, y0)
	var row_south := _row(tile, y1)
	if row_north.is_empty() or row_south.is_empty():
		return NAN
	var top := lerpf(row_north[x0], row_north[x1], fx)
	var bottom := lerpf(row_south[x0], row_south[x1], fx)
	return lerpf(top, bottom, fy)


func close() -> void:
	for tile in _tiles.values():
		var file: FileAccess = tile.get("file")
		if file != null:
			file.close()
	_tiles.clear()


func loaded_tile_count() -> int:
	return _tiles.size()


func _open_tile(name: String) -> Dictionary:
	if _tiles.has(name):
		return _tiles[name]
	if _missing.has(name):
		return {}
	var path := directory.path_join(name + ".hgt")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_missing[name] = true
		return {}
	var size := int(file.get_length())
	var n := 0
	if size == 3601 * 3601 * 2:
		n = 3601
	elif size == 1201 * 1201 * 2:
		n = 1201
	elif size == 1801 * 1801 * 2:
		n = 1801
	if n == 0:
		file.close()
		_missing[name] = true
		return {}
	if _tiles.size() >= MAX_TILES:
		var oldest: String = String(_tiles.keys()[0])
		var old_file: FileAccess = _tiles[oldest].get("file")
		if old_file != null:
			old_file.close()
		_tiles.erase(oldest)
	var tile := {"file": file, "n": n, "rows": {}}
	_tiles[name] = tile
	return tile


func _row(tile: Dictionary, row: int) -> PackedFloat32Array:
	var rows: Dictionary = tile["rows"]
	if rows.has(row):
		return rows[row]
	var n: int = tile["n"]
	var file: FileAccess = tile["file"]
	if file == null:
		return PackedFloat32Array()
	var bytes := PackedByteArray()
	file.seek(row * n * 2)
	bytes = file.get_buffer(n * 2)
	if bytes.size() < n * 2:
		return PackedFloat32Array()
	var values := PackedFloat32Array()
	values.resize(n)
	for i in range(n):
		var raw := bytes.decode_s16(i * 2)
		values[i] = 0.0 if raw == VOID else float(raw)
	if rows.size() >= MAX_ROWS:
		rows.clear()
	rows[row] = values
	return values
