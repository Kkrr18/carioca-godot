class_name PlaceholderCharacter
extends Node3D

## Boneco provisório do jogador, montado com primitivas.
##
## **Isto não é um modelo humano.** É um substituto funcional: doze nós com
## juntas de verdade (quadril, ombro, tornozelo não), para que a animação
## procedural do `CharacterAnimator` tenha onde acontecer e o jogador consiga ler
## para onde o personagem está virado e a que velocidade anda.
##
## Por que não usar os `.fbx` da raiz do repositório: eles não têm licença
## declarada no projeto, não são importados por nada e o ambiente onde esta etapa
## foi escrita não consegue abrir um `.fbx` para saber o que há dentro. Dizer que
## são "o personagem" seria inventar. O caminho para trocar é real e está pronto:
## basta um `Player` com um `CharacterAnimator.bind_tree()` apontando para um
## `AnimationTree` de um modelo importado; a pose procedural continua existindo
## como fallback.
##
## Convenção de eixo: o personagem olha para -Z (frente), como a câmera da Godot.
## Girar uma junta em +X joga a ponta para frente.

const HEIGHT := 1.78

var body: Node3D = null

var _joints: Dictionary = {}
var _torso: MeshInstance3D = null
var _head: MeshInstance3D = null
var _accent: MeshInstance3D = null
var _skin_material: StandardMaterial3D = null
var _cloth_material: StandardMaterial3D = null


func _ready() -> void:
	if body == null:
		_build()


func _build() -> void:
	_skin_material = MaterialLibrary.pedestrian(Color(0.72, 0.54, 0.42))
	_cloth_material = MaterialLibrary.pedestrian(Color(0.20, 0.33, 0.55))

	body = Node3D.new()
	body.name = "Body"
	add_child(body)

	_torso = _mesh(CapsuleMesh.new(), _cloth_material, "Torso")
	var torso_mesh := _torso.mesh as CapsuleMesh
	torso_mesh.radius = 0.21
	torso_mesh.height = 0.62
	torso_mesh.radial_segments = 10
	torso_mesh.rings = 3
	_torso.position = Vector3(0.0, 1.16, 0.0)

	_head = _mesh(SphereMesh.new(), _skin_material, "Head")
	var head_mesh := _head.mesh as SphereMesh
	head_mesh.radius = 0.125
	head_mesh.height = 0.25
	head_mesh.radial_segments = 10
	head_mesh.rings = 5
	_head.position = Vector3(0.0, 1.60, 0.0)

	# Marca de frente no peito: sem ela não dá para saber para onde ele olha.
	_accent = _mesh(BoxMesh.new(), MaterialLibrary.pedestrian(Color(0.92, 0.76, 0.35)), "Front")
	(_accent.mesh as BoxMesh).size = Vector3(0.14, 0.14, 0.06)
	_accent.position = Vector3(0.0, 1.20, -0.2)

	_joints["arm_l"] = _limb("ArmL", Vector3(-0.25, 1.38, 0.0), Vector3(0.085, 0.5, 0.085), _cloth_material)
	_joints["arm_r"] = _limb("ArmR", Vector3(0.25, 1.38, 0.0), Vector3(0.085, 0.5, 0.085), _cloth_material)
	_joints["leg_l"] = _limb("LegL", Vector3(-0.11, 0.86, 0.0), Vector3(0.13, 0.82, 0.13), _cloth_material)
	_joints["leg_r"] = _limb("LegR", Vector3(0.11, 0.86, 0.0), Vector3(0.13, 0.82, 0.13), _cloth_material)


func _mesh(mesh: Mesh, material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(instance)
	return instance


func _limb(node_name: String, origin: Vector3, size: Vector3, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = origin
	body.add_child(pivot)

	var instance := MeshInstance3D.new()
	instance.name = node_name + "Mesh"
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = material
	instance.position = Vector3(0.0, -size.y * 0.5, 0.0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pivot.add_child(instance)
	return pivot


## Aplica a pose produzida por `CharacterAnimator`.
##
## Espera as chaves: leg_swing, arm_swing, bob, lean, twist, squash.
## Valores ausentes caem para neutro — o boneco nunca fica em pose inválida.
func pose(values: Dictionary) -> void:
	if body == null:
		return
	var leg := float(values.get("leg_swing", 0.0))
	var arm := float(values.get("arm_swing", 0.0))
	var bob := float(values.get("bob", 0.0))
	var lean := float(values.get("lean", 0.0))
	var twist := float(values.get("twist", 0.0))
	var squash := clampf(float(values.get("squash", 1.0)), 0.6, 1.4)

	body.position.y = bob
	body.rotation.x = lean
	body.rotation.y = twist
	var widen := 1.0 + (1.0 - squash) * 0.55
	body.scale = Vector3(widen, squash, widen)

	_apply_joint("leg_l", leg)
	_apply_joint("leg_r", -leg)
	_apply_joint("arm_l", arm)
	_apply_joint("arm_r", -arm)


func _apply_joint(joint_name: String, angle: float) -> void:
	var joint: Node3D = _joints.get(joint_name, null)
	if joint != null:
		joint.rotation.x = angle


func joint(joint_name: String) -> Node3D:
	return _joints.get(joint_name, null)


func joint_count() -> int:
	return _joints.size()


## Altura visual, para câmera e mira. Não é a altura da cápsula de colisão.
func eye_height() -> float:
	return 1.6


func set_body_color(color: Color) -> void:
	if _cloth_material != null:
		_cloth_material.albedo_color = color
