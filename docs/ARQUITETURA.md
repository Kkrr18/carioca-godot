# Arquitetura do CARIOCA

Este documento explica as decisões que sustentam o mundo e o porquê delas. Onde
o plano original previa uma tecnologia, há uma nota dizendo o que foi feito e
por quê.

---

## 1. Modelo de coordenadas

Três espaços, com regra de conversão única:

| Espaço | Tipo | Onde vive |
|---|---|---|
| Geográfico | latitude, longitude (graus) | dados de origem |
| Métrico global | `Vector2(easting, northing)`, metros | índices, setores, disco |
| Local 3D | `Vector3(x, altura, z)` | árvore de cena |

Convenção local: **x = leste, z = sul, -z = norte** (mantém a frente da câmera da
Godot como norte). `GeoCoordinateSystem` é a única porta de entrada para
converter; nada mais no projeto faz conta com latitude.

### Por que LCC e não UTM

O estado atravessa os fusos 23S e 24S. Dois fusos significam descontinuidade
métrica no meio do mapa e conversão de espaço sempre que o jogador cruza a
fronteira de zona. Foi adotada uma **cônica conforme de Lambert** sobre SIRGAS
2000 / GRS80, com paralelos padrão em -21° e -23,5° e meridiano central -42,5°.

- O fator de escala fica entre 0,9999 e 1,0001 em todo o estado — a projeção que
  os testes verificam (`scale_factor` = 1 exatamente nos paralelos padrão).
- É analiticamente invertível: ida e volta fecha em 1e-9 grau.
- A falsa origem (500 000, 8 000 000) mantém toda coordenada do estado positiva,
  o que simplifica índice de setor e leitura de arquivo.

Latitudes são espelhadas para o hemisfério norte durante o cálculo (a formulação
clássica supõe cone com ápice ao norte) e devolvidas com sinal negado.

### Floating origin

Com o jogador a mais de 2 km da origem, a precisão de `float` de 32 bits já
tremeria geometria. Ao cruzar esse limite, todo o conteúdo do mundo desliza 2 km
para trás e a origem métrica avança junto. Dois nós separados recebem o
deslocamento — `World` (setores) e `Actors` (jogador, veículos, NPCs) — e nada é
recalculado: uma subtração de posição em algumas dezenas de nós.

Detalhe importante: **nada que recompõe posição a partir do espaço métrico pode
ser deslocado manualmente**. Por isso o `SectorStreamingManager` não é filho da
raiz do mundo: ele apenas posiciona os setores, que são.

---

## 2. Hierarquia geográfica

| Nível | Tamanho | Papel |
|---|---|---|
| Tile regional | 2000 m | agrupamento e prioridade de dados |
| Bloco | 512 m | **unidade de carregamento, de memória e de colisão** |
| Célula de detalhe | 128 m | granularidade fina: distância de LOD, diagnóstico, camadas futuras |
| Microárea | 100 m | organização local de objetos |

O plano da Etapa 2 chama o bloco de 512 m de *tile* e pede um *setor* de 128 m. O
código mantém os nomes da Etapa 1 porque `SECTOR_SIZE = 512` está gravado nas
chaves de disco e na reticulação do gerador urbano; `WorldGridConfig` documenta a
correspondência e é a porta de entrada para mudar as dimensões.

Setores e microáreas têm grades independentes ancoradas na origem do espaço
métrico. 512 não é múltiplo de 100, então alinhar microáreas dentro do bloco
criaria faixas irregulares; a grade própria de 100 m resolve sem casos especiais.
A célula de detalhe, ao contrário, divide o bloco exatamente (4×4), e por isso
tem grade própria ancorada também na origem: as duas formas de calcular o índice
coincidem por construção.

O índice de um setor é uma função pura da posição:

```
gx = floor(easting / 512)      gy = floor(northing / 512)
```

Não existe registro central, nem estado. Dois sistemas independentes chegam
sempre à mesma chave — é o que permite o disco, o streaming e os testes
concordarem sem sincronização.

---

## 3. Pipeline de dados

```
OSM / SRTM / IBGE  →  ferramentas  →  data/geographic/sectors/**.json  →  runtime
                                        ↑
                          gerador procedural (fallback determinístico)
```

`SectorRepository.load_payload(coord)` devolve o arquivo do setor **se existir e
se a versão do schema bater**; caso contrário, gera na hora com o mesmo gerador
que a ferramenta de bake usa. Consequência prática: o jogo nunca fica sem mundo,
e cada arquivo importado substitui o procedimento naquele setor, sem tocar em
nenhum outro sistema.

### Schema do setor (versão 2)

