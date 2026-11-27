class_name UrbanSchema
extends RefCounted

## Vocabulário e versões da geração urbana (Etapa 3).
##
## O payload de setor continua com o schema da Etapa 2 (`WorldSchema`). O que
## esta classe versiona é a camada urbana **dentro** dele: quadras, lotes,
## tipologias e mobiliário. Um setor gerado pela Etapa 3 carrega
## `urban_version = 3` e `urban_v3 = true`, e o `SectorInstance` usa isso para
## escolher o construtor de malha detalhado em vez do caixote da Etapa 1.
##
## Nada aqui é numérico de ajuste: os números de geração moram em `UrbanConfig`.
## Isto aqui é só o vocabulário, para que gerador, construtor de malha,
## ferramentas e testes concordem sobre os mesmos nomes.

const URBAN_VERSION := 3

## Origem dos dados de rua de um setor.
##
## `osm`        extrato importado pelo `import_osm.gd` (geometria real).
## `estimado`   traçado esquemático autoral de `data/geographic/urban`
##              (georreferenciado, mas NÃO é dado cadastral nem OSM).
## `procedural` reticulação determinística da Etapa 1, sem dado externo.
const SOURCE_OSM := "osm"
const SOURCE_ESTIMATED := "estimado"
const SOURCE_PROCEDURAL := "procedural"

# --- tipologias de edificação ------------------------------------------------

const TYPOLOGY_HOUSE_GROUND := "house_ground"
const TYPOLOGY_HOUSE_TWO_STOREY := "house_two_storey"
const TYPOLOGY_HOUSE_GARAGE := "house_with_garage"
const TYPOLOGY_HOUSE_PORCH := "house_with_porch"
const TYPOLOGY_RESIDENTIAL_BUILDING := "residential_building"
const TYPOLOGY_COMMERCIAL_BUILDING := "commercial_building"
const TYPOLOGY_MIXED_BUILDING := "mixed_building"

const TYPOLOGIES: Array[String] = [
	TYPOLOGY_HOUSE_GROUND,
	TYPOLOGY_HOUSE_TWO_STOREY,
	TYPOLOGY_HOUSE_GARAGE,
	TYPOLOGY_HOUSE_PORCH,
	TYPOLOGY_RESIDENTIAL_BUILDING,
	TYPOLOGY_COMMERCIAL_BUILDING,
	TYPOLOGY_MIXED_BUILDING,
]

## Categoria de uso — o mesmo vocabulário de `kind` que a Etapa 1 já grava, para
## que trânsito, pedestres e porta de interior continuem lendo sem mudança.
const KIND_RESIDENTIAL := "residential"
const KIND_COMMERCIAL := "commercial"
const KIND_MIXED := "mixed"
const KIND_PUBLIC := "public"

# --- coberturas --------------------------------------------------------------

const ROOF_FLAT := "flat"
const ROOF_GABLE := "gable"
const ROOF_HIP := "hip"
const ROOF_MONOSLOPE := "monoslope"
const ROOF_SHED := "shed"

# --- módulos de fachada ------------------------------------------------------

const MODULE_WINDOW := "window"
const MODULE_DOOR := "door"
const MODULE_GARAGE := "garage"
const MODULE_PORCH := "porch"
const MODULE_BALCONY := "balcony"
const MODULE_SHOPFRONT := "shopfront"
const MODULE_AWNING := "awning"
const MODULE_STAIRS := "stairs"

## Lados de uma edificação no referencial (u, n) do lote.
##   0 frente (para a rua)   1 direita   2 fundos   3 esquerda
const SIDE_FRONT := 0
const SIDE_RIGHT := 1
const SIDE_BACK := 2
const SIDE_LEFT := 3

# --- mobiliário urbano -------------------------------------------------------

const PROP_LIGHT := "light"
const PROP_TRAFFIC_LIGHT := "traffic_light"
const PROP_SIGN := "sign"
const PROP_BIN := "bin"
const PROP_BENCH := "bench"
const PROP_SHELTER := "shelter"
const PROP_UTILITY_BOX := "utility_box"
const PROP_CROSSWALK := "crosswalk"
const PROP_LANE_MARKING := "lane_marking"

