# Etapa 3 — Geração Urbana: relatório de integração

Este documento responde à entrega da Etapa 3: o que já existia, o que foi
acrescentado, o que foi mudado, o que foi deliberadamente recusado e o que
continua faltando. Como o da Etapa 2, ele é separado de `ARQUITETURA.md`: aqui
está o **como chegou**; lá está **o que é**.

---

## 1. Limitação de escopo, declarada de saída

**Não recebi o ZIP de nenhuma etapa anterior.** O que existe neste repositório é
o trabalho das etapas 1 e 2, e é sobre ele que a Etapa 3 foi construída. Todas
as afirmações abaixo são verificáveis lendo os arquivos citados; nenhuma delas
diz "integrei com algo que não vi".

**Nada aqui foi executado.** O ambiente onde este código foi escrito não tem
Godot — nem `godot --headless` roda. A suíte e a cena de demonstração existem
para que a primeira execução real seja barata:

```bash
godot --headless --path . --script res://tests/run_tests.gd
godot --path . city/demo/guapimirim_center_demo.tscn
```

Rode a suíte antes de qualquer outra coisa. Se algo falhar, o primeiro suspeito
não é a camada urbana em si, e sim o contrato que ela supõe: `SectorGrid` com
512 m de bloco, `TerrainService.height_at` puro em relação à posição, e o
`SectorInstance` montando malha na thread principal.

**Nenhum FPS foi medido.** Nenhum número de desempenho neste documento é
resultado de medição; são estimativas de ordem de grandeza, e estão marcadas como
tal quando aparecem.

---

## 2. Auditoria das etapas anteriores

### O que foi reaproveitado sem alteração de contrato

| Sistema | Arquivo | Situação na Etapa 3 |
|---|---|---|
| Projeção LCC | `world/geography/lcc_projection.gd` | **intacto** |
| Fachada de coordenadas | `world/geography/geo_coordinate_system.gd` | **intacto** |
| Grade espacial | `world/geography/sector_grid.gd` | **intacto** |
| Índice de municípios e densidade | `world/geography/municipality_index.gd` | **intacto** |
| Altura do terreno (SRTM + procedural) | `world/terrain/terrain_service.gd` | **intacto** |
| Malha de terreno e saia | `world/sectors/terrain_mesh_builder.gd` | **intacto** |
| Malha de vias | `world/sectors/road_mesh_builder.gd` | **intacto** |
| Origem flutuante | `world/streaming/floating_origin.gd` | **intacto** |
| LOD do terreno | `world/lod/*` | **intacto** |
| Fila, cache, orçamento, retentativa | `world/streaming/*` | **intacto** |
| Gerador procedural de ruas | `city/procedural_generation/city_generator.gd` | **estendido** (função nova `build_roads_only`) |
| Repositório de setor | `world/sectors/sector_repository.gd` | **redirecionado** (passa a chamar o gerador urbano) |
| Instância de setor | `world/sectors/sector_instance.gd` | **estendido** (caminho urbano novo; caminho antigo preservado) |
| Malhas primitivas | `rendering/materials/procedural_meshes.gd` | **estendido** (vegetação e mobiliário novos) |
| Perfis de qualidade | `rendering/quality/quality_profile.gd` | **estendido** (nove chaves urbanas) |
| HUD | `ui/hud/hud.gd` | **estendido** (uma linha de diagnóstico) |

### Duas mudanças que tocam arquivos existentes, e por quê

1. **`SectorRepository.load_payload` passou a chamar `UrbanGenerator`.** Era a
   única porta de entrada de payload do streaming; deixar a camada urbana fora
   dela exigiria um segundo caminho de carga, e dois caminhos divergem. A
   prioridade das fontes continua a mesma (arquivo > framework > procedural) —
   o que mudou é existir uma camada em cima da base, não quem manda.

2. **`CityGenerator.build_payload` foi refatorado em duas funções.** O corpo que
   monta a reticulação saiu para `build_roads_only(coord, seed, density)`, porque
   a rede urbana precisa das ruas dos oito vizinhos para fechar as quadras da
   fronteira. Pedir os nove payloads completos geraria lote e prédio que seriam
   jogados fora. `build_payload` chama a função nova, com resultado idêntico —
   `tests/unit/test_city_generator.gd` continua válido sem alteração.

---

## 3. A decisão central: de onde vêm as ruas

