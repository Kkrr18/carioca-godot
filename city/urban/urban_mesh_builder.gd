class_name UrbanMeshBuilder
extends RefCounted

## Constrói a malha da cidade: fachada por pavimento, janelas, portas, vitrine,
## sacada, telhado, muro com portão, calçada, guia e sinalização. Uma malha por
## camada e por setor, com cor por vértice.
##
## Por que uma malha só: o custo de draw call passa a ser proporcional ao número
## de setores (dezenas), e não ao de edificações (milhares). É a mesma decisão da
## Etapa 1, estendida para a fachada detalhada.
##
## **Conformação ao relevo.** A geração de payload não consulta terreno (roda nas
## threads do streaming e não pode disputar o cache do SRTM). Aqui, na thread
## principal, cada edificação é apoiada no ponto **mais baixo** dos seus cantos e
## o vão até o mais alto é preenchido com um embasamento. Casa em rua inclinada
## nasce com sapata aparente em vez de flutuar.
##
## **Nada de buraco de verdade.** Janela é um quad levemente deslocado para fora
## da parede, com moldura em cor de esquadria. Furar a parede custaria recorte de
## geometria por janela em tempo de carga, sem ganho visual a 30 FPS no celular.


const CURB_SINK := 0.05
const WINDOW_INSET := 0.07
const PARAPET_HEIGHT := 0.45


# --- edificações -------------------------------------------------------------


static func build_buildings(payload: Dictionary, terrain: TerrainService, origin_metric: Vector2) -> ArrayMesh:
	var buildings: Array = payload.get("buildings", [])
	if buildings.is_empty():
		return null
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for raw in buildings:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var building: Dictionary = raw
		var appended := false
		if building.has("frame") and building.has("footprint"):
			appended = _append_urban_building(tool, building, terrain, origin_metric)
		else:
			appended = _append_legacy_building(tool, building, terrain, origin_metric)
		if appended:
			any = true
	if not any:
		return null
	return tool.commit()


static func _append_urban_building(tool: SurfaceTool, building: Dictionary, terrain: TerrainService, origin_metric: Vector2) -> bool:
	var footprint := PolygonUtils.from_array(building.get("footprint", []))
	if footprint.size() < 3:
		return false
	var frame: Dictionary = building.get("frame", {})
	var frame_origin := _vec2(frame.get("origin", [0.0, 0.0]))
	var dir := _vec2(frame.get("dir", [1.0, 0.0]))
	var normal := _vec2(frame.get("normal", [0.0, 1.0]))
	var width := float(frame.get("width", 8.0))
	var depth := float(frame.get("depth", 8.0))
	if width < 2.0 or depth < 2.0:
		return false

	var levels := maxi(int(building.get("levels", 1)), 1)
	var floor_height := float(building.get("floor_height", 3.05))
	var height := float(building.get("height", float(levels) * floor_height))
	var palette: Dictionary = building.get("palette", {})
	var wall_color := _color(palette.get("wall", [0.85, 0.83, 0.77]), 1.0)
	var roof_color := _color(palette.get("roof", [0.42, 0.30, 0.26]), 1.0)
	var trim_color := _color(palette.get("trim", [0.95, 0.95, 0.93]), 1.0)
	var glass_color := _color(palette.get("glass", [0.22, 0.28, 0.33]), 1.0)
	var accent_color := _color(palette.get("accent", [0.6, 0.45, 0.32]), 1.0)

	# Apoio no terreno: mínimo dos cantos manda no pé-direito, máximo fecha o vão.
	var low := INF
	var high := -INF
	for point in footprint:
		var ground := _height_at(terrain, origin_metric, point)
		low = minf(low, ground)
		high = maxf(high, ground)
	if not is_finite(low) or not is_finite(high):
		return false
	var base := low - 0.25
	var floor_y := high + 0.12
	var top := floor_y + height

	# Embasamento: preenche a diferença de cota até o piso.
	if floor_y - base > 0.05:
		_add_ring(tool, footprint, base, floor_y, wall_color.darkened(0.22), true)

	for level in range(levels):
		var y0 := floor_y + float(level) * floor_height
		var y1 := minf(y0 + floor_height, top)
		if y1 - y0 < 0.05:
			continue
		var shade := 1.0 + (float(level % 3) - 1.0) * 0.05
		var color := Color(
			clampf(wall_color.r * shade, 0.0, 1.0),
			clampf(wall_color.g * shade, 0.0, 1.0),
			clampf(wall_color.b * shade, 0.0, 1.0)
		)
		_add_ring(tool, footprint, y0, y1, color, false)
		if level > 0:
			# Faixa entre pavimentos: uma linha fina que dá leitura de andar.
			_add_ring(tool, footprint, y0 - 0.06, y0 + 0.02, trim_color.darkened(0.15), false)

	_add_modules(tool, building, frame_origin, dir, normal, width, depth, floor_y, floor_height, levels, footprint,
		trim_color, glass_color, accent_color)

	_add_roof(tool, building, frame_origin, dir, normal, width, depth, top, roof_color, wall_color)
	_add_lot_wall(tool, building, floor_y, wall_color, trim_color, accent_color)
	return true


