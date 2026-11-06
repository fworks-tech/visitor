# Visitor documentation

Index of the project documents. Start with the root [README](../README.md) for
the game overview and commands, then use this page to go deeper.

## Engineering and conventions

- [AGENTS.md](../AGENTS.md): architecture map, conventions, house rules and
  agent instructions
- [HOUSE_SYSTEM.md](HOUSE_SYSTEM.md): single-source floor plan, room lookup,
  stairs and collision
- [APERTURE_VIEWS.md](APERTURE_VIEWS.md): doorway, peephole, window, crack and
  hatch composition
- [ENGINE_EVALUATION.md](ENGINE_EVALUATION.md): why the project stays on Godot 4.x
- [adr/](adr/): architecture decision records

## Art and audio

- [ART_DIRECTION_ANALOG.md](ART_DIRECTION_ANALOG.md): analog-horror target,
  palette and lighting
- [STYLE_PROMPTS.md](STYLE_PROMPTS.md): image-generation style prompts
- [PORTRAIT_PROMPTS.md](PORTRAIT_PROMPTS.md): visitor portrait direction
- [AUDIO_DIRECTION.md](AUDIO_DIRECTION.md): five-bus audio plan and
  silence-first rules

## Characters

- [CHARACTER_PIPELINE.md](CHARACTER_PIPELINE.md): blockout to L2/L3, budgets,
  Godot integration and QA gates
- [CHARACTER_GENERATION_RESEARCH.md](CHARACTER_GENERATION_RESEARCH.md): how
  character creators work, standards, precision and the Character DNA rationale
- [BLENDER_AGENT_PLAYBOOK.md](BLENDER_AGENT_PLAYBOOK.md): rules and acceptance
  for OpenCode or a Blender artist
- [../tools/characters/README.md](../tools/characters/README.md): commands,
  DNA schema, validator and export template
- [../tools/characters/OPENCODE_TASK.md](../tools/characters/OPENCODE_TASK.md):
  copy-paste task for one character

## Demo and QA

- [DEMO.md](DEMO.md): two-night demo scope, cut list and gates
- [QA_LOG.md](QA_LOG.md): test history, sign-off template and open items
- [PLAYTEST_SCRIPT.md](PLAYTEST_SCRIPT.md): structured playtest prompts
- [DEVICE_QA.md](DEVICE_QA.md): Android and iOS checks

## Production

- [EXPORT_GUIDE.md](EXPORT_GUIDE.md): Godot export settings
- [SIGNING_GUIDE.md](SIGNING_GUIDE.md): Android signing and iOS provisioning
- [STORE_LISTING.md](STORE_LISTING.md): store copy and asset checklist
- [SHARED_BRANDING.md](SHARED_BRANDING.md): DEEPTALES brand rules shared with
  the studio

## Operations

- [ci/contract-workflow.yml](ci/contract-workflow.yml): copy to
  `.github/workflows/contract.yml` to enable the data gate