O pedido é "importar a geometria real das ruas". Isso exige um dado que **não
existe neste repositório**: nenhum arquivo `.osm` acompanha o projeto, e o
ambiente não tem acesso de rede para baixar um extrato. Inventar um traçado e
chamá-lo de real seria a única coisa que o pedido proíbe explicitamente.

A solução foi construir **três fontes com prioridade explícita** e declarar a
procedência de cada uma dentro do próprio payload:

| Prioridade | Fonte | O que é | Licença |
|---|---|---|---|
| 1 | payload de setor com `source: osm` | geometria importada por `tools/map_importer/import_osm.gd` | ODbL 1.0 (OpenStreetMap) |
| 2 | `data/geographic/urban/guapimirim_centro.json` | **traçado esquemático autoral**, georreferenciado ao centro municipal | CC0-1.0 (obra do projeto) |
| 3 | reticulação procedural da Etapa 1 | grade determinística, sem dado externo | CC0-1.0 |

As três entram no **mesmo pipeline**: rede de ruas → quadras → lotes →
edificações → mobiliário → vegetação. Trocar de fonte não muda uma linha de
lote; muda de onde veio a rua.

O traçado esquemático existe para o sistema ter sobre o que trabalhar hoje. Ele
é um desenho de larga escala em metros, ancorado no centro de Guapimirim de
`data/geographic/municipalities.json`, com eixos arteriais, coletoras, locais
irregulares, um eixo ferroviário e o Rio Iconha. **Não é levantamento, não é
dado cadastral e não é OpenStreetMap** — e isso está escrito no `provenance` do
próprio arquivo, no `provenance` de cada payload gerado e em
`data/geographic/urban/ATTRIBUTION.md`.

Quando existir um extrato real do município:

```bash
godot --headless --path . --script res://tools/map_importer/import_osm.gd -- \
    --input=data/geographic/osm/guapimirim.osm --bbox=-22.60,-43.05,-22.48,-42.91
```

A partir daí aquele setor passa a usar a geometria importada, e o traçado
esquemático deixa de ser consultado ali.

---

## 4. O que foi construído

Tudo em `city/urban/`. Cada arquivo tem uma responsabilidade e não conhece a
árvore de cena.

### 4.1 `polygon_utils.gd` — a base

Área, centroide, orientação, ponto-em-polígono, recorte por meia-reta,
recorte por faixa, encolhimento por arestas, interseção de segmentos,
sobreposição com tolerância, triangulação por *ear clipping* e conversão para
JSON.

Decisão que atravessa a etapa: **nenhuma operação geométrica usa "deslocar
aresta"**. Quadra, lote e recuo são todos recorte por meia-reta sobre o polígono
real, porque deslocamento de aresta se auto-intersecta em polígono côncavo — e
quarteirão de esquina é côncavo.

### 4.2 `road_network.gd` — a rede

Polilinhas viram grafo plano: cruzamentos são calculados e cortam os segmentos,
pontas a menos de 60 cm são fundidas num nó só. Sem as duas coisas não existe
face fechada, e sem face fechada não existe quadra.

Consulta principal: `clearance_to_road(ponto)` — folga até a **borda** da pista,
com índice espacial em células de 32 m para não varrer a rede a cada objeto.

### 4.3 `urban_block_builder.gd` — quadras

Extração de faces por percurso de meia-aresta: em cada nó, sai-se pela aresta de
menor giro anti-horário em relação à direção de chegada, excluída a volta. As
faces internas saem em sentido anti-horário; a externa sai em sentido horário e
é descartada.

Depois, recuo por aresta: metade da pista da via correspondente + calçada +
folga. A "via correspondente" é a mais próxima do ponto médio da aresta, então
quadra de esquina recua de forma diferente em cada lado — como na cidade.

**Quadra de fronteira** pertence ao setor que contém o seu centroide e é gerada
por inteiro, com as ruas do entorno. É o que evita o quarteirão cortado ao meio
e o duplicado na divisa.

### 4.4 `parcel_splitter.gd` — lotes

Guilhotina em duas direções, e canto de quadra como terceiro passo:

1. fatias de largura variável paralelas à via principal (a testada);
2. cada fatia cortada em lote de frente e lote de fundo;
3. se a faixa encosta numa via perpendicular, o canto vira lote de esquina.

