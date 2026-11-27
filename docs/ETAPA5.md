# Etapa 5 — Sistema de Veículos

A Etapa 4 deu um personagem que anda pelo mundo das Etapas 1–3. A Etapa 5 dá a
ele um carro para dirigir nesse mesmo mundo: encontrar, entrar, acelerar, frear,
fazer curva, dar ré, buziná, sair e voltar a pé — sobre as ruas do Centro de
Guapimirim, com streaming, floating origin e clima funcionando.

**Estado honesto:** o código foi escrito sem execução local (este ambiente não
tem Godot) e verificado pela suíte headless no CI (Godot 4.4). A dirigibilidade
**não foi julada por uma pessoa** e nenhum FPS foi medido. Os sons do carro são
placeholders sintetizados, declarados como tais. O que cada teste cobre — e o
que ninguém testou — está em §7 e §8.

---

## 1. Auditoria (o que já existia e o que se preservou)

| Sistema | Estado antes | Decisão da Etapa 5 |
|---|---|---|
| `gameplay/vehicles/vehicle.gd` | `VehicleBody3D` + 4 `VehicleWheel3D`, motor/freio/esterço brutos lidos de `Player.read_move_input()` | **Preservada** como base; a intenção passa a vir do `DriveModel` |
| `gameplay/vehicles/vehicle_manager.gd` | spawn sobre o terreno, frota sob teto, `nearest()` | **Preservada**; recebe perfil do preset e propaga a chuva como antes |
| `Player.enter_vehicle()/exit_vehicle()` | API pública da Etapa 1, já usada por provedor e HUD | **Preservadas** as assinaturas; por dentro, banco do motorista e saída pelo lado livre |
| `PlayerCamera` | colisão, zoom, suavização por eixo (Etapa 4) | **Estendida**, não duplicada: `VehicleCamera` é subclasse |
| `PlayerInteraction` + `VehicleInteractionProvider` | candidato "E dirigir" com prioridade 10 | **Inalterados** — a entrada continua pelo mesmo caminho |
| `InputBindings` | ações nomeadas a pé | Estendidas com `carioca_handbrake`, `carioca_horn`, `carioca_camera_mode` |
| `TouchControls` | analógico, olhar, pinça, 3 botões | Estendida com **modo veículo** (layout troca quando o motorista entra) |
| `AudioManager` | ambiência sintetizada, sem arquivos | **Inalterado**; o carro tem áudio próprio (`VehicleAudio`) |
| Streaming / floating origin | carros já nascem na raiz de atores, que o rebase desloca | **Inalterado** — e agora travado por teste |
| `TrafficManager` | agentes de IA próprios, **não** usa `Vehicle` | **Inalterado**; integração trânsito↔Veículo fica para a próxima etapa |

Nada das Etapas 1–4 foi apagado ou renomeado. As constantes legadas de
`Vehicle` (`LEGACY_*`) continuam porque o HUD e o bootstrap as leram.

## 2. Decisão de física

**`VehicleBody3D` + `VehicleWheel3D` nativos.** Suspensão, atrito de pneu,
contato com terreno (inclinação, lombada), gravidade e colisão vêm do servidor
de física — mais estáveis e mais baratos do que reimplementar pneus em
GDScript, e a decisária da Etapa 1 mantida com justificativa, não por
conveniência. Custo por carro: 4 rodas com raio de suspensão curto, um corpo,
sem raycasts extra no `_physics_process` (a única consulta física nova é a
sonda de saída, chamada uma vez por saída).

Limitações assumidas, documentadas:

- **Sem câmbio simulado**: ré/frente é uma marcha lógica do `DriveModel`, não
  uma caixa de câmbio com relações.
- **Sem diferencial e sem bloqueio de roda**: o que gira de traseira no freio
  de mão vem da queda de `wheel_friction_slip` traseira, não de um modelo de
  derrapagem lateral.
- **Transferência de peso simplificada**: é a que o centro de massa (0,35 m) e
  a suspensão produzem sozinhos; não há modelo de carga por eixo.

## 3. Arquitetura

```
DrivingProfile   números: motor, teto, freio, mão, esterço, aderência, tração
DriveModel       intenção: pedais, marcha, esterço por velocidade, retorno
Vehicle          corpo físico: aplica o que o modelo decide, clima, saída
VehicleCamera    a mesma câmera do personagem, com modo veicular
VehicleAudio     motor/buzina/freio sintetizados (placeholders declarados)
```

