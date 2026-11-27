class_name ProtagonistModel
extends Node3D

## Modelo visual do protagonista: o `PROTAGONISTA.fbx` importado.
##
## Substitui o `PlaceholderCharacter` quando o `.fbx` já foi importado
## (editor aberto ou `--import` no CI). Sem o import, `load_if_available()`
## devolve nulo e o boneco provisório segue valendo — o jogo nunca fica sem
## personagem, e nenhuma outra parte do código precisa saber qual dos dois está
## no lugar: os dois respondem a `pose(values)`.
##
## Normalização: modelos FBX chegam em escalas e origens arbitrárias (centímetro,
## pés, pivô no chão ou no quadril). Na entrada, a AABB combinada de todas as
## malhas mede o modelo e ele é reescalado para a altura declarada do boneco
## (1,78 m), com os pés em y=0 e o centro x/z no eixo. É o mesmo contrato que o
## boneco de primitivas cumpre, e é o que faz a cápsula de colisão do `Player`
## continuar correta sem mudar um número.
##
## Animação: se a cena importada trouxer um `AnimationPlayer`, ele é devolvido
## para o `CharacterAnimator.bind_player()`. O animador só toca animação cujo
## nome corresponde ao estado (`idle`, `walk`, …) — nomes que não batem não
## tocam nada, e a pose procedural segue valendo no corpo inteiro (bob, lean,
## twist, squash abaixo).

const MODEL_PATH := "res://PROTAGONISTA.fbx"

## Mesma altura declarada pelo `PlaceholderCharacter.HEIGHT`.
const TARGET_HEIGHT := 1.78

## Ajuste de orientação em radianos no eixo Y, se o modelo importado olhar para
## o lado errado ao andar: 180° é `PI`. O contrato do personagem é olhar para
## -Z, igual à frente da câmera da Godot.
var facing_yaw: float = 0.0

var animation_player: AnimationPlayer = null

var _model: Node3D = null
var _base_position := Vector3.ZERO
var _base_yaw := 0.0
var _base_scale := Vector3.ONE


## Fábrica: devolve o modelo pronto ou `null` quando o `.fbx` não está
## importado — nunca levanta erro, nunca deixa cena vazia.
static func load_if_available() -> ProtagonistModel:
	if not ResourceLoader.exists(MODEL_PATH):
		return null
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return null
	var model := ProtagonistModel.new()
	if not model._build(packed):
		model.free()
		return null
	return model


func _build(packed: PackedScene) -> bool:
	var scene := packed.instantiate()
	if scene == null:
		return false
	_model = scene
	add_child(scene)

	var aabb := _combined_aabb(scene, Transform3D.IDENTITY)
	if aabb.size.y > 0.001:
		var s := TARGET_HEIGHT / aabb.size.y
		_base_scale = Vector3(s, s, s)
		# Pés no chão: o fundo da AABB vai para y=0. Centro x/z no eixo,
		# porque o pivô do FBX raramente fica no meio do personagem.
		_base_position = Vector3(
			-aabb.get_center().x * s,
			-aabb.position.y * s,
			-aabb.get_center().z * s
		)
	_model.position = _base_position
	_base_yaw = facing_yaw
	_model.rotation.y = _base_yaw
	_model.scale = _base_scale

	animation_player = _find_animation_player(scene)
	return true


## AABB combinada de todas as malhas, com os transforms acumulados — a cena
## ainda não está na árvore, então não existe AABB global pronta.
func _combined_aabb(node: Node3D, parent_xform: Transform3D) -> AABB:
	var xform := parent_xform * node.transform
	var parts: Array[AABB] = []
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			parts.append(xform * mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			var child_aabb := _combined_aabb(child, xform)
			if child_aabb.size.length_squared() > 0.0:
				parts.append(child_aabb)
	if parts.is_empty():
		return AABB()
	var total := parts[0]
	for i in range(1, parts.size()):
		total = total.merge(parts[i])
	return total


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


## Aplica a pose produzida por `CharacterAnimator`.
##
## Sem esqueleto conhecido, o corpo inteiro responde ao que dá para responder
## sem inventar juntas: sobe e desce com o passo (bob), inclina na corrida
## (lean), torce no giro (twist) e comprime na aterrissagem (squash). Os
## valores base da normalização são compostos, nunca sobrescritos.
func pose(values: Dictionary) -> void:
	if _model == null:
		return
	var bob := float(values.get("bob", 0.0))
	var lean := float(values.get("lean", 0.0))
	var twist := float(values.get("twist", 0.0))
	var squash := clampf(float(values.get("squash", 1.0)), 0.6, 1.4)
	var widen := 1.0 + (1.0 - squash) * 0.55

	_model.position = _base_position + Vector3(0.0, bob, 0.0)
	_model.rotation.y = _base_yaw + twist
	_model.rotation.x = lean
	_model.scale = Vector3(
		_base_scale.x * widen,
		_base_scale.y * squash,
		_base_scale.z * widen
	)


## Altura visual, para câmera e mira. Não é a altura da cápsula de colisão.
func eye_height() -> float:
	return TARGET_HEIGHT * 0.9
