extends TestCase

## Vegetação e mobiliário urbano: nascem derivados da geometria da rua, nunca no
## asfalto e nunca dentro de uma parede.

const DENSITY := 0.85


func _grid_segments() -> Array:
	# Duas ruas cruzadas mais dois miolos de quadra: dá esquina, calçada, área
	# livre e lote — tudo que a distribuição precisa considerar.
	var segments: Array = [
		{"a": Vector2(-200.0, 0.0), "b": Vector2(200.0, 0.0), "width": 12.0, "road_class": WorldSchema.ROAD_ARTERIAL, "id": "h"},
		{"a": Vector2(0.0, -200.0), "b": Vector2(0.0, 200.0), "width": 9.0, "road_class": WorldSchema.ROAD_COLLECTOR, "id": "v"},
		{"a": Vector2(-200.0, 140.0), "b": Vector2(-60.0, 140.0), "width": 6.0, "road_class": WorldSchema.ROAD_LOCAL, "id": "l1"},
		{"a": Vector2(60.0, 140.0), "b": Vector2(200.0, 140.0), "width": 6.0, "road_class": WorldSchema.ROAD_LOCAL, "id": "l2"},
		{"a": Vector2(-200.0, -140.0), "b": Vector2(-60.0, -140.0), "width": 6.0, "road_class": WorldSchema.ROAD_LOCAL, "id": "l3"},
		{"a": Vector2(60.0, -140.0), "b": Vector2(200.0, -140.0), "width": 6.0, "road_class": WorldSchema.ROAD_LOCAL, "id": "l4"},
	]
	var corners := [
		Vector2(-200.0, -200.0), Vector2(200.0, -200.0), Vector2(200.0, 200.0), Vector2(-200.0, 200.0),
	]
	for i in range(4):
		segments.append({
			"a": corners[i],
			"b": corners[(i + 1) % 4],
			"width": 9.0,
			"road_class": WorldSchema.ROAD_COLLECTOR,
			"id": "ring%d" % i,
		})
	return segments


func _setup() -> Dictionary:
	var network := RoadNetwork.from_segments(_grid_segments())
	var config := UrbanConfig.new()
	var rect := Rect2(Vector2(-200.0, -200.0), Vector2(400.0, 400.0))
	var blocks := UrbanBlockBuilder.build(network, config, rect)
	var parcels: Array = []
	for block in blocks:
		for parcel in ParcelSplitter.split(block, network, config, 20170):
			parcel["block_id"] = str((block as Dictionary)["id"])
			parcels.append(parcel)

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

	var prop_context := {
		"network": network,
		"blocks": blocks,
		"parcels": parcels,
		"buildings": buildings,
		"config": config,
		"seed_value": 20170,
		"coord": Vector2i(878, 15621),
		"rect": rect,
		"open_spaces": [],
	}
	var props := UrbanProps.plan(prop_context)
	var vegetation := UrbanVegetation.plan({
		"network": network,
		"blocks": blocks,
		"parcels": parcels,
		"buildings": buildings,
		"config": config,
		"seed_value": 20170,
		"coord": Vector2i(878, 15621),
		"rect": rect,
		"barriers": [],
		"open_spaces": [],
		"props": props,
	})
	return {
		"network": network,
		"config": config,
		"rect": rect,
		"blocks": blocks,
		"parcels": parcels,
		"buildings": buildings,
		"props": props,
		"vegetation": vegetation,
	}


func test_street_furniture_is_planned() -> void:
	var setup := _setup()
	var props: Dictionary = setup["props"]
	var total := 0
	for key in props.keys():
		total += (props[key] as Array).size()
	assert_greater(float(total), 0.0, "mobiliário planejado")
	assert_greater(float((props.get(UrbanSchema.PROP_LIGHT, []) as Array).size()), 0.0, "postes de iluminação")


func test_street_furniture_stays_off_the_pavement() -> void:
	var setup := _setup()
	var problems := UrbanProps.validate(setup["props"], setup["network"], setup["rect"])
	for problem in problems:
		fail(problem)
	assert_eq(problems.size(), 0, "mobiliário nunca sobre a pista nem fora do setor")


func test_traffic_signals_only_at_real_crossings() -> void:
	var setup := _setup()
	var network: RoadNetwork = setup["network"]
	var signals: Array = (setup["props"] as Dictionary).get(UrbanSchema.PROP_TRAFFIC_LIGHT, [])
	assert_greater(float(signals.size()), 0.0, "há semáforo no cruzamento arterial")
	for raw in signals:
		var point: Vector2 = (raw as Dictionary)["pos"]
		assert_greater(network.clearance_to_road(point) + 0.01, 0.0, "semáforo fora do asfalto")


func test_vegetation_avoids_pavement_and_buildings() -> void:
	var setup := _setup()
	var network: RoadNetwork = setup["network"]
	var vegetation: Dictionary = setup["vegetation"]
	var total := 0
	for key in ["trees", "bushes", "grass"]:
		total += (vegetation.get(key, []) as Array).size()
	assert_greater(float(total), 0.0, "vegetação distribuída")

	for raw in vegetation.get("trees", []):
		var point: Vector2 = (raw as Dictionary)["pos"]
		assert_greater(network.clearance_to_road(point) + 0.01, 0.0, "árvore fora do asfalto")
	for raw in setup["buildings"]:
		var building: Dictionary = raw
		var footprint: PackedVector2Array = building["footprint"]
		for entry in vegetation.get("trees", []):
			var point: Vector2 = (entry as Dictionary)["pos"]
			if PolygonUtils.point_in_polygon(point, footprint):
				fail("árvore dentro de uma edificação")
				break


func test_distribution_is_deterministic() -> void:
	var first := _setup()
	var second := _setup()
	var props_a: Dictionary = first["props"]
	var props_b: Dictionary = second["props"]
	for key in props_a.keys():
		assert_eq((props_a[key] as Array).size(), (props_b[key] as Array).size(), "mesma quantidade de %s" % str(key))
	var trees_a: Array = (first["vegetation"] as Dictionary).get("trees", [])
	var trees_b: Array = (second["vegetation"] as Dictionary).get("trees", [])
	assert_eq(trees_a.size(), trees_b.size(), "mesma quantidade de árvores")
	for i in range(mini(trees_a.size(), trees_b.size())):
		var point_a: Vector2 = (trees_a[i] as Dictionary)["pos"]
		var point_b: Vector2 = (trees_b[i] as Dictionary)["pos"]
		assert_almost_eq(point_a.x, point_b.x, 0.001, "mesma posição de árvore")


func test_density_multiplier_reduces_content() -> void:
	var setup := _setup()
	var config: UrbanConfig = setup["config"]
	var network: RoadNetwork = setup["network"]
	var sparse := UrbanConfig.new()
	sparse.tree_density = 0.1
	sparse.prop_density = 0.1
	var sparse_props := UrbanProps.plan({
		"network": network,
		"blocks": setup["blocks"],
		"parcels": setup["parcels"],
		"buildings": setup["buildings"],
		"config": sparse,
		"seed_value": 20170,
		"coord": Vector2i(878, 15621),
		"rect": setup["rect"],
		"open_spaces": [],
	})
	var full_total := 0
	for key in (setup["props"] as Dictionary).keys():
		full_total += ((setup["props"] as Dictionary)[key] as Array).size()
	var sparse_total := 0
	for key in sparse_props.keys():
		sparse_total += (sparse_props[key] as Array).size()
	assert_true(sparse_total < full_total, "densidade menor rende menos mobiliário (%d < %d)" % [sparse_total, full_total])
	assert_greater(config.tree_density, 0.0, "configuração de referência com vegetação")
