# Etapa 2 — Terreno e Streaming: relatório de integração

Este documento responde à entrega da Etapa 2: o que já existia, o que foi
acrescentado, o que foi mudado e o que continua faltando. Ele é deliberadamente
separado de `ARQUITETURA.md`, que descreve o sistema como ele **é**, não como ele
chegou aqui.

---

## 1. Limitação de escopo, declarada de saída

**Não recebi o ZIP da Etapa 1 para auditoria externa.** O que existe neste
repositório é o trabalho completo da etapa anterior, e é sobre ele que a Etapa 2
foi construída. Todas as afirmações abaixo são verificáveis lendo os arquivos
citados; nenhuma delas diz "integrei com algo que não vi".

**Nada aqui foi executado.** O ambiente onde este código foi escrito não tem
Godot. A suíte de testes existe para que a primeira execução real seja barata —
rode-a antes de qualquer outra coisa:

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

---

## 2. Auditoria da Etapa 1

### O que já existia e foi reaproveitado sem alteração de contrato

| Sistema | Arquivo | Situação na Etapa 2 |
|---|---|---|
| Altura do terreno (SRTM + procedural) | `world/terrain/terrain_service.gd` | **reaproveitado** — é a função pura que garante ausência de costura |
| Malha de terreno | `world/sectors/terrain_mesh_builder.gd` | **estendido** — parâmetro opcional de saia |
| Instância de setor | `world/sectors/sector_instance.gd` | **estendido** — troca de resolução do terreno em tempo real |
| Grade espacial | `world/geography/sector_grid.gd` | **estendido** — dimensões configuráveis + célula de detalhe |
| Árvore de setores | `world/sectors/sector_instance.gd` | **reaproveitado** |
| Repositório de payload | `world/sectors/sector_repository.gd` | **reaproveitado** |
| Projeção geográfica | `world/geography/lcc_projection.gd` | **reaproveitado sem mudança** |
| Fachada de coordenadas | `world/geography/geo_coordinate_system.gd` | **reaproveitado sem mudança** |
| Origem flutuante | `world/streaming/floating_origin.gd` | **reaproveitado sem mudança** — agora com teste de invariante |
| Streaming assíncrono | `world/streaming/sector_streaming_manager.gd` | **refatorado por dentro, API pública preservada** |
| Gerador urbano | `city/procedural_generation/city_generator.gd` | **reaproveitado** — continua sem saber que existe LOD |
| Perfis de qualidade | `rendering/quality/quality_profile.gd` | **estendido** — passa a ser a fonte dos números de LOD e memória |

### O que a Etapa 1 declarava como ausente

O README da etapa anterior listava, com honestidade:

> **Sem LOD por distância** ainda: o corte é por setor (dentro do raio carrega o
> setor inteiro, fora descarrega). LOD 0–3 e oclusão entram na fase de expansão.

É exatamente essa lacuna que a Etapa 2 fecha — LOD 0–3 — e nada além dela. A
oclusão **continua ausente** (ver §8).

### Sistemas que já existiam e foram preservados por decisão

Não reimplementei projeção, elevação, geração urbana, save, HUD ou minimapa. Duas
mudanças tocaram arquivos existentes fora do streaming:

1. `municipality_index.gd` — o cache de densidade passou a ser protegido por
   `Mutex`. Motivo concreto: o streaming roda **duas** gerações de payload em
   paralelo, e ambas escrevem nesse `Dictionary`; `Dictionary` não é
   thread-safe. É um defeito real da Etapa 1 que só aparece sob a concorrência
   que a Etapa 2 exercita.
2. `quality_profile.gd` — a aplicação do perfil deixou de escrever campo a campo
   no manager e passou a chamar `configure_quality()`. Antes, um número novo no
   perfil não chegava ao streaming sem edição em dois arquivos.

---

## 3. Vocabulário: por que o código não se chama "tile" e "setor"

O plano da Etapa 2 pede **tile de 512 m** e **setor de 128 m**. A Etapa 1 usa
**setor de 512 m** e **microárea de 100 m**. Os números do plano e os nomes do
código não coincidem.

Renomear tudo foi recusado porque `SECTOR_SIZE = 512` está gravado em:

- chaves de disco (`data/geographic/sectors/.../878_15621.json` e o id legível
  `RJ_METRO_GUAPI_0878_15621`),
- a reticulação do gerador urbano (LOD não muda onde uma rua passa),
- dez arquivos de teste da Etapa 1.

Trocar o nome não produz um pixel diferente e quebraria dados já gerados. A
solução adotada separa **valor** de **nome**:

