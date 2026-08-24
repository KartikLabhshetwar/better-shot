@main
enum RecordingAudioPlanCheck {
    static func main() {
        let micOnly = RecordingAudioPlan(systemAudio: false, microphone: true)
        precondition(micOnly.capturesAudio, "ScreenCaptureKit needs audio capture on before it delivers microphone samples")
        precondition(!micOnly.systemAudio, "a mic-only recording must never write the system audio track")

        let silent = RecordingAudioPlan(systemAudio: false, microphone: false)
        precondition(!silent.capturesAudio, "a recording with both switches off must not capture audio at all")

        let systemOnly = RecordingAudioPlan(systemAudio: true, microphone: false)
        precondition(systemOnly.capturesAudio && systemOnly.systemAudio && !systemOnly.microphone)

        let both = RecordingAudioPlan(systemAudio: true, microphone: true)
        precondition(both.capturesAudio && both.systemAudio && both.microphone)

        print("RecordingAudioPlanCheck: microphone-only recordings capture audio without writing system audio")
    }
}