A frente do lote não é inferida da fatia: depois de formado o polígono, procura-se
a aresta com menor folga até o asfalto e orienta-se a normal para dentro do lote.
Lote de esquina acaba com a frente certa na rua que de fato o atende.

**Dois lotes nunca se sobrepõem** porque cada um nasce de uma fatia disjunta —
não é checagem, é propriedade da construção. `ParcelSplitter.validate()` confere
a propriedade nos testes.

### 4.5 `building_generator.gd` — edificações

Sete tipologias: casa térrea, casa de dois pavimentos, casa com garagem, casa com
varanda, edifício residencial, prédio comercial e construção mista. A escolha vem
de densidade urbana, área do lote, testada e um sorteio determinístico.

A pegada é um recorte do lote recuado pelos afastamentos; se não couber, encolhe
em até quatro tentativas; se continuar não cabendo, o lote fica vazio e vira
quintal com vegetação — como num loteamento real.

O gerador **não consulta o terreno**. É de propósito: roda nas threads de trabalho
do streaming e não pode disputar o cache do SRTM. A adaptação ao relevo acontece
na construção da malha, com embasamento (§4.10), e o inspetor mede a inclinação
e aponta o que passou da tolerância.

### 4.6 `building_modules.gd` — fachada como dado

Janela, porta, garagem, varanda, sacada, vitrine, toldo, escada — planejados como
**dados** (lado, posição ao longo da parede, peitoril, altura), não como malha. A
separação permite testar a composição da fachada sem GPU e mudar estilo sem
arriscar geometria. Paleta e cobertura também são dados: cor final viaja no
payload.

### 4.7 `urban_props.gd` — mobiliário

Poste, semáforo, placa, lixeira, banco, abrigo, caixa de infraestrutura, faixa de
pedestre e marcação de eixo. Todos derivados da via: o poste caminha ao longo da
aresta alternando de lado; o semáforo só nasce em nó de grau ≥ 3 com via
coletora ou arterial; a lixeira nasce ao lado da porta de estabelecimento
comercial. Todo objeto é rejeitado se cair no asfalto.

### 4.8 `urban_vegetation.gd` — vegetação

Árvore de calçada (espaçamento por via), árvore de quintal, arbusto de lote
vazio, gramado de praça. Toda posição passa por três rejeições: asfalto, pegada
de edificação e faixa de barreira. Quatro espécies, uma malha e um `MultiMesh`
por espécie.

### 4.9 `landmark_registry.gd` + `data/geographic/landmarks/`

Sistema de pontos de referência **movido a dado**: um JSON novo em
`data/geographic/landmarks/` acrescenta local, sem tocar em gerador, malha ou
teste. Cada entrada traz `confidence` (`alta`/`media`/`baixa`), `sources`,
`licence` e uma frase `honesty` dizendo o que aquele dado é e o que não é.

Quatro registros para o Centro de Guapimirim, **todos com confiança declarada e
nenhum declarado reprodução fiel**:

| id | papel | confiança | o que é |
|---|---|---|---|
| `estacao_guapimirim` | ponto de referência | baixa | massa genérica de estação sobre o eixo ferroviário |
| `espaco_aberto_central` | área aberta | baixa | praça genérica, sem nome levantado |
| `rio_iconha` | barreira | baixa | traçado aproximado do curso d'água |
| `eixo_ferroviário` | barreira | baixa | eixo esquemático, sem bitola nem pátio |

O edifício construído no ponto marcado carrega `landmark_id` e `confidence` no
payload, e o inspetor imprime os dois. Não existe no código nenhuma afirmação de
fidelidade arquitetônica.

### 4.10 `urban_mesh_builder.gd` — a malha

Uma malha de edificações e uma de pavimento por setor, com cor por vértice.

- **Parede por pavimento** ao longo do polígono da pegada (aceita lote irregular),
  com faixa fina entre andares.
- **Janela** é quad deslocado 7 cm para fora, com moldura em cor de esquadria e
  peitoril. Não há furo: furar parede custaria recorte por janela em tempo de
  carga, sem ganho a 30 FPS no celular.
- **Telhado** de duas águas, quatro águas, uma água ou laje com platibanda —
  conforme a tipologia.
- **Sacada** com laje e guarda-corpo, **varanda** com cobertura e pilares,
  **escada** de entrada, **vitrine** com toldo e bandeira de letreiro.
