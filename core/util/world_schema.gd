class_name WorldSchema
extends RefCounted

## Versões e constantes compartilhadas entre geradores, importadores, runtime e
## testes. Existe para evitar dependência circular entre eles.

const SECTOR_SCHEMA_VERSION := 2
const SAVE_FORMAT_VERSION := 1
const GEO_DATA_VERSION := 1

## Classes de via (mesmos nomes do OpenStreetMap, reduzidos ao que o jogo usa).
const ROAD_ARTERIAL := "arterial"
const ROAD_COLLECTOR := "collector"
const ROAD_LOCAL := "local"
const ROAD_SERVICE := "service"
const ROAD_PATH := "path"

const ROAD_WIDTHS := {
	"arterial": 14.0,
	"collector": 9.0,
	"local": 6.0,
	"service": 4.5,
	"path": 2.5,
}


static func width_for(road_class: String) -> float:
	return float(ROAD_WIDTHS.get(road_class, 6.0))


## Converte uma classe viária do OSM na classe interna.
static func classify_highway(highway_tag: String) -> String:
	match highway_tag:
		"motorway", "trunk", "primary", "secondary":
			return ROAD_ARTERIAL
		"tertiary", "motorway_link", "trunk_link", "primary_link", "secondary_link":
			return ROAD_COLLECTOR
		"residential", "unclassified", "living_street", "pedestrian":
			return ROAD_LOCAL
		"service", "track":
			return ROAD_SERVICE
		"footway", "path", "cycleway", "steps", "bridleway":
			return ROAD_PATH
		_:
			return ROAD_LOCAL
