# Etapa 4 — Personagem: relatório de integração

Este documento responde à entrega da Etapa 4: o que já existia, o que foi
acrescentado, o que foi mudado, o que **não** foi feito e por quê. É separado de
`ARQUITETURA.md`, que descreve o sistema como ele **é**.

---

## 1. Limitação de escopo, declarada de saída

**Não recebi o ZIP de nenhuma etapa anterior.** O que existe neste repositório é o
trabalho das etapas 1, 2 e 3, e é sobre ele que a Etapa 4 foi construída.

**Nada aqui foi executado.** O ambiente onde este código foi escrito não tem
Godot — nem `godot --headless` roda. Toda afirmação abaixo é verificável lendo os
arquivos citados; nenhuma diz "testei e passou".

A suíte e a cena de demonstração existem para que a primeira execução real seja
barata:

```bash
godot --headless --path . --script res://tests/run_tests.gd
godot --path . gameplay/demo/player_demo.tscn
```

**Nenhum FPS foi medido.** A meta continua sendo 60 FPS no PC e 30 no iPhone 12;
nada neste documento é medição.

---

## 2. Auditoria: o que já existia

| Sistema | Arquivo | Situação |
|---|---|---|
| Jogador em terceira pessoa | `gameplay/player/player.gd` | **reescrito por dentro, API preservada** |
| Câmera em terceira pessoa com colisão | `gameplay/camera/player_camera.gd` | **estendido** |
| Controles de toque | `ui/hud/touch_controls.gd` | **reescrito** |
| HUD (prompt e diagnóstico) | `ui/hud/hud.gd` | **estendido** |
| Veículos e entrada unificada | `gameplay/vehicles/*` | **intacto** |
| Interiores e porta | `interiors/interior_manager/*` | **intacto** |
| Terreno, streaming, floating origin | `world/*` | **intactos** |
| Geração urbana | `city/urban/*` | **intacta** |
| Perfis de qualidade | `rendering/quality/quality_profile.gd` | **estendido** |
| Configuração | `core/configuration/carioca_settings.gd` | **estendido** |
| Bootstrap do jogo | `core/bootstrap/game_bootstrap.gd` | **estendido** |

### O que existia de verdade, e o que faltava

O controlador da Etapa 1 era funcional: aceleração, pulo, gravidade, alinhamento
ao movimento, câmera com raio de colisão, `read_move_input` unificado para
jogador e veículo, e `try_interact` com veículo, interior e porta. Era um
controlador de **um arquivo só**, e é onde estavam os problemas.

**Defeito real encontrado na auditoria, e corrigido nesta etapa:**

```gdscript
# Etapa 1, player.gd:92
var yaw := camera_rig.yaw() if camera_rig != null else 0.0
```

`yaw` é **variável** em `PlayerCamera`, não método. Isso levanta erro de execução
a cada passo de física **sempre que há câmera** — ou seja, no jogo inteiro. O
movimento nunca funcionou com câmera ativa; sem câmera, funcionava.

A correção está em `Player._camera_yaw()`, com comentário explicando o caso, e há
teste que trava a propriedade: `tests/unit/test_player_camera.gd::
test_yaw_is_a_property_for_the_interior_manager`.

Esse teste não é decorativo: `InteriorManager.enter()` escreve
`player.camera_rig.yaw = PI`. Se `yaw` virar método, esse caminho quebra em
silêncio. O teste é o aviso.

### O que faltava, e não era "só refatorar"

- **Nada de estado explícito.** "Está pulando?" era `velocity.y > 0`, refeito em
  cada sistema que precisava saber.
- **Nada de caminhada.** Havia uma velocidade só e `sprint` como booleano;
  correr era sempre, sem escolha entre andar e correr.
- **Nada de coyote time nem buffer de pulo.** Pular na borda da calça caía no
  vazio, e pular um instante antes de encostar não valia.
- **Nada de rampa.** Andar numa ladeira dava a mesma velocidade do plano.
- **Nada de fatiamento de passo.** A 40 m/s, um passo de 60 Hz avança 66 cm —
  mais que a cápsula. Daí atravessar parede em velocidade alta.
- **Nada de animação.** Um boneco de cápsula com um nariz.
- **Nada de provedor de interação.** `try_interact` conhecia três sistemas por
  nome, e o HUD mantinha uma **segunda cópia** da mesma cadeia.
- **Nada de ação nomeada.** `Input.is_key_pressed(KEY_W)` direto, sem `InputMap`,
  sem remapeamento.