- **Muro com portão** na testada, com vão para o portão.
- **Calçada e guia** ao longo de cada via, e **sinalização horizontal** (faixa de
  pedestre e marcação de eixo) no pavimento.
- **Embasamento**: a edificação apoia no canto mais baixo da pegada e o vão até o
  mais alto é preenchido. Casa em rua inclinada nasce com sapata aparente em vez
  de flutuar.

### 4.11 `urban_generator.gd` — o orquestrador

Monta a rede com recorte maior que o setor, extrai quadras, divide lotes, gera
edificações (respeitando pontos de referência, áreas abertas e faixas de
barreira), planeja mobiliário e vegetação e serializa para o payload.

**O payload é aditivo.** Mantém todas as chaves da Etapa 2 — `roads`, `buildings`
com `center`/`size`/`angle`/`height`/`kind`/`door`, `trees`, `props`, `water`,
`version`, `grid`, `origin` — e acrescenta `blocks`, `parcels`, `vegetation`,
`street_objects`, `landmarks`, `barriers`, `open_spaces`, `urban_geometry`,
`urban_stats`, `provenance` e `urban_v3`. Trânsito, pedestres, minimapa, porta de
interior, `RoadGraph` e `validate_sectors` continuam lendo o que já liam; é por
isso que nenhum deles precisou mudar.

**Setor rural continua barato**: sem dado externo e abaixo da densidade mínima,
a função devolve exatamente o payload da Etapa 2.

---

## 5. Integração com o streaming da Etapa 2

| Requisito | Como está resolvido |
|---|---|
| Geração por setor | `UrbanGenerator.build_payload(coord)` é a unidade; nada gerado fora de um setor |
| Instanciação sob demanda | `SectorInstance.build` monta a camada urbana só quando o payload chega; nenhum setor é pré-carregado |
| Descarregamento do distante | `release()` da Etapa 2 libera a árvore inteira, incluindo malha urbana e MultiMeshes |
| Cache de recursos | `SectorPayloadCache` já guardava payload; agora guarda também o urbano — voltar para trás não regera |
| LOD de edifícios e vegetação | `apply_detail`: mobiliário some a partir do nível 2, vegetação a partir do 3, sombra do prédio a partir do 3; prédio e calçada ficam sempre (a silhueta é o que se lê de longe) |
| Controle de memória | `memory_estimate_kb` da Etapa 2 já contava malha e MultiMesh; a camada urbana entra na mesma conta |
| Sem objetos duplicados | quadra pertence ao setor do centroide; ponto de referência gera uma vez; vegetação e mobiliário só emitem dentro do próprio recorte |
| Persistência de identificadores | `sector_id/B%03d`, `sector_id/L%02d`, `sector_id/Q%03d` — o identificador carrega o setor, então sobrevive a save, bake e recarga |

**Geração fora da thread principal.** O payload continua sendo montado nas
threads do `WorkerThreadPool`, como na Etapa 2. Para isso, `UrbanConfig` é um
instantâneo: trocar de perfil **substitui** o objeto em vez de alterá-lo em
campo, então um worker sempre lê um conjunto coerente de números.

---

## 6. Configuração e perfis

`UrbanConfig` é o dono único dos números de urbanismo (calçada, recuo, largura de
lote, profundidade, teto de edificações, detalhe de fachada, densidades). Nenhum
gerador escolhe tamanho por conta própria.

`QualityProfile` ganhou nove chaves:

| chave | mobile | pc_medium | pc_high |
|---|---|---|---|
| `urban_detail` | 1 | 2 | 2 |
| `urban_tree_density` | 0,55 | 0,85 | 1,0 |
| `urban_prop_density` | 0,5 | 0,85 | 1,0 |
| `urban_max_buildings` | 44 | 96 | 160 |
| `urban_parcel_scale` | 1,25 | 1,0 | 0,92 |
| `urban_max_vegetation` | 90 | 220 | 320 |
| `urban_max_props` | 70 | 180 | 260 |
| `urban_landmark_radius` | 12 | 16 | 18 |

O perfil mobile usa lote mais largo (menos lotes, menos prédios), fachada
simplificada e metade da vegetação. É calibragem inicial, **não** resultado de
benchmark.

---

## 7. Ferramentas

