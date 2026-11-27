# Changelog

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
