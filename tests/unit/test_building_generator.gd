extends TestCase

## Edificações: cabem no lote, não invadem a rua, variam de tipologia e são
## determinísticas.

const DENSITY := 0.9


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
			"road_class": WorldSchema.ROAD_COLLECTOR,
			"id": "ring%d" % i,
		})
	return segments


func _setup(size: float = 260.0) -> Dictionary:
	var network := RoadNetwork.from_segments(_ring(size))
	var config := UrbanConfig.new()
	var rect := Rect2(Vector2(-size, -size), Vector2(size * 2.0, size * 2.0))
	var blocks := UrbanBlockBuilder.build(network, config, rect)
	var parcels: Array = []
	if not blocks.is_empty():
		parcels = ParcelSplitter.split(blocks[0], network, config, 20170)
	var context := {
		"config": config,
		"network": network,
		"density": DENSITY,
		"seed_value": 20170,
		"sector_id": "RJ_METRO_GUAPI_TESTE",
	}
	var buildings: Array = []
	for parcel in parcels:
		var building := BuildingGenerator.generate(parcel, context)
		if not building.is_empty():
			buildings.append(building)
	return {"network": network, "config": config, "parcels": parcels, "buildings": buildings}


func test_most_parcels_get_a_building() -> void:
	var setup := _setup()
	var parcels: Array = setup["parcels"]
	var buildings: Array = setup["buildings"]
	assert_greater(float(parcels.size()), 4.0, "há lotes")
	assert_greater(float(buildings.size()), 0.0, "há edificações")
	assert_greater(float(buildings.size()) / float(maxi(parcels.size(), 1)), 0.5, "a maioria dos lotes é ocupada")


func test_buildings_fit_inside_their_parcel() -> void:
	var setup := _setup()
	var parcels: Array = setup["parcels"]
	for parcel in parcels:
		var context := {
			"config": setup["config"],
			"network": setup["network"],
			"density": DENSITY,
			"seed_value": 20170,
			"sector_id": "RJ_METRO_GUAPI_TESTE",
		}
		var building := BuildingGenerator.generate(parcel, context)
		if building.is_empty():
			continue
		var footprint: PackedVector2Array = building["footprint"]
		var poly: PackedVector2Array = (parcel as Dictionary)["poly"]
		for point in footprint:
			var distance := PolygonUtils.distance_to_polygon(point, poly)
			assert_true(distance <= 0.2, "vértice da pegada dentro do lote (folga %.3f m)" % distance)


func test_buildings_never_sit_on_the_street() -> void:
	var setup := _setup()
	var network: RoadNetwork = setup["network"]
	var config: UrbanConfig = setup["config"]
	for raw in setup["buildings"]:
		var building: Dictionary = raw
		var footprint: PackedVector2Array = building["footprint"]
		for point in footprint:
			assert_greater(network.clearance_to_road(point) + 0.01, 0.0, "nenhum vértice sobre a pista")
		assert_greater(float(building["height"]), 2.0, "altura utilizável")
		assert_true(int(building["levels"]) >= 1, "pelo menos um pavimento")


func test_typologies_vary() -> void:
	var setup := _setup()
	var distinct := {}
	for raw in setup["buildings"]:
		distinct[str((raw as Dictionary)["typology"])] = true
	assert_greater(float(distinct.size()), 2.0, "ao menos três tipologias diferentes (%d)" % distinct.size())
	for typology in distinct.keys():
		assert_true(UrbanSchema.is_typology(str(typology)), "tipologia declarada no vocabulário: %s" % str(typology))


func test_modules_are_planned_for_facades() -> void:
	var setup := _setup()
	var with_windows := 0
	for raw in setup["buildings"]:
		var building: Dictionary = raw
		var modules: Array = building["modules"]
		for module in modules:
			if str((module as Dictionary)["type"]) == UrbanSchema.MODULE_WINDOW:
				with_windows += 1
		assert_true(building.has("roof"), "cobertura definida")
		assert_true(building.has("palette"), "paleta definida")
	assert_greater(float(with_windows), 0.0, "janelas planejadas em alguma fachada")


func test_generation_is_deterministic() -> void:
	var first := _setup()
	var second := _setup()
	var a: Array = first["buildings"]
	var b: Array = second["buildings"]
	assert_eq(a.size(), b.size(), "mesma quantidade de edificações")
	for i in range(mini(a.size(), b.size())):
		var ba: Dictionary = a[i]
		var bb: Dictionary = b[i]
		assert_eq(str(ba["typology"]), str(bb["typology"]), "mesma tipologia")
		assert_eq(int(ba["levels"]), int(bb["levels"]), "mesmo número de pavimentos")
		assert_almost_eq(float(ba["height"]), float(bb["height"]), 0.001, "mesma altura")


func test_landmark_massing_is_marked_as_estimate() -> void:
	var config := UrbanConfig.new()
	var landmark := {
		"id": "teste",
		"name": "Teste",
		"confidence": UrbanSchema.CONFIDENCE_LOW,
		"point": Vector2(1234.0, 5678.0),
		"generate": {"type": "building", "footprint_m": [30.0, 12.0], "levels": 2, "height_m": 7.5},
	}
	var building := BuildingGenerator.generate_landmark(landmark, config, "RJ_TESTE", 20170)
	assert_false(building.is_empty(), "massa de referência gerada")
	if building.is_empty():
		return
	assert_eq(str(building["landmark_id"]), "teste", "identificador do ponto de referência")
	assert_eq(str(building["confidence"]), UrbanSchema.CONFIDENCE_LOW, "confiança propagada para o registro")
	assert_almost_eq((building["footprint"] as PackedVector2Array).size(), 4.0, 0.001, "pegada é um retângulo de quatro cantos")
