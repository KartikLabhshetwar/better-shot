import Foundation

@main
enum SmartRedactionCheck {
    static func matches(in text: String) -> [String] {
        SmartRedactionRecognizer.sensitiveRanges(in: text).map { String(text[$0]) }
    }

    static func main() {
        // MARK: - Each rule fires on its own kind of secret

        assert(matches(in: "reach me at jane.doe@example.com today") == ["jane.doe@example.com"], "email must be caught")
        assert(matches(in: "see https://internal.corp/dashboard?token=1 for details") == ["https://internal.corp/dashboard?token=1"], "URL must be caught")
        assert(matches(in: "server lives at 10.0.12.7 in the rack") == ["10.0.12.7"], "IPv4 must be caught")
        assert(matches(in: "version 999.1.2.3 build notes").isEmpty, "octets over 255 are not an address")
        assert(matches(in: "call 415-555-0134 anytime") == ["415-555-0134"], "phone number must be caught")
        assert(matches(in: "card 4539 1488 0343 6467 on file") == ["4539 1488 0343 6467"], "a Luhn-valid card must be caught")
        assert(matches(in: "order 1234 5678 9012 3456 shipped").isEmpty, "a Luhn-invalid digit run is not a card")
        assert(matches(in: "key sk-proj-AbCdEf123456 in env") == ["sk-proj-AbCdEf123456"], "API key prefix must be caught")
        assert(matches(in: "token ghp_16C7e42F292c6912E7710c838347Ae178B4a rotated") == ["ghp_16C7e42F292c6912E7710c838347Ae178B4a"], "GitHub token must be caught")
        assert(matches(in: "session eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.sflKxwRJSMeKKF2QT4 expires") == ["eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.sflKxwRJSMeKKF2QT4"], "JWT must be caught")
        assert(matches(in: "update index.min.js and archive.tar.gz today").isEmpty, "dotted filenames are not tokens")

        // MARK: - Labeled secrets box the value, not the label

        do {
            let found = matches(in: "password: hunter2rocks")
            assert(found == ["hunter2rocks"], "the secret after the label is the redaction target, got \(found)")
        }

        // MARK: - Plain prose stays untouched

        assert(matches(in: "The quick brown fox jumps over the lazy dog").isEmpty, "prose must not be flagged")
        assert(matches(in: "meeting moved to Thursday at 3pm, room 204").isEmpty, "everyday numbers must not be flagged")

        // MARK: - Overlapping hits merge into one range

        do {
            let found = matches(in: "https://api.example.com/v1?user=jane@example.com")
            assert(found.count == 1, "overlapping URL and email must merge, got \(found)")
        }

        print("SmartRedactionCheck: all assertions passed")
    }
}
