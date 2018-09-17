//
//  BufferManager.swift
//  aurioTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/1/30.
//
//
/*

 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 This class handles buffering of audio data that is shared between the view and audio controller

 */

import AudioToolbox
import libkern
import AVFoundation
import Accelerate

let kNumFrameBuffers = 16
let kDefaultFrameSamples = 1024
let kDelayBufferCount = 16

class BufferManager {
    // Flag of whether time consuming process starts
    var isStartSession = false
    
    //for FFT Buffer
    private var mFFTInputBuffer: UnsafeMutablePointer<Float32>?
    private var mFFTInputBufferFrameIndex: Int
    private var mFFTInputBufferLen: Int
    var FFTOutputBufferLength: Int {return mFFTInputBufferLen / 2}
    private var mHasNewFFTData: Int32   //volatile
    private var mNeedsNewFFTData: Int32 //volatile
    var hasNewFFTData: Bool {return mHasNewFFTData != 0}
    var needsNewFFTData: Bool {return mNeedsNewFFTData != 0}
    
    //for sending data to database
    private var sendingBuffer: UnsafeMutablePointer<Float32>?
    var isSendingRealtimeData:Bool = false;
    
    //for HMM Buffer
    private(set) var frameBuffers: UnsafeMutablePointer<UnsafeMutablePointer<Float32>?>
    private var mFrameBufferIndex: Int
    private var mFrameSampleIndex: Int
    var backgroundSigma: Float = 0.01
    var startBufferIndex = 0
    var isStartSound = false
    private(set) var MFCCBuffers: UnsafeMutablePointer<Float32>?
    var recentResult = "SILENCE"
    var delayIndex = 0
    var eventCount = 0;
    var eventString: String!
    var eventTime = [String]()
    
    private var mDSPHelper: DSPHelper
    
    init(maxFramesPerSlice inMaxFramesPerSlice: Int) {//4096
        frameBuffers = UnsafeMutablePointer.allocate(capacity: Int(kNumFrameBuffers))
        mFrameBufferIndex = 0
        mFrameSampleIndex = 0
        mFFTInputBuffer = nil
        mFFTInputBufferFrameIndex = 0
        mFFTInputBufferLen = inMaxFramesPerSlice
        mHasNewFFTData = 0
        mNeedsNewFFTData = 0
        for i in 0..<kNumFrameBuffers {
            frameBuffers[Int(i)] = UnsafeMutablePointer.allocate(capacity: Int(kDefaultFrameSamples))
        }
        mFFTInputBuffer = UnsafeMutablePointer.allocate(capacity: Int(inMaxFramesPerSlice))
        
        mDSPHelper = DSPHelper(maxFramesPerSlice: inMaxFramesPerSlice)
        OSAtomicIncrement32Barrier(&mNeedsNewFFTData)
    }
    
    
    deinit {
        mFFTInputBuffer?.deallocate()
        
        for i in 0..<kNumFrameBuffers {
            frameBuffers[Int(i)]?.deallocate()
            frameBuffers[Int(i)] = nil
        }
        frameBuffers.deallocate()
    }
    
    func CopyAudioDataToFFTInputBuffer(_ inData: UnsafePointer<Float32>, numFrames: Int) {
        let framesToCopy = min(numFrames, mFFTInputBufferLen - mFFTInputBufferFrameIndex)
        memcpy(mFFTInputBuffer?.advanced(by: mFFTInputBufferFrameIndex), inData, size_t(framesToCopy * MemoryLayout<Float32>.size))
        mFFTInputBufferFrameIndex += framesToCopy * MemoryLayout<Float32>.size
        if mFFTInputBufferFrameIndex >= mFFTInputBufferLen {
            OSAtomicIncrement32(&mHasNewFFTData)
            OSAtomicDecrement32(&mNeedsNewFFTData)
        }
    }
    
    func GetFFTOutput(_ outFFTData: UnsafeMutablePointer<Float32>) {
        mDSPHelper.computeFFT(mFFTInputBuffer, outFFTData: outFFTData)
        mFFTInputBufferFrameIndex = 0
        OSAtomicDecrement32Barrier(&mHasNewFFTData)
        OSAtomicIncrement32Barrier(&mNeedsNewFFTData)
    }
    