## Parede em volta de um polígono, de y0 a y1. Normal apontando para fora do
## polígono, calculada pela direção e conferida contra o centroide.
static func _add_ring(tool: SurfaceTool, poly: PackedVector2Array, y0: float, y1: float, color: Color, is_plinth: bool) -> void:
	var count := poly.size()
	if count < 3:
		return
	var centroid := PolygonUtils.centroid(poly)
	for i in range(count):
		var a := poly[i]
		var b := poly[(i + 1) % count]
		if a.distance_to(b) < 0.05:
			continue
		var midpoint := (a + b) * 0.5
		var outward := midpoint - centroid
		if outward.length_squared() < 1.0e-6:
			var edge := (b - a).normalized()
			outward = Vector2(-edge.y, edge.x)
		outward = outward.normalized()
		var hint := Vector3(outward.x, 0.0, outward.y)
		var shade := 0.86 if is_plinth else 1.0
		_add_quad(
			tool,
			Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y),
			Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y),
			Color(color.r * shade, color.g * shade, color.b * shade),
			hint
		)


static func _add_modules(tool: SurfaceTool, building: Dictionary, frame_origin: Vector2, dir: Vector2, normal: Vector2,
		width: float, depth: float, floor_y: float, floor_height: float, levels: int,
		footprint: PackedVector2Array, trim: Color, glass: Color, accent: Color) -> void:
	var modules: Array = building.get("modules", [])
	if modules.is_empty():
		return
	var top := floor_y + float(levels) * floor_height
	for raw in modules:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var module: Dictionary = raw
		var plane := _module_plane(frame_origin, dir, normal, width, depth, int(module.get("side", 0)), float(module.get("along", 0.0)))
		var anchor: Vector2 = plane["anchor"]
		var tangent: Vector2 = plane["tangent"]
		var outward: Vector2 = plane["outward"]
		if not PolygonUtils.point_in_polygon(anchor + outward * 0.2, footprint):
			if not _inside_footprint_loose(anchor, footprint, 0.6):
				continue
		var kind := str(module.get("type", ""))
		var module_width := float(module.get("width", 1.0))
		var module_height := float(module.get("height", 1.2))
		var sill := floor_y + float(module.get("sill", 0.0))
		if sill + module_height > top + 0.4:
			module_height = maxf(top + 0.2 - sill, 0.3)
		match kind:
			UrbanSchema.MODULE_WINDOW:
				_add_window(tool, anchor, tangent, outward, module_width, module_height, sill, trim, glass)
			UrbanSchema.MODULE_DOOR:
				_add_panel(tool, anchor, tangent, outward, module_width, module_height, floor_y, accent.darkened(0.25))
			UrbanSchema.MODULE_GARAGE:
				_add_panel(tool, anchor, tangent, outward, module_width, module_height, floor_y, Color(0.34, 0.35, 0.37))
			UrbanSchema.MODULE_SHOPFRONT:
				_add_shopfront(tool, anchor, tangent, outward, module_width, module_height, floor_y, glass, accent)
			UrbanSchema.MODULE_BALCONY:
				_add_balcony(tool, anchor, tangent, outward, module_width, float(module.get("depth", 1.1)), sill, trim)
			UrbanSchema.MODULE_PORCH:
				_add_porch(tool, anchor, tangent, outward, module_width, float(module.get("depth", 2.0)), module_height, sill, trim, accent)
			UrbanSchema.MODULE_STAIRS:
				_add_stairs(tool, anchor, tangent, outward, module_width, floor_y, trim.darkened(0.2))
			_:
				pass

