//
//  RecorderInput.swift
//  Recorder
//
//  Created by kwon-jh on 06/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation

protocol RecorderInput {
    var type: Recorder.TrackType { get }
    func prepare()
    func start()
    func finish()
}
