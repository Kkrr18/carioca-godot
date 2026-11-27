extends TestCase

## Streaming de ponta a ponta, com terreno e geração reais.
##
## O teste headless não tem laço de frame chamando `_process`, então ele conduz o
## manager por `tick_for_test` e o cache do sistema operacional drena as tarefas
## com `OS.delay_msec`. O resultado é o mesmo caminho de código do jogo.

const PROFILE := "pc_medium"


class FlakyLoader extends RefCounted:
	## Carregador que falha algumas vezes e depois funciona. Serve para exercitar
	## a retentativa sem depender de disco corrompido.
	var calls: Dictionary = {}
	var target: Vector2i = Vector2i.ZERO
	var fail_times: int = 2

	func load(coord: Vector2i) -> Dictionary:
		var count := int(calls.get(coord, 0))
		calls[coord] = count + 1
		if coord == target and count < fail_times:
			return {}
		return SectorRepository.load_payload(coord, 20170)


func _make_manager(view_radius: int, profile: String = PROFILE) -> Dictionary:
	MunicipalityIndex.ensure_loaded()
	var terrain := TerrainService.new(20170)
	var world_root := Node3D.new()
	var actor_root := Node3D.new()
	var viewer := Node3D.new()
	actor_root.add_child(viewer)
	var origin := FloatingOrigin.new()
	var start := MunicipalityIndex.center_of("GUAPI")
	origin.setup(world_root, actor_root, viewer, start)

	var manager := SectorStreamingManager.new()
	manager.name = "Streaming"
	manager.seed_value = 20170
	manager.sector_parent = world_root
	manager.setup(terrain, origin, viewer)
	manager.configure_defaults(QualityProfile.get_preset(profile))
	manager.set_view_radius(view_radius)
	return {
		"manager": manager,
		"origin": origin,
		"viewer": viewer,
		"world": world_root,
		"actors": actor_root,
		"terrain": terrain,
	}


func _dispose(ctx: Dictionary) -> void:
	(ctx["manager"] as SectorStreamingManager).free()
	(ctx["origin"] as FloatingOrigin).free()
	(ctx["world"] as Node3D).free()
	(ctx["actors"] as Node3D).free()


func _tick(manager: SectorStreamingManager, frames: int, delta: float = 0.05) -> void:
	for _i in range(frames):
		manager.tick_for_test(delta)
		OS.delay_msec(2)


func _tick_until(manager: SectorStreamingManager, target: int, max_frames: int, delta: float = 0.05) -> int:
	var frames := 0
	while frames < max_frames and manager.loaded_count() < target:
		manager.tick_for_test(delta)
		OS.delay_msec(2)
		frames += 1
	return frames


func test_loads_the_ring_around_the_viewer() -> void:
	var ctx := _make_manager(1)
	var manager: SectorStreamingManager = ctx["manager"]
	var origin: FloatingOrigin = ctx["origin"]
	_tick_until(manager, 9, 600)

	var cell := SectorGrid.sector_of(origin.viewer_metric())
	assert_eq(manager.loaded_count(), 9, "raio 1 carrega nove blocos")
	assert_not_null(manager.loaded_sector(cell), "o bloco do jogador está entre eles")
	assert_eq(manager.pending_count(), 0, "fila esvaziada")
	assert_eq(manager.inflight_count(), 0, "nenhuma tarefa pendente")
	_dispose(ctx)


func test_no_duplicate_instances() -> void:
	var ctx := _make_manager(2)
	var manager: SectorStreamingManager = ctx["manager"]
	_tick_until(manager, 21, 800)

	var seen := {}
	for coord in manager.loaded_coords():
		assert_false(seen.has(coord), "coordenada não aparece duas vezes")
		seen[coord] = true
	assert_eq(seen.size(), manager.loaded_count(), "uma instância por coordenada")
	for coord in manager.loaded_coords():
		var instance: SectorInstance = manager.loaded_sector(coord)
		assert_not_null(instance, "instância disponível")
		assert_eq(instance.get_parent(), ctx["world"], "setor anexado à raiz do mundo")
	_dispose(ctx)


func test_far_move_unloads_the_old_ring() -> void:
	var ctx := _make_manager(1)
	var manager: SectorStreamingManager = ctx["manager"]
	var viewer: Node3D = ctx["viewer"]
	var origin: FloatingOrigin = ctx["origin"]
	_tick_until(manager, 9, 600)
	var old_cell := SectorGrid.sector_of(origin.viewer_metric())
	assert_not_null(manager.loaded_sector(old_cell), "bloco inicial carregado")

	viewer.position += Vector3(SectorGrid.SECTOR_SIZE * 6.0, 0.0, 0.0)
	_tick(manager, 200)

	assert_true(manager.loaded_sector(old_cell) == null, "bloco antigo descarregado")
	assert_true(manager.loaded_count() <= 9, "raio respeitado depois do salto")
	assert_greater(float(manager.loaded_count()), 6.0, "mundo servido no lugar novo")
	_dispose(ctx)


func test_fast_traversal_respects_budgets() -> void:
	var ctx := _make_manager(2)
	var manager: SectorStreamingManager = ctx["manager"]
	var viewer: Node3D = ctx["viewer"]
	manager.max_loaded_sectors = 21
	var peak := 0
	for _step in range(30):
		viewer.position += Vector3(SectorGrid.SECTOR_SIZE, 0.0, 0.0)
		for _frame in range(4):
			manager.tick_for_test(0.05)
			OS.delay_msec(1)
		peak = maxi(peak, manager.loaded_count())

	assert_true(peak <= 21, "pico de setores dentro do teto (foi %d)" % peak)
	assert_true(manager.inflight_count() <= manager.max_concurrent_tasks, "tarefas simultâneas limitadas")
	assert_greater(float(manager.loaded_count()), 0.0, "mundo continua servido ao fim")
	_dispose(ctx)


