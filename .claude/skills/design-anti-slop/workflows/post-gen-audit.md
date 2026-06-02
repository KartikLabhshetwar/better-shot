# Post-generation audit (Mode B)

Run this when the user shares an existing design (screenshot, deployed URL, code, Figma link, v0/Bolt/Lovable output) and asks for review. The output is a short written audit, ranked by impact, with named patterns and specific remediations.

The failure mode to avoid is *flagging everything*. A design that uses Inter and an indigo accent but has strong copy, a real product screenshot, and a specific headline is not slop — it is just undistinctive visually. The skill loses credibility if it treats minor visual defaults the same as a hollow hero claim. Rank by impact, not by ease.

## The three passes

Always run all three. Do not skip layer 3 because layer 1 issues were obvious; layer 3 problems are almost always the most important ones and the ones the user cannot fix by swapping tokens.

**Before flagging any hit, check the pattern's "When it's not slop" line in the catalog.** Each entry now carries one. If the design is the *not-slop* variant — purple-when-brand-is-genuinely-purple, real customer logos with attribution, a centered hero with a real-content asset below it, a bento where every tile carries real content — do **not** flag it. The "When it's not slop" lines are part of the audit, not a footnote. A pattern match that turns out to be the not-slop variant produces zero score, not a soft mention.

### Pass 1 — Visual (V1–V9)

Read `patterns/visual.md` if you need a refresher. Scan the design for:

- V1 purple/indigo gradient
- V2 default system sans (Inter / Geist / Space Grotesk / Roboto / Poppins)
- V3 gradient-filled headline
- V4 uniform rounded-2xl
- V5 unrestyled Lucide / Hero Icons
- V6 ubiquitous light drop shadows
- V7 decorative gradient blobs or radial glows
- V8 glassmorphic cards on purple
- V9 3D clay illustration in the hero

For each hit, note *where* you see it (hero / card row / footer / etc.) so the remediation can point somewhere specific.

### Pass 2 — Structural (S1–S9)

Read `patterns/structural.md` if you need a refresher. Scan the composition:

- S1 canonical SaaS hero (centered + two CTAs + logos)
- S2 three-box feature grid
- S3 logo soup
- S4 stock-feel testimonial carousel
- S5 bento grid of mixed tiles
- S6 uniform padding/radius/height across the whole page
- S7 generic dashboard sidebar
- S8 four-KPI-card row
- S9 decorative chart

This pass is the highest-signal one. Most slop lives here. If the page has two or more S-layer hits, the fix is almost never at layer 1.

### Pass 3 — Conceptual (C1–C7)

Read `patterns/conceptual.md` if you need a refresher. Read the copy and ask:

- C1 is the H1 aspirational-but-empty?
- C2 is body copy full of verb slop?
- C3 does each section say something only this product could say?
- C4 is the demo visual abstract instead of the real product?
- C5 does the page take any position?
- C6 are any numbers specific-sounding but unsourced?
- C7 are functional states missing or generic?

C5 is the subtlest of these and usually needs a re-read. If the page could be edited into a competitor's site by swapping one logo, C5 is broken.

## Scoring — how many hits matter?

*Count only **confirmed-slop-variant hits** — patterns where the design exhibits the slop variant per the catalog's "When it's not slop" line, not raw pattern matches. A page with purple-on-a-genuinely-purple-brand and real attributed logos has zero hits, not three.*

Rough calibration:

- **0 confirmed hits across all layers** → not slop. Say so plainly.
- **1–2 layer-1 confirmed hits only** → undistinctive but fine. Mention them, do not lead with them.
- **Any single layer-2 confirmed hit** → worth flagging; structural issues compound.
- **Any layer-3 confirmed hit (especially C1, C4, C5)** → this is the headline of the audit regardless of what else is present.
- **Layer-1 + layer-2 + layer-3 confirmed all present** → canonical slop. Work from layer 3 down.

## Writing the audit

Use this structure:

```
## [one-line verdict]

[One sentence: is this slop, partially slop, or not slop. If partial, at which layer.]

## What's working

[1–3 lines of honest positives. Skip only if there are genuinely none — do not
invent positives to soften, but do not strip them out to sound harsh. If the
page has a real product screenshot or a specific claim, say so.]

## What reads as slop

[Ordered by impact, deepest layer first. For each hit:

**[Pattern ID] — [one-line description]**
Where: [specific location on the page]
Why it matters: [one line on the severity for this specific design]
Fix: [the direction, not a single prescription — usually a question or
a choice for the user, not a decree]

Include 2–5 items total. More than 5 and the audit becomes noise. If there
really are more, list the top 5 and say "plus smaller issues — happy to
enumerate if useful."]

## The one change with the most leverage

[A single paragraph naming the one fix that, if made, would move this design
from slop to not-slop. This is almost always at layer 2 or 3. Not at layer 1.]

## Hand-offs

[If applicable: "For the copy rewrites across C1/C2/C6, pull in `design:ux-copy`.
For the uniform-everything issue (S6) across your product, `design:design-system`
is the right tool. For general visual polish beyond slop-specific issues,
`design:design-critique`."]
```

## Rules for remediations

- **Rank by impact, not ease.** The instinct is to lead with "change the purple." Resist it. Lead with the layer-3 fix if layer 3 is broken.
- **Name the layer for each fix.** Tell the user "this is a conceptual fix" or "this is a visual fix" so they understand why you ordered them as you did.
- **Offer direction, not prescription.** "Ask whether color here carries meaning" beats "use teal instead of purple." The skill does not have taste — it has a taxonomy.
- **Be willing to say 'this is fine.'** A clean audit is a valid result. If the design does not exhibit the slop patterns, the correct answer is to say so and explain why, not to hunt for something to flag.
- **Do not moralize.** The user is showing you AI-generated output because AI generated it. That is the context, not a crime. Describe, don't scold.

## A worked example of tone

Compare two ways of writing the same audit item:

**Bad (moralizing, vague):**
> Your hero uses that awful purple gradient everybody's sick of. You should really pick a more unique color palette — this looks super AI-generated.

**Good (named, located, directional):**
> **V1 — Purple/indigo gradient.** Where: hero background and primary CTA. Why it matters here: paired with the centered layout (S1) it's the exact handshake every v0 hero gives, so the page reads as generated before anyone reads the headline. Fix: the gradient isn't doing any semantic work — either flatten to a single surface color, or define a real palette where this specific gradient means something (a product state, a brand moment).

The second version is actionable because it is specific. That is the tone.

## When to suggest escalating to Mode A

If the audit uncovers that the design is broken at layer 3 in a way that no amount of editing will fix — the claim is hollow, the product story is generic, no point of view — say so and suggest regenerating after a proper brief, using the `pre-gen-brief.md` workflow. Some designs are not worth patching. Being honest about that is part of the skill's value.
