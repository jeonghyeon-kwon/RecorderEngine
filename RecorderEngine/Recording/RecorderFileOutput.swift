//
//  RecorderFileOutput.swift
//  Recorder
//
//  Created by kwon-jh on 06/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

final class RecorderFileOutput {

    struct RecorderData {
        let pixelBuffer: CVPixelBuffer?
        let audioBuffer: CMSampleBuffer?
        let presentationTime: CMTime?

        init(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
            self.pixelBuffer = pixelBuffer
            self.audioBuffer = nil
            self.presentationTime = presentationTime
        }

        init(audioBuffer: CMSampleBuffer) {
            self.pixelBuffer = nil
            self.audioBuffer = audioBuffer
            self.presentationTime = nil
        }
    }

    class RecorderFileOutputInput {
        private let dispatchQueue: DispatchQueue
        private let dispatchGroup: DispatchGroup
        private var writerInput: AVAssetWriterInput?
        private var writerInputAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        private var dataQueue = [RecorderData]()
        private weak var writer: AVAssetWriter?

        let inputType: Recorder.TrackType

        init(queue: DispatchQueue, group: DispatchGroup, type: Recorder.TrackType) {
            dispatchQueue = queue
            dispatchGroup = group
            inputType = type

            switch type {
            case .audioInput, .audioOutput:
                prepareAudio()
            case .video:
                prepareVideo()
            default:
                assertionFailure()
            }
        }

        private func prepareAudio() {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            writerInput?.expectsMediaDataInRealTime = true
        }

        private func prepareVideo() {
            var size = UIScreen.main.fixedCoordinateSpace.bounds.size
            let scale = UIScreen.main.scale

            size.width *= scale
            size.height *= scale

            if size.width > 1080 {
                size.height = size.height * 1080 / size.width
                size.width = 1080
            }
            if size.height > 1920 {
                size.width = size.width * 1920 / size.height
                size.height = 1920
            }

            let width = Int32(size.width.rounded())
            let height = Int32(size.height.rounded())
            let widthPadding = (4 - (width % 4)) % 4
            let heightPadding = (4 - (height % 4)) % 4

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width + widthPadding,
                AVVideoHeightKey: height + heightPadding,
                AVVideoCleanApertureKey: [
                    AVVideoCleanApertureWidthKey: width,
                    AVVideoCleanApertureHeightKey: height,
                    AVVideoCleanApertureHorizontalOffsetKey: widthPadding / 2,
                    AVVideoCleanApertureVerticalOffsetKey: heightPadding / 2
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2_000_000
                ]
            ]

            writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)

            if let writerInput = writerInput {
                writerInput.expectsMediaDataInRealTime = true

                let pixelOption = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]

                writerInputAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: pixelOption)
            }
        }

        func addInput(toWriter: AVAssetWriter) -> Bool {
            if let writerInput = writerInput, toWriter.canAdd(writerInput) {
                toWriter.add(writerInput)
                writer = toWriter
                return true
            } else {
                assertionFailure()
                return false
            }
        }

        func finish() {
            writerInput?.markAsFinished()
        }

        func append(audioBuffer: CMSampleBuffer) {
            dispatchQueue.async(group: dispatchGroup,
                                qos: .default,
                                flags: .assignCurrentContext,
                                execute: { [weak self] in
                                    guard let self = self else { return }

                                    if self.process() {
                                        self.appendAudioData(audioBuffer)
                                    } else {
                                        self.dataQueue.append(RecorderData(audioBuffer: audioBuffer))
                                    }
            })
        }

        func append(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
            dispatchQueue.async(group: dispatchGroup,
                                qos: .default,
                                flags: .assignCurrentContext,
                                execute: { [weak self] in
                                    guard let self = self else { return }

                                    if self.process() {
                                        self.appendVideoData(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
                                    } else {
                                        self.dataQueue.append(RecorderData(pixelBuffer: pixelBuffer, presentationTime: presentationTime))
                                    }
            })

        }

        private func process() -> Bool {
            guard !dataQueue.isEmpty else { return true }

            var failIndex = dataQueue.count
            for (index, data) in dataQueue.enumerated() {
                let success: Bool
                if inputType == .video {
                    success = appendVideoData(data)
                } else {
                    success = appendAudioData(data)
                }

                if !success {
                    failIndex = index
                    break
                }
            }
            dataQueue.removeFirst(failIndex)

            return dataQueue.isEmpty
        }

        private func appendAudioData(_ data: RecorderData) -> Bool {
            guard let audioBuffer = data.audioBuffer else {
                assertionFailure()
                return false
            }

            return appendAudioData(audioBuffer)
        }

        private func appendVideoData(_ data: RecorderData) -> Bool {
            guard let pixelBuffer = data.pixelBuffer,
                let presentationTime = data.presentationTime else {
                    assertionFailure()
                    return false
            }

            return appendVideoData(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
        }

        @discardableResult private func appendAudioData(_ audioBuffer: CMSampleBuffer) -> Bool {
            guard let writerInput = writerInput else {
                assertionFailure()
                return false
            }

            if writerInput.isReadyForMoreMediaData {
                if !writerInput.append(audioBuffer) {
                    if let error = writer?.error {
                        print("[RecorderFileOutput.appendAudioData] \(error)")
                    }
                }
                return true
            }
            return false
        }

        @discardableResult private func appendVideoData(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> Bool {
            guard let writerInput = writerInput,
                let writerInputAdaptor = writerInputAdaptor else {
                    assertionFailure()
                    return false
            }

            if writerInput.isReadyForMoreMediaData {
                if !writerInputAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                    if let error = writer?.error {
                        print("[RecorderFileOutput.appendVideoData] \(error)")
                    }
                }
                return true
            }
            return false
        }
    }

    private var videoURL: URL?
    private var writer: AVAssetWriter?
    private var dispatchQueue: DispatchQueue?
    private var dispatchGroup: DispatchGroup?
    private var inputs: [RecorderFileOutputInput] = []

    func prepare(trackTypes: Recorder.TrackType, videoURL: URL) {
        print(#function)

        do {
            if FileManager.default.fileExists(atPath: videoURL.path) {
                try FileManager.default.removeItem(at: videoURL)
            }

            try writer = AVAssetWriter(outputURL: videoURL, fileType: .mp4)
        } catch {
            assertionFailure()
        }

        dispatchQueue = DispatchQueue(label: "NCXVoIP-VideoRecorder")
        dispatchGroup = DispatchGroup()

        if let dispatchQueue = dispatchQueue,
            let dispatchGroup = dispatchGroup,
            let writer = writer {

            trackTypes.forEach {
                let input = RecorderFileOutputInput(queue: dispatchQueue, group: dispatchGroup, type: $0)

                if input.addInput(toWriter: writer) {
                    inputs.append(input)
                }
            }

            if !writer.startWriting() {
                assertionFailure()
            }
        }
    }

    func start(time: CMTime) {
        writer?.startSession(atSourceTime: time)
    }

    func cancel() {
        writer?.cancelWriting()
        clean()
    }

    func finish(time: CMTime, _ completion: @escaping (Bool) -> Void) {
        guard let dispatchQueue = dispatchQueue,
            let dispatchGroup = dispatchGroup else { return }

        dispatchGroup.notify(queue: dispatchQueue, execute: { [weak self] in
            guard let self = self else { return }

            self.inputs.forEach { $0.finish() }
            self.writer?.endSession(atSourceTime: time)
            self.writer?.finishWriting {
                let success: Bool

                if let writer = self.writer, writer.status == .completed {
                    success = true
                } else {
                    success = false
                }

                self.clean()
                completion(success)
            }
        })
    }

    func clean() {
        writer = nil
        dispatchQueue = nil
        dispatchGroup = nil
        inputs.removeAll()
    }

    func append(audioBuffer: CMSampleBuffer, type: Recorder.TrackType) {
        inputs.first(where: { $0.inputType == type })?.append(audioBuffer: audioBuffer)
    }

    func append(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        inputs.first(where: { $0.inputType == .video })?.append(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }
}
