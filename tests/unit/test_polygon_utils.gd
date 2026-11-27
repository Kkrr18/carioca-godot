extends TestCase

## Geometria de polígono: a base de quadra, lote e prédio.
##
## Se estas funções estiverem erradas, tudo acima erra junto — e erra de um jeito
## difícil de ver, porque o sintoma é um lote torto e não uma exceção. Por isso a
## bateria cobre área, giro, recorte, triangulação e sobreposição.


func _square(size: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(size, 0.0),
		Vector2(size, size),
		Vector2(0.0, size),
	])


func test_area_and_winding() -> void:
	var poly := _square(10.0)
	assert_almost_eq(PolygonUtils.area(poly), 100.0, 1.0e-6, "área do quadrado")
	assert_true(PolygonUtils.is_ccw(poly), "quadrado em sentido anti-horário")
	var reversed := poly.duplicate()
	reversed.reverse()
	assert_false(PolygonUtils.is_ccw(reversed), "invertido fica horário")
	assert_almost_eq(PolygonUtils.area(reversed), 100.0, 1.0e-6, "área não depende do giro")
	assert_true(PolygonUtils.is_ccw(PolygonUtils.to_ccw(reversed)), "to_ccw corrige o giro")


func test_centroid_is_the_middle() -> void:
	var centroid := PolygonUtils.centroid(_square(10.0))
	assert_almost_eq(centroid.x, 5.0, 1.0e-5, "centroide x")
	assert_almost_eq(centroid.y, 5.0, 1.0e-5, "centroide y")


func test_point_in_polygon() -> void:
	var poly := _square(10.0)
	assert_true(PolygonUtils.point_in_polygon(Vector2(5.0, 5.0), poly), "ponto interno")
	assert_false(PolygonUtils.point_in_polygon(Vector2(15.0, 5.0), poly), "ponto externo")


func test_clip_half_plane_keeps_half() -> void:
	var clipped := PolygonUtils.clip_half_plane(_square(10.0), Vector2.RIGHT, 5.0)
	assert_almost_eq(PolygonUtils.area(clipped), 50.0, 0.01, "metade do quadrado")


func test_clip_slab_produces_a_band() -> void:
	var slab := PolygonUtils.clip_slab(_square(10.0), Vector2.RIGHT, 2.0, 7.0)
	assert_almost_eq(PolygonUtils.area(slab), 50.0, 0.01, "faixa de cinco metros")


func test_inset_shrinks_equally_on_every_side() -> void:
	var inset := PolygonUtils.inset_polygon(_square(20.0), 2.0)
	assert_almost_eq(PolygonUtils.area(inset), 256.0, 0.05, "16 x 16 depois do recuo de 2 m")


func test_triangulate_square_and_concave() -> void:
	var square := PolygonUtils.triangulate(_square(10.0))
	var square_indices: PackedInt32Array = square["indices"]
	assert_eq(square_indices.size(), 6, "quadrado vira dois triângulos")

	var concave := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(10.0, 0.0),
		Vector2(10.0, 4.0),
		Vector2(4.0, 4.0),
		Vector2(4.0, 10.0),
		Vector2(0.0, 10.0),
	])
	var result := PolygonUtils.triangulate(concave)
	var points: PackedVector2Array = result["points"]
	var indices: PackedInt32Array = result["indices"]
	assert_eq(indices.size(), (concave.size() - 2) * 3, "L côncavo vira n-2 triângulos")
	var total := 0.0
	for i in range(0, indices.size(), 3):
		var a := points[indices[i]]
		var b := points[indices[i + 1]]
		var c := points[indices[i + 2]]
		total += absf((b - a).cross(c - a)) * 0.5
	assert_almost_eq(total, PolygonUtils.area(concave), 0.01, "soma dos triângulos igual à área do polígono")


func test_overlap_ignores_shared_boundary() -> void:
	var a := _square(10.0)
	var touching := PackedVector2Array([
		Vector2(10.0, 0.0), Vector2(20.0, 0.0), Vector2(20.0, 10.0), Vector2(10.0, 10.0),
	])
	assert_false(PolygonUtils.polygons_overlap(a, touching), "vizinhos que compartilham a divisa não se sobrepõem")

	var invading := PackedVector2Array([
		Vector2(9.0, 1.0), Vector2(20.0, 1.0), Vector2(20.0, 9.0), Vector2(9.0, 9.0),
	])
	assert_true(PolygonUtils.polygons_overlap(a, invading), "invasão de um metro é detectada")

	var far := PackedVector2Array([
		Vector2(30.0, 30.0), Vector2(40.0, 30.0), Vector2(40.0, 40.0), Vector2(30.0, 40.0),
	])
	assert_false(PolygonUtils.polygons_overlap(a, far), "polígonos distantes não se tocam")


func test_oriented_rect_matches_its_frame() -> void:
	var u := Vector2(1.0, 0.0)
	var n := Vector2(0.0, 1.0)
	var rect := PolygonUtils.oriented_rect(Vector2(100.0, 200.0), u, n, 0.0, 10.0, 0.0, 5.0)
	assert_almost_eq(PolygonUtils.area(rect), 50.0, 0.01, "área do retângulo orientado")
	assert_true(PolygonUtils.is_ccw(rect), "retângulo em anti-horário")
	assert_almost_eq(PolygonUtils.centroid(rect).x, 105.0, 0.01, "centroide x")
	assert_almost_eq(PolygonUtils.centroid(rect).y, 202.5, 0.01, "centroide y")


func test_serialization_roundtrip() -> void:
	var poly := _square(12.0)
	var roundtrip := PolygonUtils.from_array(PolygonUtils.to_array(poly))
	assert_eq(roundtrip.size(), poly.size(), "mesma quantidade de vértices")
	assert_almost_eq(PolygonUtils.area(roundtrip), PolygonUtils.area(poly), 0.01, "mesma área depois da ida e volta")
