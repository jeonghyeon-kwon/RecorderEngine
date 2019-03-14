//
//  Extension.swift
//  Recorder
//
//  Created by kwon-jh on 14/03/2019.
//  Copyright © 2019 LinePlus. All rights reserved.
//

import Foundation


extension OptionSet where RawValue == Int {
    func forEach(_ body: (Self) -> Void) {
        var rawValue = 1
        while rawValue < self.rawValue {
            if rawValue & self.rawValue != 0 {
                body(Self(rawValue: rawValue))
            }
            rawValue = rawValue << 1
        }
    }
}
