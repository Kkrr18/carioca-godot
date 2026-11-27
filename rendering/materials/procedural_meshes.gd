class_name ProceduralMeshes
extends RefCounted

## Malhas primitivas geradas em código e reaproveitadas por MultiMesh.
## Nada de asset externo: o projeto abre e roda sem importar nada.

static var _cache: Dictionary = {}


static func reset_cache() -> void:
	_cache.clear()


## Copa de árvore estilizada (cone). O tronco é omitido de propósito: a
## instância aparece a partir de ~30 m e o cone com cor variável lê melhor que
## tronco + copa com o dobro de vértices.
static func tree_crown() -> Mesh:
	if _cache.has("tree"):
		return _cache["tree"]
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 1.9
	cone.height = 4.2
	cone.radial_segments = 7
	cone.rings = 1
	_cache["tree"] = cone
	return cone


static func pole() -> Mesh:
	if _cache.has("pole"):
		return _cache["pole"]
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.09
	cylinder.bottom_radius = 0.14
	cylinder.height = 6.4
	cylinder.radial_segments = 6
	cylinder.rings = 1
	_cache["pole"] = cylinder
	return cylinder


static func street_light_head() -> Mesh:
	if _cache.has("light_head"):
		return _cache["light_head"]
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.18, 0.9)
	_cache["light_head"] = box
	return box


## Carroceria baixa e cabine, unidas num só mesh.
static func car_body() -> Mesh:
	if _cache.has("car_body"):
		return _cache["car_body"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lower := BoxMesh.new()
	lower.size = Vector3(1.82, 0.72, 4.25)
	tool.append_from(lower, 0, Transform3D(Basis(), Vector3(0.0, 0.62, 0.0)))
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.62, 0.62, 2.05)
	tool.append_from(cabin, 0, Transform3D(Basis(), Vector3(0.0, 1.24, -0.15)))
	var mesh := tool.commit()
	_cache["car_body"] = mesh
	return mesh


static func wheel() -> Mesh:
	if _cache.has("wheel"):
		return _cache["wheel"]
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.34
	cylinder.bottom_radius = 0.34
	cylinder.height = 0.24
	cylinder.radial_segments = 10
	cylinder.rings = 1
	_cache["wheel"] = cylinder
	return cylinder


static func pedestrian_body() -> Mesh:
	if _cache.has("ped_body"):
		return _cache["ped_body"]
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.26
	capsule.height = 1.7
	capsule.radial_segments = 8
	capsule.rings = 3
	_cache["ped_body"] = capsule
	return capsule


static func traffic_light_head() -> Mesh:
	if _cache.has("traffic_head"):
		return _cache["traffic_head"]
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.95, 0.28)
	_cache["traffic_head"] = box
	return box


## Semáforo completo: poste, braço e caixa de três luzes, com a base em y = 0.
static func traffic_signal() -> Mesh:
	if _cache.has("signal"):
		return _cache["signal"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var post := CylinderMesh.new()
	post.top_radius = 0.07
	post.bottom_radius = 0.1
	post.height = 3.4
	post.radial_segments = 6
	post.rings = 1
	tool.append_from(post, 0, Transform3D(Basis(), Vector3(0.0, 1.7, 0.0)))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.09, 0.09, 0.9)
	tool.append_from(arm, 0, Transform3D(Basis(), Vector3(0.0, 3.32, 0.45)))
	var head := BoxMesh.new()
	head.size = Vector3(0.28, 0.9, 0.26)
	tool.append_from(head, 0, Transform3D(Basis(), Vector3(0.0, 2.92, 0.86)))
	var mesh := tool.commit()
	_cache["signal"] = mesh
	return mesh


## Quad em XZ, usado como telhado de interiores.
static func flat_quad(size: Vector2) -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	tool.set_normal(Vector3.UP)
	tool.add_vertex(Vector3(-hx, 0.0, -hz))
	tool.add_vertex(Vector3(hx, 0.0, -hz))
	tool.add_vertex(Vector3(hx, 0.0, hz))
	tool.add_vertex(Vector3(-hx, 0.0, -hz))
	tool.add_vertex(Vector3(hx, 0.0, hz))
	tool.add_vertex(Vector3(-hx, 0.0, hz))
	return tool.commit()




# --- vegetação e mobiliário da Etapa 3 ---------------------------------------
#
# Todas as malhas abaixo nascem com a base em y = 0. A instância é posicionada
# pela altura do terreno sem correção nenhuma, o que evita o ajuste mágico por
# tipo de objeto espalhado pelo `SectorInstance`.


static func tree_crown_tall() -> Mesh:
	if _cache.has("tree_tall"):
		return _cache["tree_tall"]
	var cone := CylinderMesh.new()
	cone.top_radius = 0.28
	cone.bottom_radius = 1.5
	cone.height = 7.0
	cone.radial_segments = 7
	cone.rings = 1
	_cache["tree_tall"] = _translated(cone, 3.5)
	return _cache["tree_tall"]