## Posição e referencial de um módulo na parede. A convenção dos lados é a do
## `BuildingModules`: percurso anti-horário a partir da quina esquerda da frente.
static func _module_plane(frame_origin: Vector2, dir: Vector2, normal: Vector2, width: float, depth: float, side: int, along: float) -> Dictionary:
	match side:
		UrbanSchema.SIDE_FRONT:
			return {"anchor": frame_origin + dir * along, "tangent": dir, "outward": -normal}
		UrbanSchema.SIDE_RIGHT:
			return {"anchor": frame_origin + dir * width + normal * along, "tangent": normal, "outward": dir}
		UrbanSchema.SIDE_BACK:
			return {"anchor": frame_origin + dir * (width - along) + normal * depth, "tangent": -dir, "outward": normal}
		_:
			return {"anchor": frame_origin + normal * (depth - along), "tangent": -normal, "outward": -dir}


static func _inside_footprint_loose(point: Vector2, footprint: PackedVector2Array, margin: float) -> bool:
	return PolygonUtils.distance_to_polygon(point, footprint) <= margin


static func _add_window(tool: SurfaceTool, anchor: Vector2, tangent: Vector2, outward: Vector2, width: float, height: float, sill: float, trim: Color, glass: Color) -> void:
	var half := width * 0.5
	var border := 0.09
	_flat_panel(tool, anchor + outward * (WINDOW_INSET - 0.02), tangent, outward, half + border, sill - border, sill + height + border, trim)
	_flat_panel(tool, anchor + outward * WINDOW_INSET, tangent, outward, half, sill, sill + height, glass)
	# Peitoril: faixa clara embaixo, dá profundidade sem geometria extra.
	_flat_panel(tool, anchor + outward * (WINDOW_INSET + 0.02), tangent, outward, half + border, sill - border - 0.07, sill - border, trim.darkened(0.1))


## Painel plano (quad) no plano da parede, de `from_y` a `to_y`, virado para
## `outward`. A normal é passada explicitamente porque o espelhamento entre
## espaço métrico e local inverte o sentido de giro: deduzi-la do sentido da
## aresta deixaria metade das janelas iluminada pelo lado de dentro.
static func _flat_panel(tool: SurfaceTool, anchor: Vector2, tangent: Vector2, outward: Vector2, half_width: float, from_y: float, to_y: float, color: Color) -> void:
	if to_y - from_y <= 0.01 or half_width <= 0.01:
		return
	var a := anchor - tangent * half_width
	var b := anchor + tangent * half_width
	_add_quad(
		tool,
		Vector3(a.x, from_y, a.y), Vector3(b.x, from_y, b.y),
		Vector3(b.x, to_y, b.y), Vector3(a.x, to_y, a.y),
		color,
		Vector3(outward.x, 0.0, outward.y)
	)


static func _add_panel(tool: SurfaceTool, anchor: Vector2, tangent: Vector2, outward: Vector2, width: float, height: float, base_y: float, color: Color) -> void:
	var half := width * 0.5
	_flat_panel(tool, anchor + outward * (WINDOW_INSET + 0.02), tangent, outward, half, base_y, base_y + height, color)


static func _add_shopfront(tool: SurfaceTool, anchor: Vector2, tangent: Vector2, outward: Vector2, width: float, height: float, base_y: float, glass: Color, accent: Color) -> void:
	var half := maxf(width * 0.5 - 0.25, 0.6)
	_flat_panel(tool, anchor + outward * (WINDOW_INSET + 0.03), tangent, outward, half, base_y + 0.18, base_y + height, glass)
	# Bandeira do letreiro: cor de destaque, sem nome de marca.
	_flat_panel(tool, anchor + outward * (WINDOW_INSET + 0.05), tangent, outward, half, base_y + height + 0.05, base_y + height + 0.55, accent)
	# Toldo: aba inclinada para fora, na cor do letreiro.
	var top_a := anchor - tangent * half + outward * (WINDOW_INSET + 0.05)
	var top_b := anchor + tangent * half + outward * (WINDOW_INSET + 0.05)
	var low_a := top_a + outward * 1.05
	var low_b := top_b + outward * 1.05
	var awning_y := base_y + height + 0.05
	_add_quad(
		tool,
		Vector3(top_a.x, awning_y, top_a.y), Vector3(top_b.x, awning_y, top_b.y),
		Vector3(low_b.x, awning_y - 0.35, low_b.y), Vector3(low_a.x, awning_y - 0.35, low_a.y),
		accent.darkened(0.15),
		Vector3(0.0, 1.0, 0.0)
	)


