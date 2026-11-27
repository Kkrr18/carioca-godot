# CARIOCA

Mundo aberto do Estado do Rio de Janeiro — Godot 4.4, GDScript, coordenadas
geográficas reais, streaming contínuo e escala 1:1 como objetivo.

**Versão atual: 0.5.0 — Veículos.** Não é um jogo terminado: é a base técnica
que sustenta o estado inteiro, com um protótipo jogável em Guapimirim e Magé em
cima dela. A Etapa 2 acrescentou LOD por distância, prioridade de carga na
direção do movimento, cache de payload, orçamento de memória e retentativa de
carga. A Etapa 3 acrescentou a cidade: quadras extraídas da geometria das ruas,
lotes, sete tipologias de edificação com fachada por pavimento, calçada,
mobiliário, vegetação e pontos de referência. A Etapa 4 acrescentou o
personagem: motor de movimento com caminhada, corrida e sprint, *coyote time*,
*buffer* de pulo, rampa, estados explícitos, câmera com zoom e suavização por
eixo, controles de PC e toque com ação nomeada e remapeamento, e interação
extensível por provedores. A Etapa 5 acrescentou os veículos: dirigir com
aceleração progressiva, freio, ré, freio de mão, esterço por velocidade,
buzina, câmera veicular com duas distâncias, entrada pelo lado livre e controles
de PC e toque. Os relatórios estão em [docs/ETAPA2.md](docs/ETAPA2.md),
[docs/ETAPA3.md](docs/ETAPA3.md), [docs/ETAPA4.md](docs/ETAPA4.md) e
[docs/ETAPA5.md](docs/ETAPA5.md).

---

## Rodar

Requisitos: Godot **4.4** (renderer Mobile). Nenhuma dependência externa, nenhum
addon, nenhum asset para baixar.

1. Abra o Godot 4.4 → *Import* → selecione `project.godot`.
2. F5.

O mundo começa em Guapimirim. O resto nasce em volta do jogador conforme ele
anda: cada bloco de 512 m é gerado de forma determinística e carregado em
segundo plano. A resolução do terreno cai com a distância (LOD 0–3, com saia
anti-rachadura nas bordas) e o que está à frente do movimento começa a carregar
antes, que é o que evita dirigir para dentro de mundo vazio.

### Personagem

```bash
godot --path . gameplay/demo/player_demo.tscn
```

Cena do personagem em Guapimirim: o mesmo `Player`, a mesma câmera, o mesmo
streaming e a mesma cidade do jogo. `F5` mostra os controles de toque no PC, para
conferir o layout mobile sem aparelho na mão. Dois carros nascem ao lado do ponto
de partida para o teste de interação.

### Dirigir

```bash
godot --path . gameplay/demo/vehicle_demo.tscn
```

Cena da Etapa 5: o mesmo mundo urbano, com dois carros na rua ao lado do
nascimento. Aproxime-se, aperte `E`, e dirija pelas vias do Centro — `W`
acelera, `S` freia e, parado, dá ré, `ESPAÇO` é freio de mão, `H` buzina e `V`
alterna a câmera próxima e distante.

### Só terreno e streaming

```bash
godot --path . world/demo/streaming_demo.tscn
```

Cena independente do jogo, com câmera livre e painel de diagnóstico. `F2` liga o
piloto automático — uma volta em círculo, que é o melhor teste de streaming em
movimento. É a forma mais rápida de ver o LOD e o despejo de setores funcionando.

### Cidade de Guapimirim

```bash
godot --path . city/demo/guapimirim_center_demo.tscn
```

Cena independente do jogo: terreno, streaming e a camada urbana da Etapa 3 em
volta do Centro de Guapimirim. `F3` desenha as quadras e os lotes do próprio
payload carregado sobre a cidade; `F4` regenera os setores em volta sem sair da
cena; `F2` liga o piloto automático, que atravessa quadra residencial, eixo
arterial e área de referência.

**As ruas do centro são um traçado esquemático**, não um extrato do
OpenStreetMap — está declarado no `provenance` do payload, em
`data/geographic/urban/` e em [docs/ETAPA3.md](docs/ETAPA3.md) §3. Importar um
`.osm` real substitui o traçado setor por setor.

### Controles

