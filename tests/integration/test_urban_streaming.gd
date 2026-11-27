extends TestCase

## Integração: a cidade da Etapa 3 sob o streaming da Etapa 2.
##
## É o teste que garante que "não carregar a cidade inteira" continua valendo com
## quadra, lote, fachada e vegetação: o setor carrega, descarrega e volta a
## carregar idêntico, e nenhuma edificação aparece duas vezes no mundo montado.

const PROFILE := "mobile"


func _make_manager() -> Dictionary:
	MunicipalityIndex.ensure_loaded()
	var terrain := TerrainService.new(20170)
	var world_root := Node3D.new()
	var actor_root := Node3D.new()
	var viewer := Node3D.new()
	actor_root.add_child(viewer)
	var origin := FloatingOrigin.new()
	origin.setup(world_root, actor_root, viewer, MunicipalityIndex.center_of("GUAPI"))

	var manager := SectorStreamingManager.new()
	manager.name = "Streaming"
	manager.seed_value = 20170
	manager.sector_parent = world_root
	manager.setup(terrain, origin, viewer)
	manager.configure_defaults(QualityProfile.get_preset(PROFILE))
	manager.set_view_radius(1)
	return {
		"manager": manager,
		"origin": origin,
		"viewer": viewer,
		"world": world_root,
		"actors": actor_root,
		"terrain": terrain,
	}


func _dispose(context: Dictionary) -> void:
	(context["manager"] as SectorStreamingManager).free()
	(context["origin"] as FloatingOrigin).free()
	(context["world"] as Node3D).free()
	(context["actors"] as Node3D).free()


func _tick_until(manager: SectorStreamingManager, target: int, max_frames: int) -> void:
	var frames := 0
	while frames < max_frames and manager.loaded_count() < target:
		manager.tick_for_test(0.05)
		OS.delay_msec(2)
		frames += 1


func test_streaming_serves_urban_sectors() -> void:
	var context := _make_manager()
	var manager: SectorStreamingManager = context["manager"]
	_tick_until(manager, 9, 900)

	assert_eq(manager.loaded_count(), 9, "anel de nove setores carregado")
	var urban := 0
	var identifiers := {}
	for coord in manager.loaded_coords():
		var instance: SectorInstance = manager.loaded_sector(coord)
		assert_not_null(instance, "instância presente")
		if instance == null:
			continue
		if instance.is_urban_layer():
			urban += 1
		for raw in instance.payload.get("buildings", []):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var identifier := str((raw as Dictionary).get("id", ""))
			assert_false(identifiers.has(identifier), "identificador único entre setores: %s" % identifier)
			identifiers[identifier] = true
	assert_greater(float(urban), 0.0, "há setor urbano no centro de Guapimirim")
	assert_greater(float(identifiers.size()), 0.0, "edificações carregadas no anel")
	_dispose(context)


func test_walking_away_unloads_the_urban_ring() -> void:
	var context := _make_manager()
	var manager: SectorStreamingManager = context["manager"]
	var viewer: Node3D = context["viewer"]
	var origin: FloatingOrigin = context["origin"]
	_tick_until(manager, 9, 900)

	var home := SectorGrid.sector_of(origin.viewer_metric())
	var home_instance: SectorInstance = manager.loaded_sector(home)
	assert_not_null(home_instance, "setor do jogador carregado")
	var home_buildings := 0
	if home_instance != null:
		home_buildings = home_instance.urban_buildings()
	assert_greater(float(home_buildings), 0.0, "o setor do jogador tem cidade")

	viewer.position += Vector3(SectorGrid.SECTOR_SIZE * 6.0, 0.0, 0.0)
	for _frame in range(240):
		manager.tick_for_test(0.05)
		OS.delay_msec(2)

	assert_true(manager.loaded_sector(home) == null, "setor antigo descarregado")
	assert_true(manager.loaded_count() <= 9, "raio respeitado depois do salto")
	assert_greater(float(manager.loaded_count()), 0.0, "mundo servido no lugar novo")
	assert_eq(manager.memory.count(), manager.loaded_count(), "orçamento acompanha a carga")
	_dispose(context)


func test_return_rebuilds_the_same_city() -> void:
	var context := _make_manager()
	var manager: SectorStreamingManager = context["manager"]
	var viewer: Node3D = context["viewer"]
	var origin: FloatingOrigin = context["origin"]
	_tick_until(manager, 9, 900)

	var home := SectorGrid.sector_of(origin.viewer_metric())
	var before: SectorInstance = manager.loaded_sector(home)
	assert_not_null(before, "setor carregado antes de sair")
	if before == null:
		_dispose(context)
		return
	var signature := JSON.stringify(before.payload.get("buildings", []))
	var home_position := viewer.position

	viewer.position = home_position + Vector3(SectorGrid.SECTOR_SIZE * 5.0, 0.0, 0.0)
	for _frame in range(200):
		manager.tick_for_test(0.05)
		OS.delay_msec(2)
	viewer.position = home_position
	for _frame in range(240):
		manager.tick_for_test(0.05)
		OS.delay_msec(2)

	var after: SectorInstance = manager.loaded_sector(home)
	assert_not_null(after, "setor recarregado ao voltar")
	if after != null:
		assert_eq(JSON.stringify(after.payload.get("buildings", [])), signature, "a cidade reconstruída é a mesma")
	_dispose(context)


func test_profile_caps_the_urban_layer() -> void:
	var coord := SectorGrid.sector_of(MunicipalityIndex.center_of("GUAPI"))

	UrbanConfig.set_active_from_preset(QualityProfile.get_preset("mobile"))
	var mobile := UrbanGenerator.build_payload(coord, 20170)
	var mobile_buildings := (mobile.get("buildings", []) as Array).size()

	UrbanConfig.set_active_from_preset(QualityProfile.get_preset("pc_high"))
	var high := UrbanGenerator.build_payload(coord, 20170)
	var high_buildings := (high.get("buildings", []) as Array).size()

	assert_greater(float(mobile_buildings), 0.0, "perfil mobile também gera cidade")
	assert_true(mobile_buildings <= 44, "perfil mobile respeita o teto por setor (%d)" % mobile_buildings)
	assert_true(high_buildings <= 160, "perfil alto respeita o teto por setor (%d)" % high_buildings)
	assert_true((mobile.get("vegetation", {}).get("trees", []) as Array).size() <= 90, "teto de vegetação do mobile")
	assert_true((high.get("vegetation", {}).get("trees", []) as Array).size() <= 320, "teto de vegetação do perfil alto")

	UrbanConfig.set_active_from_preset(QualityProfile.get_preset(PROFILE))
