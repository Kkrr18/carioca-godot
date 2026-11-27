class_name LodProfile
extends RefCounted

## Perfil de LOD do terreno: quantos níveis existem, a que distância cada um
## começa e quanto custa trocar.
##
## Os números vêm do perfil de qualidade (`QualityProfile`), que é o único lugar
## onde "mobile" e "PC alto" divergem. Este arquivo só dá semântica a eles.
##
## Convenção: nível 0 é o mais detalhado. A distância de um nível é o limite
## superior da faixa; `0` na última posição significa "sem limite".

const MAX_LEVELS := 4
const DEFAULT_DIVISIONS := [33, 21, 13, 7]
const DEFAULT_DISTANCES := [420.0, 900.0, 1600.0, 0.0]

## Divisões da malha por nível. Diminuir divisões diminui triângulos com o
## quadrado do número: 33 -> 13 é 6,4x menos geometria no mesmo setor.
var divisions: Array[int] = []

## Distância (metros) até onde o nível vale.
var distances: Array[float] = []

## Até que nível o terreno recebe colisão de trimesh. Colisão de terreno é a
## estrutura mais caras do setor (BVH sobre todos os triângulos), então só entra
## onde o jogador pode encostar.
var collision_level: int = 1

## Profundidade da saia vertical em volta da malha, em metros. É o que impede
## rachadura visível quando dois setores vizinhos estão em níveis diferentes.
var skirt: float = 6.0

## O controlador só reavalia quando o jogador andou isto desde a última vez.
var update_distance: float = 32.0

var max_switches_per_frame: int = 2
var switch_budget_usec: int = 5000

## Tempo mínimo que uma mudança de nível precisa se sustentar antes de ser
## aplicada. É a histerese que evita oscilar parado na fronteira de faixa.
var switch_delay: float = 0.5


static func from_preset(preset: Dictionary) -> LodProfile:
	var profile := LodProfile.new()
	var raw_divisions: Array = preset.get("lod_divisions", DEFAULT_DIVISIONS)
	var raw_distances: Array = preset.get("lod_distances", DEFAULT_DISTANCES)

	var count := clampi(raw_divisions.size(), 1, MAX_LEVELS)
	var previous_divisions := 0
	for i in range(count):
		var value := maxi(int(raw_divisions[i]), 2)
		if previous_divisions > 0 and value >= previous_divisions:
			# Divisões têm de cair a cada nível; um perfil mal escrito não pode
			# gerar mais geometria no nível distante do que no próximo.
			value = maxi(previous_divisions - 1, 2)
		profile.divisions.append(value)
		previous_divisions = value

	var previous_distance := 0.0
	for i in range(count):
		var distance := 0.0
		if i < raw_distances.size():
			distance = float(raw_distances[i])
		var is_last := i == count - 1
		if distance <= 0.0 and not is_last:
			distance = previous_distance + 1.0
		if distance > 0.0 and previous_distance > 0.0 and distance <= previous_distance:
			distance = previous_distance + 1.0
		profile.distances.append(distance)
		if distance > 0.0:
			previous_distance = distance

	profile.collision_level = clampi(int(preset.get("lod_collision_level", 1)), 0, count - 1)
	profile.skirt = maxf(float(preset.get("lod_skirt", 6.0)), 0.0)
	profile.update_distance = maxf(float(preset.get("lod_update_distance", 32.0)), 1.0)
	profile.max_switches_per_frame = maxi(int(preset.get("lod_max_switches", 2)), 1)
	profile.switch_budget_usec = maxi(int(preset.get("lod_switch_budget_usec", 5000)), 1000)
	profile.switch_delay = maxf(float(preset.get("lod_switch_delay", 0.5)), 0.0)
	return profile


func level_count() -> int:
	return divisions.size()


func level_for_distance(distance: float) -> int:
	for i in range(distances.size()):
		var limit := distances[i]
		if limit <= 0.0 or distance <= limit:
			return i
	return maxi(distances.size() - 1, 0)


func divisions_for(level: int) -> int:
	if divisions.is_empty():
		return 33
	return divisions[clampi(level, 0, divisions.size() - 1)]


func has_collision(level: int) -> bool:
	return level <= collision_level


## Faixa do nível em texto, para o HUD e para o relatório de integração.
func describe() -> String:
	var parts: Array[String] = []
	for i in range(level_count()):
		var limit := distances[i]
		var label := "∞" if limit <= 0.0 else "%.0f m" % limit
		parts.append("L%d %d div até %s" % [i, divisions_for(i), label])
	return " · ".join(parts)
