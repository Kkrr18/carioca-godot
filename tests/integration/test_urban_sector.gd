extends TestCase

## Integração: montar o setor urbano de verdade, com malha, colisão, vegetação e
## mobiliário. Roda headless porque a construção de malha e a física da Godot
## funcionam sem janela.


func _coord() -> Vector2i:
	MunicipalityIndex.ensure_loaded()
	return SectorGrid.sector_of(MunicipalityIndex.center_of("GUAPI"))


func _build(coord: Vector2i) -> Dictionary:
	UrbanConfig.set_active_from_preset(QualityProfile.get_preset("pc_medium"))
	var terrain := TerrainService.new(20170)
	var payload := UrbanGenerator.build_payload(coord, 20170)
	var instance := SectorInstance.new()
	instance.build(coord, payload, terrain, 8)
	return {"instance": instance, "terrain": terrain, "payload": payload}


func test_urban_sector_builds_all_layers() -> void:
	var built := _build(_coord())
	var instance: SectorInstance = built["instance"]
	assert_true(instance.is_urban_layer(), "setor reconhecido como camada urbana")
	assert_not_null(instance.get_node_or_null("Terrain"), "terreno construído")
	assert_not_null(instance.get_node_or_null("UrbanBuildings"), "malha de edificações construída")
	assert_not_null(instance.get_node_or_null("BuildingBodies"), "corpo de colisão das edificações")
	assert_greater(float(instance.urban_buildings()), 0.0, "edificações contadas no setor")
	assert_greater(float(instance.urban_blocks()), 0.0, "quadras contadas no setor")
	assert_greater(instance.memory_estimate_kb(), 0.0, "memória estimada positiva")
	assert_greater(float(instance.build_microseconds), 0.0, "tempo de construção medido")
	instance.free()


func test_doors_are_available_for_interiors() -> void:
	var built := _build(_coord())
	var instance: SectorInstance = built["instance"]
	var doors := instance.door_positions(SectorGrid.sector_origin(instance.coord))
	assert_greater(float(doors.size()), 0.0, "portas disponíveis para o gerenciador de interiores")
	if not doors.is_empty():
		var door: Dictionary = doors[0]
		assert_true(door.has("metric"), "porta com posição métrica")
		assert_true(door.has("building_id"), "porta com identificação de edificação")
		assert_true(str(door["kind"]) in [UrbanSchema.KIND_RESIDENTIAL, UrbanSchema.KIND_COMMERCIAL, UrbanSchema.KIND_MIXED, UrbanSchema.KIND_PUBLIC], "tipo de uso declarado")
	instance.free()


func test_street_furniture_nodes_are_created() -> void:
	var built := _build(_coord())
	var instance: SectorInstance = built["instance"]
	var names: Array[String] = []
	for child in instance.get_children():
		names.append(str(child.name))
	assert_true(names.has("Pavement"), "calçada construída")
	var has_props := false
	for name in names:
		if name.begins_with("StreetProps_"):
			has_props = true
	assert_true(has_props, "mobiliário construído como MultiMesh")
	var has_vegetation := false
	for name in names:
		if name.begins_with("Vegetation_"):
			has_vegetation = true
	assert_true(has_vegetation, "vegetação construída como MultiMesh")
	instance.free()


func test_detail_level_hides_the_thin_layers() -> void:
	var built := _build(_coord())
	var instance: SectorInstance = built["instance"]
	instance.apply_detail(3)
	for child in instance.get_children():
		var name := str(child.name)
		if name.begins_with("StreetProps_"):
			assert_false((child as Node3D).visible, "mobiliário escondido no nível distante")
		if name.begins_with("Vegetation_"):
			assert_false((child as Node3D).visible, "vegetação escondida no nível mais distante")
		if name == "UrbanBuildings" or name == "Pavement":
			assert_true((child as Node3D).visible, "prédio e calçada continuam visíveis ao longe")
	instance.apply_detail(0)
	for child in instance.get_children():
		if str(child.name).begins_with("StreetProps_"):
			assert_true((child as Node3D).visible, "mobiliário volta no nível próximo")
	instance.free()


func test_rebuild_after_release_is_identical() -> void:
	var coord := _coord()
	var first := _build(coord)
	var payload_first: Dictionary = first["payload"]
	var signature := JSON.stringify(payload_first.get("buildings", []))
	(first["instance"] as SectorInstance).release()

	UrbanConfig.set_active_from_preset(QualityProfile.get_preset("pc_medium"))
	var second := UrbanGenerator.build_payload(coord, 20170)
	assert_eq(JSON.stringify(second.get("buildings", [])), signature, "recarregar o mesmo setor produz a mesma cidade")
