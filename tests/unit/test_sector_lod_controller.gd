extends TestCase

## Controlador de LOD: distância, vizinhança e histerese. É a política que decide
## quando um setor troca de malha, então cada regra tem teste próprio.

const RADIUS := 3


func _profile() -> LodProfile:
	return LodProfile.from_preset(QualityProfile.get_preset("pc_medium"))


func _coords(radius: int) -> Array:
	var out: Array = []
	for coord in SectorGrid.sectors_in_radius(Vector2i.ZERO, radius):
		out.append(coord)
	return out


func test_first_evaluation_assigns_without_switching() -> void:
	var controller := SectorLodController.new()
	controller.setup(_profile())
	var changed := controller.update(SectorGrid.sector_center(Vector2i.ZERO), _coords(RADIUS), 1.0)
	assert_array_size(changed, 0, "primeira avaliação registra níveis sem trocar malha")
	assert_eq(controller.level_of(Vector2i.ZERO), 0, "bloco do jogador no nível detalhado")


func test_level_follows_border_distance() -> void:
	var controller := SectorLodController.new()
	controller.setup(_profile())
	var center := SectorGrid.sector_center(Vector2i.ZERO)
	controller.update(center, _coords(RADIUS), 1.0)
	# centro em (256, 256): a borda oeste do bloco (1,0) está a 256 m
	assert_eq(controller.level_of(Vector2i(1, 0)), 0, "bloco vizinho ainda detalhado")
	# borda oeste de (2,0) a 768 m -> nível 1 no perfil médio
	assert_eq(controller.level_of(Vector2i(2, 0)), 1, "bloco intermediário em nível 1")
	# borda oeste de (3,0) a 1280 m -> nível 2
	assert_eq(controller.level_of(Vector2i(3, 0)), 2, "bloco distante em nível 2")


func test_provisional_level_ignores_hysteresis() -> void:
	var controller := SectorLodController.new()
	controller.setup(_profile())
	var far := controller.provisional_level(Vector2i(3, 0), SectorGrid.sector_center(Vector2i.ZERO))
	assert_eq(far, 2, "nível provisório calculado sem histórico")
	assert_eq(controller.level_of(Vector2i(3, 0)), 0, "provisório não grava estado")


func test_change_requires_sustained_time() -> void:
	var controller := SectorLodController.new()
	controller.setup(_profile())
	var coords := _coords(RADIUS)
	controller.update(SectorGrid.sector_center(Vector2i.ZERO), coords, 0.01)
	assert_eq(controller.level_of(Vector2i.ZERO), 0, "começa detalhado perto do jogador")

	var far_center := SectorGrid.sector_center(Vector2i(3, 0))
	var immediate := controller.update(far_center, coords, 0.01)
	assert_array_size(immediate, 0, "nada muda no primeiro instante")
	assert_eq(controller.level_of(Vector2i.ZERO), 0, "nível preservado pela histerese")

	var committed := false
	for _i in range(60):
		if not controller.update(far_center, coords, 0.05).is_empty():
			committed = true
			break
	assert_true(committed, "mudança sustentada é aplicada")
	assert_eq(controller.level_of(Vector2i.ZERO), 2, "bloco que ficou para trás assumiu o nível 2")


func test_neighbours_never_jump_more_than_one_level() -> void:
	var controller := SectorLodController.new()
	controller.setup(_profile())
	var coords := _coords(4)
	controller.update(SectorGrid.sector_center(Vector2i.ZERO), coords, 1.0)
	for coord in coords:
		for dir in SectorLodController.NEIGHBOURS:
			var other: Vector2i = coord + dir
			if not coords.has(other):
				continue
			var jump := absi(controller.level_of(coord) - controller.level_of(other))
			assert_true(jump <= 1, "salto de %d níveis entre %s e %s" % [jump, str(coord), str(other)])


func test_forget_drops_state() -> void:
	var controller := SectorLodController.new()
	controller.setup(_profile())
	controller.update(SectorGrid.sector_center(Vector2i.ZERO), _coords(1), 1.0)
	controller.forget(Vector2i.ZERO)
	assert_eq(controller.level_of(Vector2i.ZERO), 0, "sem estado, nível zero")
	assert_eq(controller.stats()["levels"], 8, "um registro a menos")


func test_level_counts_cover_all_loaded() -> void:
	var controller := SectorLodController.new()
	controller.setup(_profile())
	var coords := _coords(RADIUS)
	controller.update(SectorGrid.sector_center(Vector2i.ZERO), coords, 1.0)
	var counts := controller.level_counts(coords)
	assert_array_size(counts, 4, "uma contagem por nível")
	var total := 0
	for value in counts:
		total += int(value)
	assert_eq(total, coords.size(), "todo setor carregado está em um nível")


func test_reset_clears_everything() -> void:
	var controller := SectorLodController.new()
	controller.setup(_profile())
	controller.update(SectorGrid.sector_center(Vector2i.ZERO), _coords(1), 1.0)
	controller.reset()
	assert_eq(int(controller.stats()["levels"]), 0, "estado limpo")
	assert_eq(int(controller.stats()["evaluations"]), 0, "contadores limpos")