| Ação | Teclado | Toque |
|---|---|---|
| Mover | WASD / setas | analógico virtual (metade esquerda, amplitude = andar/correr) |
| Caminhar | CTRL | — |
| Correr / sprint | SHIFT | botão **correr** (alterna) |
| Pular | ESPAÇO | botão **pular** ou toque curto na área de olhar |
| Olhar | mouse | arrastar na metade direita |
| Zoom da câmera | roda do mouse / + e − | pinça de dois dedos |
| Recentralizar câmera | C | — |
| Interagir (carro, porta) | E | botão **interagir**, só quando há algo ao alcance |
| Diagnóstico | F3 | — |
| Salvar / carregar | F5 / F9 | — |
| Trocar clima | F6 | — |
| Avançar 2 h | F7 | — |
| Trocar perfil gráfico | F1 | — |
| Voltar ao início | R | — |
| Tela cheia | F11 | — |
| **No carro** | | |
| Acelerar | W | botão **acelerar** |
| Frear / dar ré | S | botão **freio/ré** (parado segurando, engata a ré) |
| Direção | A / D | analógico da metade esquerda |
| Freio de mão | ESPAÇO | botão **mão** |
| Buzina | H | botão **buzina** |
| Câmera próxima/distante | V | botão **câmera** |
| Entrar / sair | E | botão **dirigir / sair** |

As teclas são **ações nomeadas** (`ui/input/input_bindings.gd`) e podem ser
remapeadas; o remapeamento é salvo em `user://settings.cfg`. A leitura é
resiliente: sem ação registrada, a tecla padrão continua valendo.

## Testes

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

Sai com código 1 se algo falhar, o que o torna pronto para integração contínua
(há um workflow em `.github/workflows/tests.yml`).

A suíte cobre o que quebra primeiro em mundo aberto geográfico: ida e volta da
projeção, escala do mapa, chaves de bloco e de célula de detalhe, **costura da
malha entre blocos vizinhos** (inclusive com saia de LOD), determinismo do
gerador, correspondência entre chave de nó e posição global da via, grafo de
ruas, integridade de save, e — na Etapa 2 — política de LOD, fila com prioridade
de direção, cache, orçamento de memória, retentativa de carga, invariante do
floating origin, carga e descarga de anel, ausência de duplicata e sessão longa
com memória sob teto.

Na Etapa 3 entram: área e recorte de polígono, triangulação de lote irregular,
cruzamento de via virando nó, quadra com rua diagonal, **lote que não se
sobrepõe**, lote de frente para a rua, edificação dentro do lote, ausência de
construção sobre a pista, variedade de tipologia, vegetação e mobiliário fora do
asfalto, ponto de referência com confiança declarada, determinismo do payload
urbano, contrato da Etapa 1 preservado, e a cidade sob o streaming carregando,
descarregando e voltando idêntica.

Na Etapa 4 entram: aceleração até a velocidade alvo, caminhada e sprint distintos,
amplitude do analógico, desaceleração, gravidade e velocidade terminal, pulo só no
chão, *coyote time* e o seu fim, *buffer* de pulo, aterrissagem medida, rampa
rendendo menos, corpo congelado, fatiamento do passo, independência de taxa de
quadros, estados por velocidade, prioridade da aterrissagem, veículo e desligado
por cima de tudo, pose de animação, boneco com quatro juntas, interação por
prioridade, provedor quebrado não derrubando os outros, ações nomeadas e
remapeamento, limites de zoom e inclinação da câmera, **`yaw` como propriedade**,
e o personagem no mundo: nascer, pousar, andar nas quatro direções, pular e
voltar, **atravessar fronteira de setor** e **sobreviver ao rebase do floating
origin**.

## Ferramentas

```bash
# grava o mundo procedural de um recorte em JSON (inspeção ou build)
godot --headless --path . --script res://tools/sector_generator/bake_sectors.gd -- \
    --center=GUAPI --radius=2

# importa ruas e prédios reais do OpenStreetMap
godot --headless --path . --script res://tools/map_importer/import_osm.gd -- \
    --input=data/geographic/osm/guapimirim.osm --bbox=-22.75,-43.15,-22.45,-42.85

# valida todos os setores gravados
godot --headless --path . --script res://tools/validation/validate_sectors.gd

# relatório dos modelos de elevação presentes
godot --headless --path . --script res://tools/validation/elevation_report.gd

# quadras, lotes, prédios: duplicata, sobreposição com rua, prédio fora do lote
godot --headless --path . --script res://tools/urban_tools/urban_inspector.gd -- \
    --center=GUAPI --radius=1

# regenera setores específicos (--bake grava o resultado em data/geographic/sectors)
godot --headless --path . --script res://tools/urban_tools/regenerate_sector.gd -- \
    --center=GUAPI --radius=1
```

### Dados reais

- **Ruas e prédios:** extrato `.osm` de Guapimirim/Magé (Geofabrik ou Overpass).
  Vai em `data/geographic/osm/`. Setor importado tem prioridade sobre o
  procedural e sobre o traçado esquemático.
- **Relevo:** tiles SRTM `.hgt` em `data/geographic/elevation/`. Nome no padrão
  `S23W043.hgt` (SRTM1 de 3601² ou SRTM3 de 1201², detectado pelo tamanho).
  Sem nenhum arquivo, o relevo é procedural e o jogo avisa no HUD.
