class_name SectorGrid
extends RefCounted

## Hierarquia geográfica do mundo — a espinha do streaming.
##
##   Tile regional     2000 m  agrupa blocos, organiza dados e prioridade
##   Bloco              512 m  unidade de carregamento (terreno, ruas, prédios)
##   Célula de detalhe  128 m  granularidade fina: distância de LOD, diagnóstico
##   Microárea          100 m  organização local de objetos e vegetação
##
## O plano chama o bloco de 512 m de "tile" e a célula de 128 m de "setor". Os
## nomes herdados foram mantidos porque `SECTOR_SIZE = 512` está gravado nas
## chaves de disco e na reticulação do gerador urbano; `WorldGridConfig`
## documenta a correspondência e concentra a mudança de dimensão.
##
## A grade é ancorada na origem do espaço métrico global, então o índice de um
## bloco é uma função pura da posição — não existe registro central, não existe
## estado, e dois sistemas independentes chegam sempre à mesma chave.
##
## Microáreas têm grade própria de 100 m em vez de serem subdivididas dentro do
## bloco: 512 não é múltiplo de 100 e forçar alinhamento criaria faixas de
## largura irregular no meio de cada bloco. A célula de detalhe, ao contrário,
## divide o bloco exatamente (4x4) e as duas formas de calcular o índice
## coincidem por construção.

## Dimensões padrão da grade. Não são mais constantes: `configure()` troca por
## um conjunto diferente (ver `WorldGridConfig`), e por isso nenhum sistema lê um
## literal numérico — todos passam por aqui.
const DEFAULT_SECTOR_SIZE := 512.0
const DEFAULT_DETAIL_SIZE := 128.0
const DEFAULT_TILE_SIZE := 2000.0
const DEFAULT_MICRO_SIZE := 100.0

## Bloco de streaming — "tile" no vocabulário da Etapa 2.
static var SECTOR_SIZE: float = DEFAULT_SECTOR_SIZE

## Célula de detalhe — "setor" no vocabulário da Etapa 2. Subdivisão exata do
## bloco (512/128 = 4). É a unidade de granularidade fina: distância de LOD,
## futuras camadas de vegetação e mobiliário.
static var DETAIL_CELL_SIZE: float = DEFAULT_DETAIL_SIZE

static var TILE_SIZE: float = DEFAULT_TILE_SIZE
static var MICRO_SIZE: float = DEFAULT_MICRO_SIZE
static var SECTORS_PER_TILE: int = 3  ## 2000/512 = 3,9 -> um tile cobre até 3x3 blocos cheios

## Marcado em `key()`: se a grade já gerou chave nesta sessão, mudar as dimensões
## faz o disco e o runtime discordarem.
static var _has_generated_keys: bool = false


## Troca as dimensões da grade. Retorna falso para valores inválidos. Chamar
## depois que o mundo gerou chaves é permitido, mas avisado: os arquivos em
## `data/geographic/sectors` passam a representar outro lugar.
static func configure(stream_cell: float, detail_cell: float, tile: float, micro: float) -> bool:
	if stream_cell <= 0.0 or detail_cell <= 0.0 or tile <= 0.0 or micro <= 0.0:
		push_warning("SectorGrid.configure: dimensões precisam ser positivas")
		return false
	if _has_generated_keys:
		push_warning("SectorGrid.configure: a grade já gerou chaves nesta sessão — dado gravado deixa de corresponder")
	SECTOR_SIZE = stream_cell
	DETAIL_CELL_SIZE = detail_cell
	TILE_SIZE = tile
	MICRO_SIZE = micro
	SECTORS_PER_TILE = maxi(1, int(floor(tile / stream_cell)))
	return true


static func restore_defaults() -> bool:
	return configure(DEFAULT_SECTOR_SIZE, DEFAULT_DETAIL_SIZE, DEFAULT_TILE_SIZE, DEFAULT_MICRO_SIZE)


static func sector_of(metric: Vector2) -> Vector2i:
	return Vector2i(floori(metric.x / SECTOR_SIZE), floori(metric.y / SECTOR_SIZE))


static func sector_origin(coord: Vector2i) -> Vector2:
	return Vector2(float(coord.x) * SECTOR_SIZE, float(coord.y) * SECTOR_SIZE)


static func sector_center(coord: Vector2i) -> Vector2:
	return sector_origin(coord) + Vector2(SECTOR_SIZE * 0.5, SECTOR_SIZE * 0.5)


static func sector_rect(coord: Vector2i) -> Rect2:
	return Rect2(sector_origin(coord), Vector2(SECTOR_SIZE, SECTOR_SIZE))


static func contains(coord: Vector2i, metric: Vector2) -> bool:
	return sector_of(metric) == coord


static func tile_of(metric: Vector2) -> Vector2i:
	return Vector2i(floori(metric.x / TILE_SIZE), floori(metric.y / TILE_SIZE))


static func tile_of_sector(coord: Vector2i) -> Vector2i:
	return tile_of(sector_center(coord))


static func tile_rect(tile: Vector2i) -> Rect2:
	return Rect2(Vector2(float(tile.x) * TILE_SIZE, float(tile.y) * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))


static func micro_of(metric: Vector2) -> Vector2i:
	return Vector2i(floori(metric.x / MICRO_SIZE), floori(metric.y / MICRO_SIZE))