static func _add_balcony(tool: SurfaceTool, anchor: Vector2, tangent: Vector2, outward: Vector2, width: float, depth: float, sill: float, trim: Color) -> void:
	var half := width * 0.5
	var near_a := anchor - tangent * half
	var near_b := anchor + tangent * half
	var far_a := near_a + outward * depth
	var far_b := near_b + outward * depth
	var color := trim.darkened(0.08)
	# Laje: quad horizontal, normal para cima.
	_add_quad(tool,
		Vector3(near_a.x, sill - 0.14, near_a.y), Vector3(near_b.x, sill - 0.14, near_b.y),
		Vector3(far_b.x, sill - 0.14, far_b.y), Vector3(far_a.x, sill - 0.14, far_a.y),
		color, Vector3(0.0, 1.0, 0.0))
	# Guarda-corpo frontal.
	_add_quad(tool,
		Vector3(far_a.x, sill - 0.08, far_a.y), Vector3(far_b.x, sill - 0.08, far_b.y),
		Vector3(far_b.x, sill + 0.95, far_b.y), Vector3(far_a.x, sill + 0.95, far_a.y),
		color, Vector3(outward.x, 0.0, outward.y))
	# Laterais do guarda-corpo.
	for side in [-1.0, 1.0]:
		var edge_a := near_a if side < 0.0 else near_b
		var edge_b := far_a if side < 0.0 else far_b
		_add_quad(tool,
			Vector3(edge_a.x, sill - 0.08, edge_a.y), Vector3(edge_b.x, sill - 0.08, edge_b.y),
			Vector3(edge_b.x, sill + 0.95, edge_b.y), Vector3(edge_a.x, sill + 0.95, edge_a.y),
			color, Vector3(tangent.x * side, 0.0, tangent.y * side))


static func _add_porch(tool: SurfaceTool, anchor: Vector2, tangent: Vector2, outward: Vector2, width: float, depth: float, height: float, sill: float, trim: Color, accent: Color) -> void:
	if depth < 0.5:
		return
	var half := width * 0.5
	var near_a := anchor - tangent * half
	var near_b := anchor + tangent * half
	var far_a := near_a + outward * depth
	var far_b := near_b + outward * depth
	# Cobertura: quad horizontal na altura do pé-direito.
	_add_quad(tool,
		Vector3(near_a.x, sill + height, near_a.y), Vector3(near_b.x, sill + height, near_b.y),
		Vector3(far_b.x, sill + height, far_b.y), Vector3(far_a.x, sill + height, far_a.y),
		accent, Vector3(0.0, 1.0, 0.0))
	# Dois pilares fino em cor de esquadria.
	for side in [-1.0, 1.0]:
		var foot := (far_a if side < 0.0 else far_b).lerp(near_a if side < 0.0 else near_b, 0.06)
		var post := 0.11
		_add_quad(tool,
			Vector3(foot.x - tangent.x * post, sill, foot.y - tangent.y * post),
			Vector3(foot.x + tangent.x * post, sill, foot.y + tangent.y * post),
			Vector3(foot.x + tangent.x * post, sill + height, foot.y + tangent.y * post),
			Vector3(foot.x - tangent.x * post, sill + height, foot.y - tangent.y * post),
			trim, Vector3(outward.x, 0.0, outward.y))


static func _add_stairs(tool: SurfaceTool, anchor: Vector2, tangent: Vector2, outward: Vector2, width: float, floor_y: float, color: Color) -> void:
	var half := width * 0.5
	var steps := 3
	for i in range(steps):
		var ratio := float(i + 1) / float(steps + 1)
		var start := anchor + outward * (0.28 * float(steps - i))
		var stop := start + outward * 0.3
		var y := floor_y - 0.36 + ratio * 0.36
		var a := start - tangent * half
		var b := start + tangent * half
		var c := stop + tangent * half
		var d := stop - tangent * half
		_add_quad(tool,
			Vector3(a.x, y, a.y), Vector3(d.x, y, d.y),
			Vector3(c.x, y, c.y), Vector3(b.x, y, b.y),
			color, Vector3(0.0, 1.0, 0.0))


