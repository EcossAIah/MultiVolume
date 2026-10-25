import Testing
@testable import MultiVolume

/// Builds a `data1` value the way the HID system lays it out.
private func data1(key: Int, state: Int, repeating: Bool = false) -> Int {
    (key << 16) | (state << 8) | (repeating ? 1 : 0)
}

private let keyDown = 0x0A
private let keyUp = 0x0B

@Suite struct MediaKeyEventTests {

    @Test func decodesVolumeUpPress() {
        let event = MediaKeyEvent(data1: data1(key: 0, state: keyDown))
        #expect(event?.key == .volumeUp)
        #expect(event?.isPressed == true)
        #expect(event?.isRepeat == false)
    }

    @Test func decodesVolumeDownRelease() {
        let event = MediaKeyEvent(data1: data1(key: 1, state: keyUp))
        #expect(event?.key == .volumeDown)
        #expect(event?.isPressed == false)
    }

    @Test func decodesMuteRepeat() {
        let event = MediaKeyEvent(data1: data1(key: 7, state: keyDown, repeating: true))
        #expect(event?.key == .mute)
        #expect(event?.isRepeat == true)
    }

    @Test(arguments: [2, 3, 16, 17, 19, 20])
    func ignoresOtherAuxKeys(keyCode: Int) {
        // Brightness, play/pause, next, previous and similar keys must pass through.
        #expect(MediaKeyEvent(data1: data1(key: keyCode, state: keyDown)) == nil)
    }
}
