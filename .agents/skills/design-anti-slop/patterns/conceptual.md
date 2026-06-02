# Conceptual slop patterns (C1–C7)

The hardest layer, and the one that separates "AI output that happens to look okay" from "a real product someone would remember." No amount of color-swapping fixes it. If a design is broken at this layer, visual and structural fixes are cosmetic.

Entries use three fields: **Signal**, **Why it reads as slop**, and **Remediation**.

**All entries in this file are tagged `always-slop`:** these patterns are about *fake content* — hollow claims, invented stats, missing functional states, no point of view — not about design choices with tasteful variants. There is no "How to keep it tasteful" line in C-entries because the tasteful version is the *opposite* of the pattern (real claim, real stats, real states, real POV), not a refinement of it. The Remediation field is the only direction; if you're auditing and you confirm a C-hit, flag it without looking for "When it's not slop" mitigation. Counterpart files: `visual.md` and `structural.md` (both tagged `execution-sensitive` — those patterns have tasteful variants and carry a "How to keep it tasteful" line).

C1, C2, and C6 are primarily copy problems. For anything beyond a spot-fix on these, hand off to `design:ux-copy` — this skill flags them and proposes direction, but `ux-copy` owns actually writing replacements.

---

## C1 — Aspirational-but-empty headline

Signal: the H1 is a phrase like "Build the future of work," "The all-in-one platform for [anything]," "Scale without limits," "Where teams do their best work," "The modern way to [generic verb]."

Why it reads as slop: these sentences fit every company because they commit to no claim. Models produce them because when the prompt is vague, the safest headline is the one that cannot be wrong — and therefore cannot be specific, either.

Remediation: replace the abstraction with the most specific true claim the product can make. Ideally a claim with a verb, a noun that is concretely in the product, and something a competitor cannot also say. "Send invoices in 10 seconds" beats "Simplify your workflow." If the user cannot name what specifically the product does that is worth the hero slot, the problem is the product story, not the page.

---

## C2 — Verb slop in body copy

Signal: paragraphs full of "seamlessly," "empower," "revolutionize," "unlock," "effortlessly," "transform," "supercharge," "elevate," "streamline." Adjective stacks with no nouns ("powerful, intuitive, scalable").

Why it reads as slop: these are the tokens that show up in the training distribution whenever the prompt is "write marketing copy." They are maximally safe and minimally informative.

Remediation: prefer concrete verbs that describe an action a user actually takes, and specific nouns that exist in the product. Rewrite with nouns and verbs only, cutting adjectives and adverbs on the first pass. If the sentence survives that cut and still says something, it is probably working.

---

## C3 — Section-level genericity

Signal: each section on the page has a title and content that would apply equally to any competitor in the category. The "Security" section talks about encryption in general. The "Integrations" section says "connects with the tools you love." The "Pricing" section says "flexible plans for teams of all sizes."

Why it reads as slop: the sections exist because the template had them, not because the product has something specific to say in each. The model fills them with the distribution average for that section's label.

Remediation: for each section, ask "what specifically does this product do here that a competitor could not truthfully copy-paste?" If the answer is nothing, cut the section. A landing page with three sections that each say something specific beats one with ten sections that say something generic.

---

## C4 — Abstract demo visual in place of real product

Signal: the hero visual is a 3D clay illustration, a stylized device mock with a fake dashboard, a glowing gradient orb, or a mock UI with lorem-ipsum-style data. The actual product does not appear anywhere on the page.

Why it reads as slop: the model did not have a real product screenshot, so it generated an abstraction. The abstraction is fine-looking; it is also interchangeable with every other landing page's abstraction.

Remediation: show the real product, doing the real thing, with real-looking data. If the product is not visually ready for that shot, that is the real problem — fix the product UI before fixing the landing page. An annotated screenshot of the product at work is worth more than any illustration.

---

## C5 — No point of view

Signal: the page never takes a position. It does not say what it is *not*, what kind of customer it is *not* for, what it actively disagrees with, or what it replaces. It is polite, comprehensive, neutral.

Why it reads as slop: neutral pages are the safe output of a model trying not to offend. Memorable pages usually stake a claim, name an enemy category ("we are not another [thing]"), or include something that would feel wrong if it appeared on a competitor's site.

Remediation: ask the user for one opinion the product team actually holds that their competitors would disagree with. Put that opinion on the page, in the user's words if possible. A point of view does not have to be aggressive; it does have to be a choice.

---

## C6 — Fake specificity

Signal: numbers that look precise but have no source. "3x faster," "10,000+ teams," "Save 40% of your time," "Used by 500 engineers." No link, no footnote, no "based on" caveat.

Why it reads as slop: specific-sounding numbers are a common signal of credibility in training data, so the model generates them. Users have learned to distrust them because they are almost always invented.

Remediation: either cite the source (a public benchmark, a specific customer, a publicly shared metric) and link to it, or cut the number entirely. A qualitative claim that is true beats a quantitative claim that is invented.

---

## C7 — Missing functional states

Signal: forms without validation states, buttons without disabled or loading states, empty states whose illustration literally says "no data yet," error states that only handle the default case. Interactive elements that look great at rest but have no designed behavior.

Why it reads as slop: this is the layer most "anti-slop" content ignores entirely. Models generate the default state because that is what gets shown in screenshots, and the non-default states are where real product design shows up.

Remediation: for each interactive element, enumerate its states (default, hover, focus, active, disabled, loading, error, empty, success) and design at least the ones that will actually occur. Empty states should anticipate the user's first action, not just say "nothing here." Error states should be specific enough to be actionable. Accessibility is adjacent here — hand off to `design:accessibility-review` for the keyboard and screen-reader side of this.