- **Traçado esquemático:** `data/geographic/urban/guapimirim_centro.json` — ruas
  em metros ancoradas no centro municipal, **desenho do projeto, não
  levantamento**. Ver [data/geographic/urban/ATTRIBUTION.md](data/geographic/urban/ATTRIBUTION.md).
- **Pontos de referência:** `data/geographic/landmarks/` — cada entrada declara
  `confidence`, `sources` e o que o dado **não** é.

Os arquivos são lidos em pedaços: o `.hgt` inteiro nunca vai para a memória
(leitura por linha, com cache), e o `.osm` é filtrado pela caixa delimitadora.
Nada é baixado em tempo de execução.

## O que está implementado

| Item do plano | Estado |
|---|---|
| Núcleo (eventos, configuração, plataforma) | pronto, sem autoload |
| Projeção geográfica estadual | pronta (LCC SIRGAS 2000, erro < 0,02%) |
| Hierarquia bloco / célula de detalhe / microárea | pronta (512 m / 128 m / 100 m, configurável) |
| Streaming assíncrono com orçamento | pronto (WorkerThreadPool + orçamento por frame) |
| LOD 0–3 do terreno | pronto (4 níveis, saia anti-rachadura, restrição de vizinhança) |
| Prioridade na direção do movimento | pronta (fila + antecipação limitada à frente) |
| Cache de payload e orçamento de memória | prontos (LRU + teto por setor e por byte) |
| Retentativa e watchdog de carga | prontos (espera crescente, quarentena, abandono) |
| Floating origin | pronto (rebase a cada 2 km, XZ) |
| Terreno procedural determinístico | pronto |
| Terreno por SRTM real | pronto (quando houver `.hgt`) |
| Ruas: gerador por reticulação | pronto |
| Ruas: importação OSM | pronta (ferramenta + leitura pelo runtime) |
| Ruas: traçado esquemático ancorado | pronto (Centro de Guapimirim, declarado como estimativa) |
| Quadras: extração de face do grafo de ruas | pronta (aceita rua diagonal e quadra triangular) |
| Lotes: testada, fundo e esquina | prontos (guilhotina, sem sobreposição por construção) |
| Edificações: 7 tipologias por lote | prontas (casa térrea, dois pavimentos, garagem, varanda, edifício, comercial, mista) |
| Fachada modular | pronta (janela, porta, garagem, sacada, varanda, vitrine, toldo, escada) |
| Coberturas | prontas (duas águas, quatro águas, uma água, laje com platibanda) |
| Muro, portão e calçada | prontos (malha + colisão de muro) |
| Mobiliário urbano | pronto (poste, semáforo, placa, lixeira, banco, abrigo, caixa, faixa) |
| Vegetação urbana | pronta (calçada, quintal, lote vazio, praça; MultiMesh por espécie) |
| Pontos de referência | prontos (dado-driven, com confiança e licença declaradas) |
| Relevo: apoio e embasamento | pronto (prédio apoia no canto mais baixo, vão preenchido) |
| Prédios procedurais com fachada por andar | pronto (mantido como caminho sem dado urbano) |
| Vegetação e mobiliário (MultiMesh) | pronto |
| Motor de movimento do personagem | pronto (caminhada, corrida, sprint, rampa, coyote, buffer) |
| Estados do personagem | prontos (10 estados explícitos, resolvidos por prioridade) |
| Câmera em terceira pessoa | pronta (suavização por eixo, zoom, colisão, inversão) |
| Animação | procedural funcional; árvore importada com gancho pronto (sem asset) |
| Controles de PC e toque | prontos (ação nomeada, remapeamento, botões, pinça) |
| Interação com o mundo | pronta (provedores: veículo, porta, grupo `interactable`) |
| Terceira pessoa + câmera com colisão | pronto |
| Veículos dirigíveis | pronto (Etapa 5: DriveModel, ré, freio de mão, esterço por velocidade, saída pelo lado livre, buzina, câmera veicular) |
| Trânsito com faixa, freio e semáforo | pronto (agentes próprios, ainda não dirigíveis) |
| Pedestres em calçada | pronto |
| Ciclo dia/noite | pronto |
| Clima com efeito físico | pronto (chuva reduz aderência) |
| Interiores modulares | pronto (apartamento completo) |
| Ambiência sonora | sintetizada em tempo real (sem arquivos de áudio) |
| Save versionado com checksum | pronto |
| Perfis de qualidade | prontos (mobile, pc_medium, pc_high) |
| HUD de diagnóstico e minimapa | prontos |
| Testes headless | prontos |

## Limites conhecidos e honestos

