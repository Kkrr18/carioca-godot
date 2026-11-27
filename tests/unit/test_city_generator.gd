extends TestCase

## Gerador urbano: determinismo, coerência de coordenadas e conteúdo mínimo.
##
## O setor de teste nunca é um índice fixo no código — é sempre o setor que
## contém o centro de Guapimirim. Índice fixo apodrece quando a projeção muda.

func _coord() -> Vector2i:
	MunicipalityIndex.ensure_loaded()
	return SectorGrid.sector_of(MunicipalityIndex.center_of("GUAPI"))


func test_payload_is_deterministic() -> void:
	var coord := _coord()
	var first := CityGenerator.build_payload(coord, 20170)
	var second := CityGenerator.build_payload(coord, 20170)
	assert_eq(JSON.stringify(first), JSON.stringify(second), "payload idêntico entre chamadas")


func test_payload_has_required_fields() -> void:
	var payload := CityGenerator.build_payload(_coord(), 20170)
	for field in ["version", "grid", "origin", "id", "roads", "buildings", "trees"]:
		assert_true(payload.has(field), "campo %s presente" % field)
	assert_eq(int(payload["version"]), WorldSchema.SECTOR_SCHEMA_VERSION, "versão do schema")


func test_origin_matches_grid() -> void:
	var coord := _coord()
	var payload := CityGenerator.build_payload(coord, 20170)
	var origin: Array = payload["origin"]
	var expected := SectorGrid.sector_origin(coord)
	assert_almost_eq(float(origin[0]), expected.x, 1e-6, "origem x do payload")
	assert_almost_eq(float(origin[1]), expected.y, 1e-6, "origem y do payload")


func test_urban_sector_has_roads_and_buildings() -> void:
	var payload := CityGenerator.build_payload(_coord(), 20170)
	assert_true(bool(payload["urban"]), "setor central é urbano")
	assert_greater(float((payload["roads"] as Array).size()), 0.0, "setor urbano tem vias")
	assert_greater(float((payload["buildings"] as Array).size()), 0.0, "setor urbano tem edificações")


func test_road_points_are_local_to_sector() -> void:
	var payload := CityGenerator.build_payload(_coord(), 20170)
	var limit := SectorGrid.SECTOR_SIZE + 1.0
	var roads: Array = payload["roads"]
	for raw in roads:
		var road: Dictionary = raw
		var points: Array = road["points"]
		for point in points:
			var local := Vector2(float(point[0]), float(point[1]))
			assert_true(absf(local.x) <= limit, "coordenada local x dentro do setor")
			assert_true(absf(local.y) <= limit, "coordenada local y dentro do setor")


func test_buildings_have_doors_and_sane_heights() -> void:
	var payload := CityGenerator.build_payload(_coord(), 20170)
	var buildings: Array = payload["buildings"]
	for raw in buildings:
		var building: Dictionary = raw
		assert_true(building.has("door"), "edificação com porta")
		var height := float(building["height"])
		assert_true(height >= 2.0 and height <= 260.0, "altura plausível: %.1f" % height)
		var size: Array = building["size"]
		assert_greater(float(size[0]), 0.0, "testada positiva")


## O teste que sustenta o mundo inteiro: a chave do nó carrega a posição global.
## Se isto passar, dois setores vizinhos nunca discordam de onde uma via termina.
func test_node_keys_match_global_positions() -> void:
	var coord := _coord()
	var payload := CityGenerator.build_payload(coord, 20170)
	var origin := SectorGrid.sector_origin(coord)
	var roads: Array = payload["roads"]
	var checked := 0
	for raw in roads:
		var road: Dictionary = raw
		var nodes: Array = road.get("nodes", [])
		var points: Array = road.get("points", [])
		if nodes.size() < 2 or points.size() < 2:
			continue
		for index in range(2):
			var parts := str(nodes[index]).split(":")
			if parts.size() != 3:
				continue
			var metric := CityGenerator.node_metric(parts[0], int(parts[1]), int(parts[2]), 20170)
			var expected := Vector2(metric.x - origin.x, -(metric.y - origin.y))
			var actual := Vector2(float(points[index][0]), float(points[index][1]))
			assert_true(actual.distance_to(expected) < 0.05, "nó %s corresponde ao ponto local" % str(nodes[index]))
			checked += 1
	assert_greater(float(checked), 0.0, "nós verificados")


func test_node_keys_repeat_along_a_lattice() -> void:
	var payload := CityGenerator.build_payload(_coord(), 20170)
	var roads: Array = payload["roads"]
	var references := 0
	var distinct := {}
	for raw in roads:
		var road: Dictionary = raw
		for node in road.get("nodes", []):
			references += 1
			distinct[node] = true
	assert_greater(float(references), 0.0, "referências de nó")
	assert_true(distinct.size() < references, "nós são compartilhados por segmentos vizinhos")


func test_different_seed_changes_layout() -> void:
	var coord := _coord()
	var a := CityGenerator.build_payload(coord, 20170)
	var b := CityGenerator.build_payload(coord, 999)
	assert_not_eq(JSON.stringify(a), JSON.stringify(b), "semente diferente muda o arranjo")
