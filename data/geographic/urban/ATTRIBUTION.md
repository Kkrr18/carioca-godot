# Atribuição e licenças — dados geográficos urbanos

A camada urbana do CARIOCA funciona com **três fontes de rua**, em ordem de
prioridade. Cada uma tem procedência e licença próprias, e o payload do setor
grava a que foi usada em `provenance`.

## 1. Extrato OpenStreetMap (`data/geographic/sectors/`)

Importado por `tools/map_importer/import_osm.gd` a partir de um arquivo `.osm`
colocado em `data/geographic/osm/`.

- **Fonte:** OpenStreetMap — © colaboradores do OpenStreetMap.
- **Licença:** Open Database License (ODbL) 1.0 —
  <https://www.openstreetmap.org/copyright>.
- **Obrigação:** atribuição visível e, em banco de dados derivado distribuído,
  *share-alike* sobre a base. Os arquivos em `data/geographic/sectors/` são
  derivados diretos e herdam a ODbL.
- **Estado neste repositório:** **nenhum arquivo `.osm` acompanha o projeto.**
  Nenhum dado do OpenStreetMap está embutido no CARIOCA até aqui. Quando for
  embutido, este arquivo precisa ser atualizado junto.

## 2. Traçado esquemático (`data/geographic/urban/`)

Desenhado à mão para o projeto, em metros, ancorado no centro municipal de
Guapimirim definido em `data/geographic/municipalities.json`.

- **Fonte:** autoral, derivada de conhecimento público de larga escala do núcleo
  urbano.
- **Licença:** CC0-1.0 (domínio público, obra do próprio projeto).
- **O que é:** ruas com classe e largura plausíveis, na orientação do centro,
  cobrindo cerca de 1,8 km.
- **O que não é:** levantamento, dado cadastral, extrato do OpenStreetMap,
  nem declaração sobre a posição exata de nenhuma via.
- **Substituição:** setor importado de `.osm` sempre vence; e o conjunto inteiro
  deixa de ser usado assim que existir extrato do município.

## 3. Reitulação procedural (`city/procedural_generation/`)

Gerada por código, sem dado externo.

- **Fonte:** obra do próprio projeto.
- **Licença:** CC0-1.0.
- **Uso:** onde não há `.osm` nem traçado esquemático. É uma grade determinística,
  não uma afirmação sobre nenhum lugar.

## Pontos de referência (`data/geographic/landmarks/`)

Também autorais (CC0-1.0), com o mesmo esclarecimento: cada entrada traz
`confidence`, `sources` e `honesty`. **Nenhuma edificação é reprodução fiel** —
o que o gerador constrói no lugar marcado é uma massa genérica.

## Relevo

Tiles SRTM `.hgt` em `data/geographic/elevation/`. O programa SRTM é de domínio
público (USGS/NASA). Nenhum tile acompanha este repositório.
