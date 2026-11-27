class_name WorldGridConfig
extends RefCounted

## Dono único das dimensões espaciais do mundo.
##
## Nenhum sistema escolhe tamanho de célula por conta própria: a grade mora em
## `SectorGrid`, esta classe é a porta de entrada para mudá-la e para saber qual
## é o vocabulário em uso.
##
## Vocabulário (Etapa 2) x nomes herdados da Etapa 1:
##
## | Plano da Etapa 2 | Código            | Etapa 1      | Tamanho |
## |---|---|---|---|
## | Tile             | `SectorGrid.SECTOR_SIZE`  | setor        | 512 m |
## | Setor            | `SectorGrid.DETAIL_CELL_SIZE` | (novo)   | 128 m |
## | Microárea        | `SectorGrid.MICRO_SIZE`   | microárea    | 100 m |
## | —                | `SectorGrid.TILE_SIZE`    | tile regional| 2000 m|
##
## A renomeação completa para o vocabulário da Etapa 2 foi recusada de
## propósito: `SECTOR_SIZE` = 512 m está gravado nas chaves de disco
## (`data/geographic/sectors/**`, `RJ_METRO_GUAPI_0878_15621`), na reticulação do
## gerador urbano e em dez arquivos de teste. Trocar o nome de tudo isso não
## muda um único pixel e quebraria o trabalho da etapa anterior. O que se fez foi
## separar o **valor** da grade (configurável aqui) do **nome** que ele já tinha.
##
## 512 / 128 = 4 exato, então a célula de detalhe subdivide o bloco de streaming
## sem faixa irregular — o erro que a microárea de 100 m evita ter uma grade
## própria, com âncora independente.

## Tamanhos padrão. São os números que o projeto entrega hoje.
const STREAM_CELL_SIZE := 512.0
const DETAIL_CELL_SIZE := 128.0
const REGION_TILE_SIZE := 2000.0
const MICRO_CELL_SIZE := 100.0


static func defaults() -> Dictionary:
	return {
		"stream_cell": STREAM_CELL_SIZE,
		"detail_cell": DETAIL_CELL_SIZE,
		"region_tile": REGION_TILE_SIZE,
		"micro_cell": MICRO_CELL_SIZE,
	}


## Muda a grade em tempo de execução. Retorna falso quando os valores não fazem
## sentido geométrico (célula negativa, detalhe maior que o bloco).
##
## Chamar depois que o mundo começou a gerar chaves deixa o disco e a grade
## discordando; `SectorGrid.configure` avisa nesse caso e o chamador precisa
## limpar os dados gravados (`data/geographic/sectors`).
static func apply_geometry(stream_cell: float = STREAM_CELL_SIZE, detail_cell: float = DETAIL_CELL_SIZE, region_tile: float = REGION_TILE_SIZE, micro_cell: float = MICRO_CELL_SIZE) -> bool:
	if stream_cell <= 0.0 or detail_cell <= 0.0 or region_tile <= 0.0 or micro_cell <= 0.0:
		push_warning("WorldGridConfig: todas as dimensões precisam ser positivas")
		return false
	if detail_cell > stream_cell:
		push_warning("WorldGridConfig: célula de detalhe (%.1f m) maior que o bloco de streaming (%.1f m)" % [detail_cell, stream_cell])
		return false
	var ratio := stream_cell / detail_cell
	if absf(ratio - roundf(ratio)) > 1e-6:
		# Não é erro fatal: só significa que a última célula de detalhe do bloco
		# fica mais estreita. Vale o aviso porque o LOD usa essa proporção.
		push_warning("WorldGridConfig: %.1f m não é múltiplo inteiro de %.1f m" % [stream_cell, detail_cell])
	return SectorGrid.configure(stream_cell, detail_cell, region_tile, micro_cell)


static func restore_defaults() -> bool:
	return SectorGrid.configure(STREAM_CELL_SIZE, DETAIL_CELL_SIZE, REGION_TILE_SIZE, MICRO_CELL_SIZE)


static func describe() -> String:
	return "bloco %.0f m · detalhe %.0f m (%d por eixo) · microárea %.0f m · tile regional %.0f m" % [
		SectorGrid.SECTOR_SIZE,
		SectorGrid.DETAIL_CELL_SIZE,
		SectorGrid.detail_cells_per_sector(),
		SectorGrid.MICRO_SIZE,
		SectorGrid.TILE_SIZE,
	]


## Quantos blocos um raio em blocos carrega — o número que dimensiona memória e
## draw calls. Fica aqui para o perfil de qualidade e os testes usarem a mesma
## conta que o streaming.
static func cells_for_radius(radius: int) -> int:
	return SectorGrid.sectors_in_radius(Vector2i.ZERO, radius).size()


## Raio em metros que um raio em blocos representa na borda.
static func radius_m(radius: int) -> float:
	return float(maxi(radius, 0)) * SectorGrid.SECTOR_SIZE
