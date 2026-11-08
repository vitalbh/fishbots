# Community packs

The catalog the app shows in **Tema → Explorar pacotes…** is `community/index.json`, built from the packs in
`packs/examples/` and `community/packs/`. Anyone can send a pack: it's a pull request adding a folder.

## Sending a pack

1. Make it (see [docs/packs.md](../docs/packs.md)): `bin/fishbots pack new my-pack`, draw, preview, repeat.
2. Fill in the catalog's metadata in `pack.json`:

   ```json
   "id": "my-pack", "name": "Meu pacote", "names": {"en": "My pack"},
   "version": "1.0", "author": "Your name", "license": "MIT",
   "description": "Uma frase sobre o que ele traz.", "descriptions": {"en": "One sentence on what it brings."},
   "homepage": "https://…", "minApp": "0.1"
   ```

   `names` and `descriptions` (and the same `names` on each theme, fish, piece of scenery, creature and style) are
   what people see when the app is in that language.
3. Make its cover: `bin/fishbots pack cover my-pack` (cover.png: its theme and first drawings).
4. Check it like the CI will: `bin/fishbots pack check my-pack --catalog`.
5. Put the folder in `community/packs/my-pack/`, run `python3 scripts/catalog.py`, and open a pull request with both.

To publish a new version, raise `version`: people who have it installed see "Update to v…".

## What gets accepted

- Your own work, under a license that lets others use it (MIT, CC BY, CC0…), stated in `license`.
- No brands, logos or characters you don't own.
- Light enough to draw (the app pauses packs that slow the aquarium down) and good at real size: look at
  `preview-small.png`.
- Only pack files: `pack.json`, `.metal`, `cover.png`, `.md`, `.txt`. Nothing runs on anyone's Mac.

The CI ([.github/workflows/packs.yml](../.github/workflows/packs.yml)) checks each pack's metadata and cover, compiles
its drawings against the app's shader and makes sure the index is up to date.
