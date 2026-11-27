class_name PolygonUtils
extends RefCounted

## Geometria de polígonos em 2D — a base de tudo na geração urbana.
##
## Todo o cálculo roda no **espaço métrico global** (Vector2 easting/northing),
## em metros. Converter para o espaço local do setor é a última coisa que
## acontece, na hora de montar o payload. Isso importa: quadras e lotes de
## setores vizinhos precisam ser calculados no mesmo sistema, senão a mesma
## esquina nasce duas vezes com geometrias diferentes.
##
## Convenção de orientação: **anti-horário (CCW)** é positivo em `signed_area`.
## Todas as funções que produzem polígonos devolvem CCW quando a ordem importa.
## Internamente as latitudes são espelhadas no espaço métrico (northing cresce
## para norte), então "CCW" aqui é o CCW do plano (leste, norte).
##
## `PackedVector2Array` é tipo de valor: nada aqui altera o array recebido.
## Toda operação devolve um array novo.


const EPSILON := 1.0e-6
const MIN_EDGE := 0.02


# --- medidas -----------------------------------------------------------------


static func signed_area(poly: PackedVector2Array) -> float:
	var count := poly.size()
	if count < 3:
		return 0.0
	var total := 0.0
	for i in range(count):
		var a := poly[i]
		var b := poly[(i + 1) % count]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


static func area(poly: PackedVector2Array) -> float:
	return absf(signed_area(poly))


static func is_ccw(poly: PackedVector2Array) -> bool:
	return signed_area(poly) > 0.0


## Devolve o polígono em ordem anti-horária. Cópia: o original não muda.
static func to_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(poly)
	if signed_area(out) < 0.0:
		out.reverse()
	return out


## Centroide por área. Cai para a média dos vértices quando o polígono é
## degenerado — nunca devolve NAN.
static func centroid(poly: PackedVector2Array) -> Vector2:
	var count := poly.size()
	if count == 0:
		return Vector2.ZERO
	if count >= 3:
		var signed := signed_area(poly)
		if absf(signed) > EPSILON:
			var acc := Vector2.ZERO
			for i in range(count):
				var a := poly[i]
				var b := poly[(i + 1) % count]
				var cross := a.x * b.y - b.x * a.y
				acc += (a + b) * cross
			return acc / (6.0 * signed)
	var average := Vector2.ZERO
	for point in poly:
		average += point
	return average / float(count)


static func bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var low := poly[0]
	var high := poly[0]
	for point in poly:
		low.x = minf(low.x, point.x)
		low.y = minf(low.y, point.y)
		high.x = maxf(high.x, point.x)
		high.y = maxf(high.y, point.y)
	return Rect2(low, high - low)


static func perimeter(poly: PackedVector2Array) -> float:
	var count := poly.size()
	if count < 2:
		return 0.0
	var total := 0.0
	for i in range(count):
		total += poly[i].distance_to(poly[(i + 1) % count])
	return total


# --- consultas ---------------------------------------------------------------


static func point_in_polygon(point: Vector2, poly: PackedVector2Array) -> bool:
	var count := poly.size()
	if count < 3:
		return false
	var inside := false
	var j := count - 1
	for i in range(count):
		var a := poly[i]
		var b := poly[j]
		if (a.y > point.y) != (b.y > point.y):
			var t := (point.y - a.y) / (b.y - a.y)
			if point.x < a.x + t * (b.x - a.x):
				inside = not inside
		j = i
	return inside


static func point_in_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (b - a).cross(point - a)
	var d2 := (c - b).cross(point - b)
	var d3 := (a - c).cross(point - c)
	var has_negative := d1 < -EPSILON or d2 < -EPSILON or d3 < -EPSILON
	var has_positive := d1 > EPSILON or d2 > EPSILON or d3 > EPSILON
	return not (has_negative and has_positive)


static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(closest_point_on_segment(point, a, b))


static func closest_point_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < EPSILON:
		return a
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return a + ab * t


## Distância à borda de um polígono. Zero quando o ponto está dentro.
static func distance_to_polygon(point: Vector2, poly: PackedVector2Array) -> float:
	var count := poly.size()
	if count == 0:
		return INF
	if count < 3:
		return distance_to_segment(point, poly[0], poly[count - 1])
	if point_in_polygon(point, poly):
		return 0.0
	var best := INF
	for i in range(count):
		best = minf(best, distance_to_segment(point, poly[i], poly[(i + 1) % count]))
	return best


