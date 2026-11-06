# Geração e customização de personagens: o que é real, o que dá precisão

Pesquisa aplicada ao *Visitor*, usando *Fears to Fathom* como referência visual e
os padrões de avatar que existem hoje. A pergunta central: dá para ter um sistema
de dados que gere personagens humanos com precisão, em vez de depender de
improviso ou de uma IA que "inventa" um rosto?

Resposta curta: **sim para um sistema de montagem e validação; não para gerar um
humano fotorrealista do zero por código**. Criadores de personagem não esculpem
um humano novo a cada clique. Eles combinam uma base autoral, morfismos,
peças modulares, texturas e um rig padronizado. A precisão vem das restrições,
não do código sozinho.

## 1. O que o visual de Fears to Fathom está fazendo

A imagem de referência mostra um restaurante low-poly com personagens de corpo
simples e rostos fotorrealistas. A discussão pública sobre esses modelos os
descreve como "muito simples e low poly, com rostos semirrealistas", e nota que
eles aparecem em vários jogos, o que sugere um pipeline de asset reutilizável,
não um gerador procedural de humanos.

O ponto útil para o *Visitor*:

- o **rosto carrega a identidade**;
- o **corpo low-poly carrega silhueta, roupa e função**;
- a **textura facial** faz o trabalho pesado de realismo;
- o custo de geometria e rig fica baixo, o que importa para mobile;
- o resultado é um híbrido estilizado, não um humano 3D completo.

Isso é exatamente a direção do nosso blockout atual: corpo de caixas com um card
de retrato. O blockout já prova o enquadramento. O próximo salto não é "gerar um
humano por código"; é melhorar o corpo, a roupa, o rig e a apresentação do rosto.

Não há evidência pública de que *Fears to Fathom* gere corpos humanos por um
algoritmo. O que se vê é compatível com um asset híbrido autoral, possivelmente
reutilizado entre episódios. Trate a referência como **direção de arte**, não
como prova de um gerador.

## 2. Como um criador de personagem funciona de verdade

Todo criador sério tem as mesmas camadas:

| Camada | O que guarda | O que o jogador muda |
|---|---|---|
| Base mesh | topologia única, proporções canônicas | quase nada diretamente |
| Morfismos | blendshapes de corpo e rosto | altura, ombros, nariz, mandíbula |
| Peças modulares | cabelo, roupa, sapatos, acessórios | estilo e combinação |
| Materiais | atlas, máscaras, paletas | cor de pele, cabelo, tecido |
| Rig | esqueleto humanoide e pesos | não aparece na UI |
| Dados | JSON com sliders, ids e cores | tudo acima, de forma persistente |

O "código que gera o personagem" é um **assembler**: ele lê o DNA, aplica
morfismos, troca malhas, ajusta materiais e entrega o resultado ao rig. A
geometria já existe. O que o código faz é combinar e validar.

Por isso a aparência é previsível: todos os personagens compartilham a mesma
topologia, os mesmos landmarks e as mesmas faixas de morfismo. Sem essa base
comum, cada modelo vira um problema novo de rig, roupa e colisão.

## 3. O que "precisão" significa nesse contexto

Precisão não é "fotorrealismo perfeito". É **resultado previsível e verificável**:

1. **Medidas contratuais:** altura, ombros, cabeça, comprimento de braço e perna.
2. **Base canônica:** uma malha base por tipo de corpo, não uma nova por ator.
3. **Landmarks:** olhos, nariz, boca, orelhas e queixo em posições normalizadas.
4. **Faixas de morfismo:** cada slider tem mínimo, máximo e efeito documentado.
5. **Roupa compatível:** modelada sobre a mesma base ou com transferência de
   skinning; nada de roupa "flutuando" em outra topologia.
6. **Rig padronizado:** nomes de bones e hierarquia iguais em todos os atores.
7. **Seed determinística:** mesmo DNA e mesma versão produzem o mesmo asset.
8. **Validação automática:** schema, orçamento de triângulos, UVs, materiais,
   bones, animações e bounds.
9. **Revisão visual:** renders de frente, 3/4 e perfil contra o retrato.
10. **Licença e proveniência:** cada base, textura e animação tem origem.

O que não dá para garantir com precisão hoje:

- rosto idêntico a uma pessoa a partir de uma única foto, sem escaneamento;
- malha humana de qualidade a partir de texto, com topologia e rig consistentes;
- licença clara em modelos gerados por serviços que não documentam a base;
- animação facial convincente sem blendshapes ou captura.

