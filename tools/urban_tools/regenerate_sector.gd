extends SceneTree

## Regenera setores urbanos específicos, sem reconstruir a cidade inteira.
##
##   godot --headless --path . --script res://tools/urban_tools/regenerate_sector.gd -- \
##       --center=GUAPI --radius=1 [--bake] [--dry-run] [--seed=20170]
##
## Dois usos, e os dois passam pelo mesmo caminho de geração do runtime:
##
##   sem `--bake`  apaga o payload gravado daqueles setores, forçando o jogo a
##                 gerar de novo na próxima carga. É o "regenerar sem mexer no
##                 resto" — o anel de streaming descarrega e recarrega só ali.
##
##   com `--bake`  gera e **grava** o payload urbano em
##                 `data/geographic/sectors/<REGIÃO>/<MUNICÍPIO>/<setor>.json`.
##                 Depois disso o setor é lido do disco: útil para congelar um
##                 recorte de demonstração ou distribuir sem gerar na máquina.
##                 O payload gravado guarda `urban_source`, então a fonte (OSM,
##                 estimada ou procedural) sobrevive ao congelamento.

func _initialize() -> void:
	var center_code := "GUAPI"
	var radius := 1
	var bake := false
	var dry_run := false
	var seed_value := 20170
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--center="):
			center_code = argument.substr(9)
		elif argument.begins_with("--radius="):
			radius = int(argument.substr(9))
		elif argument.begins_with("--seed="):
			seed_value = int(argument.substr(7))
		elif argument == "--bake":
			bake = true
		elif argument == "--dry-run":
			dry_run = true

	MunicipalityIndex.ensure_loaded()
	UrbanConfig.set_active_from_preset(QualityProfile.get_preset("pc_medium"))
	var center := MunicipalityIndex.center_of(center_code)
	if center == Vector2.ZERO:
		print("município desconhecido: %s" % center_code)
		quit(1)
		return
	var coords := SectorGrid.sectors_in_radius(SectorGrid.sector_of(center), maxi(radius, 0))
	print("")
	print("=== regenerate_sector — %s, %d setores, semente %d ===" % [center_code, coords.size(), seed_value])

	var written := 0
	var deleted := 0
	for coord in coords:
		if not bake and not dry_run:
			if SectorRepository.exists(coord):
				SectorRepository.delete_payload(coord)
				deleted += 1
		var payload := UrbanGenerator.build_payload(coord, seed_value)
		var build_count := (payload.get("buildings", []) as Array).size()
		var block_count := (payload.get("blocks", []) as Array).size()
		var parcel_count := (payload.get("parcels", []) as Array).size()
		var source := str(payload.get("urban_source", payload.get("source", "?")))
		print("  %s  fonte %-10s  quadras %2d  lotes %3d  prédios %3d" % [
			SectorGrid.key(coord), source, block_count, parcel_count, build_count,
		])
		if bake and not dry_run:
			if SectorRepository.save_payload(coord, payload):
				written += 1

	if dry_run:
		print("  (simulação: nada foi gravado nem apagado)")
	elif bake:
		print("  gravados %d/%d setores em %s" % [written, coords.size(), SectorRepository.DATA_ROOT])
	else:
		print("  payloads apagados: %d — o runtime gera de novo na próxima carga" % deleted)
	print("")
	quit(0 if not bake or written == coords.size() else 1)