| Plano da Etapa 2 | Código | Tamanho | Papel |
|---|---|---|---|
| Tile | `SectorGrid.SECTOR_SIZE` | 512 m | unidade de carga, memória e colisão |
| Setor | `SectorGrid.DETAIL_CELL_SIZE` | 128 m | granularidade fina: distância, diagnóstico, camadas futuras |
| Microárea | `SectorGrid.MICRO_SIZE` | 100 m | organização de objetos |
| — | `SectorGrid.TILE_SIZE` | 2000 m | agrupamento de dados |

A célula de detalhe é **nova** e a grade dela é ancorada na origem métrica, como
a de setores: `512 / 128 = 4` exato, então um bloco contém 4×4 células de
detalhe sem faixa irregular em nenhuma borda. A microárea de 100 m continua com
grade própria, porque 512 não é múltiplo de 100 e realinhá-la criaria faixas de
largura irregular no meio de cada bloco.

O que a célula de detalhe faz **hoje**: é a unidade de granularidade fina
exposta por `SectorGrid` (16 células por bloco, com ida e volta testada), entra
no diagnóstico do HUD e na demonstração. O que ela **ainda não faz**: distribuir
vegetação e mobiliário por proximidade. Isso está documentado como próximo passo
em §8, não camuflado como concluído.

---

## 4. O que foi construído

### 4.1 Configuração espacial

`core/configuration/world_grid_config.gd` — dono único das dimensões. As
constantes de `SectorGrid` viraram `static var` com os mesmos valores padrão, e
`WorldGridConfig.apply_geometry()` é a porta de entrada para mudá-las, com
validação (positivas, detalhe menor que bloco, proporção inteira) e aviso quando
a grade já gerou chaves na sessão. Não há número solto de tamanho de célula em
nenhum outro arquivo.

### 4.2 LOD

- `world/lod/lod_profile.gd` — quatro níveis, divisões decrescentes, faixas
  crescentes, colisão só nos níveis próximos, profundidade de saia. Perfis
  malformados são corrigidos, não aceitos.
- `world/lod/sector_lod_controller.gd` — decide o nível de cada setor. Não toca
  em GPU nem em árvore de cena: **devolve coordenadas** e o streaming aplica com
  orçamento. Três regras: distância até a **borda** do bloco (não o centro),
  vizinhos nunca diferem por mais de um nível, e mudança só se aplica depois de
  se sustentar por `switch_delay` segundos.
- `TerrainMeshBuilder.build(..., skirt)` — saia vertical opcional. O LOD cria
  junções em T entre setores de resoluções diferentes; sem saia elas aparecem
  como frestas no horizonte. A saia é acrescentada **depois** da grade, então os
  primeiros `(divisões+1)²` vértices continuam sendo o terreno exato e o teste de
  costura da Etapa 1 segue válido.
- `SectorInstance.set_terrain_lod()` — reconstrói só a malha e a colisão do
  terreno. Vias, prédios, árvores e postes não são refeitos: sobre eles o nível
  só decide visibilidade (`apply_detail`), que é grátis.
- Colisão de trimesh só existe até `lod_collision_level`. É a estrutura mais cara
  do setor; mantê-la em 21 setores carregados seria pagar por colisão que ninguém
  alcança.

### 4.3 Streaming

| Peça | Arquivo | Papel |
|---|---|---|
| Fila com prioridade | `world/streaming/sector_request_queue.gd` | perto primeiro, inclinada na direção do movimento |
| Cache de payload | `world/streaming/sector_payload_cache.gd` | LRU por entradas e por bytes |
| Orçamento de memória | `world/streaming/sector_memory_budget.gd` | soma e escolha das vítimas |
| Política de retentativa | `world/streaming/load_retry_policy.gd` | espera crescente + quarentena |
| Controlador | `world/streaming/sector_streaming_manager.gd` | orquestra os quatro acima |

Cinco comportamentos novos no controlador:

1. **Antecipação**: acima de 4 m/s, a fila pesa a direção do movimento, e acima
   disso alguns blocos à frente do raio entram no conjunto desejado (no máximo
   cinco, e apenas à frente). O ganho cresce com a velocidade até 28 m/s: a pé é
   prioridade radial pura; de carro, prioridade à frente.
2. **Cache**: setor que sai guarda o payload. Voltar para trás não regera nem
   relê nada.
3. **Retentativa**: falha de carga agenda nova tentativa com espera linear
   (1×, 2×, 3× a base) e, acima do teto, quarentena de 60 s.
