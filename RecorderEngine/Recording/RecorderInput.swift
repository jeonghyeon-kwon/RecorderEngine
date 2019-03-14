//
//  RecorderInput.swift
//  Recorder
//
//  Created by kwon-jh on 06/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation
import AVFoundation

protocol RecorderInput: AnyObject {
    var type: Recorder.TrackType { get }
    var recorder: Recorder? { get set }

    func prepare()
    func start()
    func finish()
}

protocol RecorderPushInput: RecorderInput {
    func process(sampleBuffer: CMSampleBuffer, type: Recorder.TrackType)
}

class RecorderAudioInput: RecorderPushInput {
    let type: Recorder.TrackType
    weak var recorder: Recorder?

    init(type: Recorder.TrackType) {
        self.type = type
    }

    func prepare() {}
    func start() {}
    func finish() {}

    func process(sampleBuffer: CMSampleBuffer, type: Recorder.TrackType) {
        guard type == self.type else {
            assertionFailure()
            return
        }

        recorder?.append(audioBuffer: sampleBuffer, type: type)
    }
}

class RecorderVideoInput: RecorderPushInput {
    let type: Recorder.TrackType = .video
    weak var recorder: Recorder?

    func prepare() {}
    func start() {}
    func finish() {}

    func process(sampleBuffer: CMSampleBuffer, type: Recorder.TrackType) {
        guard type == self.type else {
            assertionFailure()
            return
        }

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            recorder?.append(pixelBuffer: pixelBuffer, presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
    }
}