```json
{
  "version": 2,
  "grid": [878, 15621],
  "origin": [449536.0, 7999232.0],
  "id": "RJ_METRO_GUAPI_0878_15621",
  "source": "procedural | osm",
  "density": 1.0,
  "urban": true,
  "roads":     [{"class": "local", "width": 6.0, "nodes": ["local:3:4", "local:4:4"],
                 "points": [[110.2, 240.7], [286.4, 233.1]]}],
  "buildings": [{"center": [.., ..], "size": [12.0, 10.5], "angle": 0.3,
                 "levels": 3, "height": 9.45, "kind": "residential",
                 "door": [.., ..]}],
  "water":     [], "trees": [[x, z, escala]], "props": [{"type": "light", "pos": [x, z]}]
}
```

Coordenadas de via e de prédio são **locais ao setor**, em metros: mantém os
números pequenos, o JSON curto e a precisão intacta.

---

## 4. Como a cidade é coerente entre setores

O ponto mais delicado da geração procedural em mundo dividido: dois setores não
podem discordar de onde uma rua passa.

A solução é uma **reticulação global**. Um nó de rua é posicionado por:

```
p = (i * spacing, j * spacing) + jitter(hash(i, j))
```

Nada na fórmula depende do setor. Cada setor guarda apenas os segmentos cujo
ponto médio cai dentro dele, e cada segmento carrega as chaves dos seus dois nós
(`local:12:34`). Consequência:

- duas vias de setores diferentes terminam no mesmo ponto, por construção;
- o grafo do trânsito conecta por chave de texto, não por coincidência de float;
- o teste `test_node_keys_match_global_positions` prova o invariante.

Três escalas de reticulação: arterial 2112 m, coletora 704 m, local 176 m. A
densidade urbana decide quais existem em cada lugar — rural tem só arterial,
núcleo urbano tem as três.

Altura dos prédios sai da densidade e de um sorteio determinístico; a fachada
muda de tom por andar. Nada disso usa `randf()`: tudo vem de hash dos índices, e
por isso o mundo é idêntico em qualquer sessão, em qualquer ordem de carga.

---

## 5. Terreno e costura

`TerrainService.height_at(metric)` é uma função pura da posição **métrica** —
nunca do setor. Duas fontes, na ordem:

1. SRTM real, se houver `.hgt` em `data/geographic/elevation/`;
2. procedural: fBm com máscara de relevo e aplainamento em área urbana.

A malha de cada setor amostra essa função numa grade de (divisões+3)² pontos,
com uma coroa de uma célula em volta para calcular normal nas bordas sem
diferenças finitas extras. Como a coluna 33 do setor A cai na mesma coordenada
métrica da coluna 0 do setor B, as alturas são idênticas: **não existe costura**.
O teste `test_mesh_edges_are_watertight` compara as duas bordas vértice a
vértice.

Resolução: 17 divisões no mobile (~30 m), 33 no PC médio (~15 m), 65 no alto
(~8 m).

### Saia e LOD

Com todos os blocos na mesma resolução, a malha fecha sem ajuda. Com LOD, dois
vizinhos podem ter resoluções diferentes e a borda compartilhada deixa de ter os
mesmos vértices: aparecem junções em T, que se veem como frestas no horizonte.

A solução é uma **saia vertical** em volta de cada malha, descendo alguns metros
abaixo da borda. Ela não corrige a geometria, apenas tapa o buraco — e como fica
sob a superfície, é invisível quando os vizinhos têm a mesma resolução. Custa
algumas centenas de triângulos por bloco.

A saia é acrescentada **depois** da grade, então os primeiros `(divisões+1)²`
vértices continuam sendo exatamente o terreno. É o que mantém válido o teste de
costura da Etapa 1 e permite comparar as duas bordas vértice a vértice.

Duas medidas reduzem a frequência com que a saia precisa trabalhar: nenhum par de
vizinhos difere por mais de um nível, e a mudança de nível tem histerese temporal
(ver §6.1).

---

## 6. Streaming

```
_process:
  célula mudou, ou a direção virou?  → recalcula o conjunto desejado
                                       (raio + até 5 blocos à frente)
  fila com prioridade                → perto primeiro, inclinada para frente
  cache                              → acerto entra pronto, sem passar por thread
  worker threads                     → lê/gera payload (até 2 por vez)
  orçamento por frame                → constrói até N blocos e para no limite de µs
  LOD                                → reavalia níveis e troca malha no orçamento
  fora do raio + histerese           → descarrega até 2 por frame
  teto de memória                    → despeja o mais distante, se estourou
```

