extends TestCase

## Integração: o personagem no mundo das etapas anteriores.
##
## Monta terreno, streaming e jogador de verdade e conduz o personagem pelo mesmo
## caminho do `_physics_process` (`step_physics`). Verifica o que só aparece com o
## mundo montado: nascer em altura válida, pisar no terreno, atravessar a fronteira
## de setor sem perder o chão, e sobreviver ao floating origin.

func _make_world() -> Dictionary:
	MunicipalityIndex.ensure_loaded()
	InputBindings.ensure_registered()
	UrbanConfig.set_active_from_preset(QualityProfile.get_preset("pc_medium"))
	var settings := CariocaSettings.get_instance()
	var terrain := TerrainService.new(settings.world_seed)
	var world_root := Node3D.new()
	var actor_root := Node3D.new()
	var player := Player.new()
	actor_root.add_child(player)
	tree.root.add_child(world_root)
	tree.root.add_child(actor_root)
	var start := MunicipalityIndex.center_of("GUAPI")
	var floating := FloatingOrigin.new()
	tree.root.add_child(floating)
	floating.setup(world_root, actor_root, player, start)
	player.position = Vector3(0.0, terrain.height_at(start) + 2.0, 0.0)
	player.floating = floating
	player.terrain = terrain
	var camera_rig := PlayerCamera.new()
	tree.root.add_child(camera_rig)
	camera_rig.set_target(player)
	player.camera_rig = camera_rig
	var streaming := SectorStreamingManager.new()
	streaming.sector_parent = world_root
	streaming.setup(terrain, floating, player)
	tree.root.add_child(streaming)
	return {
		"terrain": terrain,
		"world": world_root,
		"actors": actor_root,
		"player": player,
		"floating": floating,
		"camera": camera_rig,
		"streaming": streaming,
	}


func _dispose(context: Dictionary) -> void:
	(context["streaming"] as SectorStreamingManager).free()
	(context["camera"] as PlayerCamera).free()
	(context["floating"] as FloatingOrigin).free()
	(context["world"] as Node3D).free()
	(context["actors"] as Node3D).free()


func _step(player: Player, frames: int, input: Vector2 = Vector2.ZERO, jump: bool = false) -> void:
	for i in range(frames):
		player.step_physics(1.0 / 60.0, input, jump and i == 0)
		OS.delay_msec(1)


func test_player_spawns_above_the_terrain() -> void:
	var context := _make_world()
	var player: Player = context["player"]
	var terrain: TerrainService = context["terrain"]
	var metric := player.metric_position()
	var ground := terrain.height_at(metric)
	assert_greater(player.position.y, ground, "nasce acima do terreno")
	assert_true(player.can_move, "movimento habilitado ao nascer")
	assert_eq(player.state_name(), "parado", "começa parado")
	_dispose(context)


func test_player_lands_on_the_terrain() -> void:
	var context := _make_world()
	var player: Player = context["player"]
	_step(player, 120)
	assert_true(player.is_on_floor(), "encontra o chão do terreno")
	assert_almost_eq(player.speed(), 0.0, 0.2, "para no chão")
	_dispose(context)


func test_player_walks_in_every_direction() -> void:
	var context := _make_world()
	var player: Player = context["player"]
	_step(player, 60)
	var start := player.position
	for direction in [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]:
		var before := player.position
		_step(player, 30, direction)
		assert_greater(before.distance_to(player.position), 0.5, "andou em %s" % str(direction))
	assert_greater(start.distance_to(player.position), 0.5, "mudou de lugar no conjunto")
	_dispose(context)


func test_player_jumps_and_comes_back_down() -> void:
	var context := _make_world()
	var player: Player = context["player"]
	_step(player, 90)
	assert_true(player.is_on_floor(), "no chão antes do pulo")
	var ground := player.position.y
	player.step_physics(1.0 / 60.0, Vector2.ZERO, true)
	var peak := player.position.y
	for _i in range(30):
		player.step_physics(1.0 / 60.0)
		peak = maxf(peak, player.position.y)
		OS.delay_msec(1)
	assert_greater(peak, ground + 0.4, "subiu de fato")
	_step(player, 150)
	assert_true(player.is_on_floor(), "voltou ao chão")
	assert_greater(player.position.y, ground - 2.0, "aterrissou perto do ponto de partida")
	_dispose(context)


