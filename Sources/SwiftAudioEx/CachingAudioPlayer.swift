//
//  CachingAudioPlayer.swift
//  SwiftAudioEx
//
//  Created on 3/6/25.
//

import Foundation
import AVFoundation

// MARK: - Notification Names

public extension Notification.Name {
	static let audioDownloadCompleted = Notification.Name("AudioPlayerDownloadCompleted")
	static let audioDownloadFailed = Notification.Name("AudioPlayerDownloadFailed")
	static let audioDownloadProgress = Notification.Name("AudioPlayerDownloadProgress")
}

// MARK: - User Info Keys

public enum AudioDownloadUserInfoKey: String {
	case originalURL = "originalURL"
	case localURL = "localURL"
	case error = "error"
	case progress = "progress"
	case audioItem = "audioItem"
}

// MARK: - CachingAudioPlayer

public class CachingAudioPlayer: AudioPlayer {
	
	// MARK: - Properties
	
	// Private download manager for internal use
	private let downloadManager = AudioDownloadManager.shared
	
	// MARK: - Initialization
	
	public override init(nowPlayingInfoController: NowPlayingInfoControllerProtocol = NowPlayingInfoController(),
											 remoteCommandController: RemoteCommandController = RemoteCommandController()) {
		super.init(nowPlayingInfoController: nowPlayingInfoController,
							 remoteCommandController: remoteCommandController)
		
		// Register for notifications
		registerForNotifications()
	}
	
	// MARK: - Public Methods
	
	/**
	 Loads an AudioItem into the player and simultaneously downloads the file to disk.
	 When download completes, it will automatically switch to the local file for more reliable playback.
	 
	 - Parameters:
	 - item: The AudioItem to load.
	 - destinationURL: The specific location where the file should be saved
	 - playWhenReady: Whether to start playback when the item is ready.
	 */
	public func loadAndDownload(
		item: AudioItem,
		destinationURL: URL,
		playWhenReady: Bool? = nil
	) {
		// First load the item normally to start streaming
		load(item: item, playWhenReady: playWhenReady)
		
		// Then start the download process
		downloadAudio(item: item, destinationURL: destinationURL)
	}
	
	/**
	 Downloads an audio file without loading it into the player.
	 
	 - Parameters:
	 - item: The AudioItem to download
	 - destinationURL: The specific location where the file should be saved
	 */
	public func downloadAudio(item: AudioItem, destinationURL: URL) {
		let sourceURLString = item.getSourceUrl()
		guard let sourceURL = URL(string: sourceURLString) else {
			print("Invalid source URL: \(sourceURLString)")
			return
		}
		
		// Create parent directories if needed
		let directory = destinationURL.deletingLastPathComponent()
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		
		// Start download
		downloadManager.downloadAudio(
			from: sourceURL,
			to: destinationURL,
			audioItem: item
		)
	}
	
	/**
	 Cancels any active downloads.
	 */
	public func cancelDownload() {
		downloadManager.cancelAllDownloads()
	}
	
	/**
	 Switches the current playing item from streaming to a local file.
	 This is useful when a download completes and you want to switch to the local version.
	 
	 - parameter localURL: The local URL to switch to
	 */
	public func switchToLocalFile(_ localURL: URL) {
		guard let item = currentItem else { return }
		
		// First verify the file exists and is readable
		guard FileManager.default.fileExists(atPath: localURL.path) else {
			print("Error switching to local file: File does not exist at \(localURL.path)")
			return
		}
		
		// Check file size to ensure it's a valid audio file (not zero bytes)
		do {
			let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
			let fileSize = attributes[.size] as? UInt64 ?? 0
			if fileSize == 0 {
				print("Error switching to local file: File size is zero")
				return
			}
		} catch {
			print("Error checking local file attributes: \(error.localizedDescription)")
			return
		}
		
		// Save current playback state
		let wasPlaying = self.playerState == .playing
		let currentTime = self.currentTime
		
		// Create a new AudioItem for the local file
		let localItem: DefaultAudioItemInitialTime = createLocalAudioItem(from: item, localURL: localURL) as! DefaultAudioItemInitialTime
		localItem.initialTime = currentTime
		
		print("play the downloaded file: \(localItem.getSourceUrl())")
		
		do {
			// Activate the audio session
			if !AudioSessionController.shared.audioSessionIsActive {
				try AudioSessionController.shared.activateSession()
				// TODO: What error could this throw that should be handled?
			}
			
			load(item: localItem, playWhenReady: wasPlaying)
		} catch {
			// Would be nice to catch this as a specific error, but APError.LoadError... is generating a compile error as it's an internal reference
			// From the code, looks like this is the only error that will be thrown, so safe to assume for now it's a bad URL
			// This error also only seems to throw if an empty string is provided
			print("ERROR!!! Failed to load local file: \(error.localizedDescription)")
		}
	}
	
