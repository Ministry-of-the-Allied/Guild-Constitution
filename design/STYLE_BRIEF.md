# Style Brief — "The Royal Seal"

The visual language for the Ministry of the Allied add-on. Every window, button and pop-up follows this brief.

## The idea

The add-on should feel like **the official instruments of the Stormwind court**: state papers on heavy parchment, held in royal blue leather and gold, closed with wax. Opening it should feel like stepping into the Keep, not opening a settings menu.

Three materials do almost all the work:

| Material | Used for | Feel |
|---|---|---|
| **Royal blue leather / velvet** | The window frame, tab rail, headers | Deep, rich, slightly worn, with a soft (not sharp) grain and tooled gold lines |
| **Burnished gold** | Borders, trims, dividers, the crest, active states | Metallic: bright highlight, warm mid, brown shadow. Never flat yellow |
| **Parchment** | Every content page | Smooth warm vellum with very subtle mottling and darker, age-stained edges. No heavy grain: ink must stay easy to read |

**Wax** is the accent: seals mark anything official (casting a vote, Royal Assent, a party chamber, a herald notice).

## The frame (shared by every page)

- One window, around 1000 × 680 in game.
- An outer royal blue leather frame with a double gold rule, gold corner pieces and a riveted gold rim.
- **The Alliance crest sits in the top-left corner**, breaking out over the frame by about a third of its height. It's the mark of the whole add-on.
- The title plaque sits across the top: "MINISTRY OF THE ALLIED", with the page name underneath.
- A left-hand **tab rail** of six engraved tabs pressed in oxblood wax, with the same gradient and gloss as the official seal. The active tab is lit gold, as if gold leaf is catching the light, and carries the window's ornate border in miniature: double rule, stitching and jewelled filigree corners. Tab names always sit on one line; a count badge pins over the tab's right edge rather than squeezing the name.
- The content area is a parchment page inset into the frame, with a soft inner shadow.
- Sub-views within a page use **ribbon tabs** (silk ribbons with notched ends) across the top of the parchment.

## Colour

| Token | Hex | Use |
|---|---|---|
| Royal Blue (deep) | `#0E1F45` | Frame shadow, darkest leather |
| Royal Blue | `#1B3570` | Frame, headers, primary text on gold |
| Azure | `#3A63B8` | Highlights on blue, links on parchment |
| Gold shadow | `#6E4F17` | Engraving, gold edges |
| Gold | `#C9A24A` | Trims, rules, icons |
| Gold leaf | `#F3D98A` | Highlights, active states |
| Parchment | `#EFE2C2` | Page background |
| Vellum (aged) | `#D9C49A` | Page edges, cards |
| Ink | `#2A1F14` | Body text on parchment |
| Faded ink | `#5E4B33` | Secondary text (passes 4.5:1 on parchment) |

**Wax colours:**
- **Crown:** royal purple wax with a gold crown.
- **Silverhand:** argent (silver-white) wax with a blue hand.
- **Azeroth Exchange:** deep crimson wax with a gold coin-scale.
- **Neutral / official:** oxblood red.

**District colours** are each told apart by lightness as well as hue:
- **Old Quarter:** Iron Crimson `#8E2B22`
- **Arcane Ward:** Arcane Violet `#6B44A8`
- **Iron District:** Forge Bronze `#B0621C`
- **Cathedral Ward:** Holy Azure `#3D86C6`
- **Harbour Quarter:** Harbour Teal `#1F7A70`

## Type

- **Cinzel / Cinzel Decorative:** titles, plaques, tab labels and names of office. Roman inscriptional capitals, like carved stone in the Keep.
- **EB Garamond:** all reading text. Old-book serif, very readable at small sizes, with italics for quotes and decrees.
- Both are free (SIL Open Font License), so they can be **shipped inside the add-on** as real in-game fonts. The default game font, Friz Quadrata, is the fallback.

## Ornament

- **Filigree:** gold scrolling vines at corners and under titles, echoing the crest.
- **Dividers:** a thin gold rule with a centre lozenge.
- **Initials:** a drop cap on proclamations, in gold and blue.
- **Icons:** engraved line icons in gold (scroll, quill, scales, coin, lion, keep, ballot box). No emoji, no flat modern icons.

## Motion and sound (for the build)

- Pages turn with a quick parchment-slide.
- Casting a vote presses a wax seal down with a soft "thunk" plus the game's own sound.
- Herald pop-ups unroll from the top of the screen as a scroll, with a short fanfare from the game's sounds.
- Gold highlights catch the light with a slow sheen on hover.

## Rules

1. Gold is metallic, always as a gradient. Never flat yellow.
2. Text on parchment is ink, never pure black and never grey on beige below a 4.5:1 contrast ratio.
3. Every official act gets a seal.
4. One window, one page per subject (seven pages so far); related things go in sub-views, never new windows.
5. Nothing looks like a modern web app: no rounded pill buttons, no flat cards, no drop-shadow blobs.
