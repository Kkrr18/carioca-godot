extends TestCase

## Cache LRU de payloads: acerta o que voltou, esquece o mais antigo e nunca
## estoura o próprio orçamento.

func _payload(records: int) -> Dictionary:
	var roads: Array = []
	for i in range(records):
		roads.append({"class": "local", "points": [[float(i), 0.0], [float(i) + 1.0, 0.0]]})
	return {"version": 2, "grid": [0, 0], "roads": roads}


func test_put_and_get() -> void:
	var cache := SectorPayloadCache.new()
	cache.put(Vector2i(1, 2), _payload(3))
	assert_true(cache.has(Vector2i(1, 2)), "entrada presente")
	assert_eq(str(cache.get(Vector2i(1, 2)).get("version", 0)), "2", "payload devolvido")
	assert_eq(cache.hits, 1, "acerto contabilizado")
	assert_true(cache.get(Vector2i(9, 9)).is_empty(), "ausente devolve vazio")
	assert_eq(cache.misses, 1, "erro contabilizado")


func test_empty_payload_is_ignored() -> void:
	var cache := SectorPayloadCache.new()
	cache.put(Vector2i(0, 0), {})
	assert_eq(cache.size(), 0, "payload vazio não ocupa espaço")


func test_lru_evicts_the_least_recent() -> void:
	var cache := SectorPayloadCache.new()
	cache.limit_entries = 2
	cache.put(Vector2i(0, 0), _payload(1))
	cache.put(Vector2i(1, 0), _payload(1))
	cache.get(Vector2i(0, 0))
	cache.put(Vector2i(2, 0), _payload(1))
	assert_true(cache.has(Vector2i(0, 0)), "usado recentemente permanece")
	assert_false(cache.has(Vector2i(1, 0)), "menos recente saiu")
	assert_eq(cache.size(), 2, "respeita o limite de entradas")


func test_byte_budget_wins_over_entry_limit() -> void:
	var cache := SectorPayloadCache.new()
	cache.limit_entries = 100
	cache.limit_kb = 1.0
	cache.put(Vector2i(0, 0), _payload(40))
	assert_eq(cache.size(), 1, "a primeira entrada sempre entra")
	cache.put(Vector2i(1, 0), _payload(40))
	assert_true(cache.size() <= 1, "orçamento de bytes limita mesmo com limite de entradas alto")


func test_clear_and_stats() -> void:
	var cache := SectorPayloadCache.new()
	cache.put(Vector2i(3, 3), _payload(5))
	assert_greater(cache.size_kb(), 0.0, "estimativa positiva")
	var stats := cache.stats()
	assert_eq(int(stats["entries"]), 1, "estatística de entradas")
	assert_greater(float(stats["kb"]), 0.0, "estatística de bytes")
	cache.clear()
	assert_eq(cache.size(), 0, "limpo")


func test_estimate_scales_with_records() -> void:
	var small := SectorPayloadCache.estimate_kb(_payload(1))
	var large := SectorPayloadCache.estimate_kb(_payload(100))
	assert_greater(large, small, "mais registros custam mais")
