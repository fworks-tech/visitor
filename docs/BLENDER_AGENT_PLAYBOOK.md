# Playbook: personagens 3D no Blender via OpenCode

Instruções para um agente de código (OpenCode, Claude Code, Cursor ou similar)
produzir os modelos dos visitantes do *Visitor* no Blender, sem tocar no
gameplay. O agente lê este arquivo, o `AGENTS.md`, o contrato de personagem e a
ficha do visitante, e entrega um GLB validado, renders de revisão e um relatório.

## Como usar

1. Abra o repositório no OpenCode.
2. Cole o prompt de `tools/characters/OPENCODE_TASK.md`, trocando `<ID>` pelo
   visitante (`v001`, `v003`, `v008`).
3. O agente deve começar com um plano curto e checar o ambiente antes de modelar.
4. Aprove o plano. Depois disso, ele executa o ciclo modelar, exportar, validar,
   renderizar e reportar.
5. Só aceite o modelo quando o validador e o teste de integração passarem.

Para produção em lote, repita um personagem por vez. Nunca peça três modelos
simultâneos no mesmo diretório.

## Papel do agente

Você é o **Character Artist Agent** do projeto *Visitor*. Você opera o Blender
em modo headless (`blender --background --python ...`) e escreve scripts Python
com `bpy`/`bmesh` quando precisar. Você não altera cenas, scripts de gameplay,
dados de história ou o corpo procedural do jogo. Sua entrega é um asset.

Objetivo padrão: **L2 GAME_READY** (definido abaixo). Se o pedido for L3 HERO,
pare e peça uma base mesh ou um artista humano.

## Leitura obrigatória antes de modelar

Leia, nesta ordem:

1. `AGENTS.md` (regras do projeto, arquitetura, o que não tocar).
2. `docs/CHARACTER_PIPELINE.md` (contrato técnico e estágios).
3. `docs/ART_DIRECTION_ANALOG.md` (grade visual: dessaturado, contraste, grain).
4. `tools/characters/character_specs.json` e `character_dna.schema.json`
   (id, retrato, altura, ombros, cabelo, roupa, rig e orçamento).
5. `assets/data/visitors.json` (personalidade, sinais, roupa, história).
6. `assets/images/portraits/<retrato>` (paleta e face de referência).
7. `assets/models/visitors/<id>.glb` (blockout atual, apenas como proporção).

Se algum desses arquivos não existir, pare e reporte. Não invente o visitante.

## Níveis de qualidade

| Nível | Entrega | Rig | Textura | Uso |
|---|---|---|---|---|
| L1 BLOCKOUT | caixas/manequim, face card | não | 1k face | demo e greybox |
| **L2 GAME_READY** | silhueta, roupa, mãos, cabelo, face card ou face modelada | 20-25 bones + idle/talk | atlas 1k + face 512/1k | alvo do agente |
| L3 HERO | escultura de rosto/mãos, retopo, blend shapes | sim | 2k | artista humano ou base licenciada |

O agente pode entregar L2 com rosto em card (a mesma banda de retrato do
blockout) ou com rosto modelado simples. Não prometa L3 sem base mesh.

## Regras de ouro

- Um personagem por vez. Um `id` por execução.
- Não edite `autoload/`, `scripts/`, `scenes/`, `assets/data/` nem
  `project.godot`.
- Não sobrescreva o GLB final. Trabalhe em
  `assets/models/visitors/_wip/<id>.glb` e só promova depois do aceite.
- Não faça commit, push ou PR sem pedido explícito.
- Não use mesh, textura, animação ou add-on de terceiros sem licença registrada.
  Se usar, anote autor, URL e licença no relatório e em `ATTRIBUTIONS.md`.
- Não use IA generativa de malha com licença incerta. O asset precisa ser
  reproduzível e licenciável.
- Não altere o retrato, a paleta global ou o grade do jogo. O green grade é
  aplicado na engine, não baked na textura.
- Se o Blender não estiver instalado, não simule a entrega. Reporte o bloqueio.

## Ambiente

```bash
blender --version
python3 --version
```

Requisitos: Blender 4.2+ (4.4.x recomendado), Python 3.11+, `ffmpeg` opcional
para contact sheets. Se `blender` não estiver no PATH, use o caminho completo:

- macOS: `/Applications/Blender.app/Contents/MacOS/Blender`
- Windows: `C:\Program Files\Blender Foundation\Blender 4.4\blender.exe`
- Linux: `blender` ou o binário extraído do tarball.

Não instale add-ons pagos. Se precisar de um add-on, pare e peça autorização.

## Fluxo de trabalho

### 0. Plano e ambiente

Antes de modelar, responda em até 8 linhas:

- id, nome e nível alvo;
- altura/ombros do spec;
- o que será modelado (roupa, cabelo, face card ou face modelada);
- orçamento de triângulos e texturas;
- comandos que vai rodar;
- riscos (Blender ausente, base mesh ausente, licença).

