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
    private let input: RecorderPushInput
    private let output: RecorderPushInput
    private let video: RecorderPushInput

    init() {
        if false {
            let audio = RecorderManualRenderInput()
            input = audio
            output = audio
            video = RecorderVideoInput()

            recorder.add(input: audio)
        } else {
            input = RecorderAudioInput(type: .audioInput)
            output = RecorderAudioInput(type: .audioOutput)
            video = RecorderVideoInput()

            recorder.add(input: input)
            recorder.add(input: output)
        }

        recorder.add(input: video)

        video.recorder = recorder
        input.recorder = recorder
        output.recorder = recorder
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
                self.output.process(sampleBuffer: sampleBuffer, type: .audioOutput)
            case .audioMic:
                self.input.process(sampleBuffer: sampleBuffer, type: .audioInput)
            case .video:
                self.video.process(sampleBuffer: sampleBuffer, type: .video)
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