A partir da Etapa 2 o manager é orquestração, não implementação. Cada
responsabilidade tem dono:

| Peça | Arquivo | Decide |
|---|---|---|
| Fila | `sector_request_queue.gd` | ordem de carga |
| Cache | `sector_payload_cache.gd` | o que sobrevive fora do raio |
| Orçamento | `sector_memory_budget.gd` | quem sai quando estoura |
| Retentativa | `load_retry_policy.gd` | quando tentar de novo e quando desistir |
| LOD | `sector_lod_controller.gd` | resolução de cada bloco |
| Controlador | `sector_streaming_manager.gd` | quando cada um dos acima age |

Cinco decisões:

- **Dados fora da thread principal**: leitura de arquivo e geração procedural são
  puras e rodam em `WorkerThreadPool`. A thread principal recebe um `Dictionary`
  pronto, sob `Mutex`.
- **Construção com orçamento**: criar malha, colisão de trimesh e MultiMesh custa
  caro; o limite em microssegundos evita o travamento clássico de "andar rápido e
  o mundo engasgar".
- **Prioridade direcional**: a fila usa
  `score = distância × (1 − alinhamento × ganho)`, com `alinhamento` em [-1, 1]
  contra a direção do movimento e `ganho` crescendo com a velocidade até 28 m/s.
  A pé a fila é radial pura; de carro ela se inclina para frente. Além da
  reordenação, até cinco blocos à frente do raio entram no conjunto desejado —
  o teto existe para a antecipação não virar um segundo raio de carga.
- **Histerese de 1,6 bloco** ao descarregar: evita o carrega/descarrega em
  vaivém quando o jogador anda na fronteira.
- **Memória com teto próprio**: o raio limita quantidade, não bytes. Um bloco
  urbano denso custa várias vezes um rural, e o problema em celular é o pico. O
  despejo escolhe o mais distante e **nunca** toca no que está a menos de 1,5
  bloco do jogador.

### Cache, retentativa e watchdog

- **Cache LRU** de payloads, limitado por entradas e por bytes estimados. Setor
  que sai guarda o payload; voltar para trás não relê nem regera. O cache só é
  tocado pela thread principal — payload gerado em worker entra nele depois de
  recolhido, então não há estrutura compartilhada nova.
- **Retentativa** com espera linear (1×, 2×, 3× a base) e quarentena de 60 s
  acima do teto. Um JSON corrompido não pode gerar uma tentativa por frame.
- **Watchdog**: tarefa que não termina em 20 s é abandonada e contada como falha.
  Sem ele, uma tarefa travada segura uma das duas vagas de worker para sempre e o
  mundo para de carregar em volta do jogador.

Raio por perfil: 2 blocos (mobile), 3 (PC médio), 4 (PC alto).

### 6.1 LOD

Quatro níveis, faixas crescentes, decididos pela distância até a **borda** do
bloco — não até o centro. Um bloco cujo centro está a 700 m pode começar a 450 m
do jogador; usar o centro o colocaria num nível grosseiro e ele "cresceria" na
frente da câmera.

Três regras, nesta ordem:

1. Distância → nível, pelo perfil.
2. **Restrição de vizinhança**: nenhum par adjacente difere por mais de um nível.
   Sem isso a saia da malha vira a única coisa segurando a imagem.
3. **Histerese temporal**: a mudança precisa se sustentar por `switch_delay`
   segundos. Parado na fronteira de faixa, o bloco não troca de nível a cada
   frame.

O controlador não toca em GPU nem em árvore de cena: devolve coordenadas, e o
streaming aplica no orçamento do frame (1 troca no mobile, 2 no PC). Por isso a
política tem teste headless — o que não seria possível se ela mesma
reconstruísse malha.

O que a troca de nível refaz: malha do terreno e colisão de trimesh. O que não
refaz: vias, prédios, árvores e postes. Sobre esses, o nível só mexe em
visibilidade — postes e sombra somem no nível 2, árvores no nível 3.

Colisão de trimesh é a estrutura mais cara do bloco (BVH sobre todos os
triângulos). Ela existe só até `lod_collision_level`; manter colisão precisa em
21 blocos carregados seria pagar por algo que ninguém alcança.

---

## 7. Gameplay e IA

- **Jogador**: `CharacterBody3D` com leitura de entrada unificada
  (`read_move_input()`), usada tanto a pé quanto dirigindo. Um lugar só para
  decidir o que "acelerar" significa em teclado e em toque.
- **Câmera**: terceira pessoa com raio único de colisão, sem SpringArm — menos
  ambiguidade de eixo e distância independente da rotação do personagem.