Rode `blender --version` e `python3 tools/characters/validate_blender_output.py
--id <id>` para confirmar o estado atual. O blockout deve passar no modo padrão
(sem `--production`).

### 1. Referência e proporção

Abra o retrato e o blockout. Meça no Blender:

- altura total 1.70-1.85 m;
- ombros 0.50-0.58 m;
- cabeça ~0.22-0.25 m de altura;
- pés no chão (Z=0), origem no centro entre os pés;
- frente do personagem para **-Y** no Blender (o exportador converte para +Z
  no glTF/Godot).

Não copie a pose do retrato. O retrato é referência de rosto, paleta e roupa.

### 2. Malha

Parta do blockout apenas para proporção. Construa ou ajuste:

- silhueta legível a 720p: ombros, casaco, postura;
- roupa com volume, não caixas coladas;
- mãos e botas simplificadas, mas presentes;
- cabeça com formato humano, queixo e orelhas sugeridos;
- cabelo como volume, não chapinha;
- rosto: card de retrato ou modelagem simples com olhos, nariz e boca.

Técnicas aceitas em L2: `bmesh` para formas, `Subdivision Surface` controlado,
`Bevel`, `Solidify` para casaco, `Mirror` aplicado, `Shrinkwrap` se houver base.
Não deixe modificadores não aplicados no GLB final.

### 3. Materiais e texturas

- Um atlas de corpo/roupa em 1k (até 2k se necessário) e face em 512/1k.
- Principled BSDF: base color, roughness, normal. Metallic = 0.
- Albedo em sRGB; normal/roughness em Non-Color.
- Nome do material da face: `portrait_face`.
- Se usar face card, mantenha a banda UV `(0.34, 0.13, 0.28, 0.30)` do retrato.
- Não bake o green grade. A engine aplica o grade.
- Sem texturas acima de 2048 px.

### 4. Rig

- Armature `RIG_<id>` com 20-25 bones: root, hips, spine, chest, neck, head,
  clavicles, upper arms, forearms, hands, thighs, shins, feet.
- Peso máximo de 2 influências por vértice; normalize.
- Sem constraints/IK no export. Bake o que precisar.
- Rest pose em A-pose ou T-pose, pés no chão.
- Teste uma rotação de ombro, cotovelo, quadril e joelho antes de exportar.

### 5. Animação

- `idle`: 60 frames a 30 fps (2 s), loop, respiração sutil e micro sway.
- `talk`: 30-60 frames, loop, cabeça e mandíbula discretas.
- Nomeie as ações `idle` e `talk`; exporte como animações glTF.
- Se o card de rosto impedir mandíbula, anime cabeça/ombros e documente.

### 6. Export

Use o template do repositório:

```bash
blender --background assets/models/visitors/_wip/<id>.blend \
  --python tools/characters/blender_export.py -- \
  --id <id> \
  --out assets/models/visitors/_wip/<id>.glb \
  --preview-dir docs/renders/characters/<id> \
  --production
```

O template:

- valida escala, origem e altura;
- exige armature e animação com `--production`;
- exporta GLB com `export_yup=True`, skins e animações;
- renderiza frente, 3/4 e perfil em 720x720.

Se o template não servir para a sua cena, ajuste apenas o script de export, não
o contrato.

### 7. Validação

```bash
python3 tools/characters/validate_blender_output.py \
  --id <id> \
  --path assets/models/visitors/_wip/<id>.glb \
  --production
```

O validador de DNA checa identidade, medidas, face, roupa, rig, animações,
assets, LOD, orçamento e licença. O validador de GLB checa:

- glTF 2.0 binário, mesh e primitives;
- orçamento de triângulos (15k);
- altura 1.55-2.05 m e pés a até 0.10 m do chão;
- UVs e material `portrait_face`;
- nome do nó contendo o id;
- ausência de câmeras/luzes;
- texturas até 2048 px;
- skin, joints (>=15) e animações no modo `--production`.

Se falhar, corrija e repita. Não reporte sucesso sem a saída `PASS`.

### 8. Integração

Depois do validador:

```bash
cp assets/models/visitors/_wip/<id>.glb assets/models/visitors/<id>.glb
godot --headless --path . -- --demo --door-test
```

O teste de demo precisa terminar com `RESULT 0 failures`, incluindo
"demo visitor uses a GLB model". Se o modelo final for para o jogo completo,
declare `character_model` no visitante e valide os sinais/reveal; o corpo
procedural continua sendo o fallback.

### 9. Renders de revisão

Além dos três ângulos do export, gere um contact sheet se possível:

```bash
ffmpeg -i front.png -i three_quarter.png -i profile.png \
  -filter_complex hstack=inputs=3 <id>_sheet.png
```