    func copyAudioDataToSendingBuffer(_ inData: UnsafePointer<Float32>?, inNumFrames: Int) {
        if inData == nil { return }
        
        if isSendingRealtimeData == true {
            sendingBuffer = UnsafeMutablePointer.allocate(capacity: inNumFrames)
            memcpy(sendingBuffer, inData, size_t(inNumFrames * MemoryLayout<Float32>.size))
            WebService.sharedInstance.sendRealtimeData(data: sendingBuffer, length: inNumFrames)
            sendingBuffer?.deallocate()
        }
        
    }
    
    func sendRealtimeData() {
        //isSendingRealtimeData = true
    }
    
    func stopSendingRealtimeData() {
        //isSendingRealtimeData = false
    }
    
    func copyAudioDataToFrameBuffer(_ inData: UnsafePointer<Float32>?, inNumFrames: Int) {
        if inData == nil { return }
        
        for i in 0..<inNumFrames {//256
            if i + mFrameSampleIndex >= kDefaultFrameSamples {//1024
                mFrameSampleIndex = 0//concat buffer data with next one
                let outVar: UnsafeMutablePointer<Float32> = UnsafeMutablePointer.allocate(capacity: 1)
                // calculating the moving window variance to do changing point detection to segment
                vDSP_rmsqv(frameBuffers[mFrameBufferIndex]!, 1, outVar, vDSP_Length(kDefaultFrameSamples))
                if outVar.pointee > 3 * backgroundSigma && isStartSound == false {
                    isStartSound = true
                    startBufferIndex = mFrameBufferIndex
                } else if (outVar.pointee < backgroundSigma || (mFrameBufferIndex + 1) % kNumFrameBuffers == startBufferIndex) && isStartSound == true {
                    // satisfy one of the following two conditions:
                    // 1. the variance is less than 1*sigma_background
                    // 2. the length is greater than 16*1024/44100=370ms
                    // make a copy to MFCCBuffer to run feature extraction and HMM Viterbi decoder
                    isStartSound = false
                    let copyBufferCount = ((mFrameBufferIndex - startBufferIndex + kNumFrameBuffers) % kNumFrameBuffers + 1)
                    MFCCBuffers = UnsafeMutablePointer.allocate(capacity: copyBufferCount * kDefaultFrameSamples)
                    var copyMFCCSampleIndex = 0
                    for i in startBufferIndex..<startBufferIndex + copyBufferCount {
                        memcpy(MFCCBuffers?.advanced(by: copyMFCCSampleIndex * kDefaultFrameSamples), frameBuffers[i % kNumFrameBuffers], size_t(kDefaultFrameSamples * MemoryLayout<Float32>.size))
                        copyMFCCSampleIndex += 1
                    }
                    writeAudioFile(pcmBuffer: MFCCBuffers, frameCount: copyBufferCount * kDefaultFrameSamples, filename: "record.wav")
                    
                    createMFCCFile(wavFilename: "record.wav")
                    getHMMResult(wavFilename: "record.wav")
                    
                    // If HMM Viterbi results are successful obtained, put the recognition result. Once refreshed in View, the result will display on screen
                    let result = (readFile(filename: "result.txt") ?? "no result")
                    if result != "no result" {
                        if result.contains("NON-COUGH") {
                            recentResult = "NON-COUGH"
                            delayIndex = kDelayBufferCount
                        } else {
                            recentResult = "COUGH"
                            delayIndex = kDelayBufferCount
                            eventString = "Cough Event:"
                            let currentTime = getCurrentTimeString()
                            eventTime.append(currentTime)
                            for i in 0...eventCount
                            {
                                if i > eventCount - 5 {
                                    eventString = "\(eventString!)\n #\(i+1): \(eventTime[i])"
                                }
                            }
                            eventCount += 1
                            if WebService.sharedInstance.isStartRecording {
                                WebService.sharedInstance.uploadCoughEvent2()
                                WebService.sharedInstance.uploadRawSound()
                            }
                        }
                    }
                    MFCCBuffers?.deallocate()
                }
                if delayIndex > 0 {
                    delayIndex -= 1
                    if delayIndex == 0 {
                        recentResult = "SILENCE"
                    }
                }
 
                outVar.deallocate()
 
                mFrameBufferIndex = (mFrameBufferIndex + 1) % kNumFrameBuffers
            }
            frameBuffers[mFrameBufferIndex]?[i + mFrameSampleIndex] = (inData?[i])!
        }
        mFrameSampleIndex += inNumFrames
    }
    
}
