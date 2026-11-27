class_name OsmParser
extends RefCounted

## Leitor de extratos OpenStreetMap no formato .osm (XML).
##
## Duas passadas na prática: o arquivo lista todos os <node> antes dos <way>,
## então os nós já estão resolvidos quando as vias chegam. Só os nós dentro da
## caixa delimitadora são guardados — um extrato estadual tem milhões de nós e
## não cabe inteiro em memória de propósito.
##
## Extrai três coisas que o jogo usa: vias, pegadas de edificação e água.

const MAX_NODES_DEFAULT := 6000000


## Retorna { "features": Array, "node_count": int, "way_count": int, "warnings": Array }.
static func parse_file(path: String, bounds: Rect2, max_nodes: int = MAX_NODES_DEFAULT) -> Dictionary:
	var result := {
		"features": [],
		"node_count": 0,
		"way_count": 0,
		"warnings": [],
	}
	var parser := XMLParser.new()
	if parser.open(path) != OK:
		result["warnings"].append("não foi possível abrir %s" % path)
		return result

	var node_coords := {}
	var limit_reached := false
	var current_way := {}
	var way_nodes: Array = []
	var way_tags := {}
	var in_way := false

	var error := parser.read()
	while error == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var element := parser.get_node_name()
			match element:
				"node":
					var lat_text := parser.get_named_attribute_value_safe("lat")
					var lon_text := parser.get_named_attribute_value_safe("lon")
					if not lat_text.is_empty() and not lon_text.is_empty():
						var lat := float(lat_text)
						var lon := float(lon_text)
						if bounds.has_point(Vector2(lon, lat)):
							if node_coords.size() < max_nodes:
								node_coords[int(parser.get_named_attribute_value_safe("id"))] = Vector2(lat, lon)
							else:
								limit_reached = true
				"way":
					in_way = true
					way_nodes = []
					way_tags = {}
					current_way = {"id": parser.get_named_attribute_value_safe("id")}
				"nd":
					if in_way:
						way_nodes.append(int(parser.get_named_attribute_value_safe("ref")))
				"tag":
					if in_way:
						way_tags[parser.get_named_attribute_value_safe("k")] = parser.get_named_attribute_value_safe("v")
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "way" and in_way:
				in_way = false
				result["way_count"] = int(result["way_count"]) + 1
				var feature := _build_feature(current_way, way_nodes, way_tags, node_coords)
				if not feature.is_empty():
					(result["features"] as Array).append(feature)
		error = parser.read()

	result["node_count"] = node_coords.size()
	if limit_reached:
		(result["warnings"] as Array).append("limite de nós atingido: recorte o extrato por município")
	return result


static func _build_feature(way: Dictionary, node_refs: Array, tags: Dictionary, node_coords: Dictionary) -> Dictionary:
	var points := PackedVector2Array()
	for ref in node_refs:
		if node_coords.has(ref):
			points.append(node_coords[ref])
	if points.size() < 2:
		return {}
	if tags.has("highway"):
		var highway := str(tags["highway"])
		var road_class := WorldSchema.classify_highway(highway)
		return {
			"kind": "road",
			"road_class": road_class,
			"highway": highway,
			"width": WorldSchema.width_for(road_class),
			"name": str(tags.get("name", "")),
			"oneway": str(tags.get("oneway", "no")) == "yes",
			"points": points,
		}
	if tags.has("building") or tags.has("building:part"):
		if points.size() < 3:
			return {}
		return {
			"kind": "building",
			"levels": _levels_from(tags),
			"height": _height_from(tags),
			"building": str(tags.get("building", "yes")),
			"name": str(tags.get("name", "")),
			"points": points,
		}
	if str(tags.get("natural", "")) == "water" or tags.has("waterway") or str(tags.get("landuse", "")) == "reservoir":
		if points.size() < 3:
			return {}
		return {
			"kind": "water",
			"name": str(tags.get("name", "")),
			"points": points,
		}
	return {}


static func _levels_from(tags: Dictionary) -> int:
	if tags.has("building:levels"):
		var raw := str(tags["building:levels"]).strip_edges()
		if raw.is_valid_float():
			return maxi(int(float(raw)), 1)
	if tags.has("height"):
		var height := str(tags["height"]).replace("m", "").strip_edges()
		if height.is_valid_float():
			return maxi(int(float(height) / 3.15), 1)
	return 2


static func _height_from(tags: Dictionary) -> float:
	if tags.has("height"):
		var raw := str(tags["height"]).replace("m", "").strip_edges()
		if raw.is_valid_float():
			return maxf(float(raw), 2.5)
	return float(_levels_from(tags)) * 3.15
