# The sound

**By default, silence: sound only plays when something changes.** That includes arriving, finishing (a discreet knock-knock on the glass), starting to wait for you (the question and the tap on the glass, with a reminder every 2.5 min) and errors. Working makes no sound, only movement. The **A** key (or the menu) turns on **ambient music**, a piece generated with the ideas of the Jardim de Chuva generator (`Sources/Fishbots/Generator.swift`):
- **4 calm styles:** lullaby (kalimba music box), ambient (breath and pad), lo-fi (swung electric piano) and bossa (3+3+2). Each has the garden's progressions, tempo, scale and timbres.
- **Real phrasing, like the garden's `genPhrase`:** the motif of the singing session becomes the "A", and the phrase takes the forms AA'AB, ABAB', ABAC and AABA, with a question in the middle and an answer resolving on a chord tone. The scale adapts to the chord (Fm brings in A♭).
- **One voice at a time:** sessions take turns singing, with breathing room (sometimes nobody sings).
- **Energy:** the more sessions working, the more movement (lullaby → ambient → lo-fi → bossa). The piece changes every ~2–3 min, into a neighboring key, like the garden's radio. The piece's name appears in the footer.

The table below describes each state's signals. The note on each tool use is optional and off by default.

- **Each thing has a motif:** a short, fixed phrase. The motif is chosen from the name (source + label), stored and never changes, so you recognize it by ear.
- **The state changes the motif's "clothes", never its shape:**

| state | fish | sound |
|---|---|---|
| born | drops from above | the motif quickly, rising |
| busy | swims in the middle and up high | the motif every 2 bars; each tool is a short note; the filter pump pulses |
| idle / ok | sinks to the bottom, dimmer | the motif low and quiet every 8 bars |
| waiting | comes to the front of the glass, bigger, glowing | only the start of the motif (a question) and **taps on the glass** |
| error | red, trembling | the motif with the last note a semitone up, dissonant until fixed |
| alert | amber | like error, more spaced out |
| done | comes close to the glass | a discreet knock-knock on the glass, tuned to the motif's first two notes |

- **A session you're already looking at calls without sound:** when its terminal is in front with the focus on its pane (Rex, Herdr, iTerm, or tmux's active pane), waiting and errors skip the motif, the taps and the question read aloud. The fish still comes to the glass and changes color, and the notification still arrives. In Rex, a pane counts as focused in its session even when the Rex window shows another session. Ghostty, Terminal and the rest always call.
- The jellyfish plays the chords (D pentatonic, changing every 2 bars). Events become food and an arpeggio. A full disk makes the water cloudy and the sound muffled.

## Visualizers

They sit behind the fish and react to each note (at the position and in the color of whoever played it), to the chord, the energy and events. They're aquatic versions of the Jardim de Chuva visualizers:
- 🌟 **plankton:** dots that light up around whoever plays;
- ✨ **underwater aurora:** each piece draws a combination, and the footer shows which one came out. The options:
  - **shape:** vertical curtains or wavy bands up high; by day, it becomes golden sunbeams;
  - **color:** one or two colors, from the style's palette (lullaby lilac and pink, ambient aqua green, lo-fi amber, bossa turquoise) pulled by the chord's color;
  - **breathing:** swells on each chord and fades;
  - **following the singer:** the nearest curtain glides over to the fish that played;
  - **sparkles:** twinkling dots inside the veil;
  - it always dances faster with energy, and is stronger at night;
- 🌊 **living surface:** each note makes a wave on the surface;
- 🎼 **bubble score:** the melody moves right to left, each bubble at the note's height;
- 🌌 **plankton constellation:** each fish's notes linked by thin lines;
- 🌿 **dancing seaweed:** each chord sweeps across the seaweed like a wave, each note kicks the blades near whoever played and lights their tips;
- 🪼 **jellyfish of the harmony:** each chord lets out a jellyfish in its color, which pulses with the notes and drifts up;
- 📡 **sonar:** rings of sound from whoever played, wide and slow for low notes, small and quick for high ones, with an echo;
- ⛈️ **storm** (the deep sea's): lightning strikes the surface on chords, the tank flashes with the music, and heavy music sets a current running;
- 🐟 **school of light:** a school of little bioluminescent fish follows the melody, each note pulling it to its pitch's height and toward whoever played, each chord changing its color, a trail of light behind; a click scatters it;
- 🎆 **light fireworks:** on each event, in any mode, a burst of dots opens in the water (slowed by it) and rises, fading.

The **aurora stays in the background** (default; turn off in Visualizador → Aurora de fundo), and the chosen visualizer appears on top of it. The **Visualizador** menu lets you choose automatic by style (lullaby → plankton, ambient → constellation, lo-fi → score, bossa → surface), random (changes with each piece), off or a fixed one. In the screen saver, since there's no music, they react when fish change state.
