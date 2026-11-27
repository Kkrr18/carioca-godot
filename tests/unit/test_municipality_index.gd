extends TestCase

## Índice geográfico: cobre o estado, identifica município e fornece a densidade
## que decide onde nasce cidade.

func test_index_is_loaded() -> void:
	MunicipalityIndex.reload()
	assert_greater(float(MunicipalityIndex.count()), 60.0, "municípios carregados")
	assert_greater(float(MunicipalityIndex.regions().size()), 5.0, "regiões carregadas")


func test_nearest_identifies_major_cities() -> void:
	var cases := {
		"RIO": Vector2(-22.9068, -43.1729),
		"GUAPI": Vector2(-22.5370, -42.9820),
		"MAGE": Vector2(-22.6530, -43.0410),
		"CAMPOS": Vector2(-21.7540, -41.3240),
	}
	for expected in cases.keys():
		var point: Vector2 = cases[expected]
		var municipality := MunicipalityIndex.nearest(GeoCoordinateSystem.geographic_to_metric(point.x, point.y))
		assert_eq(str(municipality.get("code", "")), expected, "município de %s" % expected)


func test_density_is_high_in_center_and_low_far_away() -> void:
	var center := MunicipalityIndex.center_of("RIO")
	assert_almost_eq(MunicipalityIndex.density_at(center), 1.0, 1e-6, "densidade no centro do Rio")
	var far := center + Vector2(45000.0, 0.0)
	assert_true(MunicipalityIndex.density_at(far) < 0.4, "densidade a 45 km do centro")


func test_sector_id_format() -> void:
	var coord := SectorGrid.sector_of(MunicipalityIndex.center_of("GUAPI"))
	var id := MunicipalityIndex.id_for(coord)
	assert_true(id.begins_with("RJ_METRO_GUAPI_"), "prefixo do identificador: %s" % id)
	assert_eq(id.split("_").size(), 5, "identificador com 5 partes")


func test_state_bounds_are_sane() -> void:
	var bounds := MunicipalityIndex.state_bounds()
	assert_true(float(bounds["min_lat"]) < float(bounds["max_lat"]), "latitudes ordenadas")
	assert_true(float(bounds["min_lon"]) < float(bounds["max_lon"]), "longitudes ordenadas")
	assert_almost_eq(float(bounds["min_lat"]), -23.37, 0.2, "latitude mínima do estado")
	assert_almost_eq(float(bounds["max_lat"]), -20.76, 0.2, "latitude máxima do estado")


func test_sector_count_of_the_state() -> void:
	var total := MunicipalityIndex.estimated_sector_count()
	assert_greater(float(total), 1000.0, "o estado tem mais de mil setores de 512 m")


func test_center_of_unknown_falls_back() -> void:
	var metric := MunicipalityIndex.center_of("NAO_EXISTE")
	assert_true(is_finite(metric.x) and is_finite(metric.y), "centro de reserva é finito")
