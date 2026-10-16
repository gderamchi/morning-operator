import AVFAudio
import Foundation
import Testing
@testable import MorningApple

@Suite("Synthesized audio decoding and conversion — no audio device", .timeLimit(.minutes(1)))
@MainActor
struct SpeechAudioPCMTests {
    struct Layout: Sendable {
        let channels: AVAudioChannelCount
        let interleaved: Bool
    }
    nonisolated static let layouts = [Layout(channels: 1, interleaved: false), Layout(channels: 2, interleaved: false),
                          Layout(channels: 2, interleaved: true)]

    @Test(arguments: layouts, [1.0, 8.4])
    func conversionPreservesDurationAndSignalAtTheEnd(layout: Layout, seconds: Double) throws {
        let input = makeBuffer(rate: 44_100, channels: layout.channels, interleaved: layout.interleaved, seconds: seconds)
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                               channels: 1, interleaved: false))
        let output = try SpeechAudioPCM.convert(input, to: target)
        let duration = Double(output.frameLength) / output.format.sampleRate
        #expect(abs(duration - seconds) <= 1 / 48_000)
        let tail = max(0, Int(output.frameLength) - 256)..<Int(output.frameLength)
        let samples = try #require(output.floatChannelData)
        let energy = tail.reduce(0.0) { sum, index in
            let sample = Double(samples[0][index * output.stride])
            return sum + sample * sample
        }
        #expect(sqrt(energy / Double(tail.count)) > 0.03)
    }

    @Test func identicalFormatRetainsTheOwnedBuffer() throws {
        let input = makeBuffer(rate: 48_000, channels: 1, interleaved: false, seconds: 1)
        #expect(try SpeechAudioPCM.convert(input, to: input.format) === input)
    }

    @Test func emptyInputAndExcessiveOutputCapacityAreRejected() throws {
        let empty = makeBuffer(rate: 44_100, channels: 1, interleaved: false, seconds: 0)
        let ordinary = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        #expect(throws: SpeechPlaybackError.self) { try SpeechAudioPCM.convert(empty, to: ordinary) }
        let large = makeBuffer(rate: 8_000, channels: 1, interleaved: false, seconds: 75)
        let upsampled = try #require(AVAudioFormat(standardFormatWithSampleRate: 192_000, channels: 1))
        #expect(throws: SpeechPlaybackError.self) { try SpeechAudioPCM.convert(large, to: upsampled) }
    }

    @Test func realDecoderReadsSyntheticWaveWithoutPlayingOrRetainingATemporaryFile() throws {
        let before = temporaryAudioFiles()
        let decoded = try SpeechAudioPCM.decode(syntheticWave())
        #expect(decoded.frameLength == 800 && decoded.format.sampleRate == 8_000)
        #expect(SpeechAudioPCM.byteCount(decoded) > 0)
        #expect(temporaryAudioFiles() == before)
    }

    @Test(arguments: [Data(), Data([0, 1, 2, 3])])
    func malformedAudioIsRejectedAndTemporaryFilesAreRemoved(data: Data) {
        let before = temporaryAudioFiles()
        #expect(throws: (any Error).self) { try SpeechAudioPCM.decode(data) }
        #expect(temporaryAudioFiles() == before)
    }

    private func makeBuffer(rate: Double, channels: AVAudioChannelCount, interleaved: Bool, seconds: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: interleaved)!
        let frames = Int(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, frames)))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(channels) {
            for frame in 0..<frames {
                buffer.floatChannelData![channel][frame * buffer.stride] = Float(0.2 * sin(2 * .pi * 400 * Double(frame) / rate))
            }
        }
        return buffer
    }

    private func temporaryAudioFiles() -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)) ?? [])
            .filter { $0.hasPrefix("more-speech-") })
    }

    private func syntheticWave() -> Data {
        var result = Data()
        func bytes(_ text: String) { result.append(contentsOf: text.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        }
        bytes("RIFF"); integer(UInt32(36 + 1_600)); bytes("WAVEfmt "); integer(UInt32(16))
        integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(8_000)); integer(UInt32(16_000))
        integer(UInt16(2)); integer(UInt16(16)); bytes("data"); integer(UInt32(1_600))
        for frame in 0..<800 { integer(Int16(8_000 * sin(2 * .pi * 400 * Double(frame) / 8_000))) }
        return result
    }
}
