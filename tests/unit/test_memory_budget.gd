extends TestCase

## Orçamento de memória: soma, pressão e escolha de vítimas. O caso que importa é
## o último — o chão sob o jogador nunca pode ser a vítima.

func test_total_and_pressure() -> void:
	var budget := SectorMemoryBudget.new()
	budget.limit_kb = 100.0
	budget.register(Vector2i.ZERO, 60.0)
	budget.register(Vector2i(1, 0), 30.0)
	assert_almost_eq(budget.total_kb(), 90.0, 1e-6, "soma dos setores")
	assert_false(budget.is_over(), "abaixo do teto")
	budget.register(Vector2i(2, 0), 40.0)
	assert_true(budget.is_over(), "acima do teto")
	budget.release(Vector2i(2, 0))
	assert_false(budget.is_over(), "liberar volta para baixo do teto")
	assert_eq(budget.count(), 2, "contagem após liberar")


func test_victims_are_the_farthest() -> void:
	var budget := SectorMemoryBudget.new()
	budget.limit_kb = 10.0
	budget.register(Vector2i.ZERO, 10.0)
	budget.register(Vector2i(1, 0), 10.0)
	budget.register(Vector2i(5, 0), 10.0)
	var victims := budget.victims(Vector2i.ZERO, 2, 0.5, true)
	assert_array_size(victims, 2, "dois despejos pedidos")
	assert_eq(victims[0], Vector2i(5, 0), "o mais distante sai primeiro")
	assert_eq(victims[1], Vector2i(1, 0), "depois o seguinte")


func test_no_eviction_without_pressure() -> void:
	var budget := SectorMemoryBudget.new()
	budget.limit_kb = 1000.0
	budget.register(Vector2i(9, 9), 10.0)
	assert_array_size(budget.victims(Vector2i.ZERO, 4, 0.0, false), 0, "sem pressão não despeja")


func test_ground_under_player_is_never_evicted() -> void:
	var budget := SectorMemoryBudget.new()
	budget.limit_kb = 1.0
	budget.register(Vector2i.ZERO, 50.0)
	assert_array_size(budget.victims(Vector2i.ZERO, 4, 1.5, true), 0, "o bloco do jogador fica")


func test_victims_respect_the_count_limit() -> void:
	var budget := SectorMemoryBudget.new()
	budget.limit_kb = 1.0
	for i in range(6):
		budget.register(Vector2i(i, 0), 10.0)
	assert_array_size(budget.victims(Vector2i.ZERO, 2, 0.5, true), 2, "no máximo dois por frame")


func test_clear_resets_everything() -> void:
	var budget := SectorMemoryBudget.new()
	budget.register(Vector2i(1, 1), 10.0)
	budget.clear()
	assert_almost_eq(budget.total_kb(), 0.0, 1e-9, "total zerado")
	assert_eq(budget.count(), 0, "contagem zerada")
	assert_almost_eq(budget.kb_of(Vector2i(1, 1)), 0.0, 1e-9, "setor desconhecido custa zero")