## Copa baixa de árvore de calçada, com a base no chão.
static func tree_crown_grounded() -> Mesh:
	if _cache.has("tree_grounded"):
		return _cache["tree_grounded"]
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 1.9
	cone.height = 4.2
	cone.radial_segments = 7
	cone.rings = 1
	_cache["tree_grounded"] = _translated(cone, 2.1)
	return _cache["tree_grounded"]


static func bush() -> Mesh:
	if _cache.has("bush"):
		return _cache["bush"]
	var sphere := SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.3
	sphere.radial_segments = 7
	sphere.rings = 3
	_cache["bush"] = _translated(sphere, 0.55)
	return _cache["bush"]


## Tufo de grama: dois quads cruzados, barato e suficiente a distância.
static func grass_tuft() -> Mesh:
	if _cache.has("grass"):
		return _cache["grass"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for angle in [0.0, PI * 0.5]:
		var dir := Vector2(cos(angle), sin(angle)) * 0.42
		var a := Vector3(-dir.x, 0.0, -dir.y)
		var b := Vector3(dir.x, 0.0, dir.y)
		var c := Vector3(dir.x, 0.42, dir.y)
		var d := Vector3(-dir.x, 0.42, -dir.y)
		tool.set_normal(Vector3.UP)
		tool.add_vertex(a)
		tool.add_vertex(b)
		tool.add_vertex(c)
		tool.add_vertex(a)
		tool.add_vertex(c)
		tool.add_vertex(d)
	var mesh := tool.commit()
	_cache["grass"] = mesh
	return mesh


static func bench() -> Mesh:
	if _cache.has("bench"):
		return _cache["bench"]
	var seat := BoxMesh.new()
	seat.size = Vector3(1.8, 0.09, 0.46)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(seat, 0, Transform3D(Basis(), Vector3(0.0, 0.45, 0.0)))
	var back := BoxMesh.new()
	back.size = Vector3(1.8, 0.42, 0.07)
	tool.append_from(back, 0, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0.0, 0.7, -0.2)))
	for side in [-0.75, 0.75]:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.09, 0.45, 0.4)
		tool.append_from(leg, 0, Transform3D(Basis(), Vector3(side, 0.22, 0.0)))
	var mesh := tool.commit()
	_cache["bench"] = mesh
	return mesh


static func trash_bin() -> Mesh:
	if _cache.has("bin"):
		return _cache["bin"]
	var body := CylinderMesh.new()
	body.top_radius = 0.26
	body.bottom_radius = 0.22
	body.height = 0.78
	body.radial_segments = 8
	body.rings = 1
	_cache["bin"] = _translated(body, 0.39)
	return _cache["bin"]


static func street_sign() -> Mesh:
	if _cache.has("sign"):
		return _cache["sign"]
	var post := CylinderMesh.new()
	post.top_radius = 0.045
	post.bottom_radius = 0.055
	post.height = 2.35
	post.radial_segments = 5
	post.rings = 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(post, 0, Transform3D(Basis(), Vector3(0.0, 1.175, 0.0)))
	var plate := BoxMesh.new()
	plate.size = Vector3(0.62, 0.62, 0.05)
	tool.append_from(plate, 0, Transform3D(Basis(), Vector3(0.0, 2.1, 0.0)))
	var mesh := tool.commit()
	_cache["sign"] = mesh
	return mesh


static func bus_shelter() -> Mesh:
	if _cache.has("shelter"):
		return _cache["shelter"]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof := BoxMesh.new()
	roof.size = Vector3(3.6, 0.12, 1.5)
	tool.append_from(roof, 0, Transform3D(Basis(), Vector3(0.0, 2.4, 0.0)))
	for side in [-1.72, 1.72]:
		var post := BoxMesh.new()
		post.size = Vector3(0.1, 2.4, 0.1)
		tool.append_from(post, 0, Transform3D(Basis(), Vector3(side, 1.2, 0.6)))
	var back := BoxMesh.new()
	back.size = Vector3(3.4, 1.9, 0.06)
	tool.append_from(back, 0, Transform3D(Basis(), Vector3(0.0, 1.35, -0.66)))
	var bench_slab := BoxMesh.new()
	bench_slab.size = Vector3(2.6, 0.08, 0.34)
	tool.append_from(bench_slab, 0, Transform3D(Basis(), Vector3(0.0, 0.5, -0.45)))
	var mesh := tool.commit()
	_cache["shelter"] = mesh
	return mesh


static func utility_box() -> Mesh:
	if _cache.has("utility"):
		return _cache["utility"]
	var box := BoxMesh.new()
	box.size = Vector3(0.62, 1.05, 0.42)
	_cache["utility"] = _translated(box, 0.52)
	return _cache["utility"]


static func _translated(mesh: Mesh, height: float) -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(mesh, 0, Transform3D(Basis(), Vector3(0.0, height, 0.0)))
	return tool.commit()
