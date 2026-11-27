extends TestCase

## Floating origin: o rebase não pode alterar a posição métrica do jogador.
## É o invariante que sustenta a precisão em 380 km de mundo — e o único lugar
## onde ele pode ser verificado sem GPU.

func _origin_at(start: Vector2) -> Dictionary:
	var world_root := Node3D.new()
	var actor_root := Node3D.new()
	var viewer := Node3D.new()
	actor_root.add_child(viewer)
	var origin := FloatingOrigin.new()
	origin.setup(world_root, actor_root, viewer, start)
	return {
		"origin": origin,
		"viewer": viewer,
		"world": world_root,
		"actors": actor_root,
	}


func _dispose(ctx: Dictionary) -> void:
	(ctx["origin"] as FloatingOrigin).free()
	(ctx["world"] as Node3D).free()
	(ctx["actors"] as Node3D).free()


func test_rebase_recenters_viewer_without_moving_the_world() -> void:
	var start := Vector2(449536.0, 7999232.0)
	var ctx := _origin_at(start)
	var origin: FloatingOrigin = ctx["origin"]
	var viewer: Node3D = ctx["viewer"]
	viewer.position = Vector3(3000.0, 5.0, -1200.0)
	var metric_before := origin.local_to_metric(viewer.position)

	origin.rebase(Vector3(viewer.position.x, 0.0, viewer.position.z))

	assert_almost_eq(viewer.position.x, 0.0, 1e-6, "viewer volta ao eixo x")
	assert_almost_eq(viewer.position.z, 0.0, 1e-6, "viewer volta ao eixo z")
	assert_almost_eq(viewer.position.y, 5.0, 1e-6, "altura não muda")
	var metric_after := origin.local_to_metric(viewer.position)
	assert_almost_eq(metric_before.x, metric_after.x, 0.01, "leste preservado")
	assert_almost_eq(metric_before.y, metric_after.y, 0.01, "norte preservado")
	_dispose(ctx)


func test_static_and_actor_roots_move_together() -> void:
	var ctx := _origin_at(Vector2(500000.0, 8000000.0))
	var origin: FloatingOrigin = ctx["origin"]
	var world: Node3D = ctx["world"]
	var viewer: Node3D = ctx["viewer"]
	var sector := Node3D.new()
	sector.position = Vector3(100.0, 0.0, -200.0)
	world.add_child(sector)
	viewer.position = Vector3(2600.0, 0.0, 0.0)

	origin.rebase(Vector3(2600.0, 0.0, 0.0))

	assert_almost_eq(sector.position.x, 100.0 - 2600.0, 1e-6, "setor deslocado junto")
	assert_almost_eq(viewer.position.x, 0.0, 1e-6, "jogador centralizado")
	_dispose(ctx)


func test_repeated_rebase_does_not_drift() -> void:
	var start := Vector2(500000.0, 8000000.0)
	var ctx := _origin_at(start)
	var origin: FloatingOrigin = ctx["origin"]
	var viewer: Node3D = ctx["viewer"]
	var expected := start

	for step in range(5):
		viewer.position += Vector3(2100.0, 0.0, -300.0)
		expected += Vector2(2100.0, 300.0)
		var before := origin.local_to_metric(viewer.position)
		origin.rebase(Vector3(viewer.position.x, 0.0, viewer.position.z))
		var after := origin.local_to_metric(viewer.position)
		assert_almost_eq(after.x, before.x, 0.01, "passo %d preserva leste" % step)
		assert_almost_eq(after.y, before.y, 0.01, "passo %d preserva norte" % step)

	assert_almost_eq(origin.local_to_metric(viewer.position).x, expected.x, 0.05, "sem deriva acumulada em leste")
	assert_almost_eq(origin.local_to_metric(viewer.position).y, expected.y, 0.05, "sem deriva acumulada em norte")
	assert_eq(origin.rebase_count, 5, "rebases contabilizados")
	_dispose(ctx)


func test_local_coordinates_stay_small() -> void:
	# Sem floating origin, andar 40 km acumularia coordenada local de 40 km, onde
	# um float de 32 bits já não resolve centímetros.
	var ctx := _origin_at(Vector2(500000.0, 8000000.0))
	var origin: FloatingOrigin = ctx["origin"]
	var viewer: Node3D = ctx["viewer"]
	for step in range(20):
		viewer.position += Vector3(2100.0, 0.0, 0.0)
		origin.rebase(Vector3(viewer.position.x, 0.0, viewer.position.z))
		assert_true(
			absf(viewer.position.x) < FloatingOrigin.REBASE_THRESHOLD + 1.0,
			"coordenada local contida no passo %d (%.1f m)" % [step, viewer.position.x]
		)
	_dispose(ctx)