const PROP_TYPES: Array[String] = [
	PROP_LIGHT,
	PROP_TRAFFIC_LIGHT,
	PROP_SIGN,
	PROP_BIN,
	PROP_BENCH,
	PROP_SHELTER,
	PROP_UTILITY_BOX,
]

# --- vegetação ---------------------------------------------------------------

const SPECIES_TREE := 0
const SPECIES_TREE_TALL := 1
const SPECIES_BUSH := 2
const SPECIES_GRASS := 3

const SPECIES_NAMES: Array[String] = ["arvore", "arvore_alta", "arbusto", "gramado"]

# --- comércio ----------------------------------------------------------------

## Categorias genéricas. Nenhuma marca, nenhum logotipo: o sistema é feito para
## receber identificação de estabelecimento vindo de dado geográfico autorizado,
## e até lá usa rótulo genérico por categoria.
const CATEGORY_MARKET := "mercado"
const CATEGORY_PHARMACY := "farmacia"
const CATEGORY_RESTAURANT := "restaurante"
const CATEGORY_STORE := "loja"
const CATEGORY_WORKSHOP := "oficina"
const CATEGORY_BAKERY := "padaria"
const CATEGORY_SMALL := "pequeno_estabelecimento"

const COMMERCE_CATEGORIES: Array[String] = [
	CATEGORY_MARKET,
	CATEGORY_PHARMACY,
	CATEGORY_RESTAURANT,
	CATEGORY_STORE,
	CATEGORY_WORKSHOP,
	CATEGORY_BAKERY,
	CATEGORY_SMALL,
]

const CATEGORY_LABELS := {
	CATEGORY_MARKET: "Mercado",
	CATEGORY_PHARMACY: "Farmácia",
	CATEGORY_RESTAURANT: "Restaurante",
	CATEGORY_STORE: "Loja",
	CATEGORY_WORKSHOP: "Oficina",
	CATEGORY_BAKERY: "Padaria",
	CATEGORY_SMALL: "Comércio",
}

# --- papéis de ponto de referência -------------------------------------------

const ROLE_LANDMARK := "landmark"
const ROLE_BARRIER := "barrier"
const ROLE_OPEN_SPACE := "open_space"

## Rótulos de confiança usados nos dados de referência. Existem para que uma
## posição aproximada nunca seja lida como levantamento.
const CONFIDENCE_HIGH := "alta"
const CONFIDENCE_MEDIUM := "media"
const CONFIDENCE_LOW := "baixa"

const CONFIDENCE_LABELS := {
	CONFIDENCE_HIGH: "alta",
	CONFIDENCE_MEDIUM: "média",
	CONFIDENCE_LOW: "baixa (posição aproximada)",
}


static func is_typology(value: String) -> bool:
	return TYPOLOGIES.has(value)


static func kind_for_typology(typology: String) -> String:
	match typology:
		TYPOLOGY_COMMERCIAL_BUILDING:
			return KIND_COMMERCIAL
		TYPOLOGY_MIXED_BUILDING:
			return KIND_MIXED
		_:
			return KIND_RESIDENTIAL


## Rótulo legível para o HUD, o inspetor e o relatório.
static func typology_label(typology: String) -> String:
	match typology:
		TYPOLOGY_HOUSE_GROUND:
			return "casa térrea"
		TYPOLOGY_HOUSE_TWO_STOREY:
			return "casa de dois pavimentos"
		TYPOLOGY_HOUSE_GARAGE:
			return "casa com garagem"
		TYPOLOGY_HOUSE_PORCH:
			return "casa com varanda"
		TYPOLOGY_RESIDENTIAL_BUILDING:
			return "edifício residencial"
		TYPOLOGY_COMMERCIAL_BUILDING:
			return "prédio comercial"
		TYPOLOGY_MIXED_BUILDING:
			return "construção mista"
		_:
			return typology
