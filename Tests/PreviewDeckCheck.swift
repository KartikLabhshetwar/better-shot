import Foundation

// Mirror of PreviewOverlay's deck rules (Sources/Preview/PreviewOverlay.swift).

let maxItems = 5

func show(_ url: URL, in items: inout [URL]) {
    items.removeAll { $0 == url }
    items.append(url)
    while items.count > maxItems { items.removeFirst() }
}

func deckHeight(count: Int, panel: CGFloat, thumb: CGFloat, spacing: CGFloat, clearAll: CGFloat) -> CGFloat {
    panel + CGFloat(max(count - 1, 0)) * (thumb + spacing) + (count > 1 ? clearAll : 0)
}

let urls = (1...7).map { URL(fileURLWithPath: "/tmp/shot\($0).png") }
var items: [URL] = []

show(urls[0], in: &items)
show(urls[1], in: &items)
show(urls[2], in: &items)
assert(items == [urls[0], urls[1], urls[2]], "successive captures stack newest last")

show(urls[0], in: &items)
assert(items == [urls[1], urls[2], urls[0]], "re-showing an existing capture moves it to the newest slot without duplicating")

for url in urls[3...] { show(url, in: &items) }
assert(items.count == maxItems, "deck caps at \(maxItems)")
assert(items == [urls[0], urls[3], urls[4], urls[5], urls[6]], "oldest cards are evicted first")

items.removeAll { $0 == urls[4] }
assert(items == [urls[0], urls[3], urls[5], urls[6]], "removing one card keeps the rest in order")

assert(deckHeight(count: 0, panel: 170, thumb: 98, spacing: 10, clearAll: 26) == 170)
assert(deckHeight(count: 1, panel: 170, thumb: 98, spacing: 10, clearAll: 26) == 170)
assert(deckHeight(count: 3, panel: 170, thumb: 98, spacing: 10, clearAll: 26) == 170 + 2 * 108 + 26)

print("PreviewDeckCheck passed")
