/// System audio and the microphone are separate switches, but ScreenCaptureKit only delivers microphone samples on a stream that already captures audio, so a mic-only recording still has to turn capture on and then drop the system audio output.
struct RecordingAudioPlan: Equatable {
    let systemAudio: Bool
    let microphone: Bool

    var capturesAudio: Bool { systemAudio || microphone }
}
