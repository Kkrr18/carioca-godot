extends TestCase

## A projeção é a fundação de tudo: se ida e volta não fecham, nenhuma
## coordenada do mundo é confiável.

const STATE_POINTS: Array[Vector2] = [
	Vector2(-22.9068, -43.1729), # Rio de Janeiro
	Vector2(-22.6530, -43.0410), # Magé
	Vector2(-22.5370, -42.9820), # Guapimirim
	Vector2(-23.0070, -44.3180), # Angra dos Reis
	Vector2(-21.7540, -41.3240), # Campos dos Goytacazes
	Vector2(-20.9300, -41.8680), # Varre-Sai (extremo norte)
	Vector2(-23.3700, -44.8900), # extremo sudoeste
	Vector2(-21.0430, -41.9690), # Natividade
]


func test_forward_inverse_round_trip() -> void:
	for point in STATE_POINTS:
		var metric := CariocaProjection.forward(point.x, point.y)
		var back := CariocaProjection.inverse(metric.x, metric.y)
		assert_almost_eq(back.x, point.x, 1e-9, "latitude de volta em %.4f" % point.x)
		assert_almost_eq(back.y, point.y, 1e-9, "longitude de volta em %.4f" % point.y)


func test_scale_factor_is_exact_at_standard_parallels() -> void:
	assert_almost_eq(CariocaProjection.scale_factor(-21.0), 1.0, 1e-9, "paralelo padrão norte")
	assert_almost_eq(CariocaProjection.scale_factor(-23.5), 1.0, 1e-9, "paralelo padrão sul")
	assert_almost_eq(CariocaProjection.scale_factor(-22.5), 1.0, 6e-4, "latitude central do estado")


func test_metric_space_is_positive_over_the_state() -> void:
	var bounds := MunicipalityIndex.state_bounds()
	var corners := [
		Vector2(float(bounds["max_lat"]), float(bounds["min_lon"])),
		Vector2(float(bounds["max_lat"]), float(bounds["max_lon"])),
		Vector2(float(bounds["min_lat"]), float(bounds["min_lon"])),
		Vector2(float(bounds["min_lat"]), float(bounds["max_lon"])),
	]
	for corner in corners:
		var metric := CariocaProjection.forward(corner.x, corner.y)
		assert_greater(metric.x, 0.0, "easting positivo em %.4f" % corner.x)
		assert_greater(metric.y, 0.0, "northing positivo em %.4f" % corner.y)


func test_northing_grows_to_north_and_easting_to_east() -> void:
	var south := CariocaProjection.forward(-23.2, -43.2)
	var north := CariocaProjection.forward(-22.2, -43.2)
	var west := CariocaProjection.forward(-22.5, -44.4)
	var east := CariocaProjection.forward(-22.5, -41.4)
	assert_greater(north.y, south.y, "northing aumenta para o norte")
	assert_greater(east.x, west.x, "easting aumenta para o leste")


func test_distances_match_geodesic() -> void:
	var pairs := [
		[Vector2(-22.9068, -43.1729), Vector2(-22.6530, -43.0410)], # Rio -> Magé
		[Vector2(-22.5370, -42.9820), Vector2(-22.6530, -43.0410)], # Guapi -> Magé
		[Vector2(-22.9068, -43.1729), Vector2(-21.7540, -41.3240)], # Rio -> Campos
		[Vector2(-23.0070, -44.3180), Vector2(-22.5370, -42.9820)], # Angra -> Guapi
	]
	for pair in pairs:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var metric_a := CariocaProjection.forward(a.x, a.y)
		var metric_b := CariocaProjection.forward(b.x, b.y)
		var metric_distance := metric_a.distance_to(metric_b)
		var geodesic := _haversine(a, b)
		var error := absf(metric_distance - geodesic) / geodesic
		assert_true(error < 0.003, "distância entre %.3f e %.3f difere %.4f%% do geodésico" % [a.x, b.x, error * 100.0])


func test_tangent_approximation_converges_over_short_spans() -> void:
	var origin := Vector2(-22.537, -42.982)
	var target := Vector2(-22.560, -43.010)
	var exact := CariocaProjection.forward(target.x, target.y) - CariocaProjection.forward(origin.x, origin.y)
	var approximate := GeoCoordinateSystem.tangent_offsets(target.x, target.y, origin.x, origin.y)
	var difference := exact.distance_to(approximate)
	assert_true(difference < 25.0, "aproximação de plano tangente erra %.2f m em ~3,8 km (esperado < 25 m)" % difference)


func _haversine(a: Vector2, b: Vector2) -> float:
	var radius := 6371008.8
	var lat1 := deg_to_rad(a.x)
	var lat2 := deg_to_rad(b.x)
	var delta_lat := deg_to_rad(b.x - a.x)
	var delta_lon := deg_to_rad(b.y - a.y)
	var h := sin(delta_lat * 0.5) * sin(delta_lat * 0.5) + cos(lat1) * cos(lat2) * sin(delta_lon * 0.5) * sin(delta_lon * 0.5)
	return 2.0 * radius * asin(minf(sqrt(h), 1.0))
