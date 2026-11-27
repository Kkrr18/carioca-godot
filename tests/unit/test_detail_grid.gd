extends TestCase

## Célula de detalhe (128 m): precisa subdividir o bloco de 512 m exatamente, sem
## faixa irregular e sem sobreposição. Se ela estiver errada, a distância de LOD
## e qualquer camada de detalhe futuro consultam o lugar errado.

func test_detail_round_trip() -> void:
	var metric := Vector2(300123.0, 8000456.0)
	var cell := SectorGrid.detail_of(metric)
	var sector := SectorGrid.sector_of(metric)
	assert_eq(SectorGrid.sector_of_detail(cell), sector, "célula de detalhe pertence ao bloco")
	var index := SectorGrid.detail_index_in_sector(metric)
	assert_true(index.x >= 0 and index.x < 4, "índice x dentro do bloco")
	assert_true(index.y >= 0 and index.y < 4, "índice y dentro do bloco")
	assert_eq(SectorGrid.detail_cell_of_sector(index, sector), cell, "índice + bloco reconstrói a célula")


func test_detail_cells_tile_the_block() -> void:
	var sector := Vector2i(600, 15600)
	var cells := SectorGrid.detail_cells_in_sector(sector)
	assert_array_size(cells, 16, "4x4 células de detalhe por bloco")
	var covered := 0.0
	for cell in cells:
		assert_true(SectorGrid.sector_of_detail(cell) == sector, "célula não escapa do bloco")
		covered += SectorGrid.detail_rect(cell).get_area()
	var expected := SectorGrid.SECTOR_SIZE * SectorGrid.SECTOR_SIZE
	assert_almost_eq(covered, expected, 1e-3, "área das células igual à do bloco")


func test_detail_origin_is_pure() -> void:
	var metric := Vector2(-1500.0, 250.0)
	var cell := SectorGrid.detail_of(metric)
	var origin := SectorGrid.detail_origin(cell)
	assert_true(metric.x >= origin.x and metric.x < origin.x + SectorGrid.DETAIL_CELL_SIZE, "faixa em leste")
	assert_true(metric.y >= origin.y and metric.y < origin.y + SectorGrid.DETAIL_CELL_SIZE, "faixa em norte")


func test_detail_cells_within_radius() -> void:
	var sector := Vector2i(600, 15600)
	var center := SectorGrid.sector_center(sector)
	var near := SectorGrid.detail_cells_within(sector, center, 150.0)
	assert_array_size(near, 4, "quatro células cabem num raio de 150 m do centro")
	assert_true(near.size() < 16, "nem todas as células estão no raio")


func test_nearest_point_uses_the_border() -> void:
	var coord := Vector2i(10, 20)
	var center := SectorGrid.sector_center(coord)
	assert_almost_eq(SectorGrid.distance_to_sector_m(coord, center), 0.0, 1e-9, "ponto dentro tem distância zero")
	var outside := center + Vector2(1000.0, 0.0)
	var nearest := SectorGrid.nearest_point_in_sector(coord, outside)
	assert_almost_eq(nearest.x, SectorGrid.sector_origin(coord).x + SectorGrid.SECTOR_SIZE, 1e-6, "ponto na borda leste")
	assert_almost_eq(
		SectorGrid.distance_to_sector_m(coord, outside),
		1000.0 - SectorGrid.SECTOR_SIZE * 0.5,
		1e-6,
		"distância medida até a borda, não até o centro"
	)