IA image-to-3D (Tripo, Meshy e similares) serve para **conceito e base**, não para
produção repetível. O topology costuma vir irregular, o rig não existe e a
consistência entre personagens se perde.

## 4. Padrões e ferramentas que valem usar

### glTF 2.0

O formato de transporte do nosso pipeline. Suporta malhas, skins, morph targets e
animações, e o Godot 4 importa nativamente. É o que já usamos nos GLBs do demo.
Especificação: https://registry.khronos.org/glTF/

### VRM 1.0

Extensão de glTF para avatares humanos: mapeamento de bones humanoides,
expressões e primavera de cabelo/roupa. Útil se o projeto tiver um criador de
avatar ou precisar trocar animações entre personagens. No Godot, o addon
`godot-vrm` importa VRM 1.0.

- Especificação: https://github.com/vrm-c/vrm-specification
- Addon Godot: https://github.com/V-Sekai/godot-vrm

### Mixamo / Unity Humanoid

Mixamo fornece animações e um rig humanoide reconhecível. Unity Humanoid é uma
referência de mapeamento de bones; Godot 4 tem retargeting de esqueleto 3D, mas
exige nomes/hierarquia consistentes e T-pose.

- Mixamo: https://www.mixamo.com/
- Retargeting no Godot: https://docs.godotengine.org/en/4.4/tutorials/assets_pipeline/retargeting_3d_skeletons.html

### MakeHuman / MPFB

Base humana paramétrica, open source, com morfismos de corpo e rosto e rig. É a
opção mais próxima de "gerar um humano" sem custo de licença de motor. Verifique
a licença de cada asset pack antes de usar em build comercial; a base e os
assets têm condições próprias.

- Documentação: https://static.makehumancommunity.org/mpfb/docs/characters/index.html

### Character Creator 4

Pipeline comercial de personagem realista, com morphs, roupas e exportação. Bom
se houver orçamento e um artista; não é uma dependência de runtime.

- https://www.reallusion.com/character-creator/

### MetaHuman

Altíssima fidelidade, mas centrado no Unreal Engine e pesado para mobile/Godot.
Serve como referência de qualidade, não como pipeline do *Visitor*.

- https://www.unrealengine.com/en-US/metahuman

### Avatar SDK / MetaPerson

Geração de avatar a partir de selfie, com SDK e exportação. O Ready Player Me foi
descontinuado em 2026, então não é uma aposta de longo prazo. Serviços de selfie
têm custo, privacidade e licença a resolver.

- https://avatarsdk.com/
- https://avatarsdk.com/blog/2026/01/15/switch-from-ready-player-me-to-avatar-sdk-fast-familiar-production-ready/

### Blender + Python

O denominador comum. É onde a base é limpa, o rig é montado, as roupas são
ajustadas e o GLB é exportado. O nosso playbook já assume Blender headless e
validação fora do Blender.

- https://www.blender.org/

## 5. O caminho certo para o Visitor

### Fase A: híbrido L2, estilo Fears to Fathom

- corpo low-poly autoral, 8k a 15k triângulos;
- rosto em card de retrato, ou cabeça simples com textura facial;
- 3 a 5 bases de corpo (slim, lean, average, heavy, broad);
- roupas modulares encaixadas nas mesmas bases;
- rig humanoide de 20 a 25 bones;
- `idle` e `talk`;
- validação de contrato e renders.

Isso entrega 20 visitantes com custo controlado e mantém a estética do jogo.

### Fase B: rostos 3D para personagens herói

Só para quem precisa de close-up e expressão: cabeça esculpida, blendshapes
ARKit/FACS, textura 2k, olhos e dentes separados. É caro e deve ser exceção.

### Fase C: criador de personagem no jogo

Se o *Visitor* um dia tiver criação de personagem, o mesmo DNA pode ser dirigido
pela UI: sliders de corpo, seleção de cabelo/roupa, cor de pele e voz. O runtime
não precisa "gerar" geometria; ele monta peças e aplica morphs. Essa é a
arquitetura que jogos com customização usam.

Não construa a Fase C agora. O jogo tem um elenco fixo; o valor imediato está em
padronizar os 20 atores e produzir os modelos.

## 6. Character DNA v1 do Visitor