- **`DriveModel` é matemática pura** (mesmo padrão do `PlayerMotor` da Etapa
  4): entra `delta`, velocidade assinada, pedais e volante; saem
  `engine_force`, `brake`, `steering` e marcha. Todo passo é em função de
  `delta`, e há teste provando que dois passos de 1/120 s = um de 1/60 s.
- **Ré honesta**: S em movimento freia; segurando S com o carro parado por
  0,25 s, engata a ré. Um toque de freio nunca engata ré — é o que separa
  "freio de emergência" de "quero dar ré".
- **Aceleração progressiva**: a força cai perto do teto configurável
  (`vehicle_max_speed` por preset) e a resistência do ar vem do `linear_damp`.
- **Esterço por velocidade**: disponível = `max_steer × steer_factor(v)`, de
  100% parado a 32% acima de ~94 km/h; sem input, o volante volta pelo centro.
- **Freio de mão**: freio forte nas quatro rodas e aderência traseira a 35%.
- **Câmera veicular por herança**: reusa colisão, zoom, pinça e suavização da
  Etapa 4; acrescenta suavização proporcional à velocidade, acompanhamento
  atrás do carro com pausa de 2 s ao toque manual, e duas distâncias (tecla
  `V` / botão de toque). `MODE_CABIN` está reservado para a câmera interna
  futura.
- **Entrada**: provedor existente → `enter_vehicle()` → motorista sentado no
  banco esquerdo (`DRIVER_SEAT_OFFSET`), corpo oculto, controlador a pé
  desligado, câmera em modo veicular.
- **Saída**: sonda uma esfera de 0,5 m nos dois lados (`side_is_blocked`) e
  escolhe o lado livre mais próximo; se os dois estiverem bloqueados, sai pelo
  preferido mesmo assim — nunca deixar o jogador preso.
- **Toque**: no modo veículo o analógico vira volante, e os pedais
  (acelerar, freio/ré), mão, buzina, câmera e sair são botões. O HUD troca o
  layout automaticamente ao entrar/sair.
- **Áudio**: tom do motor com pitch por carga (`engine_tone`, puro e testado),
  buzina de dois tons gerada em buffer, gancho de derrapagem vazio declarado.

## 4. Modelo do primeiro carro

Provisório e sem asset externo (licença: n/a — geometria gerada em código, no
mesmo padrão de todo o projeto). Quatro malhas por carro:

- `car_shell()` — capô, teto, porta-malas, colunas A/B/C, laterais e saia;
- `car_trim()` — para-choques, grade, alojamento dos retrovisores;
- `car_glass()` — para-brisa inclinado, vigia, janelas laterais (material
  transparente próprio);
- `car_lights()` — par de faróis e par de lanternas, materiais emissivos
  separados;
- rodas: pneu e aro em malhas e materiais distintos, girando e esterçando pelo
  `VehicleWheel3D` nativo.

Um modelo melhor entra por cima sem tocar em física: as malhas são filhos
visuais do corpo.

## 5. Integração com o mundo

O carro nasce 1,4 m acima do terreno (`VehicleManager.spawn_at`), é filho da
raiz de atores — a mesma raiz que o floating origin desloca — e **não pertence
a setor nenhum**, então descarregamento de setor nunca leva o carro embora
(travado por teste). O rebase preserva a posição métrica (testado). A chuva
interpolando para `grip_wet` continua valendo (testado), e o preset de
qualidade chega ao carro por `VehicleManager.apply_preset` (testado). A
demonstração usa o mundo real: `gameplay/demo/vehicle_demo.tscn`.

## 6. Arquivos

**Criados**

- `gameplay/vehicles/driving_profile.gd` — números por preset
- `gameplay/vehicles/drive_model.gd` — matemática de direção
- `gameplay/vehicles/vehicle_camera.gd` — câmera veicular (subclasse)
- `gameplay/vehicles/vehicle_audio.gd` — placeholders de motor/buzina
- `gameplay/demo/vehicle_demo.gd` + `.tscn` — demonstração dirigível
- `tests/unit/test_driving_profile.gd`, `test_drive_model.gd`,
  `test_vehicle_camera.gd`, `test_vehicle_audio.gd`
