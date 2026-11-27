# Changelog

## 0.4.0 — Personagem

Etapa 4: o mundo das etapas anteriores passa a ter um personagem com movimento
próprio, câmera de terceira pessoa, animação e interação. Relatório completo em
[docs/ETAPA4.md](docs/ETAPA4.md).

### Correção de defeito da Etapa 1

- **`camera_rig.yaw()` era chamado como método**, mas `yaw` é variável em
  `PlayerCamera`. Isso levantava erro a cada passo de física sempre que havia
  câmera — no jogo inteiro. O movimento só funcionava sem câmera ativa. A
  correção está em `Player._camera_yaw()`, e há teste que trava a propriedade
  porque `InteriorManager.enter()` escreve `camera_rig.yaw = PI`.

### Movimento

- **`MovementProfile`**: velocidades, acelerações, janelas de tempo e fator de
  fatiamento num objeto, com valores por perfil de qualidade.
- **`PlayerMotor`**: a matemática do movimento separada da cena — testável sem
  física, sem frame e sem flakiness.
- **Caminhada, corrida e sprint** como três intenções; no teclado, `CTRL`, `W` e
  `SHIFT+W`; no toque, amplitude do analógico mais botão de sprint.
- **Aceleração e desaceleração em taxas diferentes**, para o personagem parar ao
  soltar a entrada em vez de deslizar.
- **Rampa**: velocidade desejada projetada no plano do chão — subir ladeira rende
  menos.
- **Coyote time (0,12 s) e buffer de pulo (0,14 s)**.
- **Aterrissagem medida uma vez**, na transição ar → chão, com a velocidade de
  impacto copiada.
- **Fatiamento do passo** (`substeps_for`): conta pura; só entra acima de 0,45 m
  por passo, então a 60 Hz e 10 m/s continua um `move_and_slide`.

### Estados

- **`MovementStateMachine`**: 10 estados explícitos resolvidos por prioridade
  (veículo, desligado, interação, ar, aterrissagem, virar, velocidade).
- A janela de interação vive no objeto, e `update` sobrescreve o valor do
  contexto — o estado não depende de cópia do temporizador.

### Animação

- **`CharacterAnimator`**: pose procedural derivada de estado e velocidade; e
  gancho para `AnimationTree`/`AnimationPlayer` importados, sem fingir asset.
- **`PlaceholderCharacter`**: boneco provisório com doze nós e quatro juntas de
  verdade (membros opostos, subida, inclinação, torção, esmagamento).
- **Nenhum modelo humano licenciado.** Os `.fbx` da raiz não têm licença
  declarada e não são usados.

### Câmera

- **Suavização por eixo**: horizontal rápida, vertical lenta — sem sacudir em
  degrau.
- **Encurtar imediato, alongar suave**: parede entre câmera e jogador não vira
  interior de parede na tela.
- **Zoom** por roda, teclas e pinça; **ombro proporcional** à distância.
- Inversão de eixo Y e sensibilidade das preferências.

### Interação

- **`PlayerInteraction` por provedores**: veículo, porta e grupo `interactable`.
  Prioridade primeiro, distância depois.
- **O HUD deixou de ter a cópia da cadeia de interação** — lê
  `Player.interaction_prompt()`.
- **Cadeia legada mantida** quando nenhum provedor responde.

### Controles

- **`InputBindings`**: onze ações nomeadas, teclas padrão, registro idempotente
  no `InputMap`, remapeamento salvo em `user://settings.cfg`.
- **Leitura resiliente**: sem ação registrada, a tecla padrão continua valendo.
- **Controles de toque reescritos**: botões de pulo, sprint e interação
  desenhados; pinça para zoom; layout por tamanho de tela; lógica testável por
  números.

### Integração

- `Player` preserva a API pública da Etapa 1 e ganhou `step_physics()` para o
  teste conduzir o corpo pelo mesmo caminho do jogo.
- `QualityProfile` ganhou treze chaves de personagem e câmera por perfil.
- `CariocaSettings` passou a guardar câmera, toque e remapeamento.
- Nada de terreno, streaming, geração urbana ou interior foi alterado.

### Testes

Oito arquivos novos, cerca de 90 métodos: motor, estados, animação, boneco,
interação, ações nomeadas, câmera e o personagem no mundo (fronteira de setor e
rebase do floating origin).

### Limites que continuam

- Nada foi executado neste ambiente; nenhum FPS foi medido.
- Animação por asset não existe: só a procedural roda.
- Sem IK, ragdoll, escalada ou natação; remapeamento só de teclado.

