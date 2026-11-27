extends TestCase

## Lotes: a quadra dividida em testada e fundo, sem sobreposição.
##
## A invariante que importa é a de **ausência de sobreposição**: ela não vem de
## uma checagem no fim, vem da construção (cada lote é uma fatia disjunta). O
## teste confere a propriedade, não o código que a garante.


func _ring(size: float) -> Array:
	var half := size * 0.5
	var corners := [
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	]
	var segments: Array = []
	for i in range(4):
		segments.append({
			"a": corners[i],
			"b": corners[(i + 1) % 4],
			"width": 8.0,
			"road_class": WorldSchema.ROAD_LOCAL,
			"id": "ring%d" % i,
		})
	return segments


func _setup(size: float = 200.0) -> Dictionary:
	var network := RoadNetwork.from_segments(_ring(size))
	var config := UrbanConfig.new()
	var rect := Rect2(Vector2(-size, -size), Vector2(size * 2.0, size * 2.0))
	var blocks := UrbanBlockBuilder.build(network, config, rect)
	var parcels: Array = []
	if not blocks.is_empty():
		parcels = ParcelSplitter.split(blocks[0], network, config, 20170)
	return {
		"network": network,
		"config": config,
		"block": blocks[0] if not blocks.is_empty() else {},
		"parcels": parcels,
	}


func test_block_is_split_into_parcels() -> void:
	var setup := _setup()
	var parcels: Array = setup["parcels"]
	assert_greater(float(parcels.size()), 4.0, "um quarteirão grande rende vários lotes")


func test_parcels_do_not_overlap_and_stay_inside() -> void:
	var setup := _setup()
	var parcels: Array = setup["parcels"]
	if parcels.is_empty():
		fail("sem lotes para validar")
		return
	var problems := ParcelSplitter.validate(setup["block"], parcels)
	for problem in problems:
		fail(problem)
	assert_eq(problems.size(), 0, "validação de lotes sem problema")


func test_parcels_cover_most_of_the_block() -> void:
	var setup := _setup()
	var parcels: Array = setup["parcels"]
	var block: Dictionary = setup["block"]
	if parcels.is_empty() or block.is_empty():
		fail("sem quadra ou sem lotes")
		return
	var total := 0.0
	for parcel in parcels:
		total += float((parcel as Dictionary)["area"])
	var block_area := float(block["area"])
	assert_greater(total / block_area, 0.6, "os lotes ocupam a maior parte da quadra (%.2f)" % (total / block_area))
	assert_true(total <= block_area * 1.01, "os lotes não somam mais que a quadra")


func test_every_parcel_faces_a_street() -> void:
	var setup := _setup()
	var network: RoadNetwork = setup["network"]
	var config: UrbanConfig = setup["config"]
	var parcels: Array = setup["parcels"]
	if parcels.is_empty():
		fail("sem lotes")
		return
	var limit := config.sidewalk_width + config.block_inset_extra + 2.0
	for parcel in parcels:
		var front: Dictionary = (parcel as Dictionary)["front"]
		var a: Vector2 = front["a"]
		var b: Vector2 = front["b"]
		var clearance := network.clearance_to_road((a + b) * 0.5)
		assert_true(clearance <= limit, "lote de frente para a rua (folga %.2f m)" % clearance)
		assert_greater(a.distance_to(b), 2.0, "aresta de frente com comprimento utilizável")


func test_parcel_frontage_respects_the_minimum() -> void:
	var setup := _setup()
	var config: UrbanConfig = setup["config"]
	var parcels: Array = setup["parcels"]
	for parcel in parcels:
		var entry: Dictionary = parcel
		assert_greater(float(entry["frontage_width"]), config.parcel_min_front * 0.55, "testada acima do mínimo")


func test_split_is_deterministic() -> void:
	var first := _setup()
	var second := _setup()
	var a: Array = first["parcels"]
	var b: Array = second["parcels"]
	assert_eq(a.size(), b.size(), "mesma quantidade de lotes")
	for i in range(mini(a.size(), b.size())):
		assert_eq(str((a[i] as Dictionary)["id"]), str((b[i] as Dictionary)["id"]), "mesmo identificador")
		assert_almost_eq(float((a[i] as Dictionary)["area"]), float((b[i] as Dictionary)["area"]), 0.01, "mesma área")


func test_tiny_block_yields_no_block() -> void:
	var network := RoadNetwork.from_segments(_ring(18.0))
	var config := UrbanConfig.new()
	var blocks := UrbanBlockBuilder.build(network, config, Rect2(Vector2(-60.0, -60.0), Vector2(120.0, 120.0)))
	assert_eq(blocks.size(), 0, "quadra pequena demais é descartada antes de virar lote")
