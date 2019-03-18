//
//  RecorderMixInput.swift
//  Recorder
//
//  Created by LinePlus on 17/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation
import AVFoundation

class RecorderMixInput: RecorderPushInput {
    private let queue = DispatchQueue(label: "MixAudioEngine.Queue")
    private let audioEngine = AVAudioEngine()
    private let inputPlayer = AVAudioPlayerNode()
    private let outputPlayer = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()
    private var running = false
    private var inputStarted = false
    private var outputStarted = false

    weak var recorder: Recorder?
    let type: Recorder.TrackType = .audioOutput

    init() {
        prepare()
    }

    func prepare() {
        print("[MixAudioEngine.prepare]")
    }

    func start() {
        print("[MixAudioEngine.start]")

        audioEngine.attach(inputPlayer)
        audioEngine.attach(outputPlayer)
        audioEngine.attach(mixer)

        audioEngine.connect(mixer, to: audioEngine.mainMixerNode, fromBus: 0, toBus: 0, format: nil)
        audioEngine.mainMixerNode.outputVolume = 0

        let format = mixer.outputFormat(forBus: 0)
        let sampleRate = CMTimeScale(format.sampleRate)
        var sampleCount = CMTimeValue(CACurrentMediaTime() * format.sampleRate)
        var cmFormat: CMAudioFormatDescription?

        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: format.streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &cmFormat)

        assert(cmFormat != nil)

        mixer.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] (buffer, time) in
            guard let recorder = self?.recorder else { return }

            var sampleBuffer: CMSampleBuffer?
            var timingInfo = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: sampleRate),
                presentationTimeStamp: CMTime(value: sampleCount, timescale: sampleRate),
                decodeTimeStamp: .invalid)

            CMSampleBufferCreate(
                allocator: kCFAllocatorDefault,
                dataBuffer: nil,
                dataReady: false,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: cmFormat,
                sampleCount: CMItemCount(buffer.frameLength),
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timingInfo,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer)

            if let sampleBuffer = sampleBuffer {
                CMSampleBufferSetDataBufferFromAudioBufferList(
                    sampleBuffer,
                    blockBufferAllocator: kCFAllocatorDefault,
                    blockBufferMemoryAllocator: kCFAllocatorDefault,
                    flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                    bufferList: buffer.audioBufferList)
                CMSampleBufferSetDataReady(sampleBuffer)

                recorder.append(audioBuffer: sampleBuffer, type: .audioOutput)
            } else {
                assertionFailure()
            }

            sampleCount += CMTimeValue(buffer.frameLength)
        }

        do {
            try audioEngine.start()
            running = true

            print("[MixAudioEngine.start] engine started")
        } catch {
            assertionFailure()
        }
    }

    func finish() {
        print("[MixAudioEngine.finish]")

        queue.sync {
            running = false
        }

        mixer.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()

        print("[MixAudioEngine.finish] engine stopped")
    }

    func convert(sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let cmFormat = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            assertionFailure()
            return nil
        }

        let fromFormat = AVAudioFormat(cmAudioFormatDescription: cmFormat)
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: fromFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            assertionFailure()
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frames)

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else {
            assertionFailure()
            return nil
        }

        guard buffer.format.commonFormat != .pcmFormatFloat32 else {
            return buffer
        }

        guard let toFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fromFormat.sampleRate, channels: fromFormat.channelCount, interleaved: false),
            let converter = AVAudioConverter(from: fromFormat, to: toFormat),
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: toFormat, frameCapacity: AVAudioFrameCount(frames)) else {
                return nil
        }

        if converter.convert(to: convertedBuffer, error: nil, withInputFrom: { (packetCount, status) -> AVAudioBuffer? in
            status.pointee = .haveData
            return buffer
        }) != .haveData {
            assertionFailure()
            return nil
        }

        return convertedBuffer
    }


    func process(sampleBuffer: CMSampleBuffer, type: Recorder.TrackType) {
        guard let buffer = convert(sampleBuffer: sampleBuffer) else {
            return
        }

        queue.sync {
            guard running else { return }

            switch type {
            case .audioInput:
                if !inputStarted {
                    audioEngine.connect(inputPlayer, to: mixer, fromBus: 0, toBus: 1, format: buffer.format)
                    inputPlayer.play()
                    inputStarted = true
                }
                inputPlayer.scheduleBuffer(buffer, at: nil, options: [])
            case .audioOutput:
                if !outputStarted {
                    audioEngine.connect(outputPlayer, to: mixer, fromBus: 0, toBus: 0, format: buffer.format)
                    outputPlayer.play()
                    outputStarted = true
                }
                outputPlayer.scheduleBuffer(buffer, at: nil, options: [])
            default:
                break
            }
        }
    }
}