O arquivo `tools/characters/character_specs.json` agora carrega um objeto `dna`
por personagem. O schema está em
`tools/characters/character_dna.schema.json`; o validador é
`tools/characters/validate_character_dna.py`.

Campos:

| Campo | Para que serve |
|---|---|
| `id`, `name`, `portrait`, `seed` | identidade e determinismo |
| `body.height_m`, `shoulder_m`, `build`, `head_scale`, `limb_length`, `posture` | proporção e silhueta |
| `face.mode`, `source`, `uv_band`, `expression`, `blendshapes` | card, malha ou scan; região do retrato |
| `hair.style`, `color`, `coverage` | cabelo e chapéu |
| `outfit.layers[].slot/asset/color/fit/material` | roupa modular |
| `rig.profile`, `mixamo`, `vrm`, `max_influences` | compatibilidade de animação |
| `animations` | `idle`, `talk` |
| `assets.model`, `textures` | arquivos finais |
| `lod[]` | orçamento por distância |
| `validation.level`, `max_tris`, `max_materials`, `require_rig`, `require_animations` | gate de qualidade |
| `license` | proveniência |

O DNA atual está em **L1** (blockout). O alvo do OpenCode/Blender é **L2**, com
`require_rig` e `require_animations` verdadeiros, no máximo 15k triângulos e 4
materiais.

Exemplo resumido:

```json
{
  "id": "v001",
  "dna": {
    "seed": 1001,
    "body": {"height_m": 1.78, "shoulder_m": 0.58, "build": "lean"},
    "face": {"mode": "card", "source": "res://.../visitor_01_marcus_vane.png"},
    "outfit": {"layers": [{"slot": "coat", "asset": "generated_coat"}]},
    "rig": {"profile": "humanoid_20", "mixamo": true, "vrm": true},
    "animations": ["idle", "talk"],
    "validation": {"level": "L1", "max_tris": 15000, "max_materials": 4}
  }
}
```

## 7. Como garantir precisão no handoff

O playbook de Blender agora deve ser lido junto com o DNA:

1. o agente abre o `character_specs.json` e trava id, seed, altura, ombros,
   cabelo, roupa e rig;
2. constrói ou ajusta a malha dentro dessas faixas;
3. exporta em `_wip`;
4. roda `validate_character_dna.py` e `validate_blender_output.py --production`;
5. só promove o GLB depois de `PASS`;
6. renderiza frente, 3/4 e perfil para revisão humana;
7. registra licença e proveniência.

O validador de DNA não julga beleza. Ele impede que o agente mude medidas,
esqueça o rig, use material demais ou invente um asset sem caminho. A aprovação
visual continua humana.

## 8. Referências

- Discussão sobre os modelos low-poly com rostos semirrealistas:
  https://www.reddit.com/r/gamedev/comments/1xdrrhj/character_models_from_fears_to_fathom_etc/
- Fears to Fathom, criador Mukul Negi (Rayll):
  https://fearstofathom.wiki.gg/wiki/Rayll_Studios
- glTF 2.0:
  https://registry.khronos.org/glTF/
- VRM 1.0:
  https://github.com/vrm-c/vrm-specification
- Godot VRM:
  https://github.com/V-Sekai/godot-vrm
- Retargeting no Godot 4:
  https://docs.godotengine.org/en/4.4/tutorials/assets_pipeline/retargeting_3d_skeletons.html
- Mixamo:
  https://www.mixamo.com/
- MakeHuman/MPFB:
  https://static.makehumancommunity.org/mpfb/docs/characters/index.html
- Character Creator:
  https://www.reallusion.com/character-creator/
- MetaHuman:
  https://www.unrealengine.com/en-US/metahuman
- Avatar SDK:
  https://avatarsdk.com/
- ARKit blendshapes:
  https://developer.apple.com/documentation/arkit/arfaceanchor/blendshapelocation

## 9. Limites e honestidade

- Um agente de código consegue L2; não consegue L3 hero sozinho.
- A semelhança com o retrato é limitada pelo card e pela iluminação; para
  likeness real, é preciso escultura/scan e revisão.
- IA generativa de malha não é determinística nem necessariamente licenciável.
- O visual de *Fears to Fathom* é alcançável com o híbrido, mas copiar
  personagens, texturas ou assets do jogo não é.
- O pipeline precisa de um artista humano para aprovar rosto, silhueta e
  proporção; o validador garante contrato, não direção de arte.
