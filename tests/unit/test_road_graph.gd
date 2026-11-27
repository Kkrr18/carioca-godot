extends TestCase

## Grafo de ruas: é o que o trânsito usa para atravessar setores.

func _base() -> Vector2i:
	MunicipalityIndex.ensure_loaded()
	return SectorGrid.sector_of(MunicipalityIndex.center_of("GUAPI"))


func _payloads() -> Dictionary:
	var out := {}
	var base := _base()
	for dy in range(0, 2):
		for dx in range(0, 2):
			var coord := Vector2i(base.x + dx, base.y + dy)
			out[coord] = CityGenerator.build_payload(coord, 20170)
	return out


func test_graph_builds_from_payloads() -> void:
	var graph := RoadGraph.new()
	graph.rebuild(_payloads())
	assert_greater(float(graph.edge_count()), 0.0, "arestas construídas")
	assert_greater(float(graph.node_count()), 0.0, "nós construídos")


func test_shared_nodes_reduce_node_count() -> void:
	var graph := RoadGraph.new()
	graph.rebuild(_payloads())
	assert_true(graph.node_count() < graph.edge_count() * 2, "nós são compartilhados entre arestas")


func test_outgoing_is_bidirectional() -> void:
	var graph := RoadGraph.new()
	graph.rebuild(_payloads())
	var checked := 0
	for index in range(mini(graph.edge_count(), 12)):
		var road := graph.road(index)
		var node_a := str(road["node_a"])
		var node_b := str(road["node_b"])
		assert_true(graph.outgoing(node_a).size() > 0, "nó A tem saída")
		assert_true(graph.outgoing(node_b).size() > 0, "nó B tem saída")
		assert_true(graph.outgoing(node_a).has(index), "aresta listada no nó A")
		assert_true(graph.outgoing(node_b).has(index), "aresta listada no nó B")
		checked += 1
	assert_greater(float(checked), 0.0, "arestas verificadas")


func test_intersections_exist_in_urban_area() -> void:
	var graph := RoadGraph.new()
	graph.rebuild(_payloads())
	assert_greater(float(graph.intersections().size()), 0.0, "há cruzamentos com grau 3 ou mais")


func test_nearest_road_finds_something() -> void:
	var graph := RoadGraph.new()
	graph.rebuild(_payloads())
	var sample := SectorGrid.sector_center(_base())
	var index := graph.nearest_road(sample)
	assert_true(index >= 0, "aresta encontrada perto do centro do setor")
	var road := graph.road(index)
	assert_true(road.has("width"), "aresta tem largura")


func test_heading_is_normalized() -> void:
	var graph := RoadGraph.new()
	graph.rebuild(_payloads())
	if graph.edge_count() > 0:
		var heading := graph.road_heading(0)
		assert_almost_eq(heading.length(), 1.0, 1e-6, "direção normalizada")
