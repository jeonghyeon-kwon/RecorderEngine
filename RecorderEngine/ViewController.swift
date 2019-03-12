//
//  ViewController.swift
//  Recorder
//
//  Created by kwon-jh on 06/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet private var startButton: UIButton!
    @IBOutlet private var pauseButton: UIButton!
    @IBOutlet private var colorView: UIView!

    private var manager: ReplayManager?

    enum State {
        case none
        case started
        case paused
        case finieded
    }

    private var state = State.none

    deinit {
        timer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        startButton.setTitle("Start", for: .normal)
        pauseButton.setTitle("Pause", for: .normal)

        manager = ReplayManager()

        prepareTimer()
    }

    @IBAction func touchButton(_ sender: Any) {
        if startButton.isEqual(sender) {
            switch state {
            case .none:
                startButton.setTitle("Stop", for: .normal)
                manager?.start()
                state = .started
            case .started:
                startButton.setTitle("Start", for: .normal)
                manager?.stop()
                state = .finieded
            default:
                break
            }
        } else {
            switch state {
            case .started:
                pauseButton.setTitle("Resum", for: .normal)
                manager?.pause()
                state = .paused
            case .paused:
                pauseButton.setTitle("Pause", for: .normal)
                manager?.resum()
                state = .started
            default:
                break
            }
        }
    }

    var timer: Timer?

    func prepareTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let r = CGFloat.random(in: 0.0..<1.0)
            let g = CGFloat.random(in: 0.0..<1.0)
            let b = CGFloat.random(in: 0.0..<1.0)
            self.colorView.backgroundColor = UIColor(red: r, green: g, blue: b, alpha: 1.0)
        }
    }
}

