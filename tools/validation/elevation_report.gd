extends SceneTree

## Relatório dos modelos digitais de elevação presentes em disco.
##
##   godot --headless --script res://tools/validation/elevation_report.gd
##
## Diz o que está disponível, a resolução (SRTM1 ou SRTM3), a cobertura em
## latitude/longitude e uma amostragem de altura. É o primeiro arquivo a olhar
## quando o relevo real parecer errado.

const ELEVATION_DIR := "res://data/geographic/elevation"
const SAMPLES := 12


func _initialize() -> void:
	var dir := DirAccess.open(ELEVATION_DIR)
	if dir == null:
		print("pasta ausente: %s" % ELEVATION_DIR)
		print("o mundo usará relevo procedural até um .hgt ser colocado aqui")
		quit(0)
		return

	var tiles: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.to_lower().ends_with(".hgt"):
			tiles.append(entry.get_basename())
		entry = dir.get_next()
	dir.list_dir_end()

	if tiles.is_empty():
		print("nenhum .hgt em %s — usando relevo procedural" % ELEVATION_DIR)
		quit(0)
		return

	var source := HGTElevationSource.new(ELEVATION_DIR)
	print("%d tiles de elevação encontrados" % tiles.size())
	for tile in tiles:
		var file := FileAccess.open(ELEVATION_DIR.path_join(tile + ".hgt"), FileAccess.READ)
		var size := 0
		if file != null:
			size = int(file.get_length())
		var resolution := "?"
		if size == 3601 * 3601 * 2:
			resolution = "SRTM1 (1 arco de segundo, ~30 m)"
		elif size == 1201 * 1201 * 2:
			resolution = "SRTM3 (3 arcos de segundo, ~90 m)"
		print("  %s — %s — %.1f MB" % [tile, resolution, float(size) / 1048576.0])

	var bounds := _tile_bounds(tiles[0])
	var minimum := INF
	var maximum := -INF
	var valid := 0
	for i in range(SAMPLES):
		var t := float(i) / float(maxi(SAMPLES - 1, 1))
		var lat := lerpf(bounds.x, bounds.z, t)
		var lon := lerpf(bounds.y, bounds.w, t)
		var height := source.height_at(lat, lon)
		if is_nan(height):
			continue
		valid += 1
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		print("  amostra %.4f, %.4f -> %.0f m" % [lat, lon, height])

	if valid > 0:
		print("faixa amostrada: %.0f m a %.0f m" % [minimum, maximum])
	else:
		print("nenhuma amostra válida — verifique nomes de arquivo e projeção")
	quit(0)


## Retorna Rect2(min_lon, min_lat, largura, altura) do tile HGT.
func _tile_bounds(tile_name: String) -> Vector4:
	var north := tile_name.substr(0, 1) == "N"
	var east := tile_name.substr(3, 1) == "E"
	var lat_value := int(tile_name.substr(1, 2))
	var lon_value := int(tile_name.substr(4, 3))
	var lat := float(lat_value) if north else -float(lat_value)
	var lon := float(lon_value) if east else -float(lon_value)
	return Vector4(lat, lon, lat + 1.0, lon + 1.0)