func test_prefetch_ahead_when_moving() -> void:
	var ctx := _make_manager(1)
	var manager: SectorStreamingManager = ctx["manager"]
	var viewer: Node3D = ctx["viewer"]
	# 1,5 m a cada 0,05 s = 30 m/s, velocidade de carro na via arterial.
	for _step in range(60):
		viewer.position += Vector3(1.5, 0.0, 0.0)
		manager.tick_for_test(0.05)
		OS.delay_msec(1)

	assert_greater(manager.viewer_speed(), 20.0, "velocidade estimada pelo manager")
	var stats := manager.stats()
	assert_greater(float(stats["prefetch"]), 0.0, "blocos antecipados na direção do movimento")
	_dispose(ctx)


func test_lod_is_mixed_and_matches_controller() -> void:
	var ctx := _make_manager(2)
	var manager: SectorStreamingManager = ctx["manager"]
	_tick_until(manager, 21, 800)

	var counts: Array = manager.stats()["lod_counts"]
	assert_array_size(counts, 4, "quatro níveis no relatório")
	assert_greater(float(counts[0]), 0.0, "há setores detalhados perto do jogador")
	var coarse := int(counts[1]) + int(counts[2]) + int(counts[3])
	assert_greater(float(coarse), 0.0, "há setores em nível mais grosso ao longe")
	for coord in manager.loaded_coords():
		var instance: SectorInstance = manager.loaded_sector(coord)
		assert_eq(instance.lod_level, manager.lod.level_of(coord), "instância e controlador concordam")
		assert_true(instance.terrain_divisions > 1, "resolução de terreno aplicada")
	_dispose(ctx)


func test_memory_accounting_follows_the_loaded_set() -> void:
	var ctx := _make_manager(1)
	var manager: SectorStreamingManager = ctx["manager"]
	var viewer: Node3D = ctx["viewer"]
	_tick_until(manager, 9, 600)
	assert_greater(manager.loaded_kb(), 0.0, "memória estimada positiva")
	assert_eq(manager.memory.count(), manager.loaded_count(), "um registro por setor carregado")

	viewer.position += Vector3(SectorGrid.SECTOR_SIZE * 7.0, 0.0, 0.0)
	_tick(manager, 200)

	assert_eq(manager.memory.count(), manager.loaded_count(), "registros acompanham a carga")
	assert_almost_eq(manager.loaded_kb(), manager.memory.total_kb(), 1e-6, "leitura coerente com o orçamento")
	_dispose(ctx)


func test_returning_to_the_same_area_hits_the_cache() -> void:
	var ctx := _make_manager(1)
	var manager: SectorStreamingManager = ctx["manager"]
	var viewer: Node3D = ctx["viewer"]
	_tick_until(manager, 9, 600)
	var hits_before := manager.cache.hits
	var home := viewer.position

	viewer.position = home + Vector3(SectorGrid.SECTOR_SIZE * 5.0, 0.0, 0.0)
	_tick(manager, 200)
	viewer.position = home
	_tick(manager, 200)

	assert_greater(float(manager.cache.hits - hits_before), 0.0, "voltar ao lugar anterior usa o cache")
	assert_greater(float(manager.loaded_count()), 0.0, "setores do lugar original voltaram")
	_dispose(ctx)


func test_failed_load_is_retried_until_it_works() -> void:
	var ctx := _make_manager(1)
	var manager: SectorStreamingManager = ctx["manager"]
	var origin: FloatingOrigin = ctx["origin"]
	manager.max_concurrent_tasks = 1
	manager.retry.base_delay_s = 0.05
	manager.retry.max_attempts = 3
	var cell := SectorGrid.sector_of(origin.viewer_metric())
	var loader := FlakyLoader.new()
	loader.target = cell
	loader.fail_times = 2
	manager.payload_loader = Callable(loader, "load")

	_tick(manager, 300)

	assert_eq(int(loader.calls.get(cell, 0)), 3, "a carga foi tentada três vezes")
	assert_not_null(manager.loaded_sector(cell), "o setor terminou carregado")
	assert_greater(float(manager.stats()["retries"]), 0.0, "retentativas contabilizadas")
	_dispose(ctx)


func test_rebuild_all_releases_everything() -> void:
	var ctx := _make_manager(1)
	var manager: SectorStreamingManager = ctx["manager"]
	_tick_until(manager, 9, 600)
	assert_greater(float(manager.loaded_count()), 0.0, "carregou antes de reconstruir")

	manager.rebuild_all()

	assert_eq(manager.loaded_count(), 0, "nenhum setor depois do rebuild")
	assert_eq(manager.memory.count(), 0, "orçamento zerado")
	assert_eq(manager.pending_count(), 0, "fila zerada")
	_tick(manager, 200)
	assert_eq(manager.loaded_count(), 9, "recomeça o raio completo")
	_dispose(ctx)


func test_inline_loads_build_the_world_without_threads() -> void:
	# É o caminho do build web sem threads: WorkerThreadPool não executa
	# tarefas fora de wait_for_task_completion, e o polling nunca as vê
	# terminar. Com carga inline, a fila precisa drenar do mesmo jeito.
	var ctx := _make_manager(1)
	var manager: SectorStreamingManager = ctx["manager"]
	manager._inline_loads = true
	_tick(manager, 120)
	assert_greater(float(manager.loaded_count()), 0.0, "carga inline constrói o mundo")
	assert_eq(manager.inflight_count(), 0, "carga inline não ocupa vaga de worker")
	assert_eq(manager.memory.count(), manager.loaded_count(), "contabilidade acompanha")
	_dispose(ctx)