static func segment_intersection(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Dictionary:
	var r := b - a
	var s := d - c
	var denominator := r.cross(s)
	if absf(denominator) < 1.0e-9:
		return {"hit": false}
	var diff := c - a
	var t := diff.cross(s) / denominator
	var u := diff.cross(r) / denominator
	if t < -1.0e-6 or t > 1.0 + 1.0e-6 or u < -1.0e-6 or u > 1.0 + 1.0e-6:
		return {"hit": false}
	return {"hit": true, "t": t, "u": u, "point": a + r * t}


## Sobreposição entre dois polígonos: vértice dentro do outro ou arestas que se
## cruzam. Custa O(n·m), o que basta para a validação e para os testes.
##
## `tolerance` é o que separa "encostado" de "sobreposto". Lotes vizinhos
## compartilham a divisa exata, e uma interseção de arestas coincidentes não pode
## ser lida como sobreposição. Antes de testar, os dois polígonos encolhem por
## essa folga (5 cm por padrão): encostar deixa de contar, e qualquer invasão
## maior que a folga continua contando.
static func polygons_overlap(a: PackedVector2Array, b: PackedVector2Array, tolerance: float = 0.05) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false
	var poly_a := a
	var poly_b := b
	if tolerance > 0.0:
		var inset_a := inset_polygon(a, tolerance)
		var inset_b := inset_polygon(b, tolerance)
		if inset_a.size() < 3 or inset_b.size() < 3:
			return false
		poly_a = inset_a
		poly_b = inset_b
	if not bounds(poly_a).intersects(bounds(poly_b)):
		return false
	for point in poly_a:
		if point_in_polygon(point, poly_b):
			return true
	for point in poly_b:
		if point_in_polygon(point, poly_a):
			return true
	var count_a := poly_a.size()
	var count_b := poly_b.size()
	for i in range(count_a):
		var a0 := poly_a[i]
		var a1 := poly_a[(i + 1) % count_a]
		for j in range(count_b):
			if bool(segment_intersection(a0, a1, poly_b[j], poly_b[(j + 1) % count_b]).get("hit", false)):
				return true
	return false


# --- construção --------------------------------------------------------------


## Recorta o polígono mantendo o lado em que `normal·p >= offset`.
##
## Sutherland–Hodgman contra uma meia-reta, que é convexa: o resultado é exato
## para qualquer polígono simples. É a operação que constrói quadras, lotes e
## recuos — não existe "encolher por deslocamento de aresta" em lugar nenhum,
## porque essa técnica se auto-intersecta em polígonos côncavos.
static func clip_half_plane(poly: PackedVector2Array, normal: Vector2, offset: float) -> PackedVector2Array:
	var count := poly.size()
	var out := PackedVector2Array()
	if count < 3:
		return out
	for i in range(count):
		var current := poly[i]
		var next := poly[(i + 1) % count]
		var d_current := normal.dot(current) - offset
		var d_next := normal.dot(next) - offset
		var current_inside := d_current >= 0.0
		var next_inside := d_next >= 0.0
		if current_inside:
			out.append(current)
		if current_inside != next_inside:
			var denominator := d_current - d_next
			if absf(denominator) > 1.0e-12:
				out.append(current.lerp(next, d_current / denominator))
	return clean(out)


## Mantém a faixa `min_t <= normal·p <= max_t`.
static func clip_slab(poly: PackedVector2Array, direction: Vector2, min_t: float, max_t: float) -> PackedVector2Array:
	if max_t <= min_t:
		return PackedVector2Array()
	var out := clip_half_plane(poly, direction, min_t)
	if out.size() < 3:
		return out
	return clip_half_plane(out, -direction, -max_t)


## Remove uma faixa, devolvendo o que sobra. Só é exato quando a faixa toca uma
## das pontas do polígono (é como o gerador de lotes usa: canto de quadra).
static func remove_slab(poly: PackedVector2Array, direction: Vector2, min_t: float, max_t: float) -> PackedVector2Array:
	return clip_half_plane(poly, direction, max_t)


## Encolhe o polígono por todas as arestas. Devolve vazio quando o resultado
## deixa de ser um polígono com área — o chamador trata isso como "não cabe".
static func inset_polygon(poly: PackedVector2Array, margin: float) -> PackedVector2Array:
	if poly.size() < 3 or margin < 0.0:
		return PackedVector2Array()
	var source := to_ccw(poly)
	var result := source
	var count := source.size()
	for i in range(count):
		var a := source[i]
		var b := source[(i + 1) % count]
		var edge := b - a
		if edge.length_squared() < EPSILON:
			continue
		edge = edge.normalized()
		# Para CCW a esquerda da aresta é o interior.
		var inward := Vector2(-edge.y, edge.x)
		result = clip_half_plane(result, inward, inward.dot(a) + margin)
		if result.size() < 3:
			return PackedVector2Array()
	return result


## Remove vértices repetidos (inclusive o último igual ao primeiro).
static func clean(poly: PackedVector2Array, tolerance: float = MIN_EDGE) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(point) > tolerance:
			out.append(point)
	if out.size() >= 2 and out[0].distance_to(out[out.size() - 1]) <= tolerance:
		out.remove_at(out.size() - 1)
	return out


static func rotate(point: Vector2, angle: float) -> Vector2:
	var c := cos(angle)
	var s := sin(angle)
	return Vector2(point.x * c - point.y * s, point.x * s + point.y * c)


## Eixo local (u, n) a partir de uma direção de frente. `n` é sempre o eixo
## interior (90° à esquerda de `u`), o que mantém o referencial destro e a
## ordem dos cantos anti-horária.
static func frame(direction: Vector2) -> Dictionary:
	var u := direction.normalized()
	return {"u": u, "n": Vector2(-u.y, u.x)}


## Retângulo orientado no referencial (u, n), em ordem CCW.
static func oriented_rect(origin: Vector2, u: Vector2, n: Vector2, min_u: float, max_u: float, min_n: float, max_n: float) -> PackedVector2Array:
	return PackedVector2Array([
		origin + u * min_u + n * min_n,
		origin + u * max_u + n * min_n,
		origin + u * max_u + n * max_n,
		origin + u * min_u + n * max_n,
	])


static func project_range(poly: PackedVector2Array, axis: Vector2) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var low := axis.dot(poly[0])
	var high := low
	for point in poly:
		var value := axis.dot(point)
		low = minf(low, value)
		high = maxf(high, value)
	return Vector2(low, high)


# --- triangulação ------------------------------------------------------------


## Ear clipping. Devolve { "points": PackedVector2Array (cópia CCW), "indices":
## PackedInt32Array } — os índices valem para a cópia devolvida, não para o
## argumento, porque o sentido de rotação pode ter sido invertido.
##
## Sem isto não há como preencher telhado nem laje de um lote cujo polígono não
## é retangular — e metade dos lotes de uma cidade real não é.
static func triangulate(poly: PackedVector2Array) -> Dictionary:
	var points := to_ccw(poly)
	var count := points.size()
	var indices := PackedInt32Array()
	if count < 3:
		return {"points": points, "indices": indices}
	var remaining: Array[int] = []
	for i in range(count):
		remaining.append(i)
	var guard := 0
	var guard_limit := count * count + 8
	while remaining.size() > 3 and guard < guard_limit:
		guard += 1
		var ear_found := false
		var size_now := remaining.size()
		for k in range(size_now):
			var i_prev := remaining[(k + size_now - 1) % size_now]
			var i_cur := remaining[k]
			var i_next := remaining[(k + 1) % size_now]
			var a := points[i_prev]
			var b := points[i_cur]
			var c := points[i_next]
			if (b - a).cross(c - b) <= EPSILON:
				continue
			var contains := false
			for m in range(size_now):
				var index := remaining[m]
				if index == i_prev or index == i_cur or index == i_next:
					continue
				if point_in_triangle(points[index], a, b, c):
					contains = true
					break
			if contains:
				continue
			indices.append(i_prev)
			indices.append(i_cur)
			indices.append(i_next)
			remaining.remove_at(k)
			ear_found = true
			break
		if not ear_found:
			break
	if remaining.size() == 3:
		indices.append(remaining[0])
		indices.append(remaining[1])
		indices.append(remaining[2])
	return {"points": points, "indices": indices}


# --- serialização ------------------------------------------------------------


## Polígono -> [[x, y], ...] para JSON/payload.
static func to_array(poly: PackedVector2Array) -> Array:
	var out: Array = []
	out.resize(poly.size())
	for i in range(poly.size()):
		out[i] = [poly[i].x, poly[i].y]
	return out


static func from_array(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry in raw:
		if typeof(entry) != TYPE_ARRAY:
			continue
		var pair: Array = entry
		if pair.size() < 2:
			continue
		out.append(Vector2(float(pair[0]), float(pair[1])))
	return out
