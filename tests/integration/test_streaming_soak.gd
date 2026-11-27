extends TestCase

## Sessão longa: o cenário que só aparece depois de minutos jogando — memória
## que cresce, setor duplicado, raio que vaza. Traversal em zigue-zague por 40
## posições, conduzindo o manager como o frame faria.

const PROFILE := "mobile"
const STEPS := 40
const FRAMES_PER_STEP := 12


func test_long_traversal_keeps_memory_bounded() -> void:
	MunicipalityIndex.ensure_loaded()
	var terrain := TerrainService.new(20170)
	var world_root := Node3D.new()
	var actor_root := Node3D.new()
	var viewer := Node3D.new()
	actor_root.add_child(viewer)
	var origin := FloatingOrigin.new()
	origin.setup(world_root, actor_root, viewer, MunicipalityIndex.center_of("GUAPI"))

	var manager := SectorStreamingManager.new()
	manager.sector_parent = world_root
	manager.setup(terrain, origin, viewer)
	manager.configure_defaults(QualityProfile.get_preset(PROFILE))
	manager.max_loaded_sectors = 21

	var peak_loaded := 0
	var peak_kb := 0.0
	var step_size := SectorGrid.SECTOR_SIZE * 2.0

	for step in range(STEPS):
		var phase := int(float(step) / 8.0)
		var direction := 1.0 if phase % 2 == 0 else -1.0
		viewer.position += Vector3(direction * step_size, 0.0, SectorGrid.SECTOR_SIZE * 0.5)
		for _frame in range(FRAMES_PER_STEP):
			manager.tick_for_test(0.12)
			OS.delay_msec(1)
		peak_loaded = maxi(peak_loaded, manager.loaded_count())
		peak_kb = maxf(peak_kb, manager.loaded_kb())

	assert_true(peak_loaded <= 21, "teto de setores nunca excedido (pico %d)" % peak_loaded)
	assert_true(peak_kb <= manager.memory.limit_kb * 1.5, "memória fica perto do orçamento (pico %.0f KB)" % peak_kb)
	assert_greater(float(manager.loaded_count()), 0.0, "mundo continua vivo ao fim da sessão")
	assert_eq(manager.memory.count(), manager.loaded_count(), "contabilidade bate com a carga")

	var unique := {}
	for coord in manager.loaded_coords():
		unique[coord] = true
	assert_eq(unique.size(), manager.loaded_count(), "nenhum setor duplicado após sessão longa")

	var stats := manager.stats()
	assert_greater(float(stats["builds"]), float(STEPS), "a sessão realmente construiu mundo")
	assert_greater(float(stats["evictions"]) + float(stats["cache_entries"]), 0.0, "houve reciclagem de recursos")

	manager.free()
	origin.free()
	world_root.free()
	actor_root.free()


func test_radius_change_recovers_the_ring() -> void:
	var terrain := TerrainService.new(20170)
	var world_root := Node3D.new()
	var actor_root := Node3D.new()
	var viewer := Node3D.new()
	actor_root.add_child(viewer)
	var origin := FloatingOrigin.new()
	origin.setup(world_root, actor_root, viewer, MunicipalityIndex.center_of("GUAPI"))
	var manager := SectorStreamingManager.new()
	manager.sector_parent = world_root
	manager.setup(terrain, origin, viewer)
	manager.configure_defaults(QualityProfile.get_preset(PROFILE))
	manager.set_view_radius(1)

	for _frame in range(200):
		manager.tick_for_test(0.05)
		OS.delay_msec(2)
	assert_eq(manager.loaded_count(), 9, "raio pequeno carregado")

	manager.set_view_radius(2)
	for _frame in range(400):
		manager.tick_for_test(0.05)
		OS.delay_msec(2)
	assert_eq(manager.loaded_count(), 21, "raio maior completa o anel")

	manager.set_view_radius(1)
	for _frame in range(200):
		manager.tick_for_test(0.05)
		OS.delay_msec(2)
	# A histerese de 1,6 bloco mantém o anel de distância 2 carregado; as quatro
	# esquinas (distância 2,83) precisam sair.
	assert_true(manager.loaded_count() <= 17, "raio menor descarrega as esquinas (ficou %d)" % manager.loaded_count())

	manager.free()
	origin.free()
	world_root.free()
	actor_root.free()
