class_name FloatingOrigin
extends Node

## Origem flutuante.
##
## O estado do Rio tem cerca de 380 km de extensão; um float de 32 bits perde
## precisão suficiente para tremer geometria muito antes disso. A solução é
## manter o jogador sempre perto da origem: quando ele passa de 2 km, todo o
## conteúdo do mundo desliza 2 km para trás e a origem métrica avança junto.
##
## Dois nós separados para o deslocamento ser barato e seguro:
##   static_root  setores, terreno, ruas, prédios (dezenas de nós)
##   actor_root   jogador, veículos, NPCs (poucos nós)
##
## Nada é recalculado: os nós apenas recebem `position -= offset`, o que mantém
## as posições relativas idênticas e o jogador de volta ao centro.

signal rebased(offset: Vector3)

const REBASE_THRESHOLD := 2048.0

var origin_metric: Vector2 = Vector2.ZERO
var static_root: Node3D = null
var actor_root: Node3D = null
var viewer: Node3D = null
var rebase_count: int = 0


func setup(static_root_node: Node3D, actor_root_node: Node3D, viewer_node: Node3D, start_metric: Vector2) -> void:
	static_root = static_root_node
	actor_root = actor_root_node
	viewer = viewer_node
	origin_metric = start_metric


func metric_to_local(metric: Vector2, height: float = 0.0) -> Vector3:
	return GeoCoordinateSystem.metric_to_local(metric, origin_metric, height)


func local_to_metric(local: Vector3) -> Vector2:
	return GeoCoordinateSystem.local_to_metric(local, origin_metric)


func viewer_metric() -> Vector2:
	if viewer == null:
		return origin_metric
	return local_to_metric(viewer.position)


func viewer_lat_lon() -> Vector2:
	return GeoCoordinateSystem.metric_to_geographic(viewer_metric())


func _physics_process(_delta: float) -> void:
	if viewer == null:
		return
	var p := viewer.position
	if absf(p.x) < REBASE_THRESHOLD and absf(p.z) < REBASE_THRESHOLD:
		return
	rebase(Vector3(p.x, 0.0, p.z))


## Desloca o mundo inteiro em -offset e avança a origem métrica. Chamado
## automaticamente ao cruzar o limiar; os testes chamam direto.
func rebase(offset: Vector3) -> void:
	if offset.length_squared() < 1.0:
		return
	var shifted := Vector3(offset.x, 0.0, offset.z)
	origin_metric += Vector2(shifted.x, -shifted.z)
	rebase_count += 1
	for root in [static_root, actor_root]:
		if root == null:
			continue
		for child in root.get_children():
			var node := child as Node3D
			if node != null:
				node.position -= shifted
	rebased.emit(shifted)
	CariocaBus.get_instance().world_rebased.emit(shifted)
