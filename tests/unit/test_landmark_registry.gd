extends TestCase

## Pontos de referência: carregam de dado, declaram confiança e licença, e viram
## área reservada e faixa não edificável.

func _center_rect() -> Rect2:
	MunicipalityIndex.ensure_loaded()
	var center := MunicipalityIndex.center_of("GUAPI")
	return Rect2(center - Vector2(500.0, 500.0), Vector2(1000.0, 1000.0))


func test_datasets_are_loaded_with_provenance() -> void:
	LandmarkRegistry.reload()
	assert_greater(float(LandmarkRegistry.count()), 0.0, "pontos de referência carregados")
	for raw in LandmarkRegistry.all():
		var entry: Dictionary = raw
		assert_true(entry.has("role"), "papel declarado")
		assert_true(entry.has("confidence"), "confiança declarada")
		assert_true(entry.has("license"), "licença declarada")
		assert_true(entry.has("source"), "fonte declarada")


func test_center_of_guapimirim_has_references() -> void:
	LandmarkRegistry.reload()
	var rect := _center_rect()
	assert_greater(float(LandmarkRegistry.for_rect(rect).size()), 0.0, "há ponto de referência no centro")
	assert_greater(float(LandmarkRegistry.barriers_for_rect(rect).size()), 0.0, "há barreira (rio ou ferrovia)")
	assert_greater(float(LandmarkRegistry.open_spaces_for_rect(rect).size()), 0.0, "há área aberta declarada")


func test_barriers_generate_protected_strips() -> void:
	LandmarkRegistry.reload()
	var rect := _center_rect()
	var strips := LandmarkRegistry.protected_polygons(rect, 8.0)
	assert_greater(float(strips.size()), 0.0, "faixa protegida em volta da barreira")
	for raw in strips:
		var poly: PackedVector2Array = (raw as Dictionary)["poly"]
		assert_eq(poly.size(), 4, "faixa representada por quadrilátero")


func test_open_space_becomes_a_polygon() -> void:
	LandmarkRegistry.reload()
	var spaces := LandmarkRegistry.open_spaces_for_rect(_center_rect())
	if spaces.is_empty():
		fail("sem área aberta no centro")
		return
	var space: Dictionary = spaces[0]
	var poly: PackedVector2Array = space["poly"]
	assert_greater(float(poly.size()), 2.0, "área aberta tem polígono")
	assert_greater(float(space["radius_m"]), 2.0, "raio declarado")
	assert_true(space.has("confidence"), "confiança propagada")


func test_nothing_far_from_guapimirim() -> void:
	LandmarkRegistry.reload()
	var far := Rect2(Vector2(2400000.0, 9300000.0), Vector2(512.0, 512.0))
	assert_eq(LandmarkRegistry.for_rect(far).size(), 0, "sem referência fora do centro")
	assert_eq(LandmarkRegistry.barriers_for_rect(far).size(), 0, "sem barreira fora do centro")


func test_attribution_text_is_publishable() -> void:
	LandmarkRegistry.reload()
	var text := LandmarkRegistry.attribution_text()
	assert_true(text.contains("licença"), "atribuição inclui licença")
	assert_true(text.contains("GUAPI") or text.contains("guapimirim"), "atribuição identifica o conjunto")
