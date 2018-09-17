# Cough Detector 

===========================================================================

## DESCRIPTION:

Cough Detector is a real-time cough detection app through microphone. The algorithm is based upon paper Detection of cough signals in continuous audio recordings using hidden Markov models (https://ieeexplore.ieee.org/iel5/10/34273/01634502.pdf) published in 2006 which used MFCC and HMM to give cough event detection results. The data collection part is directly using the open source audio processing project aurioTouch (https://developer.apple.com/library/archive/samplecode/aurioTouch/Introduction/Intro.html) developed by Apple Inc. and translated from C++ to swift by OOPer in cooperation with shlab.jp, on 2015/2/1. Feature extraction and classification algorithms are both implemented by HTK (Hidden markov model ToolKit) developed by Cambridge University. (http://htk.eng.cam.ac.uk/) The corresponding modules for obatining MFCC vectors and classification results are HCopy and HVite, respectively. The original C code is modified in order to be compiled together with the swift code. Memory leakage and unlimited file opening problems are also solved. Unrelated code is removed especially for displaying a real-time sound save and FFT results. Also, this app provides a button to record your cough data and automatically sent to a remote server for further training. All DSP computations are optimized by calling the GPU-accelerating functions in module vDSP of Accelerate developed by Apple. (https://developer.apple.com/documentation/accelerate/vdsp) 

In general, this app is an indicator showing a sign on the screen when someone nearby coughs. It also shows the happening times of last five coughs.

===========================================================================

## PACKAGING LIST IN CLASSES:

EAGLView.swift
AudioController.swift
aurioTouchAppDelegate.swift
BufferManager.swift
DCRejectionFilter.swift

Above files are performing same functions as those in original version do. Please see below for details.

DSPHelper.swift -> renamed from FFTHelper.swift

WebService.swift

The class for sending sound wave data to local or remote server for visualizing or storage.

FileStringTool.swift

A tool class for converting absolute path, file name and glue code for using HTK library.xs

===========================================================================

## Compiling Instructions

Download project and switch to develop branch. 

	git clone https://github.com/eniacluo/CoughDetector.git
	cd CoughDetector
	git checkout develop

Open CoughDetector.xcodeproj by Xcode.

Connect your iPhone and Run the app on your iPhone.

Follow instructions to update if your building version or xcode version is lower than ios 11 and xcode 9.4.

================================================================================

Developed by Simon Luo in Sensorweb Lab, Center of Cyber Physical Systems in University of Georgia. All rights reserved.



**ABOVE IS THE OLD VERSION README FILE OF ORIGINAL PROJECT aurioTouch**


# aurioTouch-swift

Translated by OOPer in cooperation with shlab.jp, on 2015/2/1.

Based on
<https://developer.apple.com/library/content/samplecode/aurioTouch/Introduction/Intro.html#//apple_ref/doc/uid/DTS40007770>
2016-08-12.

As this is a line-by-line translation from the original sample code, "redistribute the Apple Software in its entirety and without modifications" would apply. See license terms in each file.
Some faults caused by my translation may exist. Not all features tested.
You should not contact to Apple or SHLab(jp) about any faults caused by my translation.

===========================================================================

##BUILD REQUIREMENTS:

Xcode 9.3

===========================================================================

Files under PublicUtility are not fully translated. Their license terms are kept there just to indicate the original files.
Some utility files are used to make line-by-line translation easier. They have another license terms.
See license terms in each file.


# aurioTouch

===========================================================================

## DESCRIPTION:

aurioTouch demonstrates use of the remote i/o audio unit for handling audio input and output. The application can display the input audio in one of the forms, a regular time domain waveform, a frequency domain waveform (computed by performing a fast fourier transform on the incoming signal), and a sonogram view (a view displaying the frequency content of a signal over time, with the color signaling relative power, the y axis being frequency and the x as time). Tap the sonogram button to switch to a sonogram view, tap anywhere on the screen to return to the oscilloscope. Tap the FFT button to perform and display the input data after an FFT transform. Pinch in the oscilloscope view to expand and contract the scale for the x axis.

The code in aurioTouch uses the remote i/o audio unit (AURemoteIO) for input and output of audio, and OpenGL for display of the input waveform. The application also uses AVAudioSession to manage route changes (as described in the Audio Session Programming Guide).

This application shows how to:

	* Set up the remote i/o audio unit for input and output.
	* Use OpenGL for graphical display of audio waveforms.
	* Use touch events such as tapping and pinching for user interaction
	* Use AVAudioSession Services to handle route changes and reconfigure the unit in response.
	* Use AVAudioSession Services to set an audio session category for concurrent input and output.
	* Use AudioServices to create and play system sounds
	

===========================================================================

## BUILD REQUIREMENTS:

Xcode 7.3.1 or later, iOS SDK 9.0 or later


===========================================================================

## RUNTIME REQUIREMENTS:

iPhone: iOS 9.0


===========================================================================

## PACKAGING LIST:

EAGLView.h
EAGLView.m

This class wraps the CAEAGLLayer from CoreAnimation into a convenient UIView subclass. This class is also responsible for handling touch events and drawing.

AudioController.h
AudioController.mm

This class demonstrates the audio APIs used to capture audio data from the microphone and play it out to the speaker. It also demonstrates how to play system sounds.

aurioTouchAppDelegate.h
aurioTouchAppDelegate.mm

The application delegate for the aurioTouch app.

FFTHelper.h
FFTHelper.cpp

This class demonstrates how to use the Accelerate framework to take Fast Fourier Transforms (FFT) of the audio data. FFTs are used to perform analysis on the captured audio data

BufferManager.h
BufferManager.cpp

This class handles buffering of audio data that is shared between the view and audio controller

DCRejectionFilter.h
DCRejectionFilter.cpp

This class implements a DC offset filter

CAMath.h

CAMath is a helper class for various math functions.

CADebugMacros.h
CADebugMacros.cpp

A helper class for printing debug messages.

CAXException.h
CAXException.cpp

A helper class for exception handling.

CAStreamBasicDescription.cpp
CAStreamBasicDescription.h

A helper class for AudioStreamBasicDescription handling and manipulation.

================================================================================

Copyright (C) 2008-2016 Apple Inc. All rights reserved.
