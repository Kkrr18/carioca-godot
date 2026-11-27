extends SceneTree

## Grava o mundo procedural em disco (bake).
##
##   godot --headless --script res://tools/sector_generator/bake_sectors.gd -- \
##       --center=GUAPI --radius=2
##   godot --headless --script res://tools/sector_generator/bake_sectors.gd -- \
##       --lat=-22.65 --lon=-43.04 --radius=3
##
## Serve para duas coisas: inspecionar o resultado do gerador em JSON e congelar
## um recorte para o build. Depois de gravar, o runtime lê o arquivo e não gera
## mais nada para aquele setor.

func _initialize() -> void:
	var center_code := "GUAPI"
	var lat := NAN
	var lon := NAN
	var radius := 2
	var seed_value := 20170
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--center="):
			center_code = argument.substr(9)
		elif argument.begins_with("--lat="):
			lat = float(argument.substr(6))
		elif argument.begins_with("--lon="):
			lon = float(argument.substr(6))
		elif argument.begins_with("--radius="):
			radius = int(argument.substr(9))
		elif argument.begins_with("--seed="):
			seed_value = int(argument.substr(7))

	MunicipalityIndex.ensure_loaded()
	var metric := Vector2.ZERO
	var label := center_code
	if is_nan(lat) or is_nan(lon):
		metric = MunicipalityIndex.center_of(center_code)
		var municipality := MunicipalityIndex.by_code(center_code)
		if municipality.is_empty():
			print("município desconhecido: %s" % center_code)
			quit(1)
			return
		label = str(municipality.get("name", center_code))
	else:
		metric = GeoCoordinateSystem.geographic_to_metric(lat, lon)
		label = "%.4f,%.4f" % [lat, lon]

	var center := SectorGrid.sector_of(metric)
	var coords := SectorGrid.sectors_in_radius(center, radius)
	print("Bake em %s — %d setores (raio %d)" % [label, coords.size(), radius])

	var written := 0
	var roads := 0
	var buildings := 0
	for coord in coords:
		var payload := CityGenerator.build_payload(coord, seed_value)
		roads += (payload["roads"] as Array).size()
		buildings += (payload["buildings"] as Array).size()
		if SectorRepository.save_payload(coord, payload):
			written += 1

	print("  gravados %d/%d setores — %d vias, %d edificações" % [written, coords.size(), roads, buildings])
	print("  pasta: %s" % SectorRepository.path_for(center).get_base_dir())
	quit(0 if written == coords.size() else 1)