- **Botão de interação não existia no toque.** Só teclado.

---

## 3. O que foi construído

### 3.1 `MovementProfile` — os números

Um objeto com todas as velocidades e janelas de tempo: caminhada, corrida, sprint,
aceleração, desaceleração, aceleração no ar, giro, pulo, gravidade, velocidade
terminal, *coyote time*, *buffer* de pulo, tempo de aterrissagem e fator de
fatiamento.

`from_preset()` lê do `QualityProfile`, garantindo a ordem `walk < run < sprint`
mesmo com preset mal escrito (há teste).

### 3.2 `PlayerMotor` — a matemática

Função pura: entra intenção e estado do chão, sai velocidade. **Não toca na árvore
de cena** — é o que permite testar aceleração, pulo, *coyote*, *buffer*,
gravidade, rampa e fatiamento sem servidor de física, sem frame e sem flakiness.

- **Acelerar e desacelerar em taxas diferentes** (26 e 34 m/s²): soltar a entrada
  para o personagem, em vez de deixá-lo deslizando.
- **Rampa**: a velocidade desejada é projetada no plano do chão e a componente que
  sobe vira altura. Subir ladeira rende menos velocidade horizontal, como deve.
- **Coyote time (0,12 s) e buffer de pulo (0,14 s)**: as duas janelas que fazem o
  pulo parecer justo.
- **Aterrissagem medida uma vez**, na transição ar → chão. A velocidade de
  impacto é copiada, não herdada de um valor antigo.
- **`substeps_for(delta)`**: conta pura de quantos `move_and_slide` o passo
  precisa. A 60 Hz e 10 m/s vale 1 — o caminho normal. Só entra fatiamento acima
  do que a cápsula de 35 cm aguenta; o teto é 8.

### 3.3 `MovementStateMachine` — os estados

Dez estados explícitos (desligado, parado, andando, correndo, sprint, pulando,
caindo, aterrissando, virando, interagindo) mais o de veículo. A resolução é
**ordenada por prioridade**: veículo, desligado, interação, ar, aterrissagem,
virar, depois velocidade.

A janela de interação vive **no objeto**, e `update` sobrescreve o valor que vem
de fora antes de resolver — assim o estado não depende de uma cópia do temporizador
que pode discordar da original.

### 3.4 `CharacterAnimator` — a camada de animação

**Dois mundos, ditos sem confusão:**

1. **Procedural** — funciona hoje, sem asset. Da velocidade e do estado saem
   parâmetros de pose: balanço de perna e braço, subida do quadril, inclinação de
   tronco, torção, esmagamento na aterrissagem.
2. **Importada** — `bind_tree()` e `bind_player()` ligam um `AnimationTree` ou
   `AnimationPlayer` de um modelo licenciado, e o mesmo código pede a transição.
   **Enquanto não existir modelo, `is_bound()` é falso e a máquina não finge
   animar por asset.**

### 3.5 `PlaceholderCharacter` — o boneco provisório

Doze nós com juntas de verdade: tronco, cabeça, marca de frente, dois braços
(ombro), duas pernas (quadril). Não é um modelo humano — é o substituto
funcional para a animação procedural ter onde acontecer e para o jogador ler para
onde anda.

**Por que não os `.fbx` da raiz:** eles não têm licença declarada no projeto, não
são importados por nada e o ambiente onde esta etapa foi escrita não consegue
abri-los. Chamá-los de "o personagem" seria inventar. O caminho de troca está
pronto: `CharacterAnimator.bind_tree()`.

> Observação de auditoria: durante esta etapa apareceram no repositório dois
> arquivos `The_Corporate_High-Flier*.fbx` (13,9 MB) e um `fps-buildings-env-kit-
> main.zip` (305 MB) que não são deste projeto. Nada no código os referencia.

### 3.6 `PlayerInteraction` — interação por provedores

Antes, `try_interact` conhecia veículo, interior e porta por nome, e o HUD
mantinha a mesma cadeia em cópia — duas cópias que podiam discordar sobre o que o
`E` faz.

Agora: **provedor → candidatos → o melhor → rótulo → execução**, num lugar só.

- `VehicleInteractionProvider` — dirigir o carro livre mais perto.
- `DoorInteractionProvider` — entrar no interior e sair dele.
- `GroupInteractionProvider` — qualquer nó no grupo `interactable` vira candidato,
  com `interaction_label()`, `interaction_priority()`, `interaction_radius()` e
  `interact()`. É o ponto de extensão para porta de casa, objeto de missão e NPC,
  sem tocar no jogador.