Os renders devem mostrar:

- silhueta e proporção;
- rosto legível no escuro;
- roupa e cabelo;
- pés no chão e enquadramento do apron da porta.

Guarde em `docs/renders/characters/<id>/`. Não commite renders grandes sem
pedido; links ou arquivos comprimidos são suficientes.

## Contrato técnico

| Item | Valor |
|---|---|
| Unidade | 1 unidade = 1 metro |
| Eixos no Blender | Z up, frente para -Y, pés em Z=0 |
| Eixos no glTF/Godot | Y up, frente para +Z, pés em Y=0 |
| Altura | 1.70-1.85 m |
| Ombros | 0.50-0.58 m |
| Triângulos | <= 15.000 |
| Materiais | corpo/roupa + `portrait_face` (máx. 4) |
| Texturas | atlas <= 2k, face <= 1k, PNG |
| Bones | 20-25, máx. 2 influências por vértice |
| Animações | `idle` 2 s, `talk` 1-2 s, 30 fps |
| Nome do nó raiz | `<id>` |
| Coleção | `CH_<id>` |
| Malha | `BODY_<id>` |
| Rig | `RIG_<id>` |
| Export | GLB, glTF 2.0, sem câmeras/luzes |

## Critérios de aceite

- [ ] O prompt foi respondido com plano e ids corretos.
- [ ] `blender --version` foi registrado.
- [ ] A cena tem `CH_<id>`, `BODY_<id>`, `RIG_<id>` e raiz `<id>`.
- [ ] Frente para -Y no Blender; pés em Z=0; escala aplicada.
- [ ] Malha L2 com roupa, mãos, cabelo e rosto legível.
- [ ] Atlas e face dentro do orçamento.
- [ ] Rig com 20-25 bones e pesos normalizados.
- [ ] `idle` e `talk` exportados.
- [ ] `validate_blender_output.py --production` retorna `PASS`.
- [ ] `--demo --door-test` retorna `RESULT 0 failures`.
- [ ] Três renders gerados.
- [ ] Relatório preenchido, sem inventar resultados.

## Formato do relatório

Responda exatamente neste bloco, sem prosa antes:

```text
CHARACTER: <id> <nome>
LEVEL: L2 GAME_READY
BLENDER: <versão>
BLEND: <caminho do .blend>
GLB: <caminho do GLB>
TRIS: <número>
MATERIALS: <nomes>
TEXTURES: <dimensões>
BONES: <número>
ANIMS: <nomes>
HEIGHT: <metros>
FEET_Y: <metros>
VALIDATION: PASS/FAIL (<comando>)
GODOT: PASS/FAIL (<comando>)
RENDERS: <caminhos>
CHANGES: <arquivos alterados>
RISKS: <licença, limitações, o que não foi feito>
NEXT: <próximo passo>
```

Se algo falhar, use `FAIL` e explique em `RISKS`. Nunca escreva `PASS` sem a
saída do comando.

## Quando parar e perguntar

Pare e faça uma pergunta objetiva se:

- o Blender não estiver instalado ou não abrir em headless;
- o pedido for L3 HERO e não houver base mesh licenciada;
- o retrato ou a ficha do visitante não existirem;
- a licença de uma base/textura/animação não estiver clara;
- o modelo não couber em 15k triângulos depois de duas tentativas;
- o validador continuar falhando por um motivo que exige decisão de arte;
- for necessário alterar gameplay, história ou o corpo procedural.

Não peça permissão para coisas já autorizadas por este playbook (rodar Blender,
escrever em `_wip`, validar, renderizar).

## Prompt de sistema sugerido

```text
Você é o Character Artist Agent do projeto Visitor. Trabalhe em Blender
headless, um personagem por vez. Leia AGENTS.md,
docs/CHARACTER_PIPELINE.md, docs/BLENDER_AGENT_PLAYBOOK.md,
tools/characters/character_specs.json e a ficha do visitante antes de agir.
Não altere gameplay, dados ou cenas. Entregue um GLB L2 GAME_READY validado,
três renders e o relatório do playbook. Se o Blender não existir, pare e reporte.
```

## Prompt de tarefa

O prompt pronto para copiar está em
`tools/characters/OPENCODE_TASK.md`. Troque `<ID>` e `<NOME>` e cole no
OpenCode. Para lote, rode um por vez e mantenha o mesmo contrato.

## Limites conhecidos

- Um agente de código consegue L2 com boa silhueta e rig, mas não substitui um
  escultor para L3.
- Blender headless sem GPU pode renderizar devagar; use EEVEE ou Workbench para
  revisão, Cycles só se necessário.
- O retrato é a referência de face; o card é aceitável em L2, mas um rosto
  modelado exige revisão humana.
- O validador verifica contrato, não beleza. A aprovação visual é humana.
