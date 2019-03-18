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

    var renderQueue: DispatchQueue?

    var renderBlock: AVAudioEngineManualRenderingBlock?
    let commonPCMFormat: AVAudioFormat

    var inputNodeFrameCount: AVAudioFrameCount = 0
    var inputNodeBuffer: AVAudioPCMBuffer?

    var inputStarted = false
    var outputStarted = false

    let maximumFrameCount: AVAudioFrameCount = 1024
    var startSampleCount: CMTimeValue = 0

    var renderedFrameCount: AVAudioFrameCount = 0
    var inputFrameCount: AVAudioFrameCount = 0
    var outputFrameCount: AVAudioFrameCount = 0

    init() {
        commonPCMFormat = engine.mainMixerNode.outputFormat(forBus: 0)
    }

    func prepare() {
        renderQueue = DispatchQueue(label: "Manual Rendering Queue")

        prepareEngine()
        prepareInputNode()
    }

    private func prepareEngine() {
        engine.attach(mic)
        engine.attach(speaker)

        engine.connect(engine.inputNode, to: engine.mainMixerNode, fromBus: 0, toBus: 0, format: nil)

        do {
            try engine.enableManualRenderingMode(.realtime, format: commonPCMFormat, maximumFrameCount: maximumFrameCount)
        } catch {
            print(error)
            assertionFailure()
        }

        renderBlock = engine.manualRenderingBlock
    }

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
            startSampleCount = CMTimeValue(CACurrentMediaTime() * commonPCMFormat.sampleRate)
        } catch {
            print(error)
            assertionFailure()
        }
    }

    private func render() {
        renderQueue?.sync {
            let count = (min(inputFrameCount, outputFrameCount) - renderedFrameCount) / maximumFrameCount

            for _ in 0..<count {
                renderFrame()
            }
        }
    }

    private func renderFrame() {
        guard let renderBlock = renderBlock,
            let buffer = AVAudioPCMBuffer(pcmFormat: commonPCMFormat, frameCapacity: maximumFrameCount) else { return }

        buffer.frameLength = maximumFrameCount

        var outputError = noErr
        let status = renderBlock(maximumFrameCount, buffer.mutableAudioBufferList, &outputError)

        switch status {
        case .success:
            if let sampleBuffer = convert(buffer: buffer) {
                recorder?.append(audioBuffer: sampleBuffer, type: type)
            }
        default:
            print(outputError)
            break
        }
    }

    private func convert(buffer: AVAudioPCMBuffer) -> CMSampleBuffer? {
        let sampleRate = CMTimeScale(commonPCMFormat.sampleRate)
        var cmFormat: CMAudioFormatDescription?
        let presentationTime = startSampleCount + CMTimeValue(renderedFrameCount)

        renderedFrameCount += buffer.frameLength

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
                                            presentationTimeStamp: CMTime(value: presentationTime, timescale: sampleRate),
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
        }

        return sampleBuffer
    }

    func finish() {
        engine.stop()
        engine.detach(mic)
        engine.detach(speaker)
    }

    func convert(sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let cmFormat = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            assertionFailure()
            return nil
        }

        let fromFormat = AVAudioFormat(cmAudioFormatDescription: cmFormat)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: fromFormat, frameCapacity: frames) else {
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
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: toFormat, frameCapacity: frames) else {
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

        switch type {
        case .audioInput:
            if !inputStarted {
                inputStarted = true
                engine.connect(mic, to: engine.mainMixerNode, fromBus: 0, toBus: 1, format: buffer.format)
                mic.play()
            }

            inputFrameCount += buffer.frameLength
            mic.scheduleBuffer(buffer, at: nil, options: [])
        case .audioOutput:
            if !outputStarted {
                outputStarted = true
                engine.connect(speaker, to: engine.mainMixerNode, fromBus: 0, toBus: 2, format: buffer.format)
                speaker.play()
            }

            outputFrameCount += buffer.frameLength
            speaker.scheduleBuffer(buffer, at: nil, options: [])
        default:
            break
        }

        render()
    }
}

