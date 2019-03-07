//
//  Replay.swift
//  Recorder
//
//  Created by kwon-jh on 06/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation
import ReplayKit

final class ReplayManager {
    private let recorder: Recorder

    var isMicrophoneEnabled = true

    init(recorder: Recorder) {
        self.recorder = recorder
    }

    deinit {
        
    }

    func start() {
        let screenRecorder = RPScreenRecorder.shared()

        guard screenRecorder.isAvailable, !screenRecorder.isRecording else { return }

        screenRecorder.isMicrophoneEnabled = isMicrophoneEnabled
        screenRecorder.startCapture(handler: { (sampleBuffer, type, error) in
            guard let error = error else {
                print(error)
                return
            }

            switch type {
            case .audioApp:
                break
            case .audioMic:
                break
            case .video:
                break
            }
        }, completionHandler: { (error) in
            guard let error = error else {
                print(error)
                return
            }

            recorder.start()
        })
    }

    func pause() {
        //TODO:
    }

    func resum() {
        //TODO:
    }

    func stop() {
        let screenRecorder = RPScreenRecorder.shared()

        guard screenRecorder.isRecording else { return }

        screenRecorder.stopCapture { (error) in
            if let error = error {
                print(error)
                recorder.cancel()
            } else {
                recorder.finish()
            }
        }
    }
}
