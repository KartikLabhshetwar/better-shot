# Pre-generation brief enforcer (Mode A)

The single most effective anti-slop move is to force specificity *before* any code is written. Once the model starts generating from a vague prompt, it has already committed to the distribution mean and every subsequent decision compounds that commitment. This workflow interrupts that.

The goal is not to block the user, frustrate them, or lecture. The goal is to extract just enough specificity that the model has something to sample from other than "generic SaaS landing page." Five short answers is usually enough.

## When to run this workflow

Run it when the user asks Claude to produce a landing page, dashboard, or app UI and has not supplied a style brief. If the request is a quick throwaway ("just mock something up rough so I can see it") or the user has already given a detailed brief, skip the full five-axis interview and proceed with a shorter fallback (see "Short path" at the bottom).

## The five axes

Ask the user about each of these, in this order. Use `AskUserQuestion` when it's available so the user can choose quickly; fall back to a single inline question listing all five if not.

### 1. Typography

Ask: "What should the type feel like? Answer with (a) a site whose typography you want to echo, (b) a named display font you'd like to try, (c) a pairing rule — e.g. 'serif H1, sans body,' 'mono for all numerics,' 'italic emphasis on the lede,' or (d) if you're stuck, name ONE site you'd be okay echoing, even a competitor — give the model something concrete to anchor on."

Why this matters: default system-safe sans (V2) is the single fastest slop signal. Even a rough typographic choice — "something with a real display serif for the H1" — removes the most obvious tell. A named reference site is better than a named font because it pins the *pairing* and the hierarchy, not just the face. **No "surprise me" lane:** the surprise-me path is itself a slop attractor (the model reaches for the next-most-common face — Tiempos, Söhne, IBM Plex — and that is now its own tell). Force a concrete pin, even if it is a competitor.

Record the answer as: "typography anchor = [reference / named face / pairing rule / competitor reference]."

### 2. Color

Ask: "What should the color do? Answer with (a) a brand hex/palette if you already have one, (b) one named primary accent ('the accent is burnt orange; everything else neutral') — semantic-by-role is fine but the accent must be named, or (c) a banlist ('no purple gradient, no shadcn default grays') paired with at least one positive direction."

Why this matters: the purple/indigo gradient (V1) is the single most recognizable slop signal and the model will default to it if color is unspecified. A banlist alone produces uglier slop (ban purple → the model picks teal-to-cyan). A *semantic* palette — even if the user only has "brand accent = one color, everything else neutral" — is the durable answer.

If the user has no opinion, do not fall back to grayscale-with-Inter — that is now its own slop attractor. Push for ONE specific semantic accent right now (a single named hue that means *something* — brand, category, mood) rather than deferring color until later. **Pendulum guard:** if you find yourself proposing strict grayscale as the safe choice, that is the warning sign — the no-color editorial-monochrome look is convergent in 2026 and reads as AI-with-taste rather than as a real brand.

Record the answer as: "color rule = [palette / semantic accent / banlist]."

### 3. Structure — "what it must not look like"

Ask: "Two parts. (1) What's a competitor or category site this should *not* resemble? Name one, or describe the look you're trying to avoid. (2) Is there one site you'd be glad it resembled, even loosely? Doesn't have to be in your category."

Why this matters: this question is load-bearing and often the most productive one. Structure is harder to articulate in the positive than in the negative. A user who cannot describe what they want can usually name what they don't want, and a negative anchor ("not another three-box feature grid with logos below," "not the v0 bento dashboard") immediately rules out the highest-probability slop layouts (S1, S2, S5). Pairing the negative with a positive doubles the anchor strength — "not v0 + closer to Linear" is a much sharper instruction than either alone.

Record the answer as: "avoid = [named reference / described structure]; aspire = [named reference, or 'none given']."

### 4. Voice and content — the actual claim

Ask: "What's the one specific thing this page is trying to say? Answer with a real headline, not 'Build the future of X.' If the product is [product], finish the sentence 'The thing that makes us different is ____.'"

