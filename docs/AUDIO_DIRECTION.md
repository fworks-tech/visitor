# Visitor — Audio Direction

> Silence is the primary sound. Sound is used for impact, not atmosphere.

---

## Philosophy

Unlike Dead Hours (which uses continuous ambient tracks and music), Visitor's audio design is built around **silence and absence**. The player should feel alone, listening for sounds through a door. When sound does come, it hits hard because the silence preceded it.

The soundscape draws from:
- **Analog horror** — VHS hum, CRT whine, tape hiss
- **Medical equipment** — flat drones, monitor beeps, the clinical sound of a waiting room
- **Surveillance** — the audio quality of a security camera feed or intercom

---

## Bus Layout

```
Master (0 dB)
├── Music (-8 dB)      — Rare. Only for menu, endings, and key story moments.
├── Ambient (-12 dB)   — Low drone, room tone, environmental silence
├── Voice (-3 dB)      — Visitor dialogue, distorted as if through a door
├── SFX (0 dB)         — Knocks, clicks, impacts, glitches
└── CRT (-18 dB)       — Constant low VHS/CRT hum, always present
```

---

## Sound Design List

### Ambient (always present, very low)
| File | Purpose | Description |
|------|---------|-------------|
| `ambient_room_tone.ogg` | Default silence | Near-silent room tone. Faint hum of the apartment. Occasional creak. 30s loop. |
| `ambient_crt_hum.ogg` | CRT overlay | Constant low 60Hz hum + tape hiss. Always playing on the CRT bus. |
| `ambient_night_drone.ogg` | Night tension | Very low sub-bass drone (~40Hz). Builds imperceptibly as the night progresses. |
| `ambient_distant_city.ogg` | World context | Faint distant sounds — sirens, wind, occasional far-off scream. Very quiet. |

### SFX — Knocks (the signature sounds)
| File | Trigger | Description |
|------|---------|-------------|
| `sfx_knock_1.ogg` | Standard visitor | Three firm knocks. Wood on wood. Close mic. |
| `sfx_knock_2.ogg` | Desperate visitor | Rapid, frantic knocking. Five or six knocks in quick succession. |
| `sfx_knock_3.ogg` | Calm visitor | Two slow, deliberate knocks. Unnervingly patient. |
| `sfx_knock_4.ogg` | Child visitor | Small, quiet knocks. Barely audible. |
| `sfx_knock_5.ogg` | Group arrival | Multiple knock patterns overlapping. Chaotic. |
| `sfx_knock_6.ogg` | Return visitor | The same knock pattern as before — recognition trigger. |

### SFX — UI
| File | Trigger | Description |
|------|---------|-------------|
| `sfx_ui_click.ogg` | Button press | Short CRT terminal click. Mechanical, cold. |
| `sfx_ui_hover.ogg` | Button hover | Faint electronic buzz, barely perceptible. |
| `sfx_reveal_sign.ogg` | Sign revealed | Short data-processing sound. Like a medical scan completing. |
| `sfx_decision_let_in.ogg` | Let In | Door unlock + creak. Heavy, final. |
| `sfx_decision_turn_away.ogg` | Turn Away | Deadbolt sliding shut. Cold, metallic. |
| `sfx_decision_eliminate.ogg` | Eliminate | Gunshot. Loud, sudden, no reverberation. Silence after. |
| `sfx_day_transition.ogg` | Night → Day | Birds. The only "natural" sound in the game. Brief, then cut. |

### SFX — Glitch
| File | Trigger | Description |
|------|---------|-------------|
| `sfx_glitch_1.ogg` | Mild VHS glitch | 0.5s tracking error sound. |
| `sfx_glitch_2.ogg` | Moderate glitch | 1s digital corruption + static burst. |
| `sfx_glitch_3.ogg` | Severe glitch | 2s total signal breakdown. Accompanies worst infection reveals. |
| `sfx_power_down.ogg` | Game over / shutdown | CRT power-off sound. Descending tone, then silence. |

### Voice
| File | Character | Description |
|------|-----------|-------------|
| `voice_*.ogg` | All visitors | All voice lines processed through a "through-the-door" filter: muffled high frequencies, slight reverb, occasional static. The voice should sound CLOSE but SEPARATED — like the person is right there but you can't reach them. |

### Music (used sparingly)
| File | Trigger | Description |
|------|---------|-------------|
| `music_menu.ogg` | Main menu | Slow, sparse piano notes over CRT hum. Unsettling. |
| `music_ending_gatekeeper.ogg` | Best ending | Warm, almost hopeful strings. Brief moment of peace. |
| `music_ending_pariah.ogg` | Worst ending | Dissonant drone, no resolution. Cut abruptly. |
| `music_ending_executioner.ogg` | Corruption ending | Industrial grinding, metal on metal. |
| `music_ending_hermit.ogg` | Alone ending | Single piano note repeating, slowing, stopping. |
| `music_ending_cure.ogg` | Cure ending | Soft cello, fragile hope. Fades to static. |
| `music_ending_infected.ogg` | Self-infected | Heartbeat slowing to flatline. |
| `music_ending_exile.ogg` | Voted out | Distant voices arguing, can't make out words. Door slam. |

---

## Audio Implementation Notes

### The "Through the Door" Filter
All visitor voice lines should use a Godot AudioBus effect chain:
1. **LowpassFilter** (cutoff ~800Hz) — muffles the voice
2. **Reverb** (small room, wet 0.3) — adds enclosed space feel
3. **Distortion** (drive 0.2) — slight analog degradation

### Dynamic Silence
- The `ambient_night_drone` volume should increase by 1 dB per visitor encountered
- After a decision is made, ALL ambient sound drops to silence for 2 seconds before resuming
- The CRT hum never stops — it's the only constant. It's the sound of the system watching.

### Glitch Audio Sync
- `sfx_glitch_*` should fire in sync with the VHS shader's `trigger_glitch()` calls
- Intensity scales: mild glitch = 0.5s sound + 0.5s visual, severe = 2s sound + 2s visual

### What NOT to do
- No background music during gameplay (only menu and endings)
- No jump scare stingers — the horror is in the silence and the decision
- No zombie groans or monster sounds — the visitors look human and should sound human (mostly)
- No ambient music swells during inspection — tension comes from the player's own doubt

---

## Sourcing Approach

For a solo indie dev:
1. **Synthesize** the CRT hum, glitch sounds, and UI clicks using free tools (Audacity, FL Studio demo, or Godot's AudioStreamGenerator)
2. **Record** knock patterns on your own door — just need a phone mic and a quiet room
3. **Foley** the door sounds (unlock, deadbolt, creak) from free sound libraries (Freesound.org, Pixabay Audio)
4. **Voice lines**: Use TTS (ElevenLabs or Coqui) with the through-the-door filter applied in post. Alternatively, record yourself and pitch/process to sound different per character.
5. **Music**: Minimal piano/cello can be sourced from royalty-free libraries or AI-generated (AIVA, Suno) with heavy editing
