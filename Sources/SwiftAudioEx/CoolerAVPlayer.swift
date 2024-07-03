//
//  File.swift
//  
//
//  Created by Joe Landon on 10/9/23.
//

import Foundation
import MediaPlayer

public class CoolerAVPlayer: AudioPlayer {
	public var workaroundSeekForward: (() -> Void)?
	public var workaroundSeekBackward: (() -> Void)?
}
