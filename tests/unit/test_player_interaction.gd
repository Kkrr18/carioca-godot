extends TestCase

## Interação por provedores: escolha, rótulo, execução e tolerância a lixo.

class FakeProvider extends RefCounted:
	var entries: Array = []
	var calls: int = 0

	func candidates(_player: Node3D) -> Array:
		calls += 1
		return entries


class BrokenProvider extends RefCounted:
	func candidates(_player: Node3D) -> Variant:
		return "isto não é uma lista"


class BareObject extends RefCounted:
	var nothing: int = 0


func _candidate(id: String, distance: float, priority: float, kind: String = "test") -> Dictionary:
	return {"id": id, "kind": kind, "label": id, "verb": "E", "distance": distance, "priority": priority}


func test_provider_registration_rules() -> void:
	var interaction := PlayerInteraction.new()
	assert_true(interaction.add_provider(FakeProvider.new()), "provedor válido aceito")
	assert_false(interaction.add_provider(BareObject.new()), "objeto sem candidates recusado")
	assert_false(interaction.add_provider(null), "nulo recusado")
	var duplicate := FakeProvider.new()
	assert_true(interaction.add_provider(duplicate), "registro novo")
	assert_false(interaction.add_provider(duplicate), "mesmo provedor não entra duas vezes")
	assert_eq(interaction.providers.size(), 2, "dois provedores registrados")


func test_priority_beats_distance() -> void:
	var interaction := PlayerInteraction.new()
	var provider := FakeProvider.new()
	provider.entries = [
		_candidate("porta", 1.0, 5.0, "door"),
		_candidate("carro", 3.4, 10.0, "vehicle"),
	]
	interaction.add_provider(provider)
	var player := Node3D.new()
	var best := interaction.refresh_now(player)
	assert_eq(str(best.get("id", "")), "carro", "prioridade vence distância")
	player.free()


func test_closest_wins_on_equal_priority() -> void:
	var interaction := PlayerInteraction.new()
	var provider := FakeProvider.new()
	provider.entries = [
		_candidate("longe", 4.0, 6.0),
		_candidate("perto", 1.2, 6.0),
	]
	interaction.add_provider(provider)
	var player := Node3D.new()
	var best := interaction.refresh_now(player)
	assert_eq(str(best.get("id", "")), "perto", "empate de prioridade decide pela distância")
	player.free()


func test_prompt_text_combines_verb_and_label() -> void:
	var interaction := PlayerInteraction.new()
	var provider := FakeProvider.new()
	provider.entries = [{"id": "x", "kind": "door", "label": "Entrar", "verb": "E", "distance": 2.0, "priority": 1.0}]
	interaction.add_provider(provider)
	var player := Node3D.new()
	interaction.refresh_now(player)
	assert_eq(interaction.prompt_text(), "E   Entrar", "rótulo mostrado ao jogador")
	player.free()


func test_interact_calls_the_target_once() -> void:
	var interaction := PlayerInteraction.new()
	var provider := FakeProvider.new()
	var hit := {"count": 0}
	var target := Callable(self, "_record_hit").bind(hit)
	provider.entries = [{"id": "x", "kind": "object", "label": "Abrir", "verb": "E", "distance": 1.0, "priority": 1.0, "target": target}]
	interaction.add_provider(provider)
	var player := Node3D.new()
	interaction.refresh_now(player)
	assert_true(interaction.interact(player), "interação executada")
	assert_eq(int(hit["count"]), 1, "ação chamada uma vez")
	player.free()


func _record_hit(hit: Dictionary, _player: Variant = null) -> void:
	hit["count"] = int(hit["count"]) + 1


func test_interact_without_target_reports_no_action() -> void:
	var interaction := PlayerInteraction.new()
	var provider := FakeProvider.new()
	provider.entries = [_candidate("sem-acao", 1.0, 1.0)]
	interaction.add_provider(provider)
	var player := Node3D.new()
	interaction.refresh_now(player)
	assert_false(interaction.interact(player), "candidato sem ação não é executado")
	player.free()


func test_empty_world_has_no_prompt() -> void:
	var interaction := PlayerInteraction.new()
	var player := Node3D.new()
	interaction.refresh_now(player)
	assert_eq(interaction.prompt_text(), "", "sem candidatos, sem texto")
	assert_false(interaction.has_target(), "sem alvo")
	player.free()


func test_broken_provider_does_not_break_interaction() -> void:
	var interaction := PlayerInteraction.new()
	interaction.add_provider(BrokenProvider.new())
	var provider := FakeProvider.new()
	provider.entries = [_candidate("bom", 1.0, 1.0)]
	interaction.add_provider(provider)
	var player := Node3D.new()
	var best := interaction.refresh_now(player)
	assert_eq(str(best.get("id", "")), "bom", "provedor quebrado é ignorado, não derruba os outros")
	player.free()


func test_refresh_is_throttled() -> void:
	var interaction := PlayerInteraction.new()
	var provider := FakeProvider.new()
	interaction.add_provider(provider)
	var player := Node3D.new()
	interaction.refresh(player, 0.02)
	var first := provider.calls
	interaction.refresh(player, 0.02)
	assert_eq(provider.calls, first, "segunda chamada dentro do intervalo não reavalia")
	interaction.refresh(player, 0.2)
	assert_eq(provider.calls, first + 1, "depois do intervalo reavalia")
	player.free()


func test_prompt_signal_only_on_change() -> void:
	var interaction := PlayerInteraction.new()
	var provider := FakeProvider.new()
	provider.entries = [_candidate("a", 1.0, 1.0)]
	interaction.add_provider(provider)
	var player := Node3D.new()
	interaction.refresh_now(player)
	var emitted := {"count": 0}
	interaction.prompt_changed.connect(func(_text: String) -> void: emitted["count"] = int(emitted["count"]) + 1)
	interaction.refresh_now(player)
	assert_eq(int(emitted["count"]), 0, "mesmo texto não reemite")
	provider.entries = []
	interaction.refresh_now(player)
	assert_eq(int(emitted["count"]), 1, "texto novo reemite")
	player.free()