- **Prioridade primeiro, distância depois.** O carro a 3,4 m ganha da porta a
  1 m porque declarou prioridade maior.

O jogador também mantém a **cadeia antiga** quando nenhum provedor responde —
`try_interact` da Etapa 1 continua fazendo o que fazia.

### 3.7 `InputBindings` — ações nomeadas

`carioca_forward`, `carioca_jump`, `carioca_interact` e mais oito, com tecla
padrão. `ensure_registered()` cria no `InputMap` e é **idempotente**. Leitura
resiliente: se a ação estiver registrada e com evento, vale a ação (e o
remapeamento vale); se não, a tecla padrão.

Esse segundo caminho mantém o jogo jogável onde `ensure_registered()` não foi
chamado — cena de teste, ferramenta headless — e mantém a Etapa 1 funcionando sem
depender de ordem de boot.

Remapeamento salvo em `user://settings.cfg` (`input_remaps`).

### 3.8 `PlayerCamera` — a câmera

- **Suavização separada por eixo**: horizontal rápida, vertical lenta. Perseguir a
  altura na mesma pressa fazia a câmera sacudir em cada degrau.
- **Encurtar é imediato, alongar é suave.** Se uma parede entra entre a câmera e o
  jogador, esperar a interpolação significa ver o interior da parede.
- **Zoom** por roda do mouse, teclas e pinça de dois dedos, com limites.
- **Ombro deslocado** proporcional à distância: perto da parede o deslocamento
  lateral encolhe, senão a câmera atravessa pelo lado.
- Inversão de eixo Y opcional; sensibilidade vinda das preferências.
- **`yaw` e `pitch` continuam variáveis públicas** — `InteriorManager` as escreve.

### 3.9 `TouchControls` — o toque

Analógico na metade esquerda (com amplitude analógica), olhar arrastando na
metade direita e **três botões desenhados**: pulo, sprint (alterna) e interação.
Mais pinça de dois dedos para zoom, layout derivado do tamanho da tela
(`layout_scale`) e sensibilidade configurável.

Toda a lógica de toque passa por `handle_touch`/`handle_drag` com números, o que
permite testar "tocar no botão de pulo marca pedido" sem emular evento de tela.

O toque curto na área de olhar continua valendo como pulo (`tap_to_jump`), para
não perder o gesto da Etapa 1.

O botão de interação **só aparece quando há interação ao alcance**, com o rótulo
vindo do jogador.

### 3.10 Integração

- `Player` preserva a API pública e continua lendo `read_move_input()`
  (teclado + analógico), que é a mesma porta que o veículo usa.
- `step_physics(delta, input, jump)` é público: o teste conduz o corpo pelo mesmo
  caminho do `_physics_process`, sem emular teclado.
- `game_bootstrap` registra as ações, aplica remapeamento e leva perfil de
  movimento e câmera para o jogador no `_apply_quality`.
- `HUD` deixou de ter a cópia da cadeia de interação: lê `interaction_prompt()`.
- `QualityProfile` ganhou treze chaves de personagem e câmera por perfil.

---

## 4. Compatibilidade com as etapas anteriores

| O que a Etapa 1 esperava | Situação |
|---|---|
| `Player.read_move_input() -> Vector2` | **mantido** |
| `Player.try_interact()` | **mantido** |
| `Player.enter_vehicle()/exit_vehicle()` | **mantidos** |
| `Player.teleport_to_local()` | **mantido** |
| `Player.metric_position()`, `ground_height()` | **mantidos** |
| `Player.VEHICLE_RADIUS`, `DOOR_RADIUS`, `WALK_SPEED`, `RUN_SPEED` | **mantidos** |
| Sinais `entered_vehicle`, `exited_vehicle` | **mantidos** |
| Campos `camera_rig`, `touch_controls`, `vehicle_manager`, `interior_manager`, `floating`, `terrain`, `current_vehicle`, `can_move`, `sprinting` | **mantidos** |
| `PlayerCamera.yaw`, `pitch`, `distance`, `sensitivity`, `set_target()` | **mantidos** |
| `InteriorManager` escrevendo `camera_rig.yaw` | **mantido** |
| `Vehicle` chamando `driver.read_move_input()` | **mantido** |
| `TouchControls.move_vector`, `consume_jump()` | **mantidos** |

Nada de terreno, streaming, geração urbana ou interior foi alterado.

---

## 5. Controles

### PC