## 0.3.0 — Geração Urbana

Etapa 3: a infraestrutura geográfica e de streaming das etapas anteriores passa a
sustentar uma cidade. O relatório completo está em
[docs/ETAPA3.md](docs/ETAPA3.md).

### Quadras e lotes

- **Quadra extraída da geometria das ruas**: cruzamentos viram nós, pontas
  próximas são fundidas e cada face fechada do grafo é um quarteirão. Rua
  diagonal produz quadra triangular, não retângulo.
- **Recuo por aresta**: metade da pista da via correspondente mais calçada. Nenhum
  lote encosta no asfalto.
- **Quadra de fronteira pertence a um setor só** (o do centroide) e é gerada por
  inteiro com as ruas do entorno.
- **Lote por guilhotina em duas direções**, com lote de esquina quando a faixa
  encosta em via perpendicular. Dois lotes nunca se sobrepõem — é propriedade da
  construção, não checagem.
- **Frente do lote medida depois do polígono**: a aresta mais próxima do asfalto,
  com a normal para dentro.

### Edificações

- **Sete tipologias**: térrea, dois pavimentos, com garagem, com varanda, edifício
  residencial, prédio comercial e construção mista.
- **Fachada modular como dado**: janela, porta, garagem, sacada, varanda, vitrine,
  toldo, escada. Planejamento separado da malha, testável sem GPU.
- **Cobertura por tipologia**: duas águas, quatro águas, uma água e laje com
  platibanda.
- **Muro e portão** na testada, com malha e colisão de caixa.
- **Embasamento**: apoio no canto mais baixo da pegada, vão preenchido até o mais
  alto.

### Cidade

- **Calçada, guia e sinalização horizontal** ao longo das vias.
- **Mobiliário urbano** derivado da via: poste, semáforo, placa, lixeira, banco,
  abrigo, caixa de infraestrutura.
- **Vegetação** por calçada, quintal, lote vazio e praça, com rejeição de asfalto,
  parede e faixa de barreira.
- **Pontos de referência por dado** (`data/geographic/landmarks/`), com
  `confidence`, `sources` e uma frase dizendo o que o dado não é.

### Dados e procedência

- **Três fontes de rua com prioridade explícita**: `.osm` importado, traçado
  esquemático ancorado e reticulação procedural. A fonte usada viaja no payload.
- **`data/geographic/urban/`** — traçado esquemático do Centro de Guapimirim, em
  metros, ancorado no centro municipal, declarado como estimativa.
- **`ATTRIBUTION.md`** — atribuição e licença de cada fonte (ODbL e CC0).

### Integração e desempenho

- **Payload aditivo**: todas as chaves da Etapa 2 preservadas; trânsito,
  pedestres, minimapa, interior e `validate_sectors` não mudaram.
- **Geração continua nas threads de trabalho**; `UrbanConfig` é instantâneo
  substituído inteiro a cada troca de perfil.
- **LOD urbano**: mobiliário some no nível 2, vegetação no 3, sombra do prédio no 3.
- **Nove chaves urbanas por perfil** de qualidade, com teto de edificações por
  setor.

### Ferramentas e testes

- `tools/urban_tools/urban_inspector.gd` — duplicata, prédio fora do lote,
  sobreposição com rua, encosta fora de tolerância, procedência e licença.
- `tools/urban_tools/regenerate_sector.gd` — regeneração por setor, com `--bake`.
- `city/demo/guapimirim_center_demo.tscn` — demonstração com `F3` desenhando
  quadras e lotes do próprio payload.
- **Dez arquivos de teste novos** (oito unitários, dois de integração).

### Limites que continuam

- Nada foi executado neste ambiente; nenhum FPS foi medido.
- As ruas do centro são esquemáticas, não OSM.
- Sem malha de rio e ferrovia; sem oclusão; colisão de prédio é caixa.

## 0.2.0 — Terreno e Streaming

Etapa 2: o mundo passa a ter resolução variável por distância, memória com teto
próprio e carga antecipada na direção do movimento. Nada da Etapa 1 foi
substituído; o relatório completo está em [docs/ETAPA2.md](docs/ETAPA2.md).

### Terreno

- **LOD 0–3 por distância**, com quatro níveis de divisões por perfil de
  qualidade. Terreno próximo a 8–15 m por quad no PC, 30 m no mobile; o nível
  distante tem até 22× menos geometria que o próximo.
