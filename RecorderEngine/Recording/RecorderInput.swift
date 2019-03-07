//
//  RecorderInput.swift
//  Recorder
//
//  Created by kwon-jh on 06/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation
import AVFoundation

protocol RecorderInput {
    var type: Recorder.TrackType { get }
    var recorder: Recorder? { get set }

    func prepare()
    func start()
    func finish()
}

class RecorderAudioInput: RecorderInput {
    let type: Recorder.TrackType
    weak var recorder: Recorder?

    init(type: Recorder.TrackType) {
        self.type = type
    }

    func prepare() {}
    func start() {}
    func finish() {}

    func process(sampleBuffer: CMSampleBuffer) {
        recorder?.append(audioBuffer: sampleBuffer, type: type)
    }
}

class RecorderVideoInput: RecorderInput {
    let type: Recorder.TrackType = .video
    weak var recorder: Recorder?

    func prepare() {}
    func start() {}
    func finish() {}

    func process(sampleBuffer: CMSampleBuffer) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            recorder?.append(pixelBuffer: pixelBuffer, presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
    }
}
