extends TestCase

## A rua sobre o relevo: subdivisão, altura acima do terreno e saia vertical.
##
## É o teste do defeito da primeira execução real: a fita amostrada só nos
## extremos desaparecia entre os vértices da malha do terreno. Sem física e sem
## cena: `TerrainService` procedural é determinístico, e o que se verifica é a
## geometria produzida.

func _terrain() -> TerrainService:
	return TerrainService.new(20170)


func _road(length_m: float) -> Array:
	return [{
		"id": "r1",
		"class": "arterial",
		"width": 12.0,
		"points": [[0.0, 0.0], [0.0, length_m]],
	}]


func test_builds_a_mesh_for_a_road() -> void:
	var mesh := RoadMeshBuilder.build(_road(96.0), _terrain(), Vector2.ZERO)
	assert_not_null(mesh, "a via vira malha")
	assert_greater(float(mesh.get_surface_count()), 0.0, "superfície presente")


func test_empty_roads_return_null() -> void:
	assert_eq(RoadMeshBuilder.build([], _terrain(), Vector2.ZERO), null, "sem vias, sem malha")


func test_surface_rides_above_the_terrain_and_has_a_skirt() -> void:
	var terrain := _terrain()
	var mesh := RoadMeshBuilder.build(_road(96.0), terrain, Vector2.ZERO)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var top_found := false
	var skirt_found := false
	for v in vertices:
		var metric := Vector2(v.x, -v.z)
		var ground := terrain.height_at(metric)
		if v.y >= ground + 0.14:
			top_found = true
		if v.y <= ground - 0.05:
			skirt_found = true
	assert_true(top_found, "há vértice de superfície acima do terreno amostrado")
	assert_true(skirt_found, "há vértice de saia abaixo da superfície")


func test_long_segments_are_sampled_in_short_steps() -> void:
	var terrain := _terrain()
	var long_mesh := RoadMeshBuilder.build(_road(96.0), terrain, Vector2.ZERO)
	var short_mesh := RoadMeshBuilder.build(_road(4.0), terrain, Vector2.ZERO)
	var long_vertices: PackedVector3Array = long_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var short_vertices: PackedVector3Array = short_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(float(long_vertices.size()) > float(short_vertices.size()) * 3.0, "trecho longo é amostrado em passos curtos")
