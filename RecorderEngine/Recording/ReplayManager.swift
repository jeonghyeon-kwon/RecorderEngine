//
//  ReplayManager.swift
//  Recorder
//
//  Created by kwon-jh on 06/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation
import ReplayKit

final class ReplayManager {
    private let recorder = Recorder()
    private let input1 = RecorderAudioInput(type: .audioInput)
    private let input2 = RecorderAudioInput(type: .audioOutput)
    private let video = RecorderVideoInput()

    init() {
        recorder.add(input: input1)
        recorder.add(input: input2)
        recorder.add(input: video)

        input1.recorder = recorder
        input2.recorder = recorder
        video.recorder = recorder
    }

    var isMicrophoneEnabled = true

    func start() {
        let screenRecorder = RPScreenRecorder.shared()

        guard screenRecorder.isAvailable, !screenRecorder.isRecording else { return }

        recorder.prepare()
        
        screenRecorder.isMicrophoneEnabled = isMicrophoneEnabled
        screenRecorder.startCapture(handler: { [weak self] (sampleBuffer, type, error) in
            guard let self = self else { return }

            if let error = error {
                print(error)
                return
            }

            switch type {
            case .audioApp:
                self.input2.process(sampleBuffer: sampleBuffer)
            case .audioMic:
                self.input1.process(sampleBuffer: sampleBuffer)
            case .video:
                self.video.process(sampleBuffer: sampleBuffer)
            }
        }, completionHandler: { [weak self] (error) in
            guard let self = self else { return }

            if let error = error {
                print(error)
            } else {
                self.recorder.start()
            }
        })
    }

    func pause() {
        recorder.pause()
    }

    func resum() {
        recorder.resum()
    }

    func stop() {
        let screenRecorder = RPScreenRecorder.shared()

        guard screenRecorder.isRecording else { return }

        screenRecorder.stopCapture { [weak self] (error) in
            guard let self = self else { return }

            if let error = error {
                print(error)
                self.recorder.cancel()
            } else {
                self.recorder.finish()
            }
        }
    }
}
