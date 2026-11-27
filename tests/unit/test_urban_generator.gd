extends TestCase

## Gerador urbano ponta a ponta: payload do setor com camada urbana, contrato
## antigo preservado e determinismo.

func _coord(offset: Vector2i = Vector2i.ZERO) -> Vector2i:
	MunicipalityIndex.ensure_loaded()
	return SectorGrid.sector_of(MunicipalityIndex.center_of("GUAPI")) + offset


func _payload(offset: Vector2i = Vector2i.ZERO) -> Dictionary:
	UrbanConfig.set_active_from_preset(QualityProfile.get_preset("pc_medium"))
	return UrbanGenerator.build_payload(_coord(offset), 20170)


func test_urban_layer_is_present() -> void:
	var payload := _payload()
	assert_true(bool(payload.get("urban_v3", false)), "camada urbana ativa no centro")
	assert_eq(int(payload.get("urban_version", 0)), UrbanSchema.URBAN_VERSION, "versão da camada urbana")
	for key in ["roads", "buildings", "blocks", "parcels", "vegetation", "street_objects", "landmarks", "provenance", "urban_stats"]:
		assert_true(payload.has(key), "chave %s presente" % key)
	assert_greater(float((payload["blocks"] as Array).size()), 0.0, "quadras geradas")
	assert_greater(float((payload["parcels"] as Array).size()), 0.0, "lotes gerados")
	assert_greater(float((payload["buildings"] as Array).size()), 0.0, "edificações geradas")


func test_legacy_contract_is_preserved() -> void:
	var payload := _payload()
	assert_eq(int(payload.get("version", 0)), WorldSchema.SECTOR_SCHEMA_VERSION, "schema de setor preservado")
	assert_eq((payload.get("grid", []) as Array).size(), 2, "campo grid preservado")
	assert_eq((payload.get("origin", []) as Array).size(), 2, "campo origin preservado")
	assert_greater(float((payload.get("roads", []) as Array).size()), 0.0, "vias disponíveis para trânsito e minimapa")
	var buildings: Array = payload.get("buildings", [])
	assert_greater(float(buildings.size()), 0.0, "edificações presentes")
	for raw in buildings:
		var building: Dictionary = raw
		for field in ["center", "size", "angle", "levels", "height", "kind", "door"]:
			assert_true(building.has(field), "campo %s da Etapa 1 preservado" % field)


func test_building_ids_are_unique_and_reproducible() -> void:
	var first := _payload()
	var second := _payload()
	var seen := {}
	var first_ids: Array = []
	for raw in first.get("buildings", []):
		var id := str((raw as Dictionary).get("id", ""))
		assert_false(seen.has(id), "identificador único: %s" % id)
		seen[id] = true
		first_ids.append(id)
	assert_greater(float(first_ids.size()), 0.0, "há identificadores")
	var second_ids: Array = []
	for raw in second.get("buildings", []):
		second_ids.append(str((raw as Dictionary).get("id", "")))
	assert_eq(JSON.stringify(first_ids), JSON.stringify(second_ids), "identificadores reproduzíveis")


func test_payload_is_deterministic() -> void:
	assert_eq(JSON.stringify(_payload()), JSON.stringify(_payload()), "payload idêntico entre chamadas")


func test_buildings_stay_inside_the_sector_bounds() -> void:
	var payload := _payload()
	var limit := SectorGrid.SECTOR_SIZE + 400.0
	for raw in payload.get("buildings", []):
		var center: Array = (raw as Dictionary).get("center", [])
		if center.size() < 2:
			fail("edificação sem centro")
			continue
		assert_true(absf(float(center[0])) <= limit, "centro x dentro do limite do setor")
		assert_true(absf(float(center[1])) <= limit, "centro y dentro do limite do setor")


func test_provenance_declares_license_and_confidence() -> void:
	var provenance: Dictionary = _payload().get("provenance", {})
	assert_true(provenance.has("license"), "licença declarada")
	assert_true(provenance.has("confidence"), "confiança declarada")
	assert_true(provenance.has("note"), "nota dizendo o que o dado é")
	assert_true(provenance.has("source"), "fonte declarada")


func test_urban_source_is_declared() -> void:
	var payload := _payload()
	var source := str(payload.get("urban_source", ""))
	assert_true(source in [UrbanSchema.SOURCE_OSM, UrbanSchema.SOURCE_ESTIMATED, UrbanSchema.SOURCE_PROCEDURAL], "fonte de rua declarada: %s" % source)
	assert_greater(float((payload.get("urban_geometry", {}) as Dictionary).size()), 0.0, "geometria de calçada declarada")


func test_distant_sector_stays_cheap() -> void:
	var payload := _payload(Vector2i(80, 80))
	assert_false(bool(payload.get("urban_v3", false)), "setor remoto mantém o caminho barato")
	assert_true(payload.has("roads"), "ainda entrega vias")
	assert_true(payload.has("trees"), "ainda entrega vegetação procedural")


func test_stats_match_the_payload() -> void:
	var payload := _payload()
	var stats: Dictionary = UrbanGenerator.stats(payload)
	assert_eq(int(stats.get("buildings", -1)), (payload.get("buildings", []) as Array).size(), "contagem de edificações confere")
	assert_eq(int(stats.get("blocks", -1)), (payload.get("blocks", []) as Array).size(), "contagem de quadras confere")
	assert_eq(int(stats.get("parcels", -1)), (payload.get("parcels", []) as Array).size(), "contagem de lotes confere")