4. **Watchdog**: tarefa que não termina em 20 s é abandonada e contada como
   falha. Sem isso, uma tarefa travada segura uma das duas vagas de worker para
   sempre.
5. **Despejo por orçamento**: além do raio, um teto de setores e um teto de
   bytes. A vítima é sempre o setor mais distante, e nada a menos de 1,5 bloco do
   jogador é despejado — nem sob pressão.

### 4.4 Testes

Onze arquivos de teste novos, cerca de 70 métodos, cobrindo os onze itens da
seção "testes obrigatórios" do pedido:

| Exigido | Onde |
|---|---|
| Carregamento de tiles | `test_streaming_manager::test_loads_the_ring_around_the_viewer` |
| Descarregamento | `::test_far_move_unloads_the_old_ring` |
| Movimento entre setores | `test_streaming_soak::test_long_traversal_keeps_memory_bounded` |
| Movimento rápido entre tiles | `::test_fast_traversal_respects_budgets` |
| Transições de borda | `test_terrain::test_mesh_edges_are_watertight` + `::test_skirt_keeps_the_grid_intact` |
| Falha de carregamento | `::test_failed_load_is_retried_until_it_works` |
| Carregamento repetido | `::test_returning_to_the_same_area_hits_the_cache` |
| Cache | `test_payload_cache` (7 métodos) |
| Liberação de recursos | `::test_memory_accounting_follows_the_loaded_set`, `::test_rebuild_all_releases_everything` |
| Precisão das coordenadas | `test_floating_origin` (4 métodos) |
| Consumo de memória prolongado | `test_streaming_soak` |
| LOD | `test_lod_profile`, `test_sector_lod_controller`, `::test_lod_is_mixed_and_matches_controller` |
| Sem duplicação | `::test_no_duplicate_instances`, `test_request_queue::test_refill_deduplicates` |

O teste headless não tem laço de frame chamando `_process`; por isso o manager
expõe `tick_for_test(delta)`, que executa **o mesmo corpo** do `_process`. Não há
caminho de código paralelo só para teste.

---

## 5. Números escolhidos e o que eles custam

| | mobile (iPhone 12) | pc_medium | pc_high |
|---|---|---|---|
| Raio (blocos) | 2 | 3 | 4 |
| Divisões por nível | 17 / 13 / 9 / 5 | 33 / 21 / 13 / 7 | 65 / 33 / 17 / 9 |
| Faixas de LOD | 384 / 760 / 1250 m | 512 / 1100 / 1800 m | 640 / 1400 / 2300 m |
| Metros por quad no nível 0 | 30 | 15 | 8 |
| Teto de setores | 21 | 41 | 61 |
| Teto de memória | 42 MB | 96 MB | 180 MB |
| Cache de payload | 6 MB | 8 MB | 12 MB |
| Trocas de LOD por frame | 1 | 2 | 2 |

Relação que dá o ganho: diminuir divisões reduz triângulos com o **quadrado** do
número. Ir de 33 para 13 divisões é 6,4× menos geometria no mesmo bloco; o nível
3 do perfil médio é 22× menos que o nível 0.

**Nenhum destes números foi medido.** São calibragem inicial coerente com o
orçamento declarado na Etapa 1, não resultado de benchmark. O teto de memória é
estimativa a partir de `SectorInstance.memory_estimate_kb()`, que conta arrays de
malha e instâncias de MultiMesh — é uma unidade de comparação entre setores, não
leitura de alocador.

---

## 6. Critérios de aceitação

| # | Critério | Situação |
|---|---|---|
| 1 | Terreno gerado a partir de dados de entrada | **atendido** — `TerrainService` com SRTM `.hgt` e procedural determinístico |
| 2 | Tiles organizados espacialmente | **atendido** — grade pura, com célula de detalhe e testes de ida e volta |
| 3 | Jogador atravessa vários setores | **atendido** — streaming contínuo com histerese |
| 4 | Setores carregados e descarregados corretamente | **atendido** — coberto por teste |
| 5 | Sem duplicação de setores | **atendido** — três defesas: fila deduplicada, mapa `_loaded`, checagem de `_inflight` |
| 6 | Bordas sem rachaduras relevantes | **atendido no desenho** — altura amostrada no espaço métrico + saia. *A aparência final depende de rodar o jogo.* |
| 7 | LOD funciona | **atendido na política e na malha**, com teste de política; *o visual não foi observado* |
| 8 | Recursos liberados corretamente | **atendido na contabilidade**, com teste; *o consumo real de GPU não foi medido* |
| 9 | Testes reproduzíveis | **atendido** — 20 arquivos, headless, saída com código 1 em falha |
| 10 | Preparado para expansão geográfica | **atendido** — LCC estadual, floating origin, grades puras, sem número solto |

