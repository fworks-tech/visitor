# Tarefa OpenCode: modelo 3D de `<NOME>` (`<ID>`)

Copie o bloco abaixo para o OpenCode dentro do repositório `visitor` e troque
`<ID>`, `<NOME>` e `<NIVEL>` (`L2` por padrão). Para lote, rode um por vez.

---

Você é o **Character Artist Agent** do projeto *Visitor*. Sua tarefa é produzir
o modelo 3D do visitante `<NOME>` (`<ID>`) no Blender, em nível `<NIVEL>`
GAME_READY, e entregar um GLB validado, três renders e um relatório.

## Contexto obrigatório

Antes de qualquer ação, leia:

- `AGENTS.md`
- `docs/CHARACTER_PIPELINE.md`
- `docs/BLENDER_AGENT_PLAYBOOK.md`
- `docs/ART_DIRECTION_ANALOG.md`
- `tools/characters/character_specs.json` e `character_dna.schema.json`
- `assets/data/visitors.json` (ficha do `<ID>`)
- o retrato indicado no spec
- `assets/models/visitors/<ID>.glb` (blockout de proporção)

Não altere `autoload/`, `scripts/`, `scenes/`, `assets/data/` nem
`project.godot`. Não edite o retrato.

## Objetivo

Entregar um personagem L2 GAME_READY:

- silhueta legível a 720p, com roupa, mãos, cabelo e rosto;
- altura 1.70-1.85 m, pés no chão, frente para -Y no Blender;
- até 15.000 triângulos;
- atlas de corpo/roupa 1k e face 512/1k;
- armature de 20-25 bones com pesos normalizados;
- animações `idle` (2 s) e `talk` (1-2 s), 30 fps;
- GLB glTF 2.0 sem câmeras ou luzes.

Se o pedido for L3 HERO, pare e peça uma base mesh licenciada ou um artista
humano. Um agente de código entrega L2, não escultura de hero.

## Primeiro passo

Responda em até 8 linhas:

1. id, nome e nível;
2. altura/ombros do spec;
3. o que será modelado (roupa, cabelo, face card ou face modelada);
4. orçamento de triângulos/texturas;
5. comandos que vai rodar;
6. riscos.

Rode:

```bash
blender --version
python3 tools/characters/validate_character_dna.py
python3 tools/characters/validate_blender_output.py --id <ID>
```

Se o Blender não existir, pare e reporte o caminho testado. Não simule a
entrega. Se o blockout atual não passar, reporte antes de modelar.

## Fluxo

1. **Referência:** abra o retrato e o blockout. Meça altura, ombros e cabeça.
2. **Cena:** crie a coleção `CH_<ID>`, a raiz `<ID>` em (0,0,0), a malha
   `BODY_<ID>` e a armature `RIG_<ID>`.
3. **Malha:** modele ou ajuste silhueta, casaco, mãos, botas, cabeça, cabelo e
   rosto. Use `bmesh`, `Subdivision Surface`, `Bevel`, `Solidify` e `Mirror`
   quando ajudar. Aplique os modificadores no final.
4. **Materiais:** crie o atlas e o material `portrait_face`; mantenha a banda
   UV `(0.34, 0.13, 0.28, 0.30)` se usar face card. Não bake o green grade.
5. **Rig:** 20-25 bones, no máximo 2 influências por vértice, sem constraints.
6. **Animação:** ações `idle` e `talk`, 30 fps, loop.
7. **Export:** use o template do repo para gerar
   `assets/models/visitors/_wip/<ID>.glb` e os renders.
8. **Validação:** rode o validador com `--production`; corrija até `PASS`.
9. **Integração:** copie para `assets/models/visitors/<ID>.glb` e rode
   `godot --headless --path . -- --demo --door-test`.
10. **Relatório:** preencha o bloco do playbook e liste os arquivos alterados.

## Comandos

```bash
# export + renders
blender --background assets/models/visitors/_wip/<ID>.blend \
  --python tools/characters/blender_export.py -- \
  --id <ID> \
  --out assets/models/visitors/_wip/<ID>.glb \
  --preview-dir docs/renders/characters/<ID> \
  --production

# contrato do GLB
python3 tools/characters/validate_blender_output.py \
  --id <ID> \
  --path assets/models/visitors/_wip/<ID>.glb \
  --production

# integração no demo
cp assets/models/visitors/_wip/<ID>.glb assets/models/visitors/<ID>.glb
godot --headless --path . -- --demo --door-test
```

Se `blender` não estiver no PATH, use o caminho completo da instalação. Se o
template de export não servir para a sua cena, ajuste só o script de export,
nunca o contrato.

## Regras

- Um personagem por execução.
- Trabalhe em `assets/models/visitors/_wip/`; não sobrescreva o GLB final antes
  do aceite.
- Não faça commit, push ou PR sem pedido explícito.
- Não use asset/add-on de terceiros sem licença registrada. Se usar, anote autor,
  URL e licença no relatório e em `ATTRIBUTIONS.md`.
- Não invente `PASS`. Cite a saída real dos comandos.
- Não altere gameplay, história, corpo procedural ou o grade do jogo.
- Se o validador falhar duas vezes pelo mesmo motivo, pare e explique.

## Critérios de aceite

- [ ] `CH_<ID>`, `BODY_<ID>`, `RIG_<ID>` e raiz `<ID>` existem.
- [ ] Frente para -Y, pés em Z=0, escala aplicada.
- [ ] <= 15.000 triângulos, atlas <= 2k, face <= 1k.
- [ ] `portrait_face` presente e UVs válidas.
- [ ] 20-25 bones, pesos normalizados.
- [ ] `idle` e `talk` no GLB.
- [ ] DNA do `<ID>` mantém as medidas e o orçamento do spec.
- [ ] `validate_character_dna.py` = `SUCCESS`.
- [ ] `validate_blender_output.py --production` = `PASS`.
- [ ] `--demo --door-test` = `RESULT 0 failures`.
- [ ] Três renders em `docs/renders/characters/<ID>/`.
- [ ] Relatório preenchido e arquivos alterados listados.

## Relatório final

Use o bloco exato de `docs/BLENDER_AGENT_PLAYBOOK.md` (seção "Formato do
relatório"). Sem prosa antes, sem `PASS` inventado.

## Pare e pergunte se

- o Blender não abrir em headless;
- faltar retrato, ficha ou spec;
- a licença de base/textura/animação não estiver clara;
- o pedido for L3 sem base mesh;
- o modelo não couber no orçamento após duas tentativas;
- for necessário mexer em gameplay, história ou no corpo procedural.
