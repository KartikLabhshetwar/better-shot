# Structural slop patterns (S1–S9)

This is the damaging layer. A design can have perfect typography and a tasteful color system and still be slop because the *composition* is identical to every other AI-generated page. Most skills miss this layer because it requires looking at the whole page, not individual tokens.

A fix at this layer usually means cutting sections, re-ordering priority, or changing the argument the page is trying to make — not restyling. That is the point.

Entries use five fields: **Signal** (what you see), **Why it reads as slop** (the root cause), **Remediation** (the direction when avoiding the pattern), **When it's not slop** (the conditions under which this pattern is *not* slop — check this gate *before* flagging in audit mode), and **How to keep it tasteful** (positive direction for the tasteful variant, used in generation mode).

**All entries in this file are tagged `execution-sensitive`:** each S-pattern has a tasteful variant *when executed with real content*. The "How to keep it tasteful" line tells you how to do it well; the "When it's not slop" line tells you when not to flag it in audit mode. Counterpart files: `visual.md` (also `execution-sensitive`), `conceptual.md` (tagged `always-slop`).

---

## S1 — The canonical SaaS hero

Signal: hero section is centered text, H1 + one-line subhead + two CTAs ("Get started" / "Book a demo") + a row of "As seen in" logos below the fold. The visual is either a product mock with a soft gradient behind it, or a 3D illustration.

Why it reads as slop: this is the structure of every SaaS landing page template from 2022 onward. The model reaches for it because it is the distribution mean for "landing page." It is not wrong — it is just invisible.

Remediation: ask what this hero is *arguing*. If the argument is "we are trustworthy and boring," the template fits. Most products have a stronger claim than that. Try: a specific customer screenshot, a single CTA with the actual action it performs, an asymmetric layout, or an editorial-style opener where the first visual element is a sentence, not a gradient button.

When it's not slop: a centered hero is slop ONLY when combined with abstract demo + two-CTA template + logo strip; a centered hero with a specific real-content asset directly below it (a real product screenshot, a real entity rendered, a real quote with attribution) is fine. Centering is not the offense.

How to keep it tasteful: directly below the H1, render a *specific* piece of real product content (an actual decision row, a real ticket, a live metric, a real customer screenshot) — not a 3D illustration, not a logo strip; pair the centering with ONE primary CTA tied to the actual product action, not two abstract verbs. Centering with real content asserts focus; centering with abstraction reads as template.

---

## S2 — Three-box feature grid

Signal: a section with three equal-sized cards in a row, each with a small Lucide icon + 2-word title + one line of description. Usually titled "Features," "Why choose us," or "How it works."

Why it reads as slop: the single most repeated SaaS layout. Once you see it you cannot unsee it. It communicates almost nothing because the model has no specific features to talk about, so it makes the placeholders look nice and moves on.

Remediation: refuse to generate this section as placeholder. If the user has not told you what the three features actually are, stop and ask. Then once you know the features, consider whether they belong in a grid at all — one feature with a real product demo beats three features with icons almost every time. Grids are appropriate only when the items are genuinely peer-level and comparable.

When it's not slop: a three-box section with three genuinely peer-level real features — each with a real screenshot or a specific claim a competitor could not copy-paste — is fine. The slop is icons + two-word titles + filler descriptions.

How to keep it tasteful: each box must carry a real screenshot or a specific verb-noun claim that names what the product actually does ("Approve invoices from Slack" with a real Slack thread mock — not "Seamless Collaboration" with a generic icon), and the three items must be genuinely peer-level — three facets of one capability, not three unrelated features stapled together; if you can't write a specific claim for all three, the section should have one feature, not three.

---

## S3 — Logo soup

Signal: a strip of low-opacity customer or tech-stack logos, usually 5–8 in a row, often labeled "Trusted by," "As seen in," or nothing at all. Stripe, Linear, Vercel, Notion, and OpenAI appear suspiciously often.

