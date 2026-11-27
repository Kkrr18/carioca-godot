extends TestCase

## Hierarquia de setores: se a grade estiver errada, o streaming carrega o lugar
## errado e a chave no disco não corresponde ao lugar.

func test_sector_of_and_origin_are_inverse() -> void:
	var samples := [
		Vector2(300000.0, 8000000.0),
		Vector2(300511.9, 8000511.9),
		Vector2(300512.0, 8000512.0),
		Vector2(-10.0, -10.0),
	]
	for sample in samples:
		var coord := SectorGrid.sector_of(sample)
		var origin := SectorGrid.sector_origin(coord)
		assert_almost_eq(origin.x, float(coord.x) * SectorGrid.SECTOR_SIZE, 1e-6, "origem x")
		assert_almost_eq(origin.y, float(coord.y) * SectorGrid.SECTOR_SIZE, 1e-6, "origem y")
		assert_true(sample.x >= origin.x and sample.x < origin.x + SectorGrid.SECTOR_SIZE, "ponto dentro da faixa x")
		assert_true(sample.y >= origin.y and sample.y < origin.y + SectorGrid.SECTOR_SIZE, "ponto dentro da faixa y")


func test_key_round_trip() -> void:
	var coords := [Vector2i(390, 15433), Vector2i(-4, 7), Vector2i(0, 0)]
	for coord in coords:
		var parsed := SectorGrid.parse_key(SectorGrid.key(coord))
		assert_eq(parsed, coord, "chave de setor ida e volta")


func test_radius_counts() -> void:
	assert_array_size(SectorGrid.sectors_in_radius(Vector2i.ZERO, 0), 1, "raio 0")
	assert_array_size(SectorGrid.sectors_in_radius(Vector2i.ZERO, 1), 9, "raio 1")
	assert_array_size(SectorGrid.sectors_in_radius(Vector2i.ZERO, 2), 21, "raio 2")
	assert_array_size(SectorGrid.sectors_in_radius(Vector2i.ZERO, 3), 37, "raio 3")


func test_radius_is_sorted_by_distance() -> void:
	var center := Vector2i(100, 200)
	var coords := SectorGrid.sectors_in_radius(center, 3)
	assert_eq(coords[0], center, "primeiro setor é o central")
	var previous := -1.0
	for coord in coords:
		var distance := SectorGrid.distance_sectors(coord, center)
		assert_true(distance >= previous, "ordem por distância")
		previous = distance


func test_sector_contains() -> void:
	var coord := Vector2i(12, 34)
	assert_true(SectorGrid.contains(coord, SectorGrid.sector_center(coord)), "centro pertence ao setor")
	assert_false(SectorGrid.contains(coord, SectorGrid.sector_center(coord) + Vector2(600.0, 0.0)), "ponto a 600 m não pertence")


func test_micro_grid_stays_inside_sector() -> void:
	var metric := Vector2(300000.0 + 130.0, 8000000.0 + 470.0)
	var index := SectorGrid.micro_index_in_sector(metric)
	assert_true(index.x >= 0 and index.x < 6, "índice micro x dentro de 0..5")
	assert_true(index.y >= 0 and index.y < 6, "índice micro y dentro de 0..5")


func test_tile_groups_sectors() -> void:
	var coord := Vector2i(390, 15433)
	var tile := SectorGrid.tile_of_sector(coord)
	var rect := SectorGrid.tile_rect(tile)
	assert_true(rect.has_point(SectorGrid.sector_center(coord)), "centro do setor dentro do tile")
