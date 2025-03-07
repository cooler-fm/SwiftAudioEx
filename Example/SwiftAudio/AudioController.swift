//
//  AudioController.swift
//  SwiftAudio_Example
//
//  Created by Jørgen Henrichsen on 25/03/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import SwiftAudioEx

let veryLongAudioFile: String = "https://dts.podtrac.com/redirect.mp3/traffic.libsyn.com/dancarlinhh/dchha70_Twilight_of_the_Aesir_II.mp3"

let mediumAudioFile: String = "https://audio.transistor.fm/m/shows/48255/a2804394ae9af9370a37625c6b46830c.mp3"

let downloadSource = DefaultAudioItem(audioUrl: mediumAudioFile, artist: "Dan Carlin", title: "Mania for Subjugation II", sourceType: .stream, artwork: #imageLiteral(resourceName: "22AMI"))

class AudioController {
    
    static let shared = AudioController()
		let player: CachingAudioPlayer
	
    let sources: [AudioItem] = [
        DefaultAudioItem(audioUrl: "https://rntp.dev/example/Longing.mp3", artist: "David Chavez", title: "Longing", sourceType: .stream, artwork: #imageLiteral(resourceName: "22AMI")),
        DefaultAudioItem(audioUrl: "https://rntp.dev/example/Soul%20Searching.mp3", artist: "David Chavez", title: "Soul Searching (Demo)", sourceType: .stream, artwork: #imageLiteral(resourceName: "22AMI")),
        DefaultAudioItem(audioUrl: "https://rntp.dev/example/Lullaby%20(Demo).mp3", artist: "David Chavez", title: "Lullaby (Demo)", sourceType: .stream, artwork: #imageLiteral(resourceName: "cover")),
        DefaultAudioItem(audioUrl: "https://rntp.dev/example/Rhythm%20City%20(Demo).mp3", artist: "David Chavez", title: "Rhythm City (Demo)", sourceType: .stream, artwork: #imageLiteral(resourceName: "22AMI")),
        DefaultAudioItem(audioUrl: "https://rntp.dev/example/hls/whip/playlist.m3u8", title: "Whip", sourceType: .stream, artwork: #imageLiteral(resourceName: "22AMI")),
        DefaultAudioItem(audioUrl: "https://ais-sa5.cdnstream1.com/b75154_128mp3", artist: "New York, NY", title: "Smooth Jazz 24/7", sourceType: .stream, artwork: #imageLiteral(resourceName: "cover")),
        DefaultAudioItem(audioUrl: "https://traffic.libsyn.com/atpfm/atp545.mp3", title: "Chapters", sourceType: .stream, artwork: #imageLiteral(resourceName: "22AMI")),
    ]
	
    init() {
        let controller = RemoteCommandController()
        player = CachingAudioPlayer(remoteCommandController: controller)
        player.remoteCommands = [
            .stop,
            .play,
            .pause,
            .togglePlayPause,
            .next,
            .previous,
            .changePlaybackPosition
        ]
    }
    
}
