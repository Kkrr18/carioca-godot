extends TestCase

## Multitouch do HUD: analógico e olhar ao mesmo tempo, pinça de zoom.
##
## O bug que este teste prende: um terceiro toque (ou um segundo na metade
## esquerda) virava pinça com uma distância inicial arbitrária, e a abertura da
## pinça era medida contra a posição do dedo de olhar **depois** de sobrescrevê-la
## — dava sempre 0, o zoom acumulava desvio a cada arrasto e a câmera desbocava
## justamente ao andar com o analógico e olhar com o dedo.

func _controls() -> TouchControls:
	var touch := TouchControls.new()
	touch.size = Vector2(1000.0, 600.0)
	touch._layout()
	return touch


func test_analog_and_look_work_together() -> void:
	var touch := _controls()
	touch.handle_touch(0, Vector2(200.0, 450.0), true)
	touch.handle_touch(1, Vector2(900.0, 300.0), true)
	touch.handle_drag(0, Vector2(240.0, 410.0))
	touch.handle_drag(1, Vector2(860.0, 320.0))
	assert_true(touch.move_vector.length() > 0.0, "analógico responde com o olhar pressionado")
	assert_true(touch.consume_look().length() > 0.0, "olhar responde com o analógico pressionado")
	assert_almost_eq(touch.consume_zoom(), 0.0, 1.0e-6, "nenhum zoom sem dois dedos na área de olhar")


func test_extra_touch_on_the_left_never_becomes_a_pinch() -> void:
	var touch := _controls()
	touch.handle_touch(0, Vector2(200.0, 450.0), true)
	touch.handle_touch(1, Vector2(200.0, 300.0), true)
	touch.handle_touch(2, Vector2(160.0, 500.0), true)
	touch.handle_drag(2, Vector2(180.0, 520.0))
	touch.handle_drag(1, Vector2(210.0, 310.0))
	assert_almost_eq(touch.consume_zoom(), 0.0, 1.0e-6, "toque extra à esquerda não vira pinça nem desbosca o zoom")


func test_pinch_measures_the_real_span_between_the_fingers() -> void:
	var touch := _controls()
	touch.handle_touch(0, Vector2(900.0, 300.0), true)
	touch.handle_touch(1, Vector2(940.0, 300.0), true)
	touch.handle_drag(1, Vector2(1140.0, 300.0))
	# Abertura inicial 40, final 400: o delta é a mudança real, não desvio.
	assert_almost_eq(touch.consume_zoom(), 360.0, 1.0e-3, "pinça mede a abertura real entre os dedos")


func test_releasing_the_look_finger_ends_the_pinch() -> void:
	var touch := _controls()
	touch.handle_touch(0, Vector2(900.0, 300.0), true)
	touch.handle_touch(1, Vector2(940.0, 300.0), true)
	touch.handle_touch(0, Vector2(900.0, 300.0), false)
	touch.handle_drag(1, Vector2(1140.0, 300.0))
	assert_almost_eq(touch.consume_zoom(), 0.0, 1.0e-6, "sem o dedo de olhar, a pinça termina")


func test_releasing_everything_returns_to_rest() -> void:
	var touch := _controls()
	touch.handle_touch(0, Vector2(200.0, 450.0), true)
	touch.handle_touch(1, Vector2(900.0, 300.0), true)
	touch.handle_drag(1, Vector2(860.0, 320.0))
	touch.handle_touch(1, Vector2(860.0, 320.0), false)
	touch.handle_touch(0, Vector2(240.0, 410.0), false)
	assert_almost_eq(touch.move_vector.length(), 0.0, 1.0e-6, "soltar o analógico zera o movimento")
	assert_almost_eq(touch.consume_look().length(), 0.0, 1.0e-6, "soltar o olhar zera o delta pendente")
