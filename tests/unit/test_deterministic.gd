extends TestCase

## Determinismo é requisito de produção: sem ele, o mundo muda a cada sessão e
## nenhum bug de geração é reproduzível.

func test_hash_is_stable() -> void:
	var first := Deterministic.hash2(12, 34, 7)
	var second := Deterministic.hash2(12, 34, 7)
	assert_eq(first, second, "mesmo par de índices, mesmo hash")
	assert_not_eq(first, Deterministic.hash2(12, 35, 7), "índices diferentes, hash diferente")
	assert_true(first >= 0, "hash não negativo")


func test_rand01_stays_in_range() -> void:
	for i in range(200):
		var value := Deterministic.rand01(i, i * 3, 11)
		assert_true(value >= 0.0 and value <= 1.0, "rand01 em [0,1]")


func test_value_noise_is_continuous() -> void:
	var previous := Deterministic.value_noise(0.0, 0.0, 3)
	for step in range(1, 60):
		var current := Deterministic.value_noise(float(step) * 0.05, 0.0, 3)
		assert_true(absf(current - previous) < 0.35, "salto de ruído pequeno entre amostras vizinhas")
		previous = current


func test_fbm_is_bounded() -> void:
	for i in range(80):
		var value := Deterministic.fbm(float(i) * 3.7, float(i) * 1.3, 4, 21)
		assert_true(value >= -1.0 and value <= 1.0, "fbm dentro de [-1,1]")


func test_noise_is_repeatable_across_calls() -> void:
	var a := Deterministic.fbm(123.456, 789.012, 4, 20170)
	var b := Deterministic.fbm(123.456, 789.012, 4, 20170)
	assert_almost_eq(a, b, 1e-12, "fbm idêntico entre chamadas")
