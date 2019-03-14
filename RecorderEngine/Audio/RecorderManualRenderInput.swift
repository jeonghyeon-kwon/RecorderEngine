//
//  RecorderManualRenderInput.swift
//  Recorder
//
//  Created by kwon-jh on 12/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation
import AVFoundation


class RecorderManualRenderInput: RecorderPushInput {
    let type: Recorder.TrackType = .audioInput
    weak var recorder: Recorder?

    let engine = AVAudioEngine()
    let mic = AVAudioPlayerNode()
    let speaker = AVAudioPlayerNode()

    let maximumFrameCount: AVAudioFrameCount = 1024
    let commonPCMFormat: AVAudioFormat

    init() {
        commonPCMFormat = engine.mainMixerNode.outputFormat(forBus: 0)
    }

    func prepare() {
        prepareEngine()
        prepareInputNode()
    }

    var renderBlock: AVAudioEngineManualRenderingBlock?

    private func prepareEngine() {
        engine.attach(mic)
        engine.attach(speaker)

        engine.connect(engine.inputNode, to: engine.mainMixerNode, fromBus: 0, toBus: 0, format: nil)

        engine.stop()

        do {
            try engine.enableManualRenderingMode(.realtime, format: commonPCMFormat, maximumFrameCount: maximumFrameCount)
        } catch {
            print(error)
            assertionFailure()
        }

        renderBlock = engine.manualRenderingBlock
    }

    var inputNodeFrameCount: AVAudioFrameCount = 0
    var inputNodeBuffer: AVAudioPCMBuffer?

    private func prepareInputNode() {
        if !engine.inputNode.setManualRenderingInputPCMFormat(commonPCMFormat) { [weak self] (frameCount) -> UnsafePointer<AudioBufferList>? in
            guard let self = self else { return nil }

            if frameCount != self.inputNodeFrameCount {
                self.inputNodeFrameCount = frameCount
                self.inputNodeBuffer = AVAudioPCMBuffer(pcmFormat: self.commonPCMFormat, frameCapacity: frameCount)
                self.inputNodeBuffer?.frameLength = self.maximumFrameCount

                if let bufferList = self.inputNodeBuffer?.mutableAudioBufferList {
                    for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                        if let data = buffer.mData {
                            memset(data, 0, Int(buffer.mDataByteSize))
                        }
                    }
                }
            }

            return self.inputNodeBuffer?.audioBufferList
            } {
            assertionFailure()
        }
    }

    func start() {
        do {
            try engine.start()
            startTimer()
        } catch {
            print(error)
            assertionFailure()
        }
    }

    var queue: DispatchQueue?
    var timer: DispatchSourceTimer?

    private func startTimer() {
        queue = DispatchQueue(label: "Audio Manual Rendering Queue")
        timer = DispatchSource.makeTimerSource(queue: queue)

        let fps = Double(maximumFrameCount) / commonPCMFormat.sampleRate
        timer?.schedule(deadline: .now(), repeating: fps)
        timer?.setEventHandler { [weak self] in
            self?.render()
        }

        timer?.resume()
    }

    private func render() {
        guard let renderBlock = renderBlock,
            let buffer = AVAudioPCMBuffer(pcmFormat: commonPCMFormat, frameCapacity: maximumFrameCount) else { return }

        buffer.frameLength = maximumFrameCount

        var outputError = noErr
        let status = renderBlock(maximumFrameCount, buffer.mutableAudioBufferList, &outputError)

        switch status {
        case .success:
            convert(buffer: buffer)
        default:
            print(outputError)
            break
        }
    }

    func convert(buffer: AVAudioPCMBuffer) {
        let sampleRate = CMTimeScale(commonPCMFormat.sampleRate)
        let sampleCount = CMTimeValue(CACurrentMediaTime() * commonPCMFormat.sampleRate)
        var cmFormat: CMAudioFormatDescription?

        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       asbd: commonPCMFormat.streamDescription,
                                       layoutSize: 0,
                                       layout: nil,
                                       magicCookieSize: 0,
                                       magicCookie: nil,
                                       extensions: nil,
                                       formatDescriptionOut: &cmFormat)

        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: sampleRate),
                                            presentationTimeStamp: CMTime(value: sampleCount, timescale: sampleRate),
                                            decodeTimeStamp: .invalid)

        CMSampleBufferCreate(allocator: kCFAllocatorDefault,
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
            let status = CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer,
                                                                        blockBufferAllocator: kCFAllocatorDefault,
                                                                        blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                                        flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                                        bufferList: buffer.audioBufferList)
            if status != noErr {
                assertionFailure()
            }

            CMSampleBufferSetDataReady(sampleBuffer)

            recorder?.append(audioBuffer: sampleBuffer, type: type)
        }
    }

    func finish() {
        timer?.cancel()
        engine.stop()
        engine.detach(mic)
        engine.detach(speaker)
    }

    var inputStarted = false
    var outputStarted = false

    func process(sampleBuffer: CMSampleBuffer, type: Recorder.TrackType) {
        guard let cmFormat = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            assertionFailure()
            return
        }

        let fromFormat = AVAudioFormat(cmAudioFormatDescription: cmFormat)
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: fromFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            assertionFailure()
            return
        }

        buffer.frameLength = AVAudioFrameCount(frames)

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else {
            assertionFailure()
            return
        }

        guard let toFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fromFormat.sampleRate, channels: fromFormat.channelCount, interleaved: false),
            let converter = AVAudioConverter(from: fromFormat, to: toFormat),
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: toFormat, frameCapacity: AVAudioFrameCount(frames)) else { return }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { (packetCount, status) -> AVAudioBuffer? in
            status.pointee = .haveData
            return buffer
        }

        if status != .haveData {
            print("Recorder Manual Rendering convert error")
            assertionFailure()
        }

        queue?.sync {
            switch type {
            case .audioInput:
                if !inputStarted {
                    inputStarted = true
                    engine.connect(mic, to: engine.mainMixerNode, fromBus: 0, toBus: 1, format: toFormat)
                    mic.play()
                }
                mic.scheduleBuffer(convertedBuffer, at: nil, options: [])
            case .audioOutput:
                if !outputStarted {
                    outputStarted = true
                    engine.connect(speaker, to: engine.mainMixerNode, fromBus: 0, toBus: 2, format: toFormat)
                    speaker.play()
                }
                speaker.scheduleBuffer(convertedBuffer, at: nil, options: [])
            default:
                break
            }
        }
    }
}