```bash
# relatório de quadras, lotes, prédios, duplicatas, sobreposição com rua e
# encostas fora de tolerância; sai com código 1 se houver erro
godot --headless --path . --script res://tools/urban_tools/urban_inspector.gd -- \
    --center=GUAPI --radius=1 [--json=relatorio.json]

# regenera setores específicos: apaga o payload gravado para forçar regeração,
# ou grava o resultado com --bake
godot --headless --path . --script res://tools/urban_tools/regenerate_sector.gd -- \
    --center=GUAPI --radius=1 [--bake] [--dry-run]
```

O inspetor responde, uma por uma, às perguntas do pedido: quadra sem lote, lote
fora da quadra, dois lotes no mesmo chão, prédio fora do lote, prédio sobre o
asfalto, identificador repetido, construção em encosta íngreme. E imprime a
atribuição de todos os conjuntos de dados usados.

A visualização de quadras e lotes está na **cena de demonstração**, tecla `F3`:
desenha os polígonos do próprio payload carregado com `ImmediateMesh`, em cima da
cidade — o mesmo dado que gerou os prédios, não uma reconstrução paralela.

---

## 8. Testes

`tests/unit/test_polygon_utils.gd`, `test_road_network.gd`,
`test_urban_block_builder.gd`, `test_parcel_splitter.gd`,
`test_building_generator.gd`, `test_urban_furniture.gd`,
`test_landmark_registry.gd`, `test_urban_generator.gd` — e, em integração,
`test_urban_sector.gd` e `test_urban_streaming.gd`.

Cobrem o que o pedido lista: construção de quadra, divisão de lote, validação de
polígono, distribuição de edificação, ausência de construção sobre rua, ausência
de duplicata, streaming urbano, descarregamento de setor, LOD urbano, colisão e
persistência de identificador. Todos determinísticos: nenhum usa `randf()`.

O que **não** há: teste de desempenho. Não existe nesta suíte nada que meça FPS,
porque nada aqui foi executado para medir.

---

## 9. Colisões e interação

- **Edificação**: uma caixa por prédio, apoiada na altura do terreno no centro.
  Caixa e não trimesh de fachada — o `CharacterBody3D` e o trânsito consultam a
  colisão a cada passo de física, e uma BVH da fachada custaria mais que a cidade.
- **Muro**: uma caixa por trecho, com o vão do portão.
- **Calçada**: superfície visual; a colisão do terreno embaixo dela continua
  valendo. Guia de 14 cm não é degrau de física.
- **Acesso de veículo, área de entrada e ponto de interação**: `door` e
  `entrance` no payload de cada edificação; `door_positions()` continua
  alimentando o `InteriorManager`.
- **Interiores**: a divisão por lote e por pavimento já está no dado
  (`levels`, `floor_height`, `footprint`), que é o que a etapa seguinte precisa
  para abrir a porta.

---

## 10. Limitações conhecidas, sem disfarce

1. **Nada foi executado.** Nem suíte, nem cena, nem ferramenta. A primeira
   execução real é a validação desta etapa.
2. **Nenhum FPS foi medido.** O custo da fachada por pavimento no iPhone 12 é
   estimativa; o teto de edificações por setor do perfil mobile é a válvula de
   segurança, não um número medido.
3. **As ruas do Centro de Guapimirim não são reais.** O traçado é esquemático e
   está declarado como tal em todos os lugares em que aparece. A fidelidade
   geográfica existe na projeção, no relevo e no centro municipal; **não** no
   traçado viário até que um `.osm` seja importado.
4. **Nenhuma edificação real foi reproduzida.** Pontos de referência geram massa
   genérica marcada com `confidence`.
5. **Sem malha de rio, ferrovia ou água.** As barreiras reservam a faixa (não se
   constrói ali) e impedem vegetação, mas o que se vê é o terreno. A água já era
   limitação da Etapa 2 e continua.
6. **Sem oclusão.** O LOD corta por distância; uma parede entre o jogador e a
   cidade não economiza nada.
7. **Vegetação e mobiliário por setor**, não por célula de detalhe de 128 m. A
   célula continua existindo, testada e visível no diagnóstico, mas ainda não
   distribui conteúdo — é a mesma pendência que a Etapa 2 deixou.
8. **Colisão de calçada não existe** (só o visual e a guia). O jogador anda na
   colisão do terreno.
