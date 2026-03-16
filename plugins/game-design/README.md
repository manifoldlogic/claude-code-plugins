# Game Design Plugin

Specialized game design consultant agents synthesized from the collective wisdom of 14 legendary game designers.

## Overview

This plugin provides 9 specialized agent personas that serve as game design consultants. Each agent synthesizes philosophies from multiple legendary designers, creating focused expertise in specific areas of game development.

Rather than imitating individual designers, these agents represent **design roles** informed by complementary perspectives:

| Agent | Focus | Source Designers |
|-------|-------|------------------|
| Core Mechanics Architect | Feel, rhythm, moment-to-moment gameplay | Miyamoto, Carmack, Jaffe, Koizumi |
| Audio-Experience Designer | Music, sound, rhythm integration | Fox, Rigopulos, Miyamoto |
| Player Psychology Guide | Motivation, emotion, difficulty curves | Miyamoto, Pardo, Rigopulos, Jaffe |
| Narrative-Mechanics Weaver | Story through gameplay, environmental storytelling | Fox, Urquhart, Nomura |
| Onboarding & Accessibility Sage | Tutorial-free teaching, inclusive design | Miyamoto, Koizumi, Rigopulos, Fox |
| Constraint Alchemist | Scope management, turning limits into features | Persson, Fox, Carmack |
| Spatial & Camera Advisor | Level layout, camera control, space design | Koizumi, Tezuka, Ward |
| Visual Identity Consultant | Art direction, character design, style cohesion | Nomura, Ishii, Miyamoto |
| Systems Designer | Emergent gameplay, progression loops | Hedlund, Persson, Pardo |

## Installation

```bash
# Add marketplace (if not already added)
/plugin marketplace add claude-code-plugins

# Install game-design plugin
/plugin install game-design@crewchief
```

After installation, restart Claude Code to activate the plugin.

## Agents

### Core Design Agents

| Agent | Description | Model |
|-------|-------------|-------|
| `core-mechanics-architect` | Design core interactions and moment-to-moment feel | Sonnet |
| `audio-experience-designer` | Integrate music and sound as core design elements | Sonnet |
| `player-psychology-guide` | Shape player motivation and emotional journey | Sonnet |
| `narrative-mechanics-weaver` | Connect story and gameplay into unified experience | Sonnet |

### Specialized Advisors

| Agent | Description | Model |
|-------|-------------|-------|
| `onboarding-sage` | Design intuitive teaching through play | Sonnet |
| `constraint-alchemist` | Transform limitations into creative advantages | Sonnet |
| `spatial-camera-advisor` | Master level layout and camera systems | Sonnet |
| `visual-identity-consultant` | Establish art direction and visual cohesion | Sonnet |
| `systems-designer` | Architect emergent systems and progression | Sonnet |

## Usage Examples

### When to Consult Each Agent

**Core Mechanics Architect:**
- "How should the primary interaction feel in a music puzzle game?"
- "Players aren't feeling satisfaction from the core loop"
- "The controls feel floaty/delayed/unresponsive"

**Audio-Experience Designer:**
- "How can music drive gameplay rather than just accompany it?"
- "When should sound effects reinforce vs. contrast the music?"
- "The audio feels disconnected from the actions"

**Player Psychology Guide:**
- "Players are quitting at this difficulty spike"
- "How do I frame this challenge to feel fair, not frustrating?"
- "What should the reward loop feel like for a 2-hour puzzle game?"

**Narrative-Mechanics Weaver:**
- "How can the puzzle mechanics reflect the story themes?"
- "The narrative feels bolted-on to the gameplay"
- "Can the environment tell the backstory?"

**Onboarding & Accessibility Sage:**
- "How do I teach this mechanic without a tutorial?"
- "Players aren't discovering the secondary abilities"
- "How can I make this accessible without making it easy?"

**Constraint Alchemist:**
- "I only have 6 months and one programmer"
- "Should I cut this feature or simplify it?"
- "How do I scope for a solo developer?"

**Spatial & Camera Advisor:**
- "The 3D camera feels disorienting in tight spaces"
- "How should the level guide players toward secrets?"
- "Open world vs. linear level design for this mechanic?"

**Visual Identity Consultant:**
- "How do I establish a cohesive art style on a small budget?"
- "The character designs don't feel memorable"
- "How do I use color to reinforce game state?"

**Systems Designer:**
- "How should the upgrade/progression system work?"
- "Players are breaking the economy"
- "How much emergent behavior is too much?"

### Multi-Agent Consultations

For complex design problems, multiple agents can provide complementary perspectives:

- **Core Mechanics + Audio**: When core action involves rhythm
- **Player Psychology + Onboarding**: For difficulty curve design
- **Narrative + Visual Identity**: For thematic cohesion
- **Constraints + Systems**: For scoping complex features

## Source Designers

These agents synthesize wisdom from 14 game design masters:

| Designer | Key Works | Core Contribution |
|----------|-----------|-------------------|
| Shigeru Miyamoto | Mario, Zelda, Pikmin | Core feel, accessibility |
| Markus Persson | Minecraft | Emergent systems, scope |
| Takashi Tezuka | Mario, Animal Crossing | World-building, level design |
| Toby Fox | Undertale, Deltarune | Subversion, music-narrative |
| Koichi Ishii | Final Fantasy, Mana | Visual identity |
| Feargus Urquhart | Baldur's Gate, Fallout | Narrative depth |
| Tetsuya Nomura | FF VII, Kingdom Hearts | Character design |
| Alex Ward | Burnout Paradise | Visceral feel, open world |
| David Jaffe | God of War | Emotion through interaction |
| Stieg Hedlund | Diablo II | Systems, loot, progression |
| Alex Rigopulos | Guitar Hero, Rock Band | Music games, accessibility |
| Rob Pardo | StarCraft, WoW | Balance, "easy/impossible" |
| Yoshiaki Koizumi | Mario Galaxy | Camera, spatial design |
| John Carmack | Doom, Quake | Tech serving gameplay |

## Philosophy

These agents embody key synthesized principles:

1. **Gameplay over graphics or story** - The moment-to-moment must be compelling
2. **Draw from life, not other games** - Originality comes from observation
3. **Iterate constantly** - Feel evolves through testing
4. **Embrace constraints** - Limits breed creativity
5. **Technology serves ideas** - Not the other way around
6. **Trust your instincts** - Playtest validates, but vision leads

## Links

- [Repository](https://github.com/manifoldlogic/claude-code-plugins)
