//
//  RecorderFileOutput.swift
//  Recorder
//
//  Created by kwon-jh on 06/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import Photos

final class Recorder {
    struct TrackType: OptionSet {
        let rawValue: Int

        static let audioInput = TrackType(rawValue: 1 << 0)
        static let audioOutput = TrackType(rawValue: 1 << 1)
        static let video = TrackType(rawValue: 1 << 2)
    }

    private enum State {
        case none
        case prepared
        case started
        case paused
        case finishing
        case finished
    }

    var isPrepared: Bool {
        return state == .prepared
    }
    var isRunning: Bool {
        return state == .started
    }
    var isFinished: Bool {
        return state == .finished
    }
    var isPaused: Bool {
        return state == .paused
    }
    
    var currentMediaTime: CMTime { return CMClockGetTime(CMClockGetHostTimeClock()) }
    var videoURL = FileManager.default.temporaryDirectory.appendingPathComponent("asdfsadfsadf.mp4")
    private var state: State = .none
    private var trackTypes: TrackType = []

    private var inputs: [RecorderInput] = []
    private var fileOutput = RecorderFileOutput()

    deinit {
        print("Recorder \(#function) state \(state)")
    }

    func prepare() {
        print("Recorder \(#function) state \(state)")

        guard state == .none || state == .finished else {
            assertionFailure()
            return
        }

        inputs.forEach { $0.prepare() }
        fileOutput.prepare(trackTypes: trackTypes, videoURL: videoURL)
        state = .prepared
    }

    func start() {
        print("Recorder \(#function) state \(state)")

        guard state == .prepared else {
            assertionFailure()
            return
        }

        inputs.forEach { $0.start() }
        fileOutput.start(time: currentMediaTime)
        state = .started
    }

    func pause() {
        //TODO:
        assertionFailure()
    }

    func resum() {
        //TODO:
        assertionFailure()
    }

    func cancel() {
        print("Recorder \(#function) state \(state)")

        if state == .started || state == .paused {
            inputs.forEach { $0.finish() }
            fileOutput.cancel()
            state = .none
        }
    }

    func finish(_ completion: (() -> Void)? = nil) {
        print("Recorder \(#function) state \(state)")

        guard state == .started else { return }

        state = .finishing
        inputs.forEach { $0.finish() }

        fileOutput.finish(time: currentMediaTime) { [weak self] (success) in
            guard let self = self else { return }

            self.state = .finished

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.videoURL)
            }, completionHandler: { (success, error) in
                if !success, let error = error {
                    print(error)
                }
            })
        }
    }
}

extension Recorder {
    func canAdd(input: RecorderInput) -> Bool {
        if trackTypes.contains(input.type) {
            return false
        }
        return true
    }

    func add(input: RecorderInput) {
        if canAdd(input: input) {
            inputs.append(input)
            trackTypes.insert(input.type)
        } else {
            assertionFailure()
        }
    }

    func remove(inputType: TrackType) {
        if trackTypes.contains(inputType) {
            inputs = inputs.filter { $0.type != inputType }
            trackTypes.remove(inputType)
        }
    }

    func replace(input: RecorderInput) {
        remove(inputType: input.type)
        add(input: input)
    }
}

extension Recorder {
    func append(audioBuffer: CMSampleBuffer, type: TrackType) {
        guard isRunning else { return }

        fileOutput.append(audioBuffer: audioBuffer, type: type)
    }

    func append(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard isRunning else { return }

        fileOutput.append(pixelBuffer: pixelBuffer, presentationTime: presentationTime)
    }

}