static func _add_roof(tool: SurfaceTool, building: Dictionary, frame_origin: Vector2, dir: Vector2, normal: Vector2,
		width: float, depth: float, top: float, roof_color: Color, wall_color: Color) -> void:
	var roof: Dictionary = building.get("roof", {})
	var roof_type := str(roof.get("type", UrbanSchema.ROOF_FLAT))
	var pitch := float(roof.get("pitch_deg", 0.0))
	var overhang := float(roof.get("overhang", 0.3))
	var half_width := width * 0.5
	var half_depth := depth * 0.5
	var eave := top
	var ridge := top + tan(deg_to_rad(pitch)) * half_depth

	match roof_type:
		UrbanSchema.ROOF_GABLE, UrbanSchema.ROOF_HIP:
			var ridge_inset := half_width if roof_type == UrbanSchema.ROOF_GABLE else half_width * 0.55
			var c0 := frame_origin - dir * overhang - normal * overhang
			var c1 := frame_origin + dir * (width + overhang) - normal * overhang
			var c2 := frame_origin + dir * (width + overhang) + normal * (depth + overhang)
			var c3 := frame_origin + normal * (depth + overhang)
			var r0 := frame_origin + dir * (half_width - ridge_inset) + normal * half_depth
			var r1 := frame_origin + dir * (half_width + ridge_inset) + normal * half_depth
			_add_quad(tool, Vector3(c0.x, eave, c0.y), Vector3(c1.x, eave, c1.y),
				Vector3(r1.x, ridge, r1.y), Vector3(r0.x, ridge, r0.y), roof_color, Vector3(0.0, 1.0, 0.0))
			_add_quad(tool, Vector3(c3.x, eave, c3.y), Vector3(c2.x, eave, c2.y),
				Vector3(r1.x, ridge, r1.y), Vector3(r0.x, ridge, r0.y), roof_color.darkened(0.08), Vector3(0.0, 1.0, 0.0))
			if roof_type == UrbanSchema.ROOF_HIP:
				_triangle(tool,
					Vector3(c1.x, eave, c1.y), Vector3(c2.x, eave, c2.y), Vector3(r1.x, ridge, r1.y),
					roof_color.darkened(0.04))
				_triangle(tool,
					Vector3(c3.x, eave, c3.y), Vector3(c0.x, eave, c0.y), Vector3(r0.x, ridge, r0.y),
					roof_color.darkened(0.12))
			else:
				_triangle(tool,
					Vector3(c1.x, eave, c1.y), Vector3(c2.x, eave, c2.y), Vector3(r1.x, ridge, r1.y),
					wall_color.darkened(0.1))
				_triangle(tool,
					Vector3(c3.x, eave, c3.y), Vector3(c0.x, eave, c0.y), Vector3(r0.x, ridge, r0.y),
					wall_color.darkened(0.14))
		UrbanSchema.ROOF_MONOSLOPE, UrbanSchema.ROOF_SHED:
			var high_side := frame_origin - normal * overhang
			var low_side := frame_origin + normal * (depth + overhang)
			var c0 := high_side - dir * overhang
			var c1 := high_side + dir * (width + overhang)
			var c3 := low_side - dir * overhang
			var c2 := low_side + dir * (width + overhang)
			_add_quad(tool,
				Vector3(c0.x, eave + tan(deg_to_rad(pitch)) * depth, c0.y),
				Vector3(c1.x, eave + tan(deg_to_rad(pitch)) * depth, c1.y),
				Vector3(c2.x, eave, c2.y), Vector3(c3.x, eave, c3.y),
				roof_color, Vector3(0.0, 1.0, 0.0))
		_:
			# Laje: topo triangulado mais platibanda.
			var polygon := _rect_polygon(frame_origin, dir, normal, width, depth)
			_fill_polygon(tool, polygon, top, roof_color, true)
			_add_ring(tool, polygon, top, top + PARAPET_HEIGHT, wall_color.darkened(0.05), false)


static func _rect_polygon(origin: Vector2, dir: Vector2, normal: Vector2, width: float, depth: float) -> PackedVector2Array:
	return PackedVector2Array([
		origin,
		origin + dir * width,
		origin + dir * width + normal * depth,
		origin + normal * depth,
	])