| Ação | Tecla padrão | Remapeável |
|---|---|---|
| Mover | W A S D / setas | sim |
| Caminhar | CTRL | sim |
| Sprint | SHIFT | sim |
| Pular | ESPAÇO | sim |
| Interagir | E | sim |
| Olhar | mouse | sensibilidade |
| Zoom | roda do mouse / + e − | — |
| Recentralizar câmera | C | sim |

### Celular

| Ação | Gesto |
|---|---|
| Mover | analógico na metade esquerda (amplitude = andar/correr) |
| Sprint | botão **correr** (alterna) |
| Pular | botão **pular** ou toque curto na área de olhar |
| Olhar | arrastar na metade direita |
| Zoom | pinça de dois dedos |
| Interagir | botão **interagir**, visível só quando há interação ao alcance |

---

## 6. Testes

Novos arquivos (sete unitários, um de integração):

| Arquivo | O que cobre |
|---|---|
| `tests/unit/test_player_motor.gd` | aceleração, caminhada/corrida/sprint, analógico, desaceleração, gravidade e velocidade terminal, pulo só no chão, coyote, buffer, aterrissagem, rampa, corpo congelado, fatiamento, independência de taxa de quadros, perfil |
| `tests/unit/test_movement_state_machine.gd` | estados por velocidade, sprint exige modificador, ar, prioridade da aterrissagem, virar só devagar, veículo e desligado por cima, janela de interação, contagem de transições, nomes e animação, reset |
| `tests/unit/test_character_animator.gd` | pose neutra, parado não anda, corrida avança passada, amplitude com velocidade, ar congela e dobra a perna, aterrissagem esmaga, nomes, vínculo sem asset não finge, reset |
| `tests/unit/test_placeholder_character.gd` | corpo e quatro juntas, membros opostos, subida/inclinação/torção/esmagamento, chaves ausentes caem para neutro, limites de esmagamento, altura dos olhos |
| `tests/unit/test_player_interaction.gd` | registro de provedor, prioridade sobre distância, empate por distância, texto do rótulo, chamada única, candidato sem ação, mundo vazio, provedor quebrado não derruba, limite de reavaliação, sinal só na mudança |
| `tests/unit/test_input_bindings.gd` | registro, idempotência, teclas padrão, remapeamento, entrada inválida, aplicação em lote, limpar remapeamento, eixo em repouso, descrição |
| `tests/unit/test_player_camera.gd` | câmera atual, limites de inclinação, limites de zoom, inversão de Y, sensibilidade, recentralizar, **`yaw` como propriedade**, números do preset |
| `tests/integration/test_player_world.gd` | nascer acima do terreno, pousar, andar nas quatro direções, pular e voltar, não afundar no terreno, **atravessar fronteira de setor**, **sobreviver ao rebase do floating origin**, interação sem erro |

Total novo: **8 arquivos, cerca de 90 métodos**. Somados à suíte das etapas
anteriores.

Nenhum teste mede FPS: não há benchmark nesta suíte, e nenhum número de
desempenho foi medido.

**Os testes de integração dependem de física real.** `test_player_world` conduz o
corpo por `step_physics` com `OS.delay_msec` entre passos, para o servidor de
física drenar. É o mesmo caminho que o `test_streaming_manager` da Etapa 2 usa, e
o mesmo risco: em máquina muito carregada o passo pode não drenar a tempo.

---

## 7. Performance: o que é decisão, não medição

| Decisão | Por quê |
|---|---|
| Estado decidido a cada passo de física, não a cada frame | é onde a decisão é usada |
| Reavaliação de interação a 10 Hz, não a 60 | o rótulo na tela não muda mais rápido |
| Um raio de câmera por frame, não vários | é o único que corta clipping |
| Colisão de prédio é caixa (Etapa 3) | o passo de física não paga BVH de fachada |
| `MultiMesh` para vegetação e mobiliário | draw call por setor, não por objeto |
| Fatiamento só acima de 0,45 m por passo | a 60 Hz e 10 m/s nunca entra |
| Orientação de membros por junta, sem skin | sem matriz de pele por vértice |
| `F3` no HUD a 4 Hz | `String.format` e reflow de `Label` custam |

**Nada disso foi medido.** São decisões coerentes com o orçamento, não resultado
de benchmark. 60 FPS no PC e 30 no iPhone 12 continuam sendo meta.

---

## 8. Limitações conhecidas, sem disfarce

1. **Nada foi executado.** Nem suíte, nem demonstração. A primeira execução real
   é a validação desta etapa.