Why it reads as slop: training data is full of templates that used those specific logos as placeholders. The model pastes them back. Even when the logos are real, logo soup as a *device* has become noise.

Remediation: if the user has real customers worth naming, name them with proper attribution and ideally a sentence of context ("Linear runs their [specific thing] on this"). If they do not, cut the section. A blank space is more honest than a wall of other companies' logos. If a social-proof element is needed, consider a specific quote, a number that is actually true, or nothing.

When it's not slop: real, recognizable customer logos with attribution and a sentence of context attached are fine; the slop is faded logos as a decorative strip with no claim and no source.

How to keep it tasteful: name 2-4 logos (not 8), pair each with a one-line attribution of what they actually use the product for ("Linear uses [product] for their on-call rotation"), and consider whether one strong customer story replaces the whole strip — three logos with context beat eight without; render the logos in their real brand colors at high opacity, not desaturated to 30%.

---

## S4 — Stock-feel testimonial carousel

Signal: quotes in cards with avatars, arranged as a carousel or 3-up grid. Names like "Sarah Chen, Product Manager" with headshot-style avatars. The quotes read as if a model wrote them because a model wrote them.

Why it reads as slop: both the quotes and the avatars are invented. Users can tell — not always consciously, but the effect is that the page stops being trusted from that section onward.

Remediation: zero testimonials beats fake testimonials. If real testimonials exist, use one at full size with attribution and, ideally, link to the source (a public tweet, podcast, case study). One real quote carries the page; five fake ones sink it.

When it's not slop: one real quote at full size with full attribution and a link to its source is fine; the slop is multiple invented testimonials with stock-feel avatars in a carousel.

How to keep it tasteful: one quote at full size with a real attributed source (name, role, company) and a link to the original (tweet, podcast timestamp, public case study); the link is load-bearing — it converts a quote from claim into evidence. Quote the customer's actual words verbatim from the source, not a polished paraphrase, and prefer specificity over praise ("cut our weekly close from 4 days to 6 hours" beats "amazing tool, changed everything").

---

## S5 — Bento grid dashboard showcase

Signal: a section (often on a landing page, sometimes as the whole product preview) showing 6–9 tiles of different sizes — a chart, an image, a quote, a metric, a small UI element — arranged in a masonry layout. Malewicz's "complex dashboards that nobody cares about or understands but fills the space."

Why it reads as slop: bento grids are the current default for "show lots of things at once without choosing." They signal density without communicating.

Remediation: ask what story the section is telling. If there is one thing the user should take away, show one thing larger. If there are multiple genuinely different product capabilities, a bento can work — but each tile has to earn its space with a real screenshot, a real number, or a real piece of content. A bento of placeholders is the strongest slop signal on the current web.

When it's not slop: a bento layout where every tile carries a real screenshot, a real number, or a real piece of product content is fine when the page genuinely has multiple distinct capabilities to show; the slop is a bento of placeholders.

How to keep it tasteful: one tile takes 50%+ of the grid and earns it with a real demo or live metric, the remaining tiles vary in proportion (no uniform masonry), and each tile answers one specific question — "what does this product let me do?" — not "what's another thing we built"; a bento should feel like a curated set of evidence, not a feature-dump in tile form.

---

## S6 — Uniform-everything page

Signal: every card has the same padding, same radius, same shadow, same height. Every section has the same vertical rhythm. There is no visual hierarchy because no element is weighted differently from any other.

Why it reads as slop: the model applied the default spacing token to everything because the prompt gave it no reason to emphasize anything. The page has no *tension*.

Remediation: this is a design-system-level problem dressed as a styling problem. The fix is to decide what the three or four most important moments on the page are and let everything else recede. If the product has a real design system, hand off to `design:design-system`. If not, the short-term fix is to pick one element per page to break the uniform rhythm — a larger hero, a taller feature card, an off-grid quote — and let that be the page's anchor.

