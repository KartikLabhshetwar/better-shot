# Iterative polish (Mode C)

Trigger when the user has already accepted the page's structure and is asking for depth, richness, or polish — phrases like "make this better," "make the assets richer," "add some depth here," "this still feels flat," "what's missing," "push it further." The structure is settled; the work is now per-asset.

The failure mode this mode exists to prevent is **reactive cosmetic padding**: bumping a radius, deepening a shadow, swapping an accent, sprinkling micro-animations, adding a gradient blob — fiddling with surface treatments to feel like progress. None of that moves the page from data-poor to data-rich, which is what "feels flat" almost always means.

## Protocol

1. **Inventory.** List every asset on the page — every card, chart, screenshot, code sample, table, list item, hero visual, callout, footer block. Name them concretely ("the hero product mock," "the pricing card row," "the integrations strip," "the changelog snippet"). Aim for completeness, not brevity.

2. **Rank.** For each asset, ask "is this data-poor or data-rich?" *Data-poor:* placeholder labels, lorem-style copy, "Item 1 / Item 2," round invented numbers, no states, no metadata, no time, no owner. *Data-rich:* real entity names, real fields, real values, hover state, footer metadata (timestamp / source / owner), edge values (zero, max, error). Pick the single weakest asset.

3. **Push.** Take that one asset from data-poor to data-rich. Add real (non-rounded) numbers, real entity names with real IDs, sparklines that plot an actual series, hover/focus states with secondary detail, footer metadata, edge cases (zero state, error state, the row at the bottom of the list). The asset should look like a screenshot from the real product, not a mock.

4. **Verify, then advance.** Confirm the change with the user using the verification handoff below. Only after that do you move to the next-weakest asset. Never batch ten cosmetic tweaks across the page in one pass.

## Forbidden moves in this mode

- Adjusting radius, shadow, padding, color tokens, or font weight as the headline change of a pass.
- Adding micro-animations, hover transitions, or scroll effects before the underlying assets carry real data.
- Generating "more sections" — Mode C deepens what's already there, it does not add scope.
- Silently reverting to Mode A and rebuilding from scratch — if the structure is genuinely wrong, surface that and ask the user explicitly before exiting this mode.

## Verification handoff

After each pass, end with this — verbatim, with the actual values filled in:

> Open `<absolute file path>` and hard-refresh (Cmd+Shift+R). Three specific things you should see change in this pass:
> 1. [the asset that was upgraded — e.g. "the hero product mock now renders Decision #4218"]
> 2. [the data points that are now real — e.g. "owner: Anya, status: shipped, blockers: 2, last updated 14:02"]
> 3. [the secondary states / metadata / interactions now visible — e.g. "hover on the row reveals the audit trail"]
>
> If you don't see those three, the file didn't reload — check the path and refresh again.

This reduces "is it actually updated?" friction from caching and file-name confusion. Do not skip it.
