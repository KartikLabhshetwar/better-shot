import Foundation

private func approx(_ a: Double, _ b: Double, _ label: String) {
    assert(abs(a - b) < 0.0001, "\(label): \(a) != \(b)")
}

private func checkSelectionFloor() {
    let selection = TrimSelection(start: 2, end: 8)

    let pushedStart = selection.settingStart(9, duration: 10)
    approx(pushedStart.start, 8 - Clip.minimumDuration, "the start handle stops one minimum duration short of the end")
    approx(pushedStart.end, 8, "moving the start handle never moves the end")

    let pushedEnd = selection.settingEnd(0, duration: 10)
    approx(pushedEnd.end, 2 + Clip.minimumDuration, "the end handle stops one minimum duration past the start")

    approx(selection.settingStart(-4, duration: 10).start, 0, "the start handle stops at zero")
    approx(selection.settingEnd(40, duration: 10).end, 10, "the end handle stops at the media duration")
}

private func checkSlide() {
    let selection = TrimSelection(start: 2, end: 8)
    let slid = selection.shifted(by: 6, duration: 10)
    approx(slid.duration, 6, "sliding the range keeps its length")
    approx(slid.start, 4, "sliding the range stops at the media end instead of squashing")
    approx(selection.shifted(by: -50, duration: 10).start, 0, "sliding the range stops at zero")
}

@main
enum TrimSelectionCheck {
    static func main() {
        checkSelectionFloor()
        checkSlide()
        print("TrimSelectionCheck: the minimum-duration floor and the media edges both hold")
    }
}
