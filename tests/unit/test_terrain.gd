extends TestCase

## Terreno: determinismo, ausência de costura entre setores e alturas plausíveis.
## A costura é o teste que importa — é o defeito visual mais óbvio de mundo
## aberto em streaming.

const DIVISIONS := 8


func test_height_is_deterministic() -> void:
	var terrain := TerrainService.new(20170)
	var metric := Vector2(300000.0, 8000000.0)
	var first := terrain.height_at(metric)
	var second := terrain.height_at(metric)
	assert_almost_eq(first, second, 1e-12, "altura idêntica entre chamadas")


func test_height_is_independent_of_sector() -> void:
	var terrain := TerrainService.new(20170)
	var metric := Vector2(310000.0, 8010000.0)
	var direct := terrain.height_at(metric)
	var coord := SectorGrid.sector_of(metric)
	var via_sector_origin := metric - SectorGrid.sector_origin(coord)
	var reconstructed := terrain.height_at(SectorGrid.sector_origin(coord) + via_sector_origin)
	assert_almost_eq(direct, reconstructed, 1e-9, "altura não depende de onde foi consultada")


func test_height_is_not_negative() -> void:
	var terrain := TerrainService.new(20170)
	for i in range(60):
		var metric := Vector2(300000.0 + float(i) * 1300.0, 8000000.0 + float(i) * 900.0)
		assert_true(terrain.height_at(metric) >= 0.0, "altura não negativa em %d" % i)


func test_mesh_edges_are_watertight() -> void:
	var terrain := TerrainService.new(20170)
	var coord_a := Vector2i(390, 15433)
	var coord_b := Vector2i(coord_a.x + 1, coord_a.y)
	var mesh_a := TerrainMeshBuilder.build(coord_a, DIVISIONS, terrain)
	var mesh_b := TerrainMeshBuilder.build(coord_b, DIVISIONS, terrain)
	assert_not_null(mesh_a, "malha do setor A")
	assert_not_null(mesh_b, "malha do setor B")

	var vertices_a: PackedVector3Array = mesh_a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var vertices_b: PackedVector3Array = mesh_b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var side := DIVISIONS + 1
	assert_eq(vertices_a.size(), side * side, "quantidade de vértices do setor A")

	var mismatches := 0
	for row in range(side):
		var index_a := row * side + DIVISIONS
		var index_b := row * side
		if absf(vertices_a[index_a].y - vertices_b[index_b].y) > 1e-4:
			mismatches += 1
	assert_eq(mismatches, 0, "borda leste de A coincide com borda oeste de B")


func test_normals_point_upwards() -> void:
	var terrain := TerrainService.new(20170)
	var normal := terrain.normal_at(Vector2(300000.0, 8000000.0))
	assert_true(normal.y > 0.0, "normal do terreno aponta para cima")
	assert_almost_eq(normal.length(), 1.0, 1e-6, "normal normalizada")


func test_hgt_tile_naming() -> void:
	assert_eq(HGTElevationSource.tile_name_for(-22.537, -42.982), "S23W043", "tile de Guapimirim")
	assert_eq(HGTElevationSource.tile_name_for(-22.9068, -43.1729), "S23W044", "tile do Rio")
	assert_eq(HGTElevationSource.tile_name_for(10.5, 20.25), "N10E020", "tile no hemisfério norte")


## A saia anti-rachadura só entra quando o LOD faz setores vizinhos divergirem.
## Ela não pode mexer na grade: os primeiros (divisões+1)² vértices continuam
## sendo o terreno exato, senão a costura entre setores iguais quebraria.
func test_skirt_keeps_the_grid_intact() -> void:
	var terrain := TerrainService.new(20170)
	var coord := Vector2i(390, 15433)
	var plain := TerrainMeshBuilder.build(coord, DIVISIONS, terrain)
	var skirted := TerrainMeshBuilder.build(coord, DIVISIONS, terrain, 8.0)
	assert_not_null(plain, "malha sem saia")
	assert_not_null(skirted, "malha com saia")

	var plain_vertices: PackedVector3Array = plain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var skirt_vertices: PackedVector3Array = skirted.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var side := DIVISIONS + 1
	var expected_extra := 4 * (side - 1) * 2
	assert_eq(skirt_vertices.size(), plain_vertices.size() + expected_extra, "dois vértices por aresta de borda")

	for i in range(side * side):
		assert_almost_eq(skirt_vertices[i].y, plain_vertices[i].y, 1e-6, "grade intacta no vértice %d" % i)

	var lowest := INF
	for i in range(side * side, skirt_vertices.size()):
		lowest = minf(lowest, skirt_vertices[i].y)
	assert_true(lowest <= plain_vertices[0].y - 7.0, "saia desce abaixo da borda")


func test_skirt_is_optional() -> void:
	var terrain := TerrainService.new(20170)
	var coord := Vector2i(390, 15433)
	var without := TerrainMeshBuilder.build(coord, DIVISIONS, terrain)
	var vertices: PackedVector3Array = without.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var side := DIVISIONS + 1
	assert_eq(vertices.size(), side * side, "sem saia, a malha tem só a grade")