- **Veículo**: `VehicleBody3D` nativo (suspensão, atrito, tração no servidor de
  física). Física seletiva: sem motorista, o carro só freia.
- **Trânsito**: cada agente percorre uma aresta, desvia para a direita, freia para
  carro à frente e para no semáforo. Ao chegar ao nó, escolhe uma aresta de saída.
  Sem pathfinding por agente, custo linear no número de agentes.
- **Semáforo**: fase determinística por nó (`hash(nó) + tempo`), sem estado
  servidor por cruzamento.
- **Pedestres**: mesmo grafo, deslocamento lateral de calçada e pausas ocasionais.
- Todos os agentes são removidos ao sair do raio carregado — NPC distante não
  executa comportamento.

---

## 8. Mundo vivo

- **Dia/noite**: sol em arco leste-oeste, base montada com `Basis.looking_at` (sem
  ambiguidade de Euler). Céu, luz ambiente, sombra e cor do sol variam juntos.
- **Clima**: limpo / chuva / neblina. A chuva muda densidade de neblina,
  **aderência dos pneus** (`wetness` → `wheel_friction_slip`) e ruído ambiente.
- **Iluminação pública**: material emissivo compartilhado, aceso ao anoitecer.
  Sem luz pontual por poste: o orçamento de luzes por cluster do mobile não
  sustenta centenas de OmniLight.
- **Áudio**: sintetizado em tempo real (ruído filtrado por modo: rua, chuva,
  interior). Sem arquivo de áudio no repositório e com barramento já separado
  para trilha entrar depois.
- **Interiores**: o apartamento fica 500 m abaixo do mundo. Entrar é um teleporte
  com três sistemas pausados (streaming, trânsito, pedestres). Sair devolve o
  jogador à porta exata.

---

## 9. Persistência

Envelope com versão, checksum e payload como texto:

```json
{ "version": 1, "checksum": "sha256 do payload", "payload": "{...}" }
```

- O checksum é sobre os **bytes** do payload, não sobre o dicionário
  re-serializado — elimina dependência de ordem de chave.
- Gravação atômica: `.tmp` + `flush` + `rename`. Queda de energia no meio deixa o
  save anterior intacto.
- Migração explícita por versão; save de versão futura é recusado.

---

## 10. Orçamento de desempenho

| Recurso | Mobile (iPhone 12) | PC médio | PC alto |
|---|---|---|---|
| Raio de bloco | 2 | 3 | 4 |
| Divisões do terreno por nível | 17/13/9/5 | 33/21/13/7 | 65/33/17/9 |
| Faixas de LOD | 384/760/1250 m | 512/1100/1800 m | 640/1400/2300 m |
| Metros por quad (nível 0) | 30 | 15 | 8 |
| Teto de blocos carregados | 21 | 41 | 61 |
| Teto de memória estimada | 42 MB | 96 MB | 180 MB |
| Cache de payload | 6 MB | 8 MB | 12 MB |
| Carros de trânsito | 6 | 12 | 20 |
| Pedestres | 8 | 20 | 36 |
| Sombra direcional | 1024 | 2048 | 4096 |
| MSAA | desligado | 2x | 4x |
| Teto de FPS | 30 | 60 | livre |

**Nenhum destes números foi medido.** São calibragem inicial coerente com o
orçamento, não resultado de benchmark.

Cada bloco é 1 draw call de terreno, 1 de vias, 1 de prédios, 2 de MultiMesh
(vegetação e mobiliário). O custo cresce com blocos carregados, não com o número
de objetos.

Diminuir divisões reduz triângulos com o quadrado do número: ir de 33 para 13 é
6,4× menos geometria no mesmo bloco. Somado a isso, o nível distante não paga
colisão nem sombra.

---

## 11. Camada urbana (Etapa 3)

A cidade é uma **camada sobre o payload de setor**, não um sistema paralelo. A
cadeia é curta e cada elo é substituível:

```
fonte de rua  ->  RoadNetwork  ->  quadras  ->  lotes  ->  edificações
                                 ->  mobiliário  ->  vegetação
                                          |
                                    UrbanGenerator  ->  payload do setor
                                          |
                      SectorInstance -> malha, colisão, MultiMesh
```

### Fontes de rua, com prioridade declarada

| Prioridade | Fonte | Procedência | Licença |
|---|---|---|---|
| 1 | payload de setor com `source: osm` | `import_osm.gd` sobre extrato `.osm` | ODbL 1.0 |
| 2 | `data/geographic/urban/` | traçado esquemático autoral | CC0-1.0 |
| 3 | reticulação procedural | obra do projeto | CC0-1.0 |

