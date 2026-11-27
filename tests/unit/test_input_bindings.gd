extends TestCase

## Ações nomeadas e remapeamento de teclas.

func _reset() -> void:
	InputBindings.reset_for_tests()


func test_registration_creates_actions() -> void:
	_reset()
	InputBindings.ensure_registered()
	for action in InputBindings.ACTIONS:
		assert_true(InputMap.has_action(action), "ação %s criada" % action)
		assert_greater(float(InputMap.action_get_events(action).size()), 0.0, "ação %s tem tecla" % action)
	_reset()


func test_registration_is_idempotent() -> void:
	_reset()
	InputBindings.ensure_registered()
	var before := InputMap.action_get_events(InputBindings.ACTION_JUMP).size()
	InputBindings.ensure_registered()
	assert_eq(InputMap.action_get_events(InputBindings.ACTION_JUMP).size(), before, "não duplica eventos")
	_reset()


func test_default_keys() -> void:
	_reset()
	var forward := InputBindings.keys_for(InputBindings.ACTION_FORWARD)
	assert_eq(forward.size(), 2, "frente aceita duas teclas")
	assert_true(forward.has(KEY_W), "W anda para frente")
	assert_true(forward.has(KEY_UP), "seta para cima também")
	assert_eq(InputBindings.primary_key(InputBindings.ACTION_JUMP), KEY_SPACE, "pulo no espaço")
	_reset()


func test_remap_changes_the_binding() -> void:
	_reset()
	InputBindings.ensure_registered()
	assert_true(InputBindings.set_remap(InputBindings.ACTION_JUMP, KEY_F), "remapeamento aceito")
	assert_eq(InputBindings.primary_key(InputBindings.ACTION_JUMP), KEY_F, "tecla nova vale")
	var events := InputMap.action_get_events(InputBindings.ACTION_JUMP)
	assert_eq(events.size(), 1, "um evento só depois do remapeamento")
	assert_eq((events[0] as InputEventKey).keycode, KEY_F, "evento com a tecla nova")
	_reset()


func test_remap_rejects_invalid_input() -> void:
	_reset()
	assert_false(InputBindings.set_remap("acao_que_nao_existe", KEY_F), "ação desconhecida recusada")
	assert_false(InputBindings.set_remap(InputBindings.ACTION_JUMP, 0), "tecla inválida recusada")
	_reset()


func test_apply_remaps_from_settings() -> void:
	_reset()
	InputBindings.ensure_registered()
	InputBindings.apply_remaps({"carioca_interact": KEY_Q, "inexistente": KEY_Z})
	assert_eq(InputBindings.primary_key(InputBindings.ACTION_INTERACT), KEY_Q, "remapeamento aplicado em lote")
	assert_eq(InputBindings.remaps().size(), 1, "ação desconhecida é ignorada")
	InputBindings.reset_remaps()
	assert_eq(InputBindings.primary_key(InputBindings.ACTION_INTERACT), KEY_E, "reset volta ao padrão")
	_reset()


func test_clear_remap_restores_default() -> void:
	_reset()
	InputBindings.set_remap(InputBindings.ACTION_SPRINT, KEY_X)
	InputBindings.clear_remap(InputBindings.ACTION_SPRINT)
	assert_eq(InputBindings.primary_key(InputBindings.ACTION_SPRINT), KEY_SHIFT, "padrão de volta")
	_reset()


func test_move_axis_is_idle_without_input() -> void:
	_reset()
	var axis := InputBindings.move_axis()
	assert_almost_eq(axis.x, 0.0, 1.0e-6, "sem entrada horizontal")
	assert_almost_eq(axis.y, 0.0, 1.0e-6, "sem entrada vertical")
	_reset()


func test_describe_lists_bindings() -> void:
	_reset()
	var text := InputBindings.describe()
	assert_true(text.contains("pulo"), "descrição cita o pulo")
	assert_true(text.contains("interagir"), "descrição cita a interação")
	_reset()
