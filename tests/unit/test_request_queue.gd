extends TestCase

## Fila de requisições: prioridade radial, inclinação na direção do movimento e
## deduplicação. É a primeira defesa contra carregar o mesmo setor duas vezes.

func test_refill_deduplicates() -> void:
	var queue := SectorRequestQueue.new()
	var coords: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 0), Vector2i(-1, 0)]
	queue.refill(coords, Vector2i.ZERO, Vector2.ZERO, 0.0)
	assert_eq(queue.size(), 3, "coordenada repetida entra uma vez")
	assert_true(queue.has(Vector2i(1, 0)), "coordenada presente")
	queue.refill(coords, Vector2i.ZERO, Vector2.ZERO, 0.0)
	assert_eq(queue.size(), 3, "reconstruir não acumula")


func test_nearest_first_without_motion() -> void:
	var queue := SectorRequestQueue.new()
	var coords: Array[Vector2i] = [Vector2i(3, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 0)]
	queue.refill(coords, Vector2i.ZERO, Vector2.ZERO, 0.6)
	assert_eq(queue.pop(), Vector2i(0, 0), "mais próximo primeiro")
	assert_eq(queue.pop(), Vector2i(1, 0), "depois o seguinte")


func test_motion_bias_serves_ahead_first() -> void:
	var queue := SectorRequestQueue.new()
	var coords: Array[Vector2i] = [Vector2i(0, 2), Vector2i(2, 0)]
	queue.refill(coords, Vector2i.ZERO, Vector2(1.0, 0.0), 0.6)
	assert_eq(queue.pop(), Vector2i(2, 0), "bloco à frente passa na frente do lateral")


func test_priority_is_cheaper_ahead() -> void:
	var queue := SectorRequestQueue.new()
	var coords: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0)]
	queue.refill(coords, Vector2i.ZERO, Vector2(1.0, 0.0), 0.6)
	assert_true(
		queue.priority(Vector2i(1, 0)) < queue.priority(Vector2i(-1, 0)),
		"à frente pontua menos (mais urgente)"
	)


func test_zero_gain_is_pure_distance() -> void:
	var queue := SectorRequestQueue.new()
	var coords: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(2, 0)]
	queue.refill(coords, Vector2i.ZERO, Vector2(1.0, 0.0), 0.0)
	assert_almost_eq(queue.priority(Vector2i(-2, 0)), 2.0, 1e-6, "sem ganho, distância pura")
	assert_almost_eq(queue.priority(Vector2i(2, 0)), 2.0, 1e-6, "sem ganho, os dois lados iguais")


func test_remove_and_clear() -> void:
	var queue := SectorRequestQueue.new()
	var coords: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2)]
	queue.refill(coords, Vector2i.ZERO, Vector2.ZERO, 0.0)
	queue.remove(Vector2i(1, 1))
	assert_false(queue.has(Vector2i(1, 1)), "removida da fila")
	assert_eq(queue.size(), 1, "tamanho após remoção")
	queue.push_back(Vector2i(5, 5))
	assert_true(queue.has(Vector2i(5, 5)), "reinserida")
	queue.push_back(Vector2i(5, 5))
	assert_eq(queue.size(), 2, "reinserção não duplica")
	queue.clear()
	assert_true(queue.is_empty(), "fila vazia")


func test_pop_on_empty_returns_sentinel() -> void:
	var queue := SectorRequestQueue.new()
	assert_eq(queue.pop(), SectorRequestQueue.SENTINEL, "sentinela quando vazia")


func test_sentinel_never_enters() -> void:
	var queue := SectorRequestQueue.new()
	var coords: Array[Vector2i] = [SectorRequestQueue.SENTINEL, Vector2i(0, 0)]
	queue.refill(coords, Vector2i.ZERO, Vector2.ZERO, 0.0)
	assert_eq(queue.size(), 1, "sentinela não é uma coordenada válida")