A fonte usada é gravada em `payload.urban_source` e em `payload.provenance`,
junto com a licença e uma nota dizendo o que o dado é. **Nenhum sistema afirma
fidelidade que não tem**: o traçado esquemático é declarado estimativa em todos
os lugares em que aparece.

### O que a geometria garante

| Propriedade | Como |
|---|---|
| Rua atravessada não vira quadra | cruzamentos são nós; segmentos são cortados neles |
| Quadra segue a forma da rua | face do grafo plano, recuada por aresta |
| Lote não invade a rua | recuo de metade da pista + calçada antes de qualquer lote |
| Dois lotes não se sobrepõem | cada lote é uma fatia disjunta de um recorte por meia-reta |
| Prédio não sai do lote | pegada é recorte do lote recuado; não cabendo, encolhe; não cabendo ainda, o lote fica vazio |
| Quadra não aparece duas vezes | pertence ao setor que contém o centroide |
| Identificador sobrevive a save e bake | `sector_id/B%03d`, `sector_id/L%02d`, `sector_id/Q%03d` |

### Relevo

A geração de payload **não** consulta o terreno: ela roda nas threads de trabalho
do streaming e não pode disputar o cache do SRTM com outra thread. O terreno
entra na construção da malha, onde a edificação apoia no canto mais baixo da
pegada e o vão até o mais alto é preenchido por um embasamento. O inspetor
(`tools/urban_tools`) mede a inclinação por edificação e lista o que passou de
22° como aviso.

### Orçamento visual

| Camada | Mobile | PC médio | PC alto |
|---|---|---|---|
| Detalhe de fachada | janela + porta | completo | completo |
| Teto de edificações por setor | 44 | 96 | 160 |
| Escala de lote | 1,25 | 1,0 | 0,92 |
| Teto de vegetação | 90 | 220 | 320 |
| Teto de mobiliário | 70 | 180 | 260 |

Cada setor urbano produz 2 malhas (edificações e pavimento) mais um MultiMesh por
espécie de vegetação e por tipo de mobiliário: cerca de 10 draw calls, contra 5
da Etapa 2. **Nenhum destes números foi medido** — são calibragem inicial.

### O que foi deliberadamente recusado

- **Renomear `SECTOR_SIZE`** — mesma razão da Etapa 2: a chave está no disco.
- **Deslocamento de aresta para recuo** — se auto-intersecta em polígono côncavo.
- **Furar parede para janela** — custo em tempo de carga sem ganho a 30 FPS.
- **Colisão por trimesh de fachada** — o passo de física não paga.
- **Chamar o terreno na geração de payload** — concorrência com o cache de SRTM.

---

## 12. Decisões que divergem do plano original

| Plano | Implementado | Por quê |
|---|---|---|
| UTM com zonas | LCC estadual | sem descontinuidade entre fusos 23S e 24S |
| Streaming "assíncrono" genérico | payload em threads + construção orçada | o gargalo real é a construção de malha, não o I/O |
| Id de setor `RJ_METRO_GUAPI_000124` | `RJ_METRO_GUAPI_0878_15621` | os índices de grade são deriváveis e verificáveis; o sequencial exigiria registro central |
| Áudio com assets | síntese em tempo real | projeto abre e roda sem baixar nada; barramento pronto para trilha |
| Luz por poste | emissivo compartilhado | orçamento de luzes do renderer mobile |
| Mapa com malha municipal do IBGE | centros aproximados + densidade | a malha oficial entra na importação; nenhum sistema consulta coordenada por conta própria, então a troca é local |

---

## 13. Próximos passos técnicos

1. Rodar a suíte e corrigir o que aparecer (é a primeira execução real).
2. Importar um extrato `.osm` real de Guapimirim e comparar quadra a quadra com o
   traçado esquemático — é o divisor entre cidade "plausível" e cidade "daquele
   lugar".
3. Malha e colisão de água + linha de costa (Angra, Niterói, lagoa), e malha de
   ferrovia para o eixo já declarado como barreira.
4. Oclusão por software — o LOD já corta por distância; falta cortar por
   visibilidade.
5. Camadas de detalhe por célula de 128 m: vegetação e mobiliário só onde o
   jogador vê, em vez de por bloco inteiro.
6. Malha de prédio em dois níveis de detalhe (caixa no nível 3, fachada no 0–1).
7. Malha municipal do IBGE substituindo os centros aproximados.
8. Interior ligado à porta de cada edificação gerada.
9. Benchmark automatizado de sessão longa (memória real, quedas de frame, tempo
   de troca de LOD e de construção de setor urbano) gravando relatório — os
   números do §10 e do §11 são estimativa até isso existir.