## Índice da microárea dentro do setor (0..5 em cada eixo). O último índice
## pode ficar mais estreito — é consequência de 512 não ser múltiplo de 100.
static func micro_index_in_sector(metric: Vector2) -> Vector2i:
	var micro := micro_of(metric)
	var sector := sector_of(metric)
	var per := int(floor(SECTOR_SIZE / MICRO_SIZE))
	return Vector2i(micro.x - sector.x * per, micro.y - sector.y * per)


## Chave estável de armazenamento: só os índices inteiros, sem rótulo humano.
## O identificador legível (RJ_METRO_GUAPI_...) é derivado em MunicipalityIndex.
static func key(coord: Vector2i) -> String:
	_has_generated_keys = true
	return "%d_%d" % [coord.x, coord.y]


static func parse_key(text: String) -> Vector2i:
	var parts := text.split("_")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


static func tile_key(tile: Vector2i) -> String:
	return "t%d_%d" % [tile.x, tile.y]


static func distance_sectors(a: Vector2i, b: Vector2i) -> float:
	var dx := float(a.x - b.x)
	var dy := float(a.y - b.y)
	return sqrt(dx * dx + dy * dy)


## Todos os setores dentro de um raio (em setores), do mais próximo ao mais
## distante. A ordem é a prioridade de carregamento.
static func sectors_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := maxi(radius, 0)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r + r:
				continue
			out.append(Vector2i(center.x + dx, center.y + dy))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return distance_sectors(a, center) < distance_sectors(b, center))
	return out


## Distância em metros do ponto ao centro do setor.
static func distance_m(coord: Vector2i, metric: Vector2) -> float:
	return sector_center(coord).distance_to(metric)


## Ponto do setor mais próximo de `metric` — a borda, quando o ponto está fora.
static func nearest_point_in_sector(coord: Vector2i, metric: Vector2) -> Vector2:
	var origin := sector_origin(coord)
	return Vector2(
		clampf(metric.x, origin.x, origin.x + SECTOR_SIZE),
		clampf(metric.y, origin.y, origin.y + SECTOR_SIZE)
	)


## Distância até a **borda** do setor. É esta que o LOD consulta: um bloco cujo
## centro está a 700 m pode começar a 450 m do jogador, e usar o centro o jogaria
## para um nível grosseiro.
static func distance_to_sector_m(coord: Vector2i, metric: Vector2) -> float:
	return metric.distance_to(nearest_point_in_sector(coord, metric))


## --- Célula de detalhe (128 m) ---------------------------------------------
##
## Grade própria ancorada na origem métrica, como a de setores: o índice é uma
## função pura da posição. 512 / 128 = 4 exato, então um bloco contém 4x4
## células de detalhe sem faixa irregular em nenhuma borda.

static func detail_of(metric: Vector2) -> Vector2i:
	return Vector2i(floori(metric.x / DETAIL_CELL_SIZE), floori(metric.y / DETAIL_CELL_SIZE))


static func detail_origin(cell: Vector2i) -> Vector2:
	return Vector2(float(cell.x) * DETAIL_CELL_SIZE, float(cell.y) * DETAIL_CELL_SIZE)


static func detail_center(cell: Vector2i) -> Vector2:
	return detail_origin(cell) + Vector2(DETAIL_CELL_SIZE * 0.5, DETAIL_CELL_SIZE * 0.5)


static func detail_rect(cell: Vector2i) -> Rect2:
	return Rect2(detail_origin(cell), Vector2(DETAIL_CELL_SIZE, DETAIL_CELL_SIZE))


## Quantas células de detalhe cabem por eixo do bloco. A última pode ser mais
## estreita se as dimensões não forem múltiplas.
static func detail_cells_per_sector() -> int:
	return maxi(1, int(round(SECTOR_SIZE / DETAIL_CELL_SIZE)))


static func detail_cell_of_sector(index: Vector2i, sector: Vector2i) -> Vector2i:
	var per := detail_cells_per_sector()
	return Vector2i(sector.x * per + index.x, sector.y * per + index.y)


static func sector_of_detail(cell: Vector2i) -> Vector2i:
	var per := detail_cells_per_sector()
	return Vector2i(floori(float(cell.x) / float(per)), floori(float(cell.y) / float(per)))


static func detail_index_in_sector(metric: Vector2) -> Vector2i:
	var cell := detail_of(metric)
	var sector := sector_of(metric)
	var per := detail_cells_per_sector()
	return Vector2i(cell.x - sector.x * per, cell.y - sector.y * per)


static func detail_cells_in_sector(sector: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var per := detail_cells_per_sector()
	for dy in range(per):
		for dx in range(per):
			out.append(detail_cell_of_sector(Vector2i(dx, dy), sector))
	return out


## Células de detalhe cujo centro cai dentro de um raio em metros. Permite saber
## o que está de fato perto do jogador dentro de um bloco carregado.
static func detail_cells_within(sector: Vector2i, metric: Vector2, radius_m: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var radius_sq := radius_m * radius_m
	for cell in detail_cells_in_sector(sector):
		if detail_center(cell).distance_squared_to(metric) <= radius_sq:
			out.append(cell)
	return out


## Caminho relativo de armazenamento de um setor no disco.
static func storage_path(coord: Vector2i, region: String = "METRO", municipality: String = "GERAL") -> String:
	return "res://data/geographic/sectors/%s/%s/%s.json" % [region, municipality, key(coord)]
