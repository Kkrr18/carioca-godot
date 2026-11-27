extends TestCase

## Boneco provisório: estrutura de juntas e aplicação de pose.
##
## O teste existe para uma coisa só, e é importante: garantir que o substituto
## **tem juntas de verdade**, para que trocar o boneco por um modelo importado
## seja substituir nós, e não reescrever a animação.

func _character() -> PlaceholderCharacter:
	var root := Node3D.new()
	tree.root.add_child(root)
	var character := PlaceholderCharacter.new()
	root.add_child(character)
	return character


func test_builds_body_and_joints() -> void:
	var character := _character()
	assert_not_null(character.body, "corpo construído")
	assert_eq(character.joint_count(), 4, "dois braços e duas pernas")
	for joint_name in ["arm_l", "arm_r", "leg_l", "leg_r"]:
		assert_not_null(character.joint(joint_name), "junta %s existe" % joint_name)
	character.get_parent().free()


func test_pose_rotates_opposite_limbs() -> void:
	var character := _character()
	character.pose({"leg_swing": 0.5, "arm_swing": -0.3})
	var left := character.joint("leg_l")
	var right := character.joint("leg_r")
	assert_almost_eq(left.rotation.x, 0.5, 1.0e-5, "perna esquerda vai para frente")
	assert_almost_eq(right.rotation.x, -0.5, 1.0e-5, "perna direita vai para trás")
	assert_almost_eq(character.joint("arm_l").rotation.x, -0.3, 1.0e-5, "braço esquerdo acompanha ao contrário")
	character.get_parent().free()


func test_pose_applies_bob_lean_and_squash() -> void:
	var character := _character()
	character.pose({"bob": 0.04, "lean": 0.12, "twist": 0.05, "squash": 0.85})
	assert_almost_eq(character.body.position.y, 0.04, 1.0e-5, "subida do quadril")
	assert_almost_eq(character.body.rotation.x, 0.12, 1.0e-5, "inclinação do tronco")
	assert_almost_eq(character.body.rotation.y, 0.05, 1.0e-5, "torção do tronco")
	assert_true(character.body.scale.y < 1.0, "esmagamento reduz a altura")
	assert_true(character.body.scale.x > 1.0, "esmagamento alarga")
	character.get_parent().free()


func test_missing_keys_fall_back_to_neutral() -> void:
	var character := _character()
	character.pose({})
	assert_almost_eq(character.joint("leg_l").rotation.x, 0.0, 1.0e-6, "sem chave, neutro")
	assert_almost_eq(character.body.position.y, 0.0, 1.0e-6, "sem subida")
	character.get_parent().free()


func test_squash_is_clamped() -> void:
	var character := _character()
	character.pose({"squash": 0.01})
	assert_true(character.body.scale.y >= 0.6, "esmagamento tem limite inferior")
	character.pose({"squash": 9.0})
	assert_true(character.body.scale.y <= 1.4, "esmagamento tem limite superior")
	character.get_parent().free()


func test_eye_height_is_reported() -> void:
	var character := _character()
	assert_greater(character.eye_height(), 1.0, "altura dos olhos plausível")
	assert_greater(float(PlaceholderCharacter.HEIGHT), 1.5, "altura declarada do boneco")
	character.get_parent().free()
