# CARIOCA

Mundo aberto do Estado do Rio de Janeiro — Godot 4.4, GDScript, coordenadas
geográficas reais, streaming contínuo e escala 1:1 como objetivo.

**Versão atual: 0.3.0 — Geração urbana.** Não é um jogo terminado: é a base
técnica que sustenta o estado inteiro, com um protótipo jogável em Guapimirim e
Magé em cima dela. A Etapa 2 acrescentou LOD por distância, prioridade de carga
na direção do movimento, cache de payload, orçamento de memória e retentativa de
carga. A Etapa 3 acrescentou a cidade: quadras extraídas da geometria das ruas,
lotes, sete tipologias de edificação com fachada por pavimento, calçada,
mobiliário, vegetação e pontos de referência. Os relatórios estão em
[docs/ETAPA2.md](docs/ETAPA2.md) e [docs/ETAPA3.md](docs/ETAPA3.md).

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
| Mover | WASD / setas | analógico virtual (metade esquerda) |
| Correr | SHIFT | — |
| Pular | ESPAÇO | toque curto na metade direita |
| Olhar | mouse | arrastar na metade direita |
| Interagir (carro, porta) | E | — |
| Diagnóstico | F3 | — |
| Salvar / carregar | F5 / F9 | — |
| Trocar clima | F6 | — |
| Avançar 2 h | F7 | — |
| Trocar perfil gráfico | F1 | — |
| Voltar ao início | R | — |
| Tela cheia | F11 | — |

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
| Terceira pessoa + câmera com colisão | pronto |
| Veículos dirigíveis | pronto (VehicleBody3D) |
| Trânsito com faixa, freio e semáforo | pronto |
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

- **Este código não foi executado.** O ambiente onde ele foi escrito não tem
  Godot. A suíte de testes existe justamente para que a primeira execução real
  seja barata — rode-a antes de qualquer outra coisa.
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
- **Nenhum FPS foi medido.** Os números dos perfis são calibragem inicial, não
  resultado de benchmark; a meta de 30 FPS no iPhone 12 continua sendo meta.
- **Colisão de prédio é caixa**, não a geometria da fachada.
- **Iluminação pública** é emissiva compartilhada, sem luz pontual por poste —
  decisão de orçamento para o iPhone 12.
- **Minimapa é 2D**, desenhado a partir do payload, não uma câmera renderizada.
- **Sem menu**: o jogo entra direto no mundo; save e perfil estão em teclas.
- Os quatro `.fbx` na raiz do repositório não são usados por nada aqui.

## Estrutura

```
core/         bootstrap, eventos, configuração, plataforma, utilitários
world/        geografia, projeção, elevação, terreno, setores, streaming, LOD, demo
city/         geração: reticulação procedural (E1) e camada urbana (E3) + demo
gameplay/     jogador, câmera, veículos
ai/           grafo de vias, trânsito, pedestres
interiors/    construtor do apartamento e gerência de interiores
systems/      dia/noite, clima, áudio, persistência
rendering/    materiais, malhas primitivas, perfis de qualidade
ui/           HUD, minimapa, controles de toque
data/         municípios, traçado urbano, pontos de referência, setores, OSM, elevação
tools/        importador OSM, bake de setores, validação, ferramentas urbanas
tests/        suíte headless
```

Detalhes de arquitetura, decisões e orçamentos: [docs/ARQUITETURA.md](docs/ARQUITETURA.md).
