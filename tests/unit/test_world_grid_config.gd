extends TestCase

## Configuração da grade: as dimensões precisam ser configuráveis de um lugar só
## e voltar ao padrão sem deixar resíduo — outros testes dependem disso.

func test_defaults_are_the_shipped_grid() -> void:
	assert_almost_eq(WorldGridConfig.STREAM_CELL_SIZE, 512.0, 1e-9, "bloco de streaming de 512 m")
	assert_almost_eq(WorldGridConfig.DETAIL_CELL_SIZE, 128.0, 1e-9, "célula de detalhe de 128 m")
	assert_almost_eq(WorldGridConfig.REGION_TILE_SIZE, 2000.0, 1e-9, "tile regional de 2 km")
	var values := WorldGridConfig.defaults()
	assert_almost_eq(float(values["stream_cell"]), 512.0, 1e-9, "dicionário de padrões")


func test_current_grid_matches_defaults() -> void:
	assert_almost_eq(SectorGrid.SECTOR_SIZE, 512.0, 1e-9, "grade em uso começa no padrão")
	assert_almost_eq(SectorGrid.DETAIL_CELL_SIZE, 128.0, 1e-9, "detalhe em uso começa no padrão")


func test_geometry_is_configurable() -> void:
	assert_true(WorldGridConfig.apply_geometry(1024.0, 128.0, 4096.0, 64.0), "geometria válida aplicada")
	assert_almost_eq(SectorGrid.SECTOR_SIZE, 1024.0, 1e-9, "bloco alterado")
	assert_almost_eq(SectorGrid.DETAIL_CELL_SIZE, 128.0, 1e-9, "detalhe alterado")
	assert_eq(SectorGrid.detail_cells_per_sector(), 8, "detalhe acompanha o bloco")
	assert_eq(SectorGrid.SECTORS_PER_TILE, 4, "blocos por tile regional recalculado")
	assert_true(WorldGridConfig.restore_defaults(), "padrões restaurados")
	assert_almost_eq(SectorGrid.SECTOR_SIZE, 512.0, 1e-9, "bloco de volta ao padrão")
	assert_eq(SectorGrid.detail_cells_per_sector(), 4, "detalhe de volta ao padrão")


func test_invalid_geometry_is_refused() -> void:
	assert_false(WorldGridConfig.apply_geometry(-1.0, 128.0, 2000.0, 100.0), "dimensão negativa recusada")
	assert_false(WorldGridConfig.apply_geometry(128.0, 512.0, 2000.0, 100.0), "detalhe maior que o bloco recusado")
	assert_almost_eq(SectorGrid.SECTOR_SIZE, 512.0, 1e-9, "grade intacta depois da recusa")


func test_radius_accounting() -> void:
	assert_eq(WorldGridConfig.cells_for_radius(0), 1, "raio zero é um bloco")
	assert_eq(WorldGridConfig.cells_for_radius(1), 9, "raio um são nove blocos")
	assert_eq(WorldGridConfig.cells_for_radius(2), 21, "raio dois são vinte e um blocos")
	assert_almost_eq(WorldGridConfig.radius_m(2), 1024.0, 1e-9, "raio em metros")


func test_describe_mentions_both_cells() -> void:
	var text := WorldGridConfig.describe()
	assert_true(text.contains("512"), "descrição cita o bloco")
	assert_true(text.contains("128"), "descrição cita o detalhe")