- `tests/integration/test_vehicle_interaction.gd`, `test_vehicle_world.gd`
- `docs/ETAPA5.md` (este relatório)

**Modificados**

- `gameplay/vehicles/vehicle.gd` — `DriveModel`, mão, ré, tração por modo,
  casco detalhado, buzina, sonda de saída
- `gameplay/vehicles/vehicle_manager.gd` — perfil por preset
- `gameplay/player/player.gd` — banco do motorista, saída pelo lado livre,
  troca de modo da câmera
- `rendering/materials/procedural_meshes.gd` — casco, trim, vidros, luzes,
  pneu/aro separados
- `rendering/materials/material_library.gd` — vidro, trim, aro, farol, lanterna
- `ui/input/input_bindings.gd` — freio de mão, buzina, câmera do carro
- `ui/hud/touch_controls.gd` — modo veículo com pedais e botões
- `ui/hud/hud.gd` — troca de layout de toque e linha de diagnóstico do carro
- `rendering/quality/quality_profile.gd` — chaves `vehicle_*` nos três presets
- `core/bootstrap/game_bootstrap.gd` — câmera veicular no jogo, preset no carro
- `tests/run_tests.gd` — seis novos arquivos na suíte

## 7. Testes

| Arquivo | O que trava |
|---|---|
| `test_drive_model` | aceleração, teto, freio em movimento, ré só parado segurando, freio de mão (força + traseira solta), esterço satura e encurta, retorno progressivo, **dois passos de 1/120 = um de 1/60** |
| `test_driving_profile` | preset aplica, absurdos são clampeados, chuva interpola, esterço só cai |
| `test_vehicle_camera` | herda a câmera a pé, modos, alturas, alternância próxima/distante, limites, reconhecimento do alvo |
| `test_vehicle_audio` | tom grave parado, pitch sobe com carga, ganho limitado, entradas absurdas clampeadas, buzina liga/desliga |
| `test_vehicle_interaction` | sentar no banco, câmera troca de modo, segunda entrada ignorada, saída solta sinais no barramento, saída ao lado do carro, lado preferido, estados a pé↔veículo |
| `test_vehicle_world` | nasce na altura do terreno, rebase preserva a geografia, descarregamento de setor não leva o carro, chuva chega às rodas, preset chega ao carro, teto de frota |

## 8. Limitações e o que NÃO foi testado

- **A dirigibilidade não foi dirigida por ninguém.** Os números (força de
  motor, amortecimento do corpo, rigidez de suspensão 36, curva de esterço)
  são calibragem inicial, não resultado de playtest. Ajuste esperado após a
  primeira sessão real.
- **Comportamento físico integrado não foi medido**: o harness headless da
  suíte não integra frames de física, então aceleração real em g, distância
  de frenagem, resposta da suspensão a lombadas e estabilidade em colisão
  **não têm número nenhum**. Os testes cobrem a intenção (o que o corpo
  recebe), não o resultado da integração.
- **Nenhum FPS foi medido** — as metas (60 no PC, 30 no iPhone 12) continuam
  metas. O custo novo por carro é 4 rodas + 7 malhas + 1 gerador de áudio.
- **Sons são placeholders**: motor é um tom sintetizado com pitch por carga,
  buzina é uma onda quadrada dupla gerada em buffer; **não há som de
  derrapagem** (o gancho `skid()` é um no-op declarado) nem de colisão. Nada
  disso deve ser descrito como "realista" — não é.
- **Câmera interna** (`MODE_CABIN`) está reservada, não implementada.
- **Retrovisores não refletem** — geometria provisória, sem render de espelho.
- **Faróis não reagem ao dia/noite** — o material emissivo é compartilhado e
  estático; o gancho existe.
- **Sem dano, sem colisão especial**: bater é física de corpos rígidos, ponto.
- **Trânsito com IA** (`TrafficManager`) continua com seus próprios agentes e
  não usa `Vehicle`; carros de tráfego dirigíveis é trabalho futuro.
- **Layout de toque no aparelho** não foi visto em tela: a lógica dos botões é
  testada por `handle_touch`, mas ninguém conferiu o layout num iPhone.
- **Build web**: o jogo agora exporta para web e publicou em CI, mas o carro
  dentro do build web não foi dirigido no navegador.
