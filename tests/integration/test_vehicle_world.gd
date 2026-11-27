extends TestCase

## O carro dentro do mundo: terreno, floating origin, streaming e clima.
##
## O que só aparece com mundo montado: nascer na altura certa, sobreviver ao
## rebase sem perder a posição geográfica, não pertencer a setor nenhum (por
## isso o descarregamento nunca leva o carro embora) e seguir o preset.

func _make_world() -> Dictionary:
	MunicipalityIndex.ensure_loaded()
	var settings := CariocaSettings.get_instance()
	var terrain := TerrainService.new(settings.world_seed)
	var world_root := Node3D.new()
	tree.root.add_child(world_root)
	var actor_root := Node3D.new()
	tree.root.add_child(actor_root)
	var player := Player.new()
	actor_root.add_child(player)
	var start := MunicipalityIndex.center_of("GUAPI")
	var floating := FloatingOrigin.new()
	tree.root.add_child(floating)
	floating.setup(world_root, actor_root, player, start)
	player.position = Vector3(0.0, terrain.height_at(start) + 2.0, 0.0)
	player.floating = floating
	player.terrain = terrain
	var manager := VehicleManager.new()
	tree.root.add_child(manager)
	manager.setup(terrain, floating, actor_root)
	return {
		"terrain": terrain,
		"world": world_root,
		"actors": actor_root,
		"player": player,
		"floating": floating,
		"manager": manager,
		"start": start,
	}


func _dispose(context: Dictionary) -> void:
	(context["manager"] as Node).free()
	(context["floating"] as Node).free()
	(context["world"] as Node).free()
	(context["actors"] as Node).free()


func test_vehicle_spawns_at_terrain_height() -> void:
	var context := _make_world()
	var terrain: TerrainService = context["terrain"]
	var manager: VehicleManager = context["manager"]
	var start: Vector2 = context["start"]
	var vehicle := manager.spawn_at(start)
	assert_not_null(vehicle, "o carro nasce")
	assert_almost_eq(vehicle.position.y, terrain.height_at(start) + 1.4, 0.01, "nasce 1,4 m acima do terreno")
	assert_almost_eq(vehicle.metric_position().x, start.x, 0.01, "posição métrica X coincide")
	assert_almost_eq(vehicle.metric_position().y, start.y, 0.01, "posição métrica norte coincide")
	assert_eq(vehicle.get_parent(), context["actors"], "o carro é filho da raiz de atores")
	_dispose(context)


func test_rebase_keeps_the_vehicle_on_its_geographic_spot() -> void:
	var context := _make_world()
	var floating: FloatingOrigin = context["floating"]
	var manager: VehicleManager = context["manager"]
	var start: Vector2 = context["start"]
	var vehicle := manager.spawn_at(start)
	var metric_before := vehicle.metric_position()
	vehicle.position += Vector3(1500.0, 0.0, 0.0)
	floating.rebase(Vector3(1500.0, 0.0, 0.0))
	var metric_after := vehicle.metric_position()
	assert_almost_eq(metric_before.x, metric_after.x, 0.02, "o rebase não move o carro na geografia (X)")
	assert_almost_eq(metric_before.y, metric_after.y, 0.02, "o rebase não move o carro na geografia (norte)")
	_dispose(context)


func test_streaming_never_owns_the_vehicle() -> void:
	var context := _make_world()
	var floating: FloatingOrigin = context["floating"]
	var manager: VehicleManager = context["manager"]
	var player: Player = context["player"]
	var start: Vector2 = context["start"]
	var vehicle := manager.spawn_at(start)
	var streaming := SectorStreamingManager.new()
	streaming.sector_parent = context["world"]
	streaming.setup(context["terrain"], floating, player)
	tree.root.add_child(streaming)

	var loaded := false
	for _i in range(400):
		streaming.tick_for_test(1.0 / 60.0)
		OS.delay_msec(2)
		if streaming.loaded_count() > 0:
			loaded = true
			break
	assert_true(loaded, "o streaming carregou setores")

	streaming.rebuild_all()
	assert_true(is_instance_valid(vehicle), "o descarregamento de setores não leva o carro")
	assert_eq(vehicle.get_parent(), context["actors"], "o carro continua na raiz de atores")
	assert_eq(vehicle.driver, null, "o carro continua sem motorista")
	streaming.free()
	_dispose(context)


func test_weather_wetness_reaches_the_wheels() -> void:
	var context := _make_world()
	var manager: VehicleManager = context["manager"]
	var vehicle := manager.spawn_at(context["start"])
	manager.set_wetness(0.5)
	assert_almost_eq(vehicle.wetness, 0.5, 1e-6, "a chuva chega ao carro")
	var expected: float = vehicle.profile.grip_for(0.5)
	assert_almost_eq(vehicle.wheels[2].wheel_friction_slip, expected, 1e-4, "a traseira segue a aderência molhada")
	assert_almost_eq(vehicle.wheels[0].wheel_friction_slip, expected, 1e-4, "a dianteira também")
	_dispose(context)


func test_quality_preset_flows_through_the_manager() -> void:
	var context := _make_world()
	var manager: VehicleManager = context["manager"]
	var vehicle := manager.spawn_at(context["start"])
	var preset := QualityProfile.get_preset("mobile")
	manager.apply_preset(preset)
	var expected := DrivingProfile.from_preset(preset)
	assert_almost_eq(vehicle.profile.engine_force, expected.engine_force, 1e-6, "força do motor vem do preset")
	assert_almost_eq(vehicle.profile.max_speed, expected.max_speed, 1e-6, "teto vem do preset")
	assert_almost_eq(vehicle.mass, expected.mass, 1e-3, "massa acompanha o perfil")
	_dispose(context)


func test_multiple_vehicles_respect_the_cap() -> void:
	var context := _make_world()
	var manager: VehicleManager = context["manager"]
	manager.max_vehicles = 3
	var first := manager.spawn_at(context["start"])
	assert_not_null(first, "o primeiro carro nasce")
	var last: Vehicle = null
	for i in range(3):
		last = manager.spawn_at(context["start"] + Vector2(float(i) * 3.0, 0.0))
	assert_not_null(last, "o teto ainda admite o último")
	assert_eq(manager.count(), 3, "a frota respeita o teto")
	var overflow := manager.spawn_at(context["start"])
	assert_eq(overflow, null, "o carro extra é recusado")
	_dispose(context)