Onde escrevi "atendido na política" ou "no desenho", a ressalva é intencional: o
critério depende de execução real, que não aconteceu.

---

## 7. Como rodar

```bash
# suíte completa
godot --headless --path . --script res://tests/run_tests.gd

# a cena de demonstração, direto
godot --path . world/demo/streaming_demo.tscn
```

Na demonstração: `WASD` move, `Q`/`E` desce e sobe, `SHIFT` acelera, `F1` troca
o perfil de qualidade, `F2` liga o piloto automático (uma volta em círculo, que
é o melhor teste de streaming sob movimento), `R` volta ao início. O painel
mostra FPS, velocidade, bloco, célula de detalhe, distribuição de LOD, memória e
cache.

No jogo (`F5` a partir de `core/bootstrap/main.tscn`), o diagnóstico é o `F3`.

---

## 8. Limitações conhecidas, sem maquiagem

1. **O código não foi executado.** Nem antes, nem agora. A primeira execução pode
   revelar erros de sintaxe ou de API que nenhuma leitura pega.
2. **Sem oclusão.** O LOD corta por distância; parede entre o jogador e a cidade
   não economiza nada. Oclusão por software entra na etapa de renderização.
3. **LOD só no terreno.** Prédios, vias e vegetação têm uma resolução. Em nível
   distante eles continuam com a mesma malha; o que muda é visibilidade de
   árvores, postes e sombra.
4. **A célula de detalhe ainda não distribui objetos.** Existe, é testada e
   aparece no diagnóstico, mas vegetação e mobiliário continuam por bloco.
5. **Números de desempenho não medidos.** Nenhum FPS declarado. A meta de 30 FPS
   no iPhone 12 continua sendo meta.
6. **Sem água, sem oclusão de água, sem linha de costa** — herdado da Etapa 1.
7. **Troca de LOD reconstrói a malha na thread principal.** É orçamentada (1–2
   por frame) e limitada por microssegundos, mas não é assíncrona. Se o perfil
   alto engasgar, o caminho é baixar `lod_max_switches` antes de mexer no resto.
8. **Estimativa de memória, não medição.** `memory_estimate_kb()` conta os arrays
   que o motor guarda; não vê overhead de BVH de colisão nem de driver.
9. **Uma tarefa abandonada pelo watchdog pode deixar payload órfão.** Ele é
   purgado na próxima reavaliação do raio, não vaza para sempre.
10. **`StaticBody3D` de terreno é reconstruído a cada troca de nível que muda a
    colisão.** Duas trocas por segundo, no pior caso.

---

## 9. Arquivos tocados

Novos (21):

```
core/configuration/world_grid_config.gd
world/lod/lod_profile.gd
world/lod/sector_lod_controller.gd
world/streaming/sector_request_queue.gd
world/streaming/sector_payload_cache.gd
world/streaming/sector_memory_budget.gd
world/streaming/load_retry_policy.gd
world/demo/streaming_demo.gd
world/demo/streaming_demo.tscn
tests/unit/test_world_grid_config.gd
tests/unit/test_detail_grid.gd
tests/unit/test_lod_profile.gd
tests/unit/test_sector_lod_controller.gd
tests/unit/test_request_queue.gd
tests/unit/test_payload_cache.gd
tests/unit/test_memory_budget.gd
tests/unit/test_load_retry_policy.gd
tests/integration/test_floating_origin.gd
tests/integration/test_streaming_manager.gd
tests/integration/test_streaming_soak.gd
docs/ETAPA2.md
```

Modificados (11):

```
world/geography/sector_grid.gd          dimensões configuráveis + célula de detalhe
world/geography/municipality_index.gd   cache de densidade sob mutex
world/sectors/terrain_mesh_builder.gd   saia anti-rachadura opcional
world/sectors/sector_instance.gd        troca de LOD, visibilidade, memory_estimate_kb, release
world/streaming/sector_streaming_manager.gd  orquestração nova, API pública igual
rendering/quality/quality_profile.gd    números de LOD e memória, um caminho de aplicação
ui/hud/hud.gd                           LOD, memória, cache e antecipação no diagnóstico
tests/run_tests.gd                      registra os onze arquivos novos
README.md · CHANGELOG.md · docs/ARQUITETURA.md
```

Nada foi apagado. Nenhum sistema da Etapa 1 foi substituído.