9. **Muro e portão são colisão de caixa**; portão não abre.
10. **Sem interior ligado ao prédio gerado.** O apartamento da Etapa 1 continua
    funcionando; a porta de cada casa nova é um ponto de entrada registrado, sem
    interior próprio.
11. **Fachada sem textura.** Tudo é cor por vértice; material e textura entram na
    etapa de renderização.
12. **`urban_v3` é tudo-ou-nada por setor.** Não há degradação por distância
    dentro da camada urbana: um setor no nível 3 continua com a malha de prédio
    completa, só com mobiliário e vegetação escondidos. Malha de prédio em dois
    níveis de detalhe é o próximo passo natural.
13. **Bake de payload urbano ainda não tem ferramenta de release.** `--bake` do
    `regenerate_sector` grava; não existe empacotamento de dados para build.
14. **`data/geographic/urban/` cobre cerca de 1,8 km.** Fora desse recorte, o
    mundo volta à reticulação procedural — que não corresponde a lugar nenhum.

---

## 11. Arquivos novos e modificados

### Novos — geração

```
city/urban/polygon_utils.gd          geometria de polígono
city/urban/urban_schema.gd           vocabulário e versões da camada
city/urban/urban_config.gd           parâmetros e instantâneo de perfil
city/urban/road_network.gd           grafo plano das vias
city/urban/urban_block_builder.gd    faces -> quadras
city/urban/parcel_splitter.gd        quadras -> lotes
city/urban/building_modules.gd       fachada como dado
city/urban/building_generator.gd     lotes -> edificações
city/urban/urban_vegetation.gd       distribuição de vegetação
city/urban/urban_props.gd            mobiliário urbano
city/urban/landmark_registry.gd      pontos de referência
city/urban/street_framework.gd       traçado esquemático
city/urban/urban_generator.gd        orquestrador e serialização
city/urban/urban_mesh_builder.gd     malha de fachada, calçada e sinalização
```

### Novos — demonstração, ferramentas e dados

```
city/demo/guapimirim_center_demo.gd      cena de demonstração
city/demo/guapimirim_center_demo.tscn
tools/urban_tools/urban_inspector.gd     relatório de validação
tools/urban_tools/regenerate_sector.gd   regeneração por setor e bake
data/geographic/urban/guapimirim_centro.json
data/geographic/urban/ATTRIBUTION.md
data/geographic/landmarks/guapimirim_centro.json
docs/ETAPA3.md
```

### Novos — testes

```
tests/unit/test_polygon_utils.gd
tests/unit/test_road_network.gd
tests/unit/test_urban_block_builder.gd
tests/unit/test_parcel_splitter.gd
tests/unit/test_building_generator.gd
tests/unit/test_urban_furniture.gd
tests/unit/test_landmark_registry.gd
tests/unit/test_urban_generator.gd
tests/integration/test_urban_sector.gd
tests/integration/test_urban_streaming.gd
```

### Modificados

```
city/procedural_generation/city_generator.gd   extração de build_roads_only
world/sectors/sector_repository.gd             carga passa pelo gerador urbano
world/sectors/sector_instance.gd               caminho urbano: malha, colisão, MultiMesh, LOD
rendering/materials/procedural_meshes.gd       malhas de vegetação e mobiliário
rendering/quality/quality_profile.gd           nove chaves urbanas por perfil
world/streaming/sector_streaming_manager.gd    aplica UrbanConfig junto com o perfil
ui/hud/hud.gd                                  linha de diagnóstico urbano
tests/run_tests.gd                             dez arquivos de teste registrados
README.md                                      versão, demonstração, ferramentas, limites
CHANGELOG.md                                   entrada 0.3.0
docs/ARQUITETURA.md                            seção da camada urbana
```

---

## 12. Como rodar

```bash
# 1. o mais importante: a suíte
godot --headless --path . --script res://tests/run_tests.gd

# 2. a cidade
godot --path . city/demo/guapimirim_center_demo.tscn
```

Na demonstração: `WASD` mover, `Q`/`E` descer/subir, `SHIFT` rápido, `F1` perfil
gráfico, `F2` piloto automático, `F3` desenhar quadras e lotes, `F4` regenerar os
setores em volta, `F5` ligar/desligar o streaming, `R` voltar ao centro.

No jogo (`core/bootstrap/main.tscn`) nada muda no que o jogador vê de interface:
a cidade simplesmente passa a ser gerada pela camada urbana onde há densidade
para isso.