Why this matters: this is where layer-3 slop (C1, C3, C5) gets defeated. A generic hero is almost always downstream of a generic brief. Refuse to generate "Build the future of work" as a placeholder — it is the single clearest signal that the page has nothing to say yet. Ask once, directly, for the real claim.

If the user cannot produce a real claim, do **not** generate a placeholder headline like "Build the future of X." Instead, render the hero with the H1 slot deliberately empty and a visible HTML comment in its place: `<!-- claim pending — fill this with the actual sentence -->`. The visible absence is a stronger forcing function than a placeholder phrase, which users will leave in and ship. Tell the user explicitly: "I left the H1 empty on purpose — the page will not feel finished until you fill it, which is the point."

Record the answer as: "claim = [actual sentence or 'H1 left empty, comment in place']."

### 5. Asset specificity — the most concrete piece of UI

Ask: "What's the most concrete piece of UI we can show on this page? Name a real entity — a record, a ticket, a decision, a transaction, a row — with real fields and real values. Not 'a dashboard,' not 'a workspace,' not 'an analytics view.'"

Why this matters: this defeats C4 (abstract demo visual) at brief-time instead of catching it in audit. The model's slop default is a stylized device mock with placeholder data; the antidote is *one* real entity with real field labels and real values pinned at brief-time. If the user names "Decision #4218: Migrate billing to Stripe — owner: Anya, status: shipped, blockers: 2," the hero already has a real product asset to render. If the user cannot name one, flag it the same way you flag a generic claim — the abstract demo is downstream of an abstract brief.

Record the answer as: "asset = [named entity with fields and values, or 'abstract acknowledged']."

## After the five answers

Assemble a compact brief — five lines, one per axis. Echo it back to the user:

> Before I build, here's the brief I'll use:
> - Typography: [answer]
> - Color: [answer]
> - Avoid: [answer]
> - Claim: [answer]
> - Asset: [answer]
>
> Good to proceed, or adjust?

Wait for confirmation. Then inject the brief verbatim into every subsequent code generation in the session — both as part of the prompt to the model, and as a comment at the top of the generated file so subsequent edits retain context.

## After generation — verification handoff

After writing the generated page to disk, end with this — verbatim, with the actual values filled in:

> Open `<absolute file path>` and hard-refresh (Cmd+Shift+R). Three specific things you should see vs. a default v0/Lovable output:
> 1. [the typographic anchor — e.g. "Tiempos serif H1, not Inter"]
> 2. [the named asset rendered — e.g. "Decision #4218 with real fields visible in the hero"]
> 3. [the structural choice — e.g. "single CTA, no logo strip, no three-box grid"]
>
> If you don't see those three, the file didn't reload — check the path and refresh again.

This reduces "is it actually updated?" friction from caching or file-name confusion. Do not skip it.

## Short path — when the user refuses the interview

Some users legitimately want a throwaway mock without being interviewed. Honor that, but do not pretend you have a brief. Instead, output a short "I'm falling back to defaults" note before generating:

> No brief provided, so I'm committing to one specific direction and naming it inline at the top of the file: ONE named accent (not indigo, not strict grayscale), a hierarchy choice (e.g. serif H1 + sans body), a single concrete asset placeholder (not a 3D illustration), and one CTA. If this ends up looking like someone else's site, the brief is the fix — happy to run through five quick questions after you see it.

This preserves user agency, surfaces the compromise, and plants the brief-enforcer as the recovery path.

## What not to do

- Do not turn this into a ten-question form. Five axes is the ceiling, not the floor.
- Do not refuse to generate at all without a brief. Users push back and the skill loses credibility. The fallback above is the compromise.
- Do not invent brand constraints the user didn't give you. If the user said "blue," do not extend that to "deep navy with coral accent." Stay minimal and additive.
- Do not moralize. The user is not being lazy by not having a brief. Most users don't have one; that is why this workflow exists.