	// MARK: - Private Methods
	
	private func registerForNotifications() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleDownloadCompleted),
			name: .audioDownloadCompleted,
			object: nil
		)
	}
	
	@objc private func handleDownloadCompleted(notification: Notification) {
		guard let userInfo = notification.userInfo,
					let originalURL = userInfo[AudioDownloadUserInfoKey.originalURL.rawValue] as? URL,
					let localURL = userInfo[AudioDownloadUserInfoKey.localURL.rawValue] as? URL else {
			return
		}
		
		print("Download completed: \(originalURL.absoluteString)")
		
		// Check if this is the currently playing item
		if let currentItem = currentItem,
				currentItem.getSourceUrl() == originalURL.absoluteString {
			// Switch to local file
			switchToLocalFile(localURL)
		}
	}
	
	private func createLocalAudioItem(from originalItem: AudioItem, localURL: URL) -> AudioItem {
		// Ensure we have a proper file URL string
		let fileURLString = localURL.path
		
		// Create a new item with the same metadata
		let localItem = DefaultAudioItemInitialTime(
			audioUrl: fileURLString,
			artist: originalItem.getArtist(),
			title: originalItem.getTitle(),
			albumTitle: originalItem.getAlbumTitle(),
			sourceType: .file,
			artwork: nil
		)
		
		// Copy artwork if available
		originalItem.getArtwork { image in
			if let image = image, let defaultItem = localItem as? DefaultAudioItemInitialTime {
				defaultItem.artwork = image
			}
		}
		
		return localItem
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}

// MARK: - Download Manager

private class AudioDownloadManager: NSObject, URLSessionDownloadDelegate {
	
	// Singleton instance
	static let shared = AudioDownloadManager()
	
	// Download session
	private lazy var downloadSession: URLSession = {
		let config = URLSessionConfiguration.background(withIdentifier: "com.SwiftAudio.downloads")
		config.isDiscretionary = false
		config.sessionSendsLaunchEvents = true
		return URLSession(configuration: config, delegate: self, delegateQueue: nil)
	}()
	
	// Active downloads: source URL -> (download task, destination URL, audio item)
	private var activeDownloads: [URL: (task: URLSessionDownloadTask, destinationURL: URL, audioItem: AudioItem?)] = [:]
	
	// MARK: - Download Methods
	
	func downloadAudio(from sourceURL: URL, to destinationURL: URL, audioItem: AudioItem? = nil) {
		print("Download started for: \(sourceURL.absoluteString)")
		print("Will download to: \(destinationURL.path)")
		
		// Cancel existing download if any
		cancelDownload(for: sourceURL)
		
		// Check if file already exists
		if FileManager.default.fileExists(atPath: destinationURL.path) {
			print("File already exists at: \(destinationURL.path)")
			
			// Notify completion immediately
			notifyDownloadCompleted(originalURL: sourceURL, localURL: destinationURL, audioItem: audioItem)
			return
		}
		
		// Start download task
		print("Starting download task")
		let downloadTask = downloadSession.downloadTask(with: sourceURL)
		activeDownloads[sourceURL] = (task: downloadTask, destinationURL: destinationURL, audioItem: audioItem)
		downloadTask.resume()
	}
	
	func cancelDownload(for url: URL) {
		if let downloadInfo = activeDownloads[url] {
			downloadInfo.task.cancel()
			activeDownloads.removeValue(forKey: url)
			print("Download canceled for: \(url.absoluteString)")
		}
	}
	
	func cancelAllDownloads() {
		for (url, downloadInfo) in activeDownloads {
			downloadInfo.task.cancel()
			print("Download canceled for: \(url.absoluteString)")
		}
		activeDownloads.removeAll()
	}
	
	// MARK: - Helper Methods
	
	private func notifyDownloadCompleted(originalURL: URL, localURL: URL, audioItem: AudioItem?) {
		var userInfo: [String: Any] = [
			AudioDownloadUserInfoKey.originalURL.rawValue: originalURL,
			AudioDownloadUserInfoKey.localURL.rawValue: localURL
		]
		
		if let audioItem = audioItem {
			userInfo[AudioDownloadUserInfoKey.audioItem.rawValue] = audioItem
		}
		
		NotificationCenter.default.post(
			name: .audioDownloadCompleted,
			object: self,
			userInfo: userInfo
		)
		
		print("Download completion notification posted for: \(originalURL.absoluteString)")
	}
	
