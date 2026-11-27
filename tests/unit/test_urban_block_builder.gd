extends TestCase

## Quadras: face fechada da rede de ruas, recuada pela calçada.
##
## O teste que dá sentido ao sistema é o da rua diagonal: se a quadra continuasse
## retangular, o gerador estaria desenhando uma grade imaginária em vez de seguir
## a rua.

func _ring(size: float, width: float) -> Array:
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
			"width": width,
			"road_class": WorldSchema.ROAD_LOCAL,
			"id": "ring%d" % i,
		})
	return segments


func _rect() -> Rect2:
	return Rect2(Vector2(-600.0, -600.0), Vector2(1200.0, 1200.0))


func test_single_ring_produces_one_block() -> void:
	var network := RoadNetwork.from_segments(_ring(120.0, 8.0))
	var blocks := UrbanBlockBuilder.build(network, UrbanConfig.new(), _rect())
	assert_eq(blocks.size(), 1, "um quarteirão fechado")
	if blocks.is_empty():
		return
	var block: Dictionary = blocks[0]
	var poly: PackedVector2Array = block["poly"]
	assert_true(PolygonUtils.is_ccw(poly), "polígono em anti-horário")
	assert_true(PolygonUtils.area(poly) < 120.0 * 120.0, "a quadra é menor que a face das ruas")
	assert_true(PolygonUtils.area(poly) > 9000.0, "a quadra mantém área útil")
	assert_eq((block["frontage"] as Array).size(), 4, "quatro frentes de rua")


func test_block_stays_off_the_pavement() -> void:
	var network := RoadNetwork.from_segments(_ring(160.0, 10.0))
	var blocks := UrbanBlockBuilder.build(network, UrbanConfig.new(), _rect())
	assert_eq(blocks.size(), 1, "um quarteirão")
	if blocks.is_empty():
		return
	var block: Dictionary = blocks[0]
	var poly: PackedVector2Array = block["poly"]
	for point in poly:
		assert_greater(network.clearance_to_road(point) + 0.01, 0.0, "nenhum vértice da quadra sobre a pista")
	var centroid: Vector2 = block["centroid"]
	assert_greater(network.clearance_to_road(centroid), 5.0, "o miolo da quadra está longe do asfalto")


func test_diagonal_road_creates_two_irregular_blocks() -> void:
	var segments := _ring(120.0, 8.0)
	segments.append({
		"a": Vector2(-60.0, -60.0),
		"b": Vector2(60.0, 60.0),
		"width": 6.0,
		"road_class": WorldSchema.ROAD_LOCAL,
		"id": "diagonal",
	})
	var network := RoadNetwork.from_segments(segments)
	var blocks := UrbanBlockBuilder.build(network, UrbanConfig.new(), _rect())
	assert_eq(blocks.size(), 2, "a diagonal divide a área em dois quarteirões")
	if blocks.size() != 2:
		return
	var triangular := 0
	for block in blocks:
		var poly: PackedVector2Array = block["poly"]
		if poly.size() <= 4:
			triangular += 1
	assert_greater(float(triangular), 0.0, "ao menos um quarteirão tem forma de canto, não de retângulo")


func test_block_belongs_to_a_single_sector() -> void:
	var network := RoadNetwork.from_segments(_ring(120.0, 8.0))
	var config := UrbanConfig.new()
	var here := UrbanBlockBuilder.build(network, config, Rect2(Vector2(-60.0, -60.0), Vector2(120.0, 120.0)))
	var elsewhere := UrbanBlockBuilder.build(network, config, Rect2(Vector2(600.0, 600.0), Vector2(300.0, 300.0)))
	assert_eq(here.size(), 1, "o setor que contém o centroide reivindica a quadra")
	assert_eq(elsewhere.size(), 0, "nenhum outro setor a reivindica")


func test_generation_is_deterministic() -> void:
	var network := RoadNetwork.from_segments(_ring(140.0, 8.0))
	var config := UrbanConfig.new()
	var first := UrbanBlockBuilder.build(network, config, _rect())
	var second := UrbanBlockBuilder.build(network, config, _rect())
	assert_eq(first.size(), second.size(), "mesma quantidade de quadras")
	for i in range(mini(first.size(), second.size())):
		var a: Dictionary = first[i]
		var b: Dictionary = second[i]
		var centroid_a: Vector2 = a["centroid"]
		var centroid_b: Vector2 = b["centroid"]
		assert_eq(str(a["id"]), str(b["id"]), "mesmo identificador")
		assert_almost_eq(float(a["area"]), float(b["area"]), 0.001, "mesma área")
		assert_almost_eq(centroid_a.x, centroid_b.x, 0.001, "mesmo centroide")
