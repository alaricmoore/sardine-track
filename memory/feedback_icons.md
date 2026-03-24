---
name: No standard emojis - use Emoji One monotone
description: User dislikes standard emojis (confusing, "simpsons characters"). Use Emoji One Monotone SVG icons instead, or plain text/unicode symbols.
type: feedback
---

Do not use standard emojis in the app. User is autistic and finds many emoji meanings confusing (happy-crying face, upside-down smile, etc.), plus dislikes the cartoon aesthetic.

**Why:** Standard emojis are ambiguous and visually jarring in the app's design. The Emoji One Monotone collection (CC BY 4.0, https://icones.js.org/collection/emojione-monotone) is clean, monochrome, and readable.

**How to apply:**
- For HTML contexts (badges, labels, cards): use inline SVGs from Emoji One Monotone, colored with CSS variables to match the theme
- For text-only contexts (chart tooltips, notifications): use plain text or simple unicode symbols (▲, ●, +) instead of emoji
- Install: `pnpm add -D @iconify-json/emojione-monotone`
- Never add standard emojis unless the user explicitly asks for them