static func _add_lot_wall(tool: SurfaceTool, building: Dictionary, floor_y: float, wall_color: Color, trim: Color, accent: Color) -> void:
	var wall: Dictionary = building.get("wall", {})
	if wall.is_empty():
		return
	var lot: Dictionary = building.get("lot", {})
	if lot.is_empty():
		return
	var origin := _vec2(lot.get("origin", [0.0, 0.0]))
	var dir := _vec2(lot.get("dir", [1.0, 0.0]))
	var normal := _vec2(lot.get("normal", [0.0, 1.0]))
	var span := float(lot.get("width", float(wall.get("span", 10.0))))
	if span < 2.0:
		return
	var height := float(wall.get("height", 1.8))
	var thickness := maxf(float(wall.get("thickness", 0.18)), 0.08)
	var gate_along := float(wall.get("gate_along", 1.0))
	var gate_width := float(wall.get("gate_width", 3.0))
	var color := wall_color.darkened(0.28)
	var base := floor_y - 0.05
	var segments: Array = [
		Vector2(0.0, gate_along),
		Vector2(gate_along + gate_width, span),
	]
	for segment in segments:
		var limits: Vector2 = segment
		if limits.y - limits.x < 0.4:
			continue
		var a := origin + dir * limits.x
		var b := origin + dir * limits.y
		var inner := normal * thickness
		_add_quad(tool,
			Vector3(a.x, base, a.y), Vector3(b.x, base, b.y),
			Vector3(b.x, base + height, b.y), Vector3(a.x, base + height, a.y),
			color, Vector3(-normal.x, 0.0, -normal.y))
		_add_quad(tool,
			Vector3((b - inner).x, base, (b - inner).y), Vector3((a - inner).x, base, (a - inner).y),
			Vector3((a - inner).x, base + height, (a - inner).y), Vector3((b - inner).x, base + height, (b - inner).y),
			color.darkened(0.06), Vector3(normal.x, 0.0, normal.y))
	# Portão: painel mais alto, em cor de destaque.
	var gate_a := origin + dir * gate_along
	var gate_b := origin + dir * (gate_along + gate_width)
	_add_quad(tool,
		Vector3(gate_a.x, base, gate_a.y), Vector3(gate_b.x, base, gate_b.y),
		Vector3(gate_b.x, base + height + 0.35, gate_b.y), Vector3(gate_a.x, base + height + 0.35, gate_a.y),
		accent.darkened(0.2), Vector3(-normal.x, 0.0, -normal.y))
	# Topo do muro: uma faixa clara que separa a parede do terreno e lê a distância.
	var span_start := origin
	var span_end := origin + dir * span
	_add_quad(tool,
		Vector3(span_start.x, base + height, span_start.y), Vector3(span_end.x, base + height, span_end.y),
		Vector3((span_end - normal * thickness).x, base + height, (span_end - normal * thickness).y),
		Vector3((span_start - normal * thickness).x, base + height, (span_start - normal * thickness).y),
		trim.darkened(0.12), Vector3(0.0, 1.0, 0.0))


# --- compatibilidade com payload sem camada urbana ---------------------------


static func _append_legacy_building(tool: SurfaceTool, building: Dictionary, terrain: TerrainService, origin_metric: Vector2) -> bool:
	var center := _vec2(building.get("center", [0.0, 0.0]))
	var size := _vec2(building.get("size", [10.0, 10.0]))
	var height := float(building.get("height", 6.0))
	if size.x <= 0.5 or size.y <= 0.5:
		return false
	var polygon := PolygonUtils.from_array(building.get("poly", []))
	if polygon.size() < 3:
		var angle := float(building.get("angle", 0.0))
		var dir := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-dir.y, dir.x)
		var corner := center - dir * (size.x * 0.5) - normal * (size.y * 0.5)
		polygon = _rect_polygon(corner, dir, normal, size.x, size.y)
	var kind := str(building.get("kind", UrbanSchema.KIND_RESIDENTIAL))
	var wall := _kind_color(kind)
	var ground := _height_at(terrain, origin_metric, PolygonUtils.centroid(polygon))
	var base := ground - 0.25
	_add_ring(tool, polygon, base, ground + height, wall, false)
	_fill_polygon(tool, polygon, ground + height, wall.darkened(0.35), true)
	return true


static func _kind_color(kind: String) -> Color:
	match kind:
		UrbanSchema.KIND_COMMERCIAL:
			return Color(0.62, 0.63, 0.66)
		UrbanSchema.KIND_PUBLIC:
			return Color(0.78, 0.74, 0.62)
		UrbanSchema.KIND_MIXED:
			return Color(0.72, 0.69, 0.64)
		_:
			return Color(0.83, 0.79, 0.71)


# --- calçada, guia e sinalização ---------------------------------------------


