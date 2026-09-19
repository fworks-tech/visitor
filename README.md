# Visitor (Dead Hours: Visitor)

A 2D mobile narrative horror game in Godot 4.x. For seven nights, someone knocks on your door. You inspect them for signs of infection and decide: let them in, turn them away, or eliminate them. Some of the infected look almost human. Almost.

> Papers, Please × "No, I'm not a Human" × the Mandela Catalogue — a fate-arbiter game where the horror is in the *almost right*.

## The Premise

The outbreak started six days ago. You're holed up in your apartment with limited supplies. Every night, survivors knock — desperate, cold, convincing. Some carry the infection, and in its early stages it mimics humanity perfectly: the right words, the right tears, the wrong details.

You have three choices at every door:

- **LET IN** — gain an ally, a drain on resources, or a threat that turns inside your walls days later
- **TURN AWAY** — stay safe tonight, carry the scream you heard walk away
- **ELIMINATE** — certain, final, and it changes what you are

Trust and corruption track who you're becoming. After seven nights, the game ends — one of seven endings, depending on who you let in, who you turned away, and what you're willing to live with.

## Key Features

- **Uncanny analog-horror art** — hand-drawn portraits through a rasterizer: almost-photographic, subtly wrong. Green monochrome UI, VHS/CRT distortion.
- **Sign-based inspection** — spend limited action points on physical checks (wounds, pallor, movement) and behavioral questions (story consistency, emotional reactions). No single sign is proof. Judgment is.
- **Delayed consequences** — the infected don't reveal themselves at the door. A wrong LET IN turns days later, inside.
- **Resource pressure** — survivors inside eat and drink. Generosity has a cost.
- **Silence-first audio** — no gameplay music. CRT hum, knocks, and what you hear through the door.

## Tech

- **Engine:** Godot 4.x (GDScript), 11 autoload singletons
- **Data-driven:** visitors, signs, story nights, and endings live in JSON (`assets/data/`)
- **Platform:** Android + iOS, portrait, touch-first

## Project Structure

See [AGENTS.md](AGENTS.md) for the complete architecture map and development conventions.

Quick orientation:

| Path | What |
|------|------|
| `autoload/` | GameManager (state machine, trust/corruption), VisitorManager (queue + decisions), SignsManager, ResourceSystem, ConsequenceSystem, SaveManager, AudioManager, SceneManager, SettingsManager, StoryManager, FlagsManager |
| `scenes/gameplay/` | `InspectionScene` (the core loop), `DayPhaseScene` (mornings) |
| `assets/data/visitors.json` | All 20 visitors — backstories, dialogue, signs, outcomes |
| `assets/data/story.json` | 7-night arc, key events, 7 endings |
| `shaders/` | CRT scanlines, VHS tracking, glitch, green tint |
| `docs/AUDIO_DIRECTION.md` | The silence-first soundscape spec |
| `docs/PORTRAIT_PROMPTS.md` | How the uncanny portraits are generated |

## Running It

```bash
# Open visitor/ in Godot 4.x → F5
# Splash → MainMenu → New Game → Night 1 begins with a knock
```

## The Seven Endings

Survive all seven nights and the epilogue is decided by your accumulated trust, corruption, and who's still breathing inside your walls: the Gatekeeper, the Pariah, the Executioner, the Hermit, the Cure, the Infected, the Exile.

---

**License:** Proprietary — All rights reserved.
**By:** Fabio Ritzel Borges
