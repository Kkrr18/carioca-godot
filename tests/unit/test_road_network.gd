extends TestCase

## Rede de vias: cruzamento vira nó, pontas quase coincidentes se fundem e a
## folga até o asfalto é medida contra a metade da pista.


func _cross() -> Array:
	return [
		{"a": Vector2(-100.0, 0.0), "b": Vector2(100.0, 0.0), "width": 8.0, "road_class": WorldSchema.ROAD_COLLECTOR, "id": "h"},
		{"a": Vector2(0.0, -100.0), "b": Vector2(0.0, 100.0), "width": 8.0, "road_class": WorldSchema.ROAD_COLLECTOR, "id": "v"},
	]


func test_crossing_becomes_a_node() -> void:
	var network := RoadNetwork.from_segments(_cross())
	assert_eq(network.node_count(), 5, "quatro pontas mais o cruzamento")
	assert_eq(network.edge_count(), 4, "cada via é cortada no cruzamento")
	assert_eq(network.intersections().size(), 1, "uma esquina de grau quatro")


func test_near_endpoints_are_merged() -> void:
	var segments := [
		{"a": Vector2(0.0, 0.0), "b": Vector2(50.0, 0.0), "width": 6.0, "road_class": WorldSchema.ROAD_LOCAL, "id": "a"},
		{"a": Vector2(50.3, 0.2), "b": Vector2(100.0, 0.0), "width": 6.0, "road_class": WorldSchema.ROAD_LOCAL, "id": "b"},
	]
	var network := RoadNetwork.from_segments(segments)
	assert_eq(network.node_count(), 3, "junção fundida por proximidade")


func test_clearance_measures_to_the_pavement_edge() -> void:
	var network := RoadNetwork.from_segments(_cross())
	assert_true(network.clearance_to_road(Vector2.ZERO) <= 0.0, "o centro do cruzamento é asfalto")
	assert_almost_eq(network.clearance_to_road(Vector2(0.0, 10.0)), 6.0, 0.1, "10 m do eixo com pista de 8 m")


func test_total_length_is_reported() -> void:
	var network := RoadNetwork.from_segments(_cross())
	assert_almost_eq(float(network.stats()["length_m"]), 400.0, 0.5, "duas vias de 200 m")


func test_degenerate_segments_are_discarded() -> void:
	var segments := [
		{"a": Vector2(0.0, 0.0), "b": Vector2(0.4, 0.0), "width": 6.0, "road_class": WorldSchema.ROAD_LOCAL, "id": "tiny"},
		{"a": Vector2(0.0, 0.0), "b": Vector2(40.0, 0.0), "width": 6.0, "road_class": WorldSchema.ROAD_LOCAL, "id": "ok"},
	]
	var network := RoadNetwork.from_segments(segments)
	assert_eq(network.edge_count(), 1, "trecho menor que o mínimo não entra")


func test_empty_network_is_safe() -> void:
	var network := RoadNetwork.from_segments([])
	assert_eq(network.edge_count(), 0, "rede vazia")
	assert_eq(network.intersections().size(), 0, "sem esquinas")
	assert_almost_eq(network.clearance_to_road(Vector2.ZERO), 9999.0, 0.01, "sem via, folga grande e não NAN")


func test_payload_roads_are_converted_from_local_space() -> void:
	# Uma via que, no espaço local do setor, vai de (0,0) a (100,0).
	var roads := [
		{"id": "r", "class": WorldSchema.ROAD_LOCAL, "width": 6.0, "points": [[0.0, 0.0], [100.0, 0.0]]},
	]
	var origin := Vector2(1000.0, 2000.0)
	var network := RoadNetwork.from_payload_roads(roads, origin)
	assert_eq(network.edge_count(), 1, "uma aresta")
	assert_almost_eq(network.node_position(int(network.edges[0]["a"])).x, 1000.0, 0.01, "x métrico do primeiro nó")
	assert_almost_eq(network.node_position(int(network.edges[0]["b"])).x, 1100.0, 0.01, "x métrico do segundo nó")