- **Saia anti-rachadura** na malha: junção em T entre setores de níveis
  diferentes deixa de abrir fresta no horizonte. A saia entra depois da grade,
  então a primeira (divisões+1)² vértices continuam sendo o terreno exato.
- **Troca de resolução em tempo real** no setor já carregado: só a malha e a
  colisão do terreno são refeitas; vias, prédios e vegetação não.
- **Colisão de trimesh só nos níveis próximos** — é a estrutura mais cara do
  setor e não se paga longe do jogador.
- **Célula de detalhe de 128 m**: subdivisão exata do bloco de 512 m (4×4), com
  grade própria ancorada na origem métrica.
- Dimensões da grade agora **configuráveis em um lugar só** (`WorldGridConfig`),
  em vez de literais espalhados.

### Streaming

- **Prioridade na direção do movimento**: a fila deixa de ser radial pura e passa
  a inclinar para frente conforme a velocidade, até 28 m/s.
- **Antecipação** de até cinco blocos à frente do raio carregado.
- **Cache LRU de payload** por entradas e por bytes: voltar para trás não relê
  nem regera nada.
- **Orçamento de memória** com despejo do setor mais distante, protegendo o chão
  sob o jogador.
- **Retentativa com espera crescente e quarentena**, além de watchdog que abandona
  tarefa travada em 20 s.
- **Controlador de LOD separado** da política: decide e devolve coordenadas, não
  toca em GPU, e por isso tem teste sem frame.
- **`tick_for_test(delta)`** no manager: o teste headless conduz o mesmo corpo do
  `_process`, sem caminho paralelo.

### Interface

- Diagnóstico (F3) mostra distribuição de LOD, memória contra o teto, acertos de
  cache, antecipação e despejos.
- Cena de demonstração isolada do jogo: `world/demo/streaming_demo.tscn`, com
  câmera livre e piloto automático.

### Corrigido

- Cache de densidade municipal (`MunicipalityIndex.density_at`) passou a ser
  protegido por `Mutex`: as duas tarefas de carga em paralelo escreviam no mesmo
  `Dictionary`, que não é thread-safe.

### Qualidade

- Suíte headless de 20 arquivos (de 9), com testes de LOD, fila, cache, orçamento,
  retentativa, floating origin, carga e descarga de anel e sessão longa.

## 0.1.0 — Fundação 2.0

Primeira entrega técnica: o núcleo geográfico capaz de sustentar a expansão do
Estado do Rio de Janeiro, mais um protótipo jogável em Guapimirim e Magé.

### Núcleo

- Projeção cônica conforme de Lambert estadual (SIRGAS 2000 / GRS80), com
  inversa analítica e fator de escala verificado nos paralelos padrão.
- Hierarquia tile (2 km) / setor (512 m) / microárea (100 m) com índices puros.
- Barramento de eventos, configuração persistente e detecção de plataforma, sem
  autoload — o que mantém ferramentas e testes rodando sem árvore de cena.
- Floating origin com rebase a cada 2 km em XZ.

### Mundo

- Streaming assíncrono: payload em `WorkerThreadPool`, construção com orçamento
  por frame, histerese no descarregamento.
- Relevo por SRTM (leitura por linha, cache) com queda para procedural
  determinístico quando não há dado.
- Malha de terreno sem costura entre setores (verificado por teste).
- Gerador urbano por reticulação global: ruas, lotes, fachadas por andar,
  vegetação e mobiliário.
- Importador de OpenStreetMap (vias, edificações, água) e validador de setores.
- Bake de setores procedurais em JSON.

### Jogo

- Jogador em terceira pessoa com controle unificado teclado/toque.
- Câmera com colisão por raio.
- Veículos dirigíveis com física nativa, entrar e sair.
- Trânsito com faixa, freio para carro à frente e semáforos determinísticos.
- Pedestres em calçada.
- Ciclo dia/noite e clima com efeito sobre aderência.
- Ambiência sonora sintetizada em tempo real.
- Apartamento modular explorável, com porta na rua e retorno à mesma posição.
- Save versionado com checksum, gravação atômica e migração.
- HUD de diagnóstico, minimapa desenhado do payload e controles de toque.
- Perfis de qualidade mobile / pc_medium / pc_high.

### Qualidade

- Suíte headless de 8 arquivos cobrindo projeção, grade de setores, índice
  geográfico, determinismo, terreno (inclusive costura), gerador, grafo de
  ruas, save e montagem de setor.
- Workflow de integração contínua para rodar a suíte.