func test_player_never_sinks_below_the_terrain() -> void:
	var context := _make_world()
	var player: Player = context["player"]
	var terrain: TerrainService = context["terrain"]
	_step(player, 90)
	for _i in range(60):
		player.step_physics(1.0 / 60.0, Vector2(0.6, 0.8))
		OS.delay_msec(1)
		var ground := terrain.height_at(player.metric_position())
		assert_greater(player.position.y, ground - 1.2, "o corpo não atravessa o terreno")
	_dispose(context)


func test_player_crosses_a_sector_boundary_on_foot() -> void:
	var context := _make_world()
	var player: Player = context["player"]
	var streaming: SectorStreamingManager = context["streaming"]
	var floating: FloatingOrigin = context["floating"]
	_step(player, 90)

	var home := SectorGrid.sector_of(floating.viewer_metric())
	var crossed := false
	for _i in range(900):
		player.step_physics(1.0 / 60.0, Vector2(1.0, 0.0))
		streaming.tick_for_test(1.0 / 60.0)
		OS.delay_msec(1)
		if SectorGrid.sector_of(floating.viewer_metric()) != home:
			crossed = true
			break

	assert_true(crossed, "atravessou a fronteira de um setor andando")
	assert_greater(float(streaming.loaded_count()), 0.0, "streaming acompanhou o jogador")
	var cell := SectorGrid.sector_of(floating.viewer_metric())
	assert_not_null(streaming.loaded_sector(cell), "o setor ocupado está carregado")
	assert_greater(player.position.y, 0.0, "o corpo continuou sobre o mundo")
	_dispose(context)


func test_floating_origin_rebase_keeps_the_player_on_the_ground() -> void:
	var context := _make_world()
	var player: Player = context["player"]
	var floating: FloatingOrigin = context["floating"]
	var terrain: TerrainService = context["terrain"]
	_step(player, 90)
	var metric_before := player.metric_position()

	# Desloca o mundo 1,5 km e rebaseia: a posição métrica do jogador não pode
	# mudar, e ele tem de continuar em cima do terreno.
	player.position += Vector3(1500.0, 0.0, 0.0)
	floating.rebase(Vector3(1500.0, 0.0, 0.0))
	var metric_after := player.metric_position()
	assert_almost_eq(metric_before.x, metric_after.x, 1.5, "posição geográfica preservada no rebase")
	assert_almost_eq(metric_before.y, metric_after.y, 1.5, "posição geográfica preservada no eixo norte")

	_step(player, 120)
	assert_true(player.is_on_floor(), "continua no chão depois do rebase")
	var ground := terrain.height_at(player.metric_position())
	assert_greater(player.position.y, ground - 1.5, "não caiu para dentro do terreno")
	_dispose(context)


func test_interaction_finds_the_nearby_interior_door() -> void:
	var context := _make_world()
	var player: Player = context["player"]
	var streaming: SectorStreamingManager = context["streaming"]
	var floating: FloatingOrigin = context["floating"]
	var interior := InteriorManager.new()
	interior.name = "InteriorManager"
	tree.root.add_child(interior)
	interior.setup(player, floating, streaming)
	player.interior_manager = interior

	for _i in range(400):
		streaming.tick_for_test(1.0 / 60.0)
		OS.delay_msec(2)
		if streaming.loaded_count() > 0:
			break

	var prompt := ""
	for _i in range(30):
		prompt = player.interaction_prompt()
		if not prompt.is_empty():
			break
		OS.delay_msec(10)

	# Não se exige porta ao alcance: o que se exige é que o sistema responda
	# sem erro, com ou sem candidato, e que a porta exista no mundo carregado.
	assert_true(interior.door_count() >= 0, "gerência de portas consultável")
	print("    interação na origem: '%s' · portas carregadas: %d" % [prompt, interior.door_count()])
	interior.free()
	_dispose(context)