When it's not slop: a deliberately flat utility tool (an admin panel, an internal dashboard, a data-entry app) where uniform rhythm IS the chosen language can be fine; the slop is uniform-by-default on a marketing or product page that needs hierarchy.

How to keep it tasteful: if the product genuinely *is* a utility tool, commit to flat rhythm as the chosen language across every surface and remove decorative breaks; if it's a customer-facing page, pick three priority elements per page (one hero moment, one anchor metric, one closing CTA) and let them break the rhythm with deliberate weight — larger, taller, off-grid, or in a contrasting surface treatment.

---

## S7 — The generic dashboard sidebar

Signal: left sidebar with 6–10 menu items: Overview, Analytics, Reports, Projects, Team, Settings, Integrations, Billing. Each with a Lucide icon. No grouping, no hierarchy, no information architecture — just an inventory.

Why it reads as slop: these are the items every template ships with. They signal "this is a SaaS app" but communicate nothing about what this specific app does.

Remediation: the sidebar should reflect the product's information architecture, not a template's. Start from the user's actual primary tasks and name the nav items after those. If "Analytics" is really "Revenue" for this product, call it Revenue. If there is no analytics view in the MVP, do not add the item. An empty section is not a feature.

When it's not slop: a sidebar whose items reflect the product's actual primary user tasks (named after what the user does, not after a template inventory) is fine, even if some items overlap with generic SaaS nav.

How to keep it tasteful: name nav items after the user's actual primary tasks (verbs over nouns where possible: "Approve invoices" over "Invoices"), group items by user workflow rather than by domain ("Daily review" + "Month-end close" beats "Reports" + "Analytics"), and omit any item that doesn't have a real destination — empty sections are debt, not features.

---

## S8 — Four-KPI-card row

Signal: the top of a dashboard has four cards of identical size, each with a metric number, a unit label, a percentage change in green or red, and a tiny sparkline. Totals, averages, arrows up.

Why it reads as slop: this is the stock dashboard opener. It almost never matches the actual decisions the user of this dashboard needs to make. The four metrics are usually chosen because four fit in a row, not because they matter together.

Remediation: ask what decision this dashboard supports. A dashboard that has a job shows the metrics that inform that job, in the relationships that matter — often that means one headline metric large, with supporting context, not four equal cards. If four peer metrics are genuinely right, give each one a time comparison, a target, or an annotation that explains when the number is good. A number floating in a card without a reference point is decoration.

When it's not slop: four KPIs are fine when they genuinely answer one decision together and each carries a target/comparison/annotation; the slop is four metrics chosen because four fit in a row.

How to keep it tasteful: each KPI carries a target, a time comparison, AND an annotation that names when the number is good ("+12% WoW, on track for Q4 $50k target"); if you can't write that annotation for all four cards, you have fewer than four real KPIs and the row should shrink to one headline metric large with the rest as supporting context.

---

## S9 — The decorative chart

Signal: a chart that has no axis labels, no legend, no time range, no data source, and does not decode to any specific question. Often a soft-gradient area chart or a mini bar chart in a card. Malewicz calls this "a chart that doesn't contribute to anything, but adds the 'data element.'"

Why it reads as slop: the chart is there because the model thinks dashboards have charts. It is not answering a question.

Remediation: every chart should answer one specific question the user has. Write the question as a sentence first, then pick the chart type and the fields. If no question can be named, cut the chart. A dashboard with three real charts is better than one with nine decorative ones.

When it's not slop: a chart that answers one specific named question with real data, real axes, real time range, and a real source is fine; the slop is the decorative chart that decodes to no question at all.

How to keep it tasteful: write the question the chart answers as a sentence in the chart title ("How is signup conversion trending this quarter?"), use real axes with real units and a real time range, and include a data source line in the footer ("Source: production analytics, updated 2026-05-09"); a chart that can't be summarized in one specific question shouldn't be on the page.