2. **Nenhum FPS medido.**
3. **Não há modelo humano com animações licenciadas.** O boneco é provisório, com
   doze nós e juntas; a pose é procedural. A camada de animação importada existe e
   não está ligada a nenhum asset.
4. **Os `.fbx` da raiz não são usados.** Não têm licença declarada no projeto e
   o ambiente não consegue abri-los.
5. **Não há IK, *foot planting* nem *motion matching*.** O pé não se fixa no chão;
   em rampa a pose não se ajusta ao plano.
6. **Não há animação de virar no lugar** além do balanço: o estado TURN usa a
   mesma oscilação da caminhada.
7. **O boneco não tem colisão própria.** A cápsula de 35 cm é que colide; o
   visual não empurra nada.
8. **Sem ragdoll, sem escalada, sem nadar, sem agachar de verdade.** Caminhada
   (`CTRL`/botão) reduz a velocidade; não muda a altura da cápsula.
9. **O botão de interação do toque depende do rótulo.** Sem interação ao
   alcance, o botão não é desenhado — o que é correto, mas significa que o
   jogador de celular não tem um botão inerte para descobrir.
10. **Remapeamento só de teclado.** Não há remapeamento de controle (gamepad);
    `InputBindings` só cria `InputEventKey`.
11. **Sem vibração, sem *feedback* háptico.**
12. **A demonstração não sobe trânsito, pedestres, clima, ciclo do dia nem
    áudio.** É a cena do personagem; o jogo completo continua em `main.tscn`.
13. **Nada foi feito com os arquivos estranhos que apareceram** no repositório
    (`The_Corporate_High-Flier*.fbx`, `fps-buildings-env-kit-main.zip`). Não são
    referenciados por nada aqui.

---

## 9. Arquivos novos e modificados

### Novos

```
gameplay/player/movement_profile.gd         números do movimento
gameplay/player/player_motor.gd             a matemática, sem cena
gameplay/player/movement_state.gd           estados explícitos
gameplay/player/character_animator.gd        pose procedural + gancho importado
gameplay/player/placeholder_character.gd     boneco provisório com juntas
gameplay/interaction/player_interaction.gd    interação por provedores
gameplay/interaction/vehicle_interaction_provider.gd
gameplay/interaction/door_interaction_provider.gd
gameplay/interaction/group_interaction_provider.gd
ui/input/input_bindings.gd                  ações nomeadas e remapeamento
gameplay/demo/player_demo.gd                 demonstração jogável
gameplay/demo/player_demo.tscn
docs/ETAPA4.md
```

### Modificados

```
gameplay/player/player.gd                   reescrito por dentro, API preservada
gameplay/camera/player_camera.gd             suavização por eixo, zoom, preset
ui/hud/touch_controls.gd                    botões, pinça, layout, testável
ui/hud/hud.gd                               prompt vem do jogador; linha de personagem
core/bootstrap/game_bootstrap.gd             registro de ações, perfis de personagem
core/configuration/carioca_settings.gd       câmera, toque e remapeamento salvos
rendering/quality/quality_profile.gd         treze chaves novas por perfil
tests/run_tests.gd                          oito arquivos registrados
README.md, CHANGELOG.md, docs/ARQUITETURA.md
```

### Testes novos

```
tests/unit/test_player_motor.gd
tests/unit/test_movement_state_machine.gd
tests/unit/test_character_animator.gd
tests/unit/test_placeholder_character.gd
tests/unit/test_player_interaction.gd
tests/unit/test_input_bindings.gd
tests/unit/test_player_camera.gd
tests/integration/test_player_world.gd
```

---

## 10. Como rodar

```bash
# 1. o mais importante: a suíte
godot --headless --path . --script res://tests/run_tests.gd

# 2. o personagem em Guapimirim
godot --path . gameplay/demo/player_demo.tscn

# 3. o jogo completo (Etapas 1–4)
godot --path . core/bootstrap/main.tscn
```

Na demonstração do personagem: `WASD` mover, `CTRL` caminhar, `SHIFT` sprint,
`ESPAÇO` pular, `E` interagir (há dois carros ao lado do ponto de nascimento),
mouse olhar, roda zoom, `F1` perfil gráfico, `F2` recentralizar câmera, `F3`
diagnóstico, `F5` mostrar/esconder os controles de toque (para conferir o layout
mobile no PC), `R` voltar ao início.

O painel da demonstração mostra estado, velocidade, subpassos, câmera, interação e
animação — os números do `PlayerMotor`, do `PlayerCamera` e do
`CharacterAnimator`, não estimativas.
