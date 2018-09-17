//
//  EAGLView.swift
//  aurioTouch
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/2/1.
//
//
/*

 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 This class wraps the CAEAGLLayer from CoreAnimation into a convenient UIView subclass

 */

// Framework includes
import Foundation
import UIKit
import OpenGLES

@objc(EAGLView)
class EAGLView: UIView {
    
    var applicationResignedActive: Bool = false
    
    private final let USE_DEPTH_BUFFER = true
    private final let SPECTRUM_BAR_WIDTH = 4
    
    
    func CLAMP<T: Comparable>(_ min: T, _ x: T, _ max: T) -> T {return x < min ? min : (x > max ? max : x)}
    
    
    // value, a, r, g, b
    typealias ColorLevel = (interpVal: GLfloat, a: GLfloat, r: GLfloat, g: GLfloat, b: GLfloat)
    let colorLevels: [ColorLevel] = [
        (0.0, 1.0, 0.0, 0.0, 0.0),
        (0.333, 1.0, 0.7, 0.0, 0.0),
        (0.667, 1.0, 0.0, 0.0, 1.0),
        (1.0, 1.0, 0.0, 1.0, 1.0),
    ]
    
    private final let kMinDrawSamples = 64
    private final let kMaxDrawSamples = 4096
    
    
    struct SpectrumLinkedTexture {
        var texName: GLuint
        var nextTex: UnsafeMutablePointer<SpectrumLinkedTexture>?
    }
    
    
    //    /* The pixel dimensions of the backbuffer */
    private var backingWidth: GLint = 0
    private var backingHeight: GLint = 0
    
    private var context: EAGLContext!
    
    /* OpenGL names for the renderbuffer and framebuffers used to render to this view */
    private var viewRenderbuffer: GLuint = 0
    private var viewFramebuffer: GLuint = 0
    
    /* OpenGL name for the depth buffer that is attached to viewFramebuffer, if it exists (0 if it does not exist) */
    private var depthRenderbuffer: GLuint = 0
    
    private var animationTimer: Timer?
    private var animationInterval: TimeInterval = 0
    private var animationStarted: TimeInterval = 0
    
    private var DetectionResultOverlay: UIImageView!
    private var labelDetectionResult: UILabel!

    private var initted_spectrum: Bool = false
    private var texBitBuffer: UnsafeMutablePointer<UInt32> =  UnsafeMutablePointer.allocate(capacity: 512)
    private var spectrumRect: CGRect = CGRect()

    private var firstTex: UnsafeMutablePointer<SpectrumLinkedTexture>? = nil

    private var l_fftData: UnsafeMutablePointer<Float32>!
    
    private var audioController: AudioController = AudioController()
    
    private var buttonStart: UIButton = UIButton(type: UIButtonType.roundedRect)
    private var buttonStop: UIButton = UIButton(type: UIButtonType.roundedRect)
    private var buttonRecord: UIButton = UIButton(type: UIButtonType.roundedRect)
    private var buttonPause: UIButton = UIButton(type: UIButtonType.roundedRect)
    private var textField: UITextField = UITextField()
    private var labelEvent: UILabel!
    private var labelName: UILabel!
    
    // You must implement this
    override class var layerClass: AnyClass {
        return CAEAGLLayer.self
    }
    
    //The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
    required init?(coder: NSCoder) {
        // Set up our overlay view that pops up when we are pinching/zooming the oscilloscope
        super.init(coder: coder)
        
        self.frame = UIScreen.main.bounds
        
        // Get the layer
        let eaglLayer = self.layer as! CAEAGLLayer
        
        eaglLayer.isOpaque = true
        
        eaglLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking : false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8,
        ]
        
        context = EAGLContext(api: .openGLES1)
        
        if context == nil || !EAGLContext.setCurrent(context) || !self.createFramebuffer() {
            fatalError("cannot initialize EAGLView")
        }
        
        l_fftData = UnsafeMutablePointer.allocate(capacity: audioController.bufferManagerInstance.FFTOutputBufferLength)
        bzero(l_fftData, size_t(audioController.bufferManagerInstance.FFTOutputBufferLength * MemoryLayout<Float32>.size))
        
        self.setupGLView()
        self.drawView()
        
        self.setupUIViews()

