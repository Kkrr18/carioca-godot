class_name UrbanConfig
extends RefCounted

## Parâmetros da geração urbana — tudo que decide tamanho de lote, recuo, altura
## e densidade de vegetação e mobiliário.
##
## Duas responsabilidades, de propósito no mesmo lugar:
##
## 1. **Ser o único lugar com números de urbanismo.** Nenhum gerador escolhe
##    largura de lote ou recuo por conta própria; todos recebem um `UrbanConfig`.
##
## 2. **Guardar o instantâneo do perfil de qualidade em uso.** A geração de
##    payload roda nas threads de trabalho do streaming, que não podem tocar na
##    árvore de cena nem em objeto de UI. `active()` devolve um instantâneo
##    imutável; trocar de perfil **substitui** o objeto em vez de alterá-lo, de
##    modo que um worker sempre leia um conjunto consistente de números — nunca
##    metade da configuração antiga com metade da nova.

# --- geometria da rua e da quadra -------------------------------------------

## Faixa de calçada, do meio-fio até a frente do lote.
var sidewalk_width: float = 2.4
var curb_height: float = 0.14

## Folga extra entre a calçada e a linha do lote (muro, canteiro).
var block_inset_extra: float = 0.5

var block_min_area: float = 160.0
var block_max_area: float = 260000.0

# --- lote -------------------------------------------------------------------

var parcel_min_area: float = 52.0
var parcel_min_front: float = 7.0
var parcel_max_front: float = 19.0
var parcel_depth_min: float = 13.0
var parcel_depth_max: float = 34.0
var parcel_corner_depth: float = 14.0

## Fator aplicado às larguras de lote. Acima de 1 o mesmo quarteirão rende menos
## lotes — é assim que o perfil mobile economiza geometria sem mudar a cidade.
var parcel_scale: float = 1.0

# --- recuos (afastamentos) ---------------------------------------------------

var setback_front_house: float = 3.2
var setback_front_commercial: float = 1.6
var setback_side: float = 1.2
var setback_rear: float = 2.4

# --- edificação -------------------------------------------------------------

var floor_height: float = 3.05
var max_levels_low_density: int = 3
var max_levels_high_density: int = 22
var min_building_area: float = 28.0

## Teto de edificações por setor. Existe para o perfil mobile, não para a
## cidade: um setor com 200 lotes pequenos não pode virar 200 casas.
var max_buildings: int = 96

## 0 = caixote com cor por andar; 1 = caixote com janelas; 2 = fachada completa
## (janelas, portas, sacadas, vitrine, toldo).
var detail: int = 2

# --- vegetação e mobiliário --------------------------------------------------

var tree_density: float = 1.0
var prop_density: float = 1.0
var tree_spacing: float = 17.0
var light_spacing_arterial: float = 42.0
var light_spacing_collector: float = 52.0
var light_spacing_local: float = 66.0
var max_vegetation_per_sector: int = 320
var max_props_per_sector: int = 260

# --- limites de coerência ----------------------------------------------------

## Densidade urbana mínima para valer a pena gerar quadra/lote. Abaixo disto o
## setor mantém a geração barata da Etapa 1.
var urban_density_threshold: float = 0.26

## Distância mínima de qualquer construção ao eixo de uma via, além da metade da
## pista. Vale como asserção de segurança no fim da geração.
var road_clearance: float = 0.6

## Raio em volta de um ponto de referência em que o gerador não cria lote comum.
var landmark_reserve_radius: float = 16.0

## Faixa não edificável em volta de rio/ferrovia, vinda do próprio dado.
var barrier_buffer: float = 6.0

## Tamanho máximo que uma quadra pode se estender além do setor que a reivindica.
## Quadras na fronteira são geradas por inteiro e pertencem a um setor só (o do
## centroide); o excesso é o preço de não ter costura no meio da rua.
var border_overflow_limit: float = 320.0


## Constrói a configuração a partir de um preset de `QualityProfile`. Chaves
## ausentes mantêm o padrão, então um preset antigo continua funcionando.
static func from_preset(preset: Dictionary) -> UrbanConfig:
	var config := UrbanConfig.new()
	config.detail = clampi(int(preset.get("urban_detail", config.detail)), 0, 2)
	config.tree_density = clampf(float(preset.get("urban_tree_density", config.tree_density)), 0.0, 1.0)
	config.prop_density = clampf(float(preset.get("urban_prop_density", config.prop_density)), 0.0, 1.0)
	config.max_buildings = maxi(int(preset.get("urban_max_buildings", config.max_buildings)), 8)
	config.parcel_scale = clampf(float(preset.get("urban_parcel_scale", config.parcel_scale)), 0.6, 2.0)
	config.max_vegetation_per_sector = maxi(int(preset.get("urban_max_vegetation", config.max_vegetation_per_sector)), 16)
	config.max_props_per_sector = maxi(int(preset.get("urban_max_props", config.max_props_per_sector)), 8)
	config.landmark_reserve_radius = maxf(float(preset.get("urban_landmark_radius", config.landmark_reserve_radius)), 0.0)
	return config


# --- instantâneo em uso ------------------------------------------------------

static var _active: UrbanConfig = null


## Configuração corrente. Uma referência só é lida por inteiro: substituir é
## seguro, alterar em campo durante uma geração não seria.
static func active() -> UrbanConfig:
	if _active == null:
		_active = UrbanConfig.new()
	return _active


static func set_active_from_preset(preset: Dictionary) -> UrbanConfig:
	_active = from_preset(preset)
	return _active


static func set_active(config: UrbanConfig) -> void:
	_active = config


static func reset_for_tests() -> UrbanConfig:
	_active = UrbanConfig.new()
	return _active


## Resumo de uma linha para HUD e relatórios.
func describe() -> String:
	return "lote %.0f–%.0f m de frente · detalhe %d · árvores %.0f%% · mobiliário %.0f%% · teto %d prédios" % [
		parcel_min_front,
		parcel_max_front,
		detail,
		tree_density * 100.0,
		prop_density * 100.0,
		max_buildings,
	]