- **Este código roda em CI** (Godot 4.4 headless, suíte em
  `.github/workflows/tests.yml`; o build web publica em
  https://kkrr18.github.io/carioca-godot/). A primeira execução real, na
  Etapa 4, revelou e corrigiu erros de parse; a suíte é a rede, não a prova
  de jogabilidade — a dirigibilidade da Etapa 5 ainda não foi julada por uma
  pessoa.
- **Água e oceano** ainda não são renderizados: `water` existe no payload, mas
  não há malha nem colisão de água. Entra com a importação da linha de costa.
- **Sem oclusão**: o LOD corta por distância; uma parede entre o jogador e a
  cidade não economiza nada. Oclusão entra na etapa de renderização.
- **LOD só no terreno e no mobiliário.** A malha de prédio tem uma resolução só;
  nos níveis distantes mudam a visibilidade de mobiliário, vegetação e sombra.
  Prédio com dois níveis de detalhe é o próximo passo natural.
- **A célula de detalhe de 128 m ainda não distribui objetos** — vegetação e
  mobiliário continuam por bloco. A grade existe, é testada e aparece no
  diagnóstico, mas não foi ligada a conteúdo.
- **As ruas do Centro de Guapimirim são um traçado esquemático**, não um extrato
  do OpenStreetMap: nenhum `.osm` acompanha o repositório. A fidelidade
  geográfica existe na projeção, no relevo e no centro municipal, não no traçado
  viário até que um extrato real seja importado.
- **Nenhuma edificação real foi reproduzida.** Ponto de referência gera massa
  genérica marcada com `confidence` no payload.
- **Sem malha de rio nem de ferrovia.** As barreiras reservam a faixa (não se
  constrói ali) e bloqueiam vegetação, mas o que se vê é o terreno.
- **Calçada não tem colisão própria**: é superfície visual sobre a colisão do
  terreno. Portão de muro não abre.
- **Não há modelo humano com animações licenciadas.** O boneco é provisório, com
  doze nós e quatro juntas, e a pose é procedural. A camada de animação importada
  existe (`CharacterAnimator.bind_tree`) e não está ligada a nenhum asset. Não há
  IK, pé fixo no chão nem *motion matching*; em rampa a pose não se ajusta ao
  plano.
- **Sem ragdoll, escalada ou natação.** Caminhar (`CTRL`/botão) reduz a
  velocidade; não muda a altura da cápsula.
- **Veículos (Etapa 5)**: sem câmbio simulado, sem diferencial e sem dano;
  a transferência de peso é a do `VehicleBody3D` nativo. A dirigibilidade
  não foi ajustada por playtest e nenhum FPS foi medido com o carro em
  movimento. **O som do carro é placeholder sintetizado** (tom de motor com
  pitch por carga e buzina gerada em buffer); não há som de derrapagem nem
  de colisão. Retrovisores não refletem e faróis não reagem ao dia/noite.
  Carros de trânsito com IA ainda não são dirigíveis.
- **O boneco não tem colisão própria**: a cápsula de 35 cm é que colide.
- **Remapeamento só de teclado**, não de controle (gamepad).
- **Nenhum FPS foi medido.** Os números dos perfis são calibragem inicial, não
  resultado de benchmark; a meta de 30 FPS no iPhone 12 continua sendo meta.
- **Colisão de prédio é caixa**, não a geometria da fachada.
- **Iluminação pública** é emissiva compartilhada, sem luz pontual por poste —
  decisão de orçamento para o iPhone 12.
- **Minimapa é 2D**, desenhado a partir do payload, não uma câmera renderizada.
- **Sem menu**: o jogo entra direto no mundo; save e perfil estão em teclas.
- Os `.fbx` na raiz do repositório não são usados por nada aqui. Os quatro
  `character_*.fbx` são da Etapa 1; `The_Corporate_High-Flier*.fbx` e
  `fps-buildings-env-kit-main.zip` apareceram no repositório durante a Etapa 4 e
  não são referenciados por código nenhum.

## Estrutura

```
core/         bootstrap, eventos, configuração, plataforma, utilitários
world/        geografia, projeção, elevação, terreno, setores, streaming, LOD, demo
city/         geração: reticulação procedural (E1) e camada urbana (E3) + demo
gameplay/     jogador, movimento, animação, câmera, interação, veículos, demo
ai/           grafo de vias, trânsito, pedestres
interiors/    construtor do apartamento e gerência de interiores
systems/      dia/noite, clima, áudio, persistência
rendering/    materiais, malhas primitivas, perfis de qualidade
ui/           HUD, minimapa, controles de toque, ações de entrada
data/         municípios, traçado urbano, pontos de referência, setores, OSM, elevação
tools/        importador OSM, bake de setores, validação, ferramentas urbanas
tests/        suíte headless
```

Detalhes de arquitetura, decisões e orçamentos: [docs/ARQUITETURA.md](docs/ARQUITETURA.md).
