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
    private let recorder: Recorder

    init() {
        
    }

    var isMicrophoneEnabled = true

    func start() {
        let screenRecorder = RPScreenRecorder.shared()

        guard screenRecorder.isAvailable, !screenRecorder.isRecording else { return }

        screenRecorder.isMicrophoneEnabled = isMicrophoneEnabled
        screenRecorder.startCapture(handler: { [weak self] (sampleBuffer, type, error) in
            guard let self = self else { return }

            if let error = error {
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
