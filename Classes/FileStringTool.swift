//
//  FileManager.swift
//  aurioTouch
//
//  Created by Zhiwei Luo on 6/2/18.
//

import Foundation
import AVFoundation

var _audioPlayer: AVAudioPlayer? = nil
// if set it as local variable, the sound cannot be played because it may be recycled

public func MD5(string: String) -> Data {
    let messageData = string.data(using:.utf8)!
    var digestData = Data(count: Int(CC_MD5_DIGEST_LENGTH))
    
    _ = digestData.withUnsafeMutableBytes {digestBytes in
        messageData.withUnsafeBytes {messageBytes in
            CC_MD5(messageBytes, CC_LONG(messageData.count), digestBytes)
        }
    }
    
    return digestData
}

public func getCurrentTimeString2() -> String
{
    let currentData = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMddHHmmss"
    dateFormatter.locale = Locale.current
    let dateString = dateFormatter.string(from: currentData)
    return dateString
}

public func getCurrentTimeString() -> String
{
    let currentData = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .short
    dateFormatter.timeStyle = .medium
    let dateString = dateFormatter.string(from: currentData)
    return dateString
}

public func createMFCCFile(wavFilename: String)
{
    let urlConfigFile = URL(fileURLWithPath: Bundle.main.path(forResource: "hcopy", ofType: "conf")!)
    let wavFile = getFilePath(filename: wavFilename)
    var mfcFile = String(wavFile.dropLast(3))
    mfcFile.append("mfc")
    let argHCopy = ["HCopy", "-C", urlConfigFile.path, wavFile, mfcFile]
    
    var cargs = argHCopy.map { strdup($0) }
    HCopy(Int32(argHCopy.count), &cargs)
    for ptr in cargs {free(ptr)}
}

public func getHMMResult(wavFilename: String)
{
    let wavFile = getFilePath(filename: wavFilename)
    var mfcFile = String(wavFile.dropLast(3))
    mfcFile.append("mfc")
    
    let urlConfigFile = URL(fileURLWithPath: Bundle.main.path(forResource: "hvite", ofType: "conf")!)
    let urlNetFile = URL(fileURLWithPath: Bundle.main.path(forResource: "net", ofType: "slf")!)
    let hmmCough = URL(fileURLWithPath: Bundle.main.path(forResource: "cough", ofType: nil)!)
    let hmmSpeech = URL(fileURLWithPath: Bundle.main.path(forResource: "speech", ofType: nil)!)
    let hmmScream = URL(fileURLWithPath: Bundle.main.path(forResource: "scream", ofType: nil)!)
    let resultFile = getFilePath(filename: "result.txt")
    let dictFile = URL(fileURLWithPath: Bundle.main.path(forResource: "dict", ofType: "txt")!)
    let hmmListFile = URL(fileURLWithPath: Bundle.main.path(forResource: "hmmlist", ofType: nil)!)
    let argHVite = ["HVite", "-C", urlConfigFile.path, "-w", urlNetFile.path, "-H", hmmCough.path, "-H", hmmSpeech.path, "-H", hmmScream.path, "-i", resultFile, dictFile.path, hmmListFile.path, mfcFile]

    var cargs = argHVite.map { strdup($0) }
    HVite(Int32(argHVite.count), &cargs)
    for ptr in cargs {free(ptr)}
}

public func getFilePath(filename: String) -> String
{
    return getFileURL(filename: filename).path
}

public func getFileURL(filename: String) -> URL
{
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let url = documentsURL.appendingPathComponent(filename)
    return url
}

public func playAudioFile(filename: String)
{
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let url = documentsURL.appendingPathComponent(filename)
    
    do {
        _audioPlayer = try AVAudioPlayer(contentsOf: url)
        _audioPlayer?.play()
    } catch {
        print("couldn't play audio")
    }
}

public func writeAudioFile(pcmBuffer: UnsafeMutablePointer<Float32>?, frameCount: Int, filename: String)
{
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let url = documentsURL.appendingPathComponent(filename)
    
    let SAMPLE_RATE =  Float64(44100.0)

    let outputFormatSettings = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: true,
        //  AVLinearPCMIsBigEndianKey: false,
        AVSampleRateKey: SAMPLE_RATE,
        AVNumberOfChannelsKey: 1
    ] as [String : Any]

    let audioFile = try? AVAudioFile(forWriting: url, settings: outputFormatSettings, commonFormat: AVAudioCommonFormat.pcmFormatFloat32, interleaved: true)

    let bufferFormat = AVAudioFormat(settings: outputFormatSettings)

    let outputBuffer = AVAudioPCMBuffer(pcmFormat: bufferFormat!, frameCapacity: AVAudioFrameCount(frameCount))

    // i had my samples in doubles, so convert then write

    for i in 0..<frameCount {
        outputBuffer?.floatChannelData!.pointee[i] = Float( pcmBuffer![i] )
    }
    outputBuffer?.frameLength = AVAudioFrameCount(frameCount)

    do{
        try audioFile?.write(from: outputBuffer!)
    } catch let error as NSError {
        print("error:", error.localizedDescription)
    }
}

public func writeFile(str: String, filename: String)
{
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let filename = documentsURL.appendingPathComponent(filename)
    
    do {
        try str.write(to: filename, atomically: true, encoding: String.Encoding.utf8)
    } catch {
        // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
        print("write files failed")
    }
}

public func getFileSize(filename: String) {
    do {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = documentsURL.appendingPathComponent(filename)
        let fileSize = try (FileManager.default.attributesOfItem(atPath: filename.path) as NSDictionary).fileSize()
        print(fileSize)
    } catch let error {
        print(error)
    }
}

public func readFile(filename: URL) -> String?
{
    do {
        let text = try String(contentsOf: filename, encoding: .utf8)
        return text
    }
    catch {
        print("open file failed")
        return nil
    }
}

public func readFile(filename: String) -> String?
{
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = documentsURL.appendingPathComponent(filename)
    do {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return text
    }
    catch {
        print("open file failed")
        return nil
    }
}

public func listFiles()
{
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    do {
        let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
        print(fileURLs)
    } catch {
        print("Error while enumerating files \(documentsURL.path): \(error.localizedDescription)")
    }
}

public func deleteAllFiles()
{
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    do {
        let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
        for path in fileURLs {
            do {
                try fileManager.removeItem(at: path)
            } catch {
                print("Could not delete file: \(path)")
            }
        }
    } catch {
        
    }
}
