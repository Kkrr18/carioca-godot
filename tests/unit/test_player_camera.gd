extends TestCase

## Câmera em terceira pessoa: limites, zoom, inversão e alvo.
##
## O teste roda com árvore de cena (o nó existe), mas **sem consulta de física
## válida** quando não há mundo: o caminho de colisão devolve a distância pedida.
## O que se testa aqui é a regra, não o raycast.

func _camera() -> PlayerCamera:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	var camera := PlayerCamera.new()
	holder.add_child(camera)
	return camera


func test_creates_a_current_camera() -> void:
	var rig := _camera()
	assert_not_null(rig.camera, "câmera criada")
	assert_true(rig.camera.current, "câmera é a atual")
	rig.get_parent().free()


func test_pitch_limits_are_respected_by_configuration() -> void:
	var rig := _camera()
	assert_true(PlayerCamera.PITCH_MIN < 0.0, "limite inferior de inclinação é negativo")
	assert_true(PlayerCamera.PITCH_MAX > 0.0, "limite superior de inclinação é positivo")
	assert_true(PlayerCamera.PITCH_MIN > -PI * 0.5, "não passa de olhar para baixo do próprio corpo")
	rig.get_parent().free()


func test_zoom_respects_its_bounds() -> void:
	var rig := _camera()
	rig.distance = 4.0
	rig.min_distance = 1.5
	rig.max_distance = 6.0
	for _i in range(20):
		rig.zoom(1.0)
	assert_almost_eq(rig.distance, 1.5, 1.0e-5, "zoom máximo limitado pelo mínimo")
	for _i in range(40):
		rig.zoom(-1.0)
	assert_almost_eq(rig.distance, 6.0, 1.0e-5, "zoom mínimo limitado pelo máximo")
	rig.get_parent().free()


func test_invert_y_is_applied_to_the_touch_delta() -> void:
	var rig := _camera()
	var touch := TouchControls.new()
	rig.touch_controls = touch
	rig.invert_y = true
	var before := rig.pitch
	touch.handle_touch(0, Vector2(900.0, 400.0), true)
	touch.handle_drag(0, Vector2(900.0, 360.0))
	rig._consume_touch_look()
	assert_true(rig.pitch != before, "inversão muda a inclinação na direção oposta")
	rig.get_parent().free()


func test_sensitivity_is_clamped() -> void:
	var rig := _camera()
	rig.set_sensitivity(0.0)
	assert_greater(rig.sensitivity, 0.0, "sensibilidade nunca é zero")
	rig.get_parent().free()


func test_reset_yaw_follows_the_target() -> void:
	var rig := _camera()
	var target := Node3D.new()
	rig.get_parent().add_child(target)
	target.rotation.y = 1.1
	rig.set_target(target)
	rig.yaw = -2.0
	rig.reset_yaw()
	assert_almost_eq(rig.yaw, 1.1, 1.0e-5, "recentrar volta o yaw ao alvo")
	target.free()
	rig.get_parent().free()


func test_yaw_is_a_property_for_the_interior_manager() -> void:
	var rig := _camera()
	# O `InteriorManager` escreve `player.camera_rig.yaw = PI`. Se `yaw` virar
	# método ou sumir, esse caminho quebra — e este teste é o aviso.
	rig.yaw = PI
	assert_almost_eq(rig.yaw, PI, 1.0e-6, "yaw continua sendo propriedade")
	assert_almost_eq(rig.yaw_angle(), PI, 1.0e-6, "leitor devolve o valor")
	rig.get_parent().free()


func test_preset_applies_camera_numbers() -> void:
	var rig := _camera()
	rig.apply_preset({
		"camera_distance": 5.0,
		"camera_min_distance": 2.0,
		"camera_max_distance": 7.0,
		"camera_smoothing": 1.4,
		"camera_collision_margin": 0.5,
		"camera_sensitivity": 0.003,
	})
	assert_almost_eq(rig.max_distance, 7.0, 1.0e-5, "distância máxima do preset")
	assert_almost_eq(rig.sensitivity, 0.003, 1.0e-6, "sensibilidade do preset")
	assert_almost_eq(rig.distance, 5.0, 1.0e-5, "distância do preset")
	rig.get_parent().free()