	private func notifyDownloadFailed(originalURL: URL, error: Error, audioItem: AudioItem?) {
		var userInfo: [String: Any] = [
			AudioDownloadUserInfoKey.originalURL.rawValue: originalURL,
			AudioDownloadUserInfoKey.error.rawValue: error
		]
		
		if let audioItem = audioItem {
			userInfo[AudioDownloadUserInfoKey.audioItem.rawValue] = audioItem
		}
		
		NotificationCenter.default.post(
			name: .audioDownloadFailed,
			object: self,
			userInfo: userInfo
		)
		
		print("Download failure notification posted for: \(originalURL.absoluteString)")
	}
	
	private func notifyDownloadProgress(originalURL: URL, progress: Float, audioItem: AudioItem?) {
		var userInfo: [String: Any] = [
			AudioDownloadUserInfoKey.originalURL.rawValue: originalURL,
			AudioDownloadUserInfoKey.progress.rawValue: progress
		]
		
		if let audioItem = audioItem {
			userInfo[AudioDownloadUserInfoKey.audioItem.rawValue] = audioItem
		}
		
		NotificationCenter.default.post(
			name: .audioDownloadProgress,
			object: self,
			userInfo: userInfo
		)
	}
	
	// MARK: - URLSessionDownloadDelegate
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		guard let originalURL = downloadTask.originalRequest?.url,
					let downloadInfo = activeDownloads[originalURL] else {
			print("Download completed but URL not found in active downloads")
			return
		}
		
		let destinationURL = downloadInfo.destinationURL
		let audioItem = downloadInfo.audioItem
		
		print("Download completed for: \(originalURL.absoluteString)")
		print("Temporary location: \(location.path)")
		print("Target location: \(destinationURL.path)")
		
		do {
			// Move downloaded file to final location
			if FileManager.default.fileExists(atPath: destinationURL.path) {
				try FileManager.default.removeItem(at: destinationURL)
				print("Removed existing file at target location")
			}
			
			try FileManager.default.moveItem(at: location, to: destinationURL)
			print("File moved to target location successfully")
			
			// Remove from active downloads
			activeDownloads.removeValue(forKey: originalURL)
			
			// Verify file exists and has content
			if !FileManager.default.fileExists(atPath: destinationURL.path) {
				print("Error: File doesn't exist after move")
				notifyDownloadFailed(originalURL: originalURL,
														 error: NSError(domain: "com.SwiftAudio", code: -1,
																						userInfo: [NSLocalizedDescriptionKey: "File missing after download"]),
														 audioItem: audioItem)
				return
			}
			
			let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
			let fileSize = attributes[.size] as? UInt64 ?? 0
			print("Downloaded file size: \(fileSize) bytes")
			
			if fileSize == 0 {
				print("Error: File is empty")
				notifyDownloadFailed(originalURL: originalURL,
														 error: NSError(domain: "com.SwiftAudio", code: -2,
																						userInfo: [NSLocalizedDescriptionKey: "Downloaded file is empty"]),
														 audioItem: audioItem)
				return
			}
			
			// Notify completion
			notifyDownloadCompleted(originalURL: originalURL, localURL: destinationURL, audioItem: audioItem)
		} catch {
			print("Error moving downloaded file: \(error.localizedDescription)")
			
			// Remove from active downloads
			activeDownloads.removeValue(forKey: originalURL)
			
			// Notify failure
			notifyDownloadFailed(originalURL: originalURL, error: error, audioItem: audioItem)
		}
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		guard let originalURL = downloadTask.originalRequest?.url,
					let downloadInfo = activeDownloads[originalURL] else {
			return
		}
		
		let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
		let audioItem = downloadInfo.audioItem
		
		// Only log every 10%
		if Int(progress * 100) % 10 == 0 {
			print("Download progress for \(originalURL.lastPathComponent): \(Int(progress * 100))%")
		}
		
		DispatchQueue.main.async {
			self.notifyDownloadProgress(originalURL: originalURL, progress: progress, audioItem: audioItem)
		}
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let originalURL = task.originalRequest?.url else {
			print("Download task completed with no URL")
			return
		}
		
		if let error = error {
			print("Download failed for \(originalURL.absoluteString): \(error.localizedDescription)")
			
			guard let downloadInfo = activeDownloads[originalURL] else {
				return
			}
			
			// Remove from active downloads
			let audioItem = downloadInfo.audioItem
			activeDownloads.removeValue(forKey: originalURL)
			
			// Notify failure
			notifyDownloadFailed(originalURL: originalURL, error: error, audioItem: audioItem)
		} else {
			print("Download task completed successfully for: \(originalURL.absoluteString)")
		}
	}
}