static func build_pavement(payload: Dictionary, terrain: TerrainService, origin_metric: Vector2) -> ArrayMesh:
	var geometry: Dictionary = payload.get("urban_geometry", {})
	var sidewalk := float(geometry.get("sidewalk_width", 2.4))
	var curb := float(geometry.get("curb_height", 0.14))
	var roads: Array = payload.get("roads", [])
	if roads.is_empty() or sidewalk <= 0.0:
		return null

	# Mesma lição do `RoadMeshBuilder` (defeito da primeira execução real):
	# amostrar só nos extremos do trecho enterrava a calçada no relevo entre
	# um vértice e outro da malha do terreno. Amostra a cada SAMPLE_STEP.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var sidewalk_color := Color(0.70, 0.69, 0.66)
	var curb_color := Color(0.58, 0.57, 0.55)
	var outer_drop := 0.3

	for raw in roads:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var road: Dictionary = raw
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var width := float(road.get("width", 6.0))
		for i in range(points.size() - 1):
			var a := _vec2(points[i])
			var b := _vec2(points[i + 1])
			var segment := b - a
			if segment.length_squared() < 1.0:
				continue
			var length := segment.length()
			var direction := segment / length
			var normal := Vector2(-direction.y, direction.x)
			var steps := clampi(int(ceilf(length / SAMPLE_STEP)), 1, MAX_STEPS)
			var prev := {}

			for s in range(steps + 1):
				var t := float(s) / float(steps)
				var center := a.lerp(b, t)
				for side_value in [-1.0, 1.0]:
					var side := float(side_value)
					var inner := center + normal * (width * 0.5) * side
					var outer := center + normal * (width * 0.5 + sidewalk) * side
					var y_in := _height_at(terrain, origin_metric, inner) + curb
					var y_out := _height_at(terrain, origin_metric, outer) + curb + 0.02
					var in_v := Vector3(inner.x, y_in, inner.y)
					var out_v := Vector3(outer.x, y_out, outer.y)
					if prev.has(side):
						var previous: Dictionary = prev[side]
						var prev_in: Vector3 = previous["in"]
						var prev_out: Vector3 = previous["out"]
						_add_quad(tool,
							prev_in, in_v, out_v, prev_out,
							sidewalk_color, Vector3(0.0, 1.0, 0.0))
						# Guia: face vertical entre o asfalto e a calçada.
						var in_road := in_v - Vector3.UP * curb
						var prev_in_road := prev_in - Vector3.UP * curb
						_add_quad(tool,
							prev_in_road, in_road, in_v, prev_in,
							curb_color, Vector3(-normal.x * side, 0.0, -normal.y * side))
						# Saia externa: a calçada nunca desaparece no relevo.
						var out_bot := out_v - Vector3.UP * outer_drop
						var prev_out_bot := prev_out - Vector3.UP * outer_drop
						_add_quad(tool,
							prev_out_bot, out_bot, out_v, prev_out,
							curb_color, Vector3(normal.x * side, 0.0, normal.y * side))
					prev[side] = {"in": in_v, "out": out_v}
					any = true

	_add_markings(tool, payload, terrain, origin_metric)
	return tool.commit() if any else null


## Passo de amostragem do relevo ao longo de uma via (m).
const SAMPLE_STEP := 8.0
const MAX_STEPS := 128


