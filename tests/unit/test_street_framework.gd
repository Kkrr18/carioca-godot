extends TestCase

## Traçado esquemático: o dado existe, cobre o centro do município e declara
## proveniência e licença. É o arquivo que trava o contrato do qual a cidade
## depende — sem ele, `UrbanGenerator` cai no caminho procedural ou devolve
## setor vazio, e o mundo nasce sem ruas.


func test_sheets_load_from_the_data_directory() -> void:
	StreetFramework.reload()
	assert_greater(float(StreetFramework.sheet_count()), 0.0, "ao menos um conjunto esquemático carregou")


func test_center_is_covered() -> void:
	MunicipalityIndex.ensure_loaded()
	var center := MunicipalityIndex.center_of("GUAPI")
	assert_false(center == Vector2.ZERO, "centro municipal resolvido")
	var rect := Rect2(center - Vector2(300.0, 300.0), Vector2(600.0, 600.0))
	assert_true(StreetFramework.covers(rect), "o recorte do centro de Guapimirim é coberto")


func test_center_has_roads_anchored_at_the_municipality() -> void:
	MunicipalityIndex.ensure_loaded()
	var center := MunicipalityIndex.center_of("GUAPI")
	var rect := Rect2(center - Vector2(300.0, 300.0), Vector2(600.0, 600.0))
	var roads := StreetFramework.roads_for_rect(rect)
	assert_greater(float(roads.size()), 0.0, "ruas do traçado dentro do recorte do centro")
	var nearest := INF
	for road in roads:
		var a: Vector2 = road["a"]
		var b: Vector2 = road["b"]
		var width := float(road["width"])
		assert_true(width > 0.0, "largura declarada")
		assert_true(a.distance_to(b) > 0.0, "segmento com comprimento")
		nearest = minf(nearest, minf(a.distance_to(center), b.distance_to(center)))
	assert_true(nearest < 1000.0, "o traçado passa perto do centro municipal")


func test_provenance_is_declared() -> void:
	MunicipalityIndex.ensure_loaded()
	var center := MunicipalityIndex.center_of("GUAPI")
	var rect := Rect2(center - Vector2(300.0, 300.0), Vector2(600.0, 600.0))
	var provenance := StreetFramework.provenance_for(rect)
	assert_true(not provenance.is_empty(), "proveniência declarada")
	assert_true(str(provenance.get("license", "")).contains("CC0"), "licença declarada")
	assert_true(not str(provenance.get("note", "")).is_empty(), "nota do que o dado é (e não é)")


func test_recorte_longe_do_nucleo_fica_sem_tracado() -> void:
	MunicipalityIndex.ensure_loaded()
	var far := MunicipalityIndex.center_of("GUAPI") + Vector2(40000.0, 40000.0)
	var rect := Rect2(far - Vector2(200.0, 200.0), Vector2(400.0, 400.0))
	assert_false(StreetFramework.covers(rect), "recorte longe do núcleo urbano fica sem traçado")