        // Set up the view to refresh at 20 hz
        self.setAnimationInterval(1.0/20.0)
        self.startAnimation()
        
    }
    
    @objc func buttonStartPressed()
    {
        let bufferManager = audioController.bufferManagerInstance
        if !bufferManager.isStartSession {
            bufferManager.isStartSession = true
            buttonStart.isEnabled = false
            buttonStop.isEnabled = true
            // buttonRecord.isHidden = false
            // buttonPause.isHidden = false
            // labelName.isHidden = false
            // textField.isHidden = false
            audioController.playButtonPressedSound()
            bufferManager.sendRealtimeData()
            WebService.sharedInstance.isStartRecording = true
            textField.endEditing(true)
            self.setupViewForSpectrum()
            self.clearTextures()
        }
    }
    
    @objc func buttonStopPressed()
    {
        let bufferManager = audioController.bufferManagerInstance
        if bufferManager.isStartSession {
            bufferManager.isStartSession = false
            buttonStart.isEnabled = true
            buttonStop.isEnabled = false
            // buttonRecord.isHidden = true
            // buttonPause.isHidden = true
            // labelName.isHidden = true
            // textField.isHidden = true
            audioController.playButtonPressedSound()
            DetectionResultOverlay.removeFromSuperview()
            bufferManager.stopSendingRealtimeData()
            WebService.sharedInstance.isStartRecording = false
        }
    }
    
    @objc func buttonRecordPressed()
    {
        buttonRecord.isEnabled = false
        buttonPause.isEnabled = true
        let bufferManager = audioController.bufferManagerInstance
        bufferManager.sendRealtimeData()
        WebService.sharedInstance.isStartRecording = true
        textField.endEditing(true)
    }
    
    @objc func buttonPausePressed()
    {
        buttonPause.isEnabled = false
        buttonRecord.isEnabled = true
        let bufferManager = audioController.bufferManagerInstance
        bufferManager.stopSendingRealtimeData()
        WebService.sharedInstance.isStartRecording = false
    }
    
    @objc func buttonClearPressed()
    {
        let bufferManager = audioController.bufferManagerInstance
        bufferManager.eventString = ""
        bufferManager.eventCount = 0
        labelEvent.text = ""
    }
    
    @objc func userDidNameChanged()
    {
        if textField.text! == "" {
            buttonRecord.isEnabled = false
        } else {
            buttonRecord.isEnabled = true
            WebService.sharedInstance.setUsername(name: textField.text!)
            let defaults = UserDefaults.standard
            defaults.set(textField.text!, forKey: "Username")
        }
    }
    
    override func layoutSubviews() {
        EAGLContext.setCurrent(context)
        self.destroyFramebuffer()
        self.createFramebuffer()
        self.drawView()
    }
    
    @discardableResult
    private func createFramebuffer() -> Bool {
        glGenFramebuffersOES(1, &viewFramebuffer)
        glGenRenderbuffersOES(1, &viewRenderbuffer)
        
        glBindFramebufferOES(GL_FRAMEBUFFER_OES.ui, viewFramebuffer)
        glBindRenderbufferOES(GL_RENDERBUFFER_OES.ui, viewRenderbuffer)
        context.renderbufferStorage(GL_RENDERBUFFER_OES.l, from: (self.layer as! EAGLDrawable))
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES.ui, GL_COLOR_ATTACHMENT0_OES.ui, GL_RENDERBUFFER_OES.ui, viewRenderbuffer)
        
        glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES.ui, GL_RENDERBUFFER_WIDTH_OES.ui, &backingWidth)
        glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES.ui, GL_RENDERBUFFER_HEIGHT_OES.ui, &backingHeight)
        
        if USE_DEPTH_BUFFER {
            glGenRenderbuffersOES(1, &depthRenderbuffer)
            glBindRenderbufferOES(GL_RENDERBUFFER_OES.ui, depthRenderbuffer)
            glRenderbufferStorageOES(GL_RENDERBUFFER_OES.ui, GL_DEPTH_COMPONENT16_OES.ui, backingWidth, backingHeight)
            glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES.ui, GL_DEPTH_ATTACHMENT_OES.ui, GL_RENDERBUFFER_OES.ui, depthRenderbuffer)
        }
        
        if glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES.ui) != GL_FRAMEBUFFER_COMPLETE_OES.ui {
            NSLog("failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES.ui))
            return false
        }
        
        return true
    }
    
    
    private func destroyFramebuffer() {
        glDeleteFramebuffersOES(1, &viewFramebuffer)
        viewFramebuffer = 0
        glDeleteRenderbuffersOES(1, &viewRenderbuffer)
        viewRenderbuffer = 0
        
        if depthRenderbuffer != 0 {
            glDeleteRenderbuffersOES(1, &depthRenderbuffer)
            depthRenderbuffer = 0
        }
    }
    
    
    @objc func startAnimation() {
        animationTimer = Timer.scheduledTimer(timeInterval: animationInterval, target: self, selector: #selector(self.drawView as () -> ()), userInfo: nil, repeats: true)
        animationStarted = Date.timeIntervalSinceReferenceDate
        audioController.startIOUnit()
    }
    
    
    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        // !!!!!!  need to make sure audioController has been running
        audioController.stopIOUnit()
    }
    
    
    private func setAnimationInterval(_ interval: TimeInterval) {
        animationInterval = interval
        
        if animationTimer != nil {
            self.stopAnimation()
            self.startAnimation()
        }
    }
    
    private func setupUIViews()
    {
        // Set up our overlay view that pops up when we are pinching/zooming the oscilloscope
        var img_ui: UIImage? = nil
        // Draw the rounded rect for the bg path using this convenience function
        let bgPath = EAGLView.createRoundedRectPath(CGRect(x: 0, y: 0, width: 110, height: 234), 15.0)
        
        let cs = CGColorSpaceCreateDeviceRGB()
        // Create the bitmap context into which we will draw
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        let cxt = CGContext(data: nil, width: 110, height: 234, bitsPerComponent: 8, bytesPerRow: 4*110, space: cs, bitmapInfo: bitmapInfo.rawValue)
        cxt?.setFillColorSpace(cs)
        let fillClr: [CGFloat] = [0.0, 0.0, 0.0, 0.7]
        cxt?.setFillColor(fillClr)
        // Add the rounded rect to the context...
        cxt?.addPath(bgPath)
        // ... and fill it.
        cxt?.fillPath()
        
        // Make a CGImage out of the context
        let img_cg = cxt?.makeImage()
        // Make a UIImage out of the CGImage
        img_ui = UIImage(cgImage: img_cg!)
        
        // Create the image view to hold the background rounded rect which we just drew
        DetectionResultOverlay = UIImageView(image: img_ui)
        DetectionResultOverlay.frame = CGRect(x: 25, y: 210, width: 325, height: 50)
        
        // Create the text view which shows the size of our oscilloscope window as we pinch/zoom
        labelDetectionResult = UILabel(frame: CGRect(x: 0, y: 0, width: 325, height: 100))
        labelDetectionResult.textAlignment = NSTextAlignment.center
        labelDetectionResult.textColor = UIColor.white
        labelDetectionResult.text = ""
        labelDetectionResult.font = UIFont.boldSystemFont(ofSize: 36.0)
        // Rotate the text view since we want the text to draw top to bottom (when the device is oriented vertically)
        labelDetectionResult.backgroundColor = UIColor.clear
        
        // Add the text view as a subview of the overlay BG
        DetectionResultOverlay.addSubview(labelDetectionResult)
        
        buttonStart.frame = CGRect(x: 25, y: 440, width: 150, height:  40)
        buttonStart.setTitle("Start", for: UIControlState.normal)
        buttonStart.backgroundColor = UIColor.clear
        buttonStart.addTarget(self, action: #selector(buttonStartPressed), for: .touchUpInside)
        buttonStart.setTitleColor(UIColor.white, for: .normal)
        buttonStart.setTitleColor(UIColor.gray, for: .disabled)
        buttonStart.layer.borderColor = UIColor.white.cgColor
        buttonStart.layer.cornerRadius = 5.0
        buttonStart.layer.borderWidth = 1.0
        addSubview(buttonStart)
        
        buttonStop.frame = CGRect(x: 200, y: 440, width: 150, height: 40)
        buttonStop.setTitle("Stop", for: UIControlState.normal)
        buttonStop.backgroundColor = UIColor.clear
        buttonStop.addTarget(self, action: #selector(buttonStopPressed), for: .touchUpInside)
        buttonStop.isEnabled = false
        buttonStop.setTitleColor(UIColor.white, for: .normal)
        buttonStop.setTitleColor(UIColor.gray, for: .disabled)
        buttonStop.layer.borderColor = UIColor.white.cgColor
        buttonStop.layer.cornerRadius = 5.0
        buttonStop.layer.borderWidth = 1.0
        addSubview(buttonStop)
        
        buttonRecord.frame = CGRect(x: 25, y: 155, width: 150, height:  40)
        buttonRecord.setTitle("Record", for: UIControlState.normal)
        buttonRecord.backgroundColor = UIColor.clear
        buttonRecord.addTarget(self, action: #selector(buttonRecordPressed), for: .touchUpInside)
        buttonRecord.isHidden = false
        buttonRecord.setTitleColor(UIColor.white, for: .normal)
        buttonRecord.setTitleColor(UIColor.gray, for: .disabled)
        buttonRecord.layer.borderColor = UIColor.white.cgColor
        buttonRecord.layer.cornerRadius = 5.0
        buttonRecord.layer.borderWidth = 1.0
        addSubview(buttonRecord)
        
        buttonPause.frame = CGRect(x: 200, y: 155, width: 150, height: 40)
        buttonPause.setTitle("Pause", for: UIControlState.normal)
        buttonPause.backgroundColor = UIColor.clear
        buttonPause.addTarget(self, action: #selector(buttonPausePressed), for: .touchUpInside)
        buttonPause.isEnabled = false
        buttonPause.isHidden = false
        buttonPause.setTitleColor(UIColor.white, for: .normal)
        buttonPause.setTitleColor(UIColor.gray, for: .disabled)
        buttonPause.layer.borderColor = UIColor.white.cgColor
        buttonPause.layer.cornerRadius = 5.0
        buttonPause.layer.borderWidth = 1.0
        addSubview(buttonPause)
        
        let buttonClear = UIButton(frame: CGRect(x: 25, y: 500, width: 325, height: 40))
        buttonClear.setTitle("Clear", for: UIControlState.normal)
        buttonClear.backgroundColor = UIColor.clear
        buttonClear.addTarget(self, action: #selector(buttonClearPressed), for: .touchUpInside)
        buttonClear.setTitleColor(UIColor.white, for: .normal)
        buttonClear.layer.borderColor = UIColor.white.cgColor
        buttonClear.layer.cornerRadius = 5.0
        buttonClear.layer.borderWidth = 1.0
        addSubview(buttonClear)
        
        labelName = UILabel(frame: CGRect(x: 25, y: 100, width: 325, height: 30))
        labelName.textAlignment = NSTextAlignment.left
        labelName.textColor = UIColor.white
        labelName.text = "Name:"
        labelName.font = UIFont.boldSystemFont(ofSize: 20.0)
        labelName.backgroundColor = UIColor.clear
        labelName.isHidden = false
        addSubview(labelName)
        
        textField.frame = CGRect(x: 125, y: 100, width: 225, height: 30)
        textField.textColor = UIColor.black
        textField.borderStyle = .roundedRect
        textField.isHidden = false
        textField.addTarget(self, action: #selector(userDidNameChanged), for: .editingChanged)
        textField.text = UserDefaults.standard.string(forKey: "Username") ?? "User"
        addSubview(textField)
        
        // Create the text view which shows the size of our oscilloscope window as we pinch/zoom
        labelEvent = UILabel(frame: CGRect(x: 25, y: 275, width: 300, height: 150))
        labelEvent.textAlignment = NSTextAlignment.left
        labelEvent.textColor = UIColor.white
        labelEvent.text = ""
        labelEvent.font = UIFont.boldSystemFont(ofSize: 14.0)
        // Rotate the text view since we want the text to draw top to bottom (when the device is oriented vertically)
        //labelEvent.transform = CGAffineTransform(rotationAngle: .pi/2)
        labelEvent.backgroundColor = UIColor.clear
        labelEvent.numberOfLines = 0 // Unlimited lines
        //labelEvent.sizeToFit()
        addSubview(labelEvent)
        
        let labelCoughDetector = UILabel(frame: CGRect(x: 25, y: 25, width: 325, height: 50))
        labelCoughDetector.textAlignment = NSTextAlignment.center
        labelCoughDetector.textColor = UIColor.red
        labelCoughDetector.text = "Cough Detector"
        labelCoughDetector.font = UIFont.boldSystemFont(ofSize: 30.0)
        //labelCoughDetector.layer.borderWidth = 1.0
        //labelCoughDetector.layer.borderColor = UIColor.red.cgColor
        labelCoughDetector.backgroundColor = UIColor.clear
        labelCoughDetector.numberOfLines = 1 // Unlimited lines
        addSubview(labelCoughDetector)
        
        let labelLine = UILabel(frame: CGRect(x: 25, y: 85, width: 325, height: 1))
        labelLine.backgroundColor = UIColor.white
        addSubview(labelLine)
        
        let imageUGA = UIImageView(frame: CGRect(x: 25, y: 600, width: 325, height: 40))
        imageUGA.image = UIImage(named: "uga-logo.png")
        addSubview(imageUGA)
        
        let labelLabName = UILabel(frame: CGRect(x: 25, y: 550, width: 325, height: 40))
        labelLabName.textAlignment = NSTextAlignment.center
        labelLabName.textColor = UIColor.gray
        labelLabName.text = "Sensorweb Research Laboratory"
        labelLabName.font = UIFont.boldSystemFont(ofSize: 18.0)
        labelLabName.backgroundColor = UIColor.clear
        labelLabName.numberOfLines = 1 // Unlimited lines
        addSubview(labelLabName)
        
    }
    
    private func setupGLView() {
        // Sets up matrices and transforms for OpenGL ES
        glViewport(0, 0, backingWidth, backingHeight)
        glMatrixMode(GL_PROJECTION.ui)
        glLoadIdentity()
        glOrthof(0, GLfloat(backingWidth), 0, GLfloat(backingHeight), -1.0, 1.0)
        glMatrixMode(GL_MODELVIEW.ui)
        
        // Clears the view with black
        glClearColor(0.0, 0.0, 0.0, 1.0)
        
        glEnableClientState(GL_VERTEX_ARRAY.ui)
    }
    
    
    // Updates the OpenGL view when the timer fires
    @objc func drawView() {
        // the NSTimer seems to fire one final time even though it's been invalidated
        // so just make sure and not draw if we're resigning active
        if self.applicationResignedActive { return }
        
        // Make sure that you are drawing to the current context
        EAGLContext.setCurrent(context)
        
        glBindFramebufferOES(GL_FRAMEBUFFER_OES.ui, viewFramebuffer)

        self.drawView(self, forTime: Date.timeIntervalSinceReferenceDate - animationStarted)
        
        glBindRenderbufferOES(GL_RENDERBUFFER_OES.ui, viewRenderbuffer)
        context.presentRenderbuffer(GL_RENDERBUFFER_OES.l)
    }
    
    private func clearTextures() {
        bzero(texBitBuffer, size_t(MemoryLayout<UInt32>.size * 512))
        
        var curTex = firstTex
        while curTex != nil {
            glBindTexture(GL_TEXTURE_2D.ui, (curTex?.pointee.texName)!)
            glTexImage2D(GL_TEXTURE_2D.ui, 0, GL_RGBA, 1, 512, 0, GL_RGBA.ui, GL_UNSIGNED_BYTE.ui, texBitBuffer)
            curTex = curTex?.pointee.nextTex
        }
    }
    
    private func setupViewForSpectrum() {
        
        spectrumRect = CGRect(x: 10.0, y: 10.0, width: 460.0, height: 300.0)
        
        //For cough count
        labelDetectionResult.text = String("-")
        self.addSubview(DetectionResultOverlay)
        
        // The bit buffer for the texture needs to be 512 pixels, because OpenGL textures are powers of
        // two in either dimensions. Our texture is drawing a strip of 300 vertical pixels on the screen,
        // so we need to step up to 512 (the nearest power of 2 greater than 300).
        texBitBuffer = UnsafeMutablePointer.allocate(capacity: 512)
        
        // Clears the view with black
        glClearColor(0.0, 0.0, 0.0, 1.0)
        
        glEnableClientState(GL_VERTEX_ARRAY.ui)
        glEnableClientState(GL_TEXTURE_COORD_ARRAY.ui)
        
        let texCount = Int(ceil(spectrumRect.width / CGFloat(SPECTRUM_BAR_WIDTH)))
        var texNames: UnsafeMutablePointer<GLuint>
        
        texNames = UnsafeMutablePointer.allocate(capacity: texCount)
        glGenTextures(GLsizei(texCount), texNames)
        
        var curTex: UnsafeMutablePointer<SpectrumLinkedTexture>? = nil
        firstTex = UnsafeMutablePointer.allocate(capacity: 1)
        firstTex?.pointee.texName = texNames[0]
        firstTex?.pointee.nextTex = nil
        curTex = firstTex
        
        bzero(texBitBuffer, size_t(MemoryLayout<UInt32>.size * 512))
        
        glBindTexture(GL_TEXTURE_2D.ui, (curTex?.pointee.texName)!)
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_MIN_FILTER.ui, GL_NEAREST)
        
        for i in 1..<texCount {
            curTex?.pointee.nextTex = UnsafeMutablePointer.allocate(capacity: 1)
            curTex = curTex?.pointee.nextTex
            curTex?.pointee.texName = texNames[i]
            curTex?.pointee.nextTex = nil
            
            glBindTexture(GL_TEXTURE_2D.ui, (curTex?.pointee.texName)!)
            glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_MIN_FILTER.ui, GL_NEAREST)
        }
        
        // Enable use of the texture
        glEnable(GL_TEXTURE_2D.ui)
        // Set a blending function to use
        glBlendFunc(GL_ONE.ui, GL_ONE_MINUS_SRC_ALPHA.ui)
        // Enable blending
        glEnable(GL_BLEND.ui)
        
        initted_spectrum = true
        
        texNames.deallocate()
    }
    
    
    private func cycleSpectrum() {
        var newFirst: UnsafeMutablePointer<SpectrumLinkedTexture>
        newFirst = UnsafeMutablePointer.allocate(capacity: 1)
        newFirst.pointee.nextTex = firstTex
        firstTex = newFirst
        
        var thisTex = firstTex
        repeat {
            if thisTex?.pointee.nextTex?.pointee.nextTex == nil {
                firstTex?.pointee.texName = (thisTex?.pointee.nextTex?.pointee.texName)!
                thisTex?.pointee.nextTex?.deallocate()
                thisTex?.pointee.nextTex = nil
            }
            thisTex = thisTex?.pointee.nextTex
        } while thisTex != nil
    }
    
    private func linearInterp<T: FloatingPoint>(_ valA: T, _ valB: T, _ fract: T) -> T {
        return valA + ((valB - valA) * fract)
    }
    private func linearInterpUInt8(_ valA: GLfloat, _ valB: GLfloat, _ fract: GLfloat) -> UInt8 {
        return UInt8(255.0 * linearInterp(valA, valB, fract))
    }
    
    private func renderFFTToTex() {
        self.cycleSpectrum()
        
        var texBitBuffer_ptr = texBitBuffer
        
        let numLevels = colorLevels.count
        
        let maxY = Int(spectrumRect.height)
        let bufferManager = audioController.bufferManagerInstance
        let fftLength = bufferManager.FFTOutputBufferLength
        for y in 0..<maxY {
            let yFract = CGFloat(y) / CGFloat(maxY - 1)
            let fftIdx = yFract * (CGFloat(fftLength) - 1)
            
            var fftIdx_i: Double = 0
            let fftIdx_f = modf(Double(fftIdx), &fftIdx_i)
            
            let lowerIndex = Int(fftIdx_i)
            var upperIndex = lowerIndex + 1
            upperIndex = (upperIndex == fftLength) ? fftLength - 1 : upperIndex
            
            let fft_l_fl = CGFloat(l_fftData[lowerIndex] + 80) / 64.0
            let fft_r_fl = CGFloat(l_fftData[upperIndex] + 80) / 64.0
            var interpVal = GLfloat(fft_l_fl * (1.0 - CGFloat(fftIdx_f)) + fft_r_fl * CGFloat(fftIdx_f))
            
            interpVal = sqrt(CLAMP(0.0, interpVal, 1.0))
            
            var newPx: UInt32 = 0xFF000000
            
            for level_i in 0 ..< numLevels-1  {
                let thisLevel = colorLevels[level_i]
                let nextLevel = colorLevels[level_i + 1]
                if thisLevel.interpVal <= GLfloat(interpVal) && nextLevel.interpVal >= GLfloat(interpVal) {
                    let fract = (interpVal - thisLevel.interpVal) / (nextLevel.interpVal - thisLevel.interpVal)
                    newPx =
                        UInt32(linearInterpUInt8(thisLevel.a, nextLevel.a, fract)) << 24
                        |
                        UInt32(linearInterpUInt8(thisLevel.r, nextLevel.r, fract)) << 16
                        |
                        UInt32(linearInterpUInt8(thisLevel.g, nextLevel.g, fract)) << 8
                        |
                        UInt32(linearInterpUInt8(thisLevel.b, nextLevel.b, fract))
                }
                
            }
            
            texBitBuffer_ptr.pointee = newPx
            texBitBuffer_ptr += 1
        }
        
        glBindTexture(GL_TEXTURE_2D.ui, (firstTex?.pointee.texName)!)
        glTexImage2D(GL_TEXTURE_2D.ui, 0, GL_RGBA, 1, 512, 0, GL_RGBA.ui, GL_UNSIGNED_BYTE.ui, texBitBuffer)
    }
    
    private func drawSpectrum() {
        // Clear the view
        glClear(GL_COLOR_BUFFER_BIT.ui)
        
        let bufferManager = audioController.bufferManagerInstance
        if bufferManager.hasNewFFTData {
            bufferManager.GetFFTOutput(l_fftData)
            self.renderFFTToTex()
        }
        
        glClear(GL_COLOR_BUFFER_BIT.ui)
        
        glEnable(GL_TEXTURE.ui)
        glEnable(GL_TEXTURE_2D.ui)
        
        glPushMatrix()
        glTranslatef(0.0, 480.0, 0.0)
        glRotatef(-90.0, 0.0, 0.0, 1.0)
        glTranslatef(spectrumRect.origin.x.f + spectrumRect.size.width.f, spectrumRect.origin.y.f, 0.0)
        
        let quadCoords: [GLfloat] = [
            0.0, 0.0,
            SPECTRUM_BAR_WIDTH.f, 0.0,
            0.0, 512.0,
            SPECTRUM_BAR_WIDTH.f, 512.0,
        ]
        
        let texCoords: [GLshort] = [
            0, 0,
            1, 0,
            0, 1,
            1, 1,
        ]
        
        glVertexPointer(2, GL_FLOAT.ui, 0, quadCoords)
        glEnableClientState(GL_VERTEX_ARRAY.ui)
        glTexCoordPointer(2, GL_SHORT.ui, 0, texCoords)
        glEnableClientState(GL_TEXTURE_COORD_ARRAY.ui)
        
        glColor4f(1.0, 1.0, 1.0, 1.0)
        
        glPushMatrix()
        var thisTex = firstTex
        while thisTex != nil {
            glTranslatef(-(SPECTRUM_BAR_WIDTH).f, 0.0, 0.0)
            glBindTexture(GL_TEXTURE_2D.ui, (thisTex?.pointee.texName)!)
            glDrawArrays(GL_TRIANGLE_STRIP.ui, 0, 4)
            thisTex = thisTex?.pointee.nextTex
        }
        glPopMatrix()
        glPopMatrix()
        
        glFlush()
    }
    
    
    private func drawView(_ sender: AnyObject, forTime time: TimeInterval) {
        if !audioController.audioChainIsBeingReconstructed {  //hold off on drawing until the audio chain has been reconstructed
            if audioController.bufferManagerInstance.isStartSession {
                if !initted_spectrum { self.setupViewForSpectrum() }
                self.drawSpectrum()
                self.displayRecentDetectResult()
            }
        }
    }
    
    private func displayRecentDetectResult()
    {
        let bufferManager = audioController.bufferManagerInstance
        if bufferManager.recentResult == "COUGH" {
            labelDetectionResult.textColor = UIColor.red
        } else {
            labelDetectionResult.textColor = UIColor.white
        }
        labelDetectionResult.text = bufferManager.recentResult
        labelEvent.text = bufferManager.eventString
    }
    
    private class func createRoundedRectPath(_ RECT: CGRect, _ _cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        
        let maxRad = max(RECT.height / 2.0, RECT.width / 2.0)
        
        var cornerRadius = _cornerRadius
        if cornerRadius > maxRad {cornerRadius = maxRad}
        
        let bl = RECT.origin
        var br = RECT.origin
        var tl = RECT.origin
        var tr = RECT.origin
        
        tl.y += RECT.size.height
        tr.y += RECT.size.height
        tr.x += RECT.size.width
        br.x += RECT.size.width
        
        path.move(to: CGPoint(x: bl.x + cornerRadius, y: bl.y))
        path.addArc(tangent1End: CGPoint(x: bl.x, y: bl.y), tangent2End: CGPoint(x: bl.x, y: bl.y + cornerRadius), radius: cornerRadius)
        path.addLine(to: CGPoint(x: tl.x, y: tl.y - cornerRadius))
        path.addArc(tangent1End: CGPoint(x: tl.x, y: tl.y), tangent2End: CGPoint(x: tl.x + cornerRadius, y: tl.y), radius: cornerRadius)
        path.addLine(to: CGPoint(x: tr.x - cornerRadius, y: tr.y))
        path.addArc(tangent1End: CGPoint(x: tr.x, y: tr.y), tangent2End: CGPoint(x: tr.x, y: tr.y - cornerRadius), radius: cornerRadius)
        path.addLine(to: CGPoint(x: br.x, y: br.y + cornerRadius))
        path.addArc(tangent1End: CGPoint(x: br.x, y: br.y), tangent2End: CGPoint(x: br.x - cornerRadius, y: br.y), radius: cornerRadius)
        
        path.closeSubpath()
        
        let ret = path.copy()
        return ret!
    }
    
    private func createGLTexture(_ texName: inout GLuint, fromCGImage img: CGImage) {
        var texW: size_t, texH: size_t
        
        let imgW = img.width
        let imgH = img.height
        
        // Find smallest possible powers of 2 for our texture dimensions
        texW = 1; while texW < imgW {texW *= 2}
        texH = 1; while texH < imgH {texH *= 2}
        
        // Allocated memory needed for the bitmap context
        let spriteData: UnsafeMutablePointer<GLubyte> = UnsafeMutablePointer.allocate(capacity: Int(texH * texW * 4))
        bzero(spriteData, texH * texW * 4)
        // Uses the bitmatp creation function provided by the Core Graphics framework.
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let spriteContext = CGContext(data: spriteData, width: texW, height: texH, bitsPerComponent: 8, bytesPerRow: texW * 4, space: img.colorSpace!, bitmapInfo: bitmapInfo.rawValue)
        
        // Translate and scale the context to draw the image upside-down (conflict in flipped-ness between GL textures and CG contexts)
        spriteContext?.translateBy(x: 0.0, y: texH.g)
        spriteContext?.scaleBy(x: 1.0, y: -1.0)
        
        // After you create the context, you can draw the sprite image to the context.
        spriteContext?.draw(img, in: CGRect(x: 0.0, y: 0.0, width: imgW.g, height: imgH.g))
        // You don't need the context at this point, so you need to release it to avoid memory leaks.
        
        // Use OpenGL ES to generate a name for the texture.
        glGenTextures(1, &texName)
        // Bind the texture name.
        glBindTexture(GL_TEXTURE_2D.ui, texName)
        // Speidfy a 2D texture image, provideing the a pointer to the image data in memory
        glTexImage2D(GL_TEXTURE_2D.ui, 0, GL_RGBA, GLsizei(texW), GLsizei(texH), 0, GL_RGBA.ui, GL_UNSIGNED_BYTE.ui, spriteData)
        // Set the texture parameters to use a minifying filter and a linear filer (weighted average)
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_MIN_FILTER.ui, GL_LINEAR)
        
        // Enable use of the texture
        glEnable(GL_TEXTURE_2D.ui)
        // Set a blending function to use
        glBlendFunc(GL_SRC_ALPHA.ui, GL_ONE.ui)
        //glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        // Enable blending
        glEnable(GL_BLEND.ui)
        
        spriteData.deallocate()
    }
 
    // Stop animating and release resources when they are no longer needed.
    deinit {
        self.stopAnimation()
        
        if EAGLContext.current() === context {
            EAGLContext.setCurrent(nil)
        }

        l_fftData?.deallocate()
        texBitBuffer.deallocate()
        var texPtr = firstTex
        while texPtr != nil {
            let nextPtr = texPtr?.pointee.nextTex
            texPtr?.deallocate()
            texPtr = nextPtr
        }
        
    }
    
    
}