static func _add_markings(tool: SurfaceTool, payload: Dictionary, terrain: TerrainService, origin_metric: Vector2) -> void:
	var objects: Dictionary = payload.get("street_objects", {})
	var white := Color(0.92, 0.92, 0.88)
	for raw in objects.get("crosswalk", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var center := _vec2(entry.get("pos", [0.0, 0.0]))
		var angle := float(entry.get("angle", 0.0))
		var length := float(entry.get("length", 5.0))
		var bars := maxi(int(entry.get("bars", 5)), 2)
		var dir := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-dir.y, dir.x)
		var bar_length := length / float(bars) * 0.55
		for i in range(bars):
			var offset := (float(i) + 0.5) / float(bars) * length - length * 0.5
			var center_bar := center + dir * offset
			var p0 := center_bar - normal * 1.4
			var p1 := center_bar + normal * 1.4
			var y0 := _height_at(terrain, origin_metric, p0) + 0.19
			var y1 := _height_at(terrain, origin_metric, p1) + 0.19
			_add_quad(tool,
				Vector3((p0 - dir * bar_length * 0.5).x, y0, (p0 - dir * bar_length * 0.5).y),
				Vector3((p0 + dir * bar_length * 0.5).x, y0, (p0 + dir * bar_length * 0.5).y),
				Vector3((p1 + dir * bar_length * 0.5).x, y1, (p1 + dir * bar_length * 0.5).y),
				Vector3((p1 - dir * bar_length * 0.5).x, y1, (p1 - dir * bar_length * 0.5).y),
				white, Vector3(0.0, 1.0, 0.0))

	for raw in objects.get("lane_marking", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		var a := _vec2(entry.get("a", [0.0, 0.0]))
		var b := _vec2(entry.get("b", [0.0, 0.0]))
		var dashes := maxi(int(entry.get("dashes", 0)), 1)
		var width := float(entry.get("width", 0.12))
		var segment := b - a
		var length := segment.length()
		if length < 4.0:
			continue
		var dir := segment / length
		var normal := Vector2(-dir.y, dir.x) * width * 0.5
		var dash_length := length / float(dashes) * 0.45
		for i in range(dashes):
			var center := a + dir * ((float(i) + 0.5) / float(dashes) * length)
			var p0 := center - dir * dash_length * 0.5
			var p1 := center + dir * dash_length * 0.5
			var q0 := p0 - normal
			var q1 := p0 + normal
			var q2 := p1 + normal
			var q3 := p1 - normal
			var y := _height_at(terrain, origin_metric, center) + 0.19
			_add_quad(tool,
				Vector3(q0.x, y, q0.y), Vector3(q3.x, y, q3.y),
				Vector3(q2.x, y, q2.y), Vector3(q1.x, y, q1.y),
				Color(0.88, 0.86, 0.78), Vector3(0.0, 1.0, 0.0))


# --- primitivas --------------------------------------------------------------


static func _height_at(terrain: TerrainService, origin_metric: Vector2, local: Vector2) -> float:
	if terrain == null:
		return 0.0
	return terrain.height_at(origin_metric + Vector2(local.x, -local.y))


## Quad com normal conferida contra uma direção desejada: nunca sai com a face
## virada para dentro, qualquer que seja o sentido de giro do polígono.
static func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, hint: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1.0e-12:
		normal = hint
	if normal.dot(hint) < 0.0:
		normal = -normal
	normal = normal.normalized()
	tool.set_color(color)
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)
	tool.add_vertex(a)
	tool.add_vertex(c)
	tool.add_vertex(d)


static func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1.0e-12:
		normal = Vector3.UP
	if normal.y < 0.0:
		normal = -normal
	normal = normal.normalized()
	tool.set_color(color)
	tool.set_normal(normal)
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)


## Preenche um polígono plano com triangulação por ear clipping.
static func _fill_polygon(tool: SurfaceTool, poly: PackedVector2Array, y: float, color: Color, upward: bool) -> void:
	if poly.size() < 3:
		return
	var result := PolygonUtils.triangulate(poly)
	var points: PackedVector2Array = result["points"]
	var indices: PackedInt32Array = result["indices"]
	if indices.is_empty():
		return
	var normal := Vector3.UP if upward else Vector3.DOWN
	tool.set_color(color)
	tool.set_normal(normal)
	for i in range(0, indices.size() - 2, 3):
		var a := points[indices[i]]
		var b := points[indices[i + 1]]
		var c := points[indices[i + 2]]
		if upward:
			tool.add_vertex(Vector3(a.x, y, a.y))
			tool.add_vertex(Vector3(c.x, y, c.y))
			tool.add_vertex(Vector3(b.x, y, b.y))
		else:
			tool.add_vertex(Vector3(a.x, y, a.y))
			tool.add_vertex(Vector3(b.x, y, b.y))
			tool.add_vertex(Vector3(c.x, y, c.y))


static func _vec2(value: Variant) -> Vector2:
	if typeof(value) == TYPE_ARRAY:
		var array: Array = value
		if array.size() >= 2:
			return Vector2(float(array[0]), float(array[1]))
	return Vector2.ZERO


static func _vec_array(value: Variant) -> Vector2:
	return _vec2(value)


static func _color(value: Variant, multiplier: float) -> Color:
	if typeof(value) == TYPE_ARRAY:
		var array: Array = value
		if array.size() >= 3:
			return Color(float(array[0]) * multiplier, float(array[1]) * multiplier, float(array[2]) * multiplier)
	return Color(0.8, 0.8, 0.8) * multiplier
