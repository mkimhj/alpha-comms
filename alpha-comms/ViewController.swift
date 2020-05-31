//
//  ViewController.swift
//  alpha-comms
//
//  Created by Maruchi Kim on 5/29/20.
//  Copyright © 2020 Maruchi Kim. All rights reserved.
//

import UIKit
import AVFoundation

//On the top of your swift
extension UIImage {
    func getPixelColor(pos: CGPoint) -> UIColor {

        let pixelData = self.cgImage!.dataProvider!.data
        let data: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)

        let pixelInfo: Int = ((Int(self.size.width) * Int(pos.y)) + Int(pos.x)) * 4

        let r = CGFloat(data[pixelInfo]) / CGFloat(255.0)
        let g = CGFloat(data[pixelInfo+1]) / CGFloat(255.0)
        let b = CGFloat(data[pixelInfo+2]) / CGFloat(255.0)
        let a = CGFloat(data[pixelInfo+3]) / CGFloat(255.0)

        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}

extension UIColor {
    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return (red, green, blue, alpha)
    }
}

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var cameraView: UIView!
    
    var session: AVCaptureSession?
    var device: AVCaptureDevice?
    var input: AVCaptureDeviceInput?
    var output: AVCaptureMetadataOutput?
    var prevLayer: AVCaptureVideoPreviewLayer?
    var videoOutput: AVCaptureVideoDataOutput?
    let videoQueue = DispatchQueue(label: "VIDEO_QUEUE")
    var frame: UIImage?
    var prevFrame: UIImage?
    var firstFrameIn = false
    var lastCaptureMs = 1
    var decodedBit = 0
    var preambleDetectCounter = 0
    var samplesPerBit = 4
    var sampleCounter = 0
    var sampleArray = [0, 0, 0, 0]
    var whiteSampleArray = [0, 0, 0, 0]
    var decodedSample = 0
    var prevDecodedBit = 0
    var expected = [0,1,0,0,0,1,0,0, 0,1,0,0,1,1,1,1, 0,1,0,1,0,0,1,1, 0,1,0,0,0,1,0,1, 0,0,1,0,0,0,0,0, 0,1,0,0,0,0,1,0, 0,1,0,0,1,1,1,1, 0,1,0,1,1,0,0,1, 0,1,0,1,0,0,1,1, 0,0,0,0,0,0,0,0]
    var expectedIndex = 0
    var mismatchedBits = 0
    var startDecoding = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        createSession()
        NSLog("Hello");
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        prevLayer?.frame.size = cameraView.frame.size
    }
    
    func createSession() {
        session = AVCaptureSession()
        device = AVCaptureDevice.default(for: AVMediaType.video)
        
        do{
            input = try AVCaptureDeviceInput(device: device!)
        }
        catch{
            print(error)
        }
        
        if let input = input{
            session?.addInput(input)
        }
        
        prevLayer = AVCaptureVideoPreviewLayer(session: session!)
        prevLayer?.frame.size = cameraView.frame.size
        prevLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        prevLayer?.connection?.videoOrientation = transformOrientation(orientation: UIInterfaceOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue)!)
        
        cameraView.layer.addSublayer(prevLayer!)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session?.addOutput(videoOutput)
        
        session?.startRunning()
    }
    
    func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera, .builtInWideAngleCamera, ], mediaType: .video, position: position)
        
        if let device = deviceDiscoverySession.devices.first {
            return device
        }
        return nil
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { (context) -> Void in
            self.prevLayer?.connection?.videoOrientation = self.transformOrientation(orientation: UIInterfaceOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue)!)
            self.prevLayer?.frame.size = self.cameraView.frame.size
        }, completion: { (context) -> Void in
            
        })
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    func transformOrientation(orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch orientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
    
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        if let cvImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ciimage = CIImage(cvImageBuffer: cvImageBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciimage, from: ciimage.extent) {
                prevFrame = frame
                frame = UIImage(cgImage: cgImage)
                firstFrameIn = true
                runLoop()
            }
        }
    }
    
    @objc func runLoop() {
        if (firstFrameIn && prevFrame != nil) {
            var differenceArray = [Int]()
            var whiteArray = [Int]()
            let sizeToPrint = 25
            
            for x in ((Int(frame!.size.width) / 2) - sizeToPrint) ..< ((Int(frame!.size.width) / 2) + sizeToPrint) {
                for y in ((Int(frame!.size.height) / 2) - sizeToPrint) ..< ((Int(frame!.size.height) / 2) + sizeToPrint) {
                    let pixel = frame!.getPixelColor(pos: CGPoint(x:x,y:y))
                    let prevPixel = prevFrame!.getPixelColor(pos: CGPoint(x:x,y:y))
                    
                    var white: CGFloat = 0
                    var alpha: CGFloat = 0
                    var prevWhite: CGFloat = 0
                    
                    if pixel.getWhite(&white, alpha: &alpha) {
                        white = round(255 * white)
                    }
                    
                    if prevPixel.getWhite(&prevWhite, alpha: &alpha) {
                        prevWhite = round(255 * prevWhite)
                    }
                    
//                    differenceArray.append(Int(white - prevWhite))
                    differenceArray.append(Int(white - prevWhite))
                    whiteArray.append(Int(white))
                }
            }
            
            let arraySum = differenceArray.reduce(0, +)
            let whiteArraySum = whiteArray.reduce(0, +)
            sampleArray[sampleCounter] = arraySum
            whiteSampleArray[sampleCounter] = whiteArraySum
            sampleCounter += 1
            
            if (sampleCounter == samplesPerBit) {
                sampleCounter = 0
                let sampleCounterSum = sampleArray.reduce(0, +)
                let whiteSum = whiteSampleArray.reduce(0, +)
                
                if (sampleCounterSum > 5000) {
                    decodedBit = 0
                    if (preambleDetectCounter != 0) {
                        preambleDetectCounter += 1
                    }
                } else if (sampleCounterSum < -5000) {
                    decodedBit = 1
                    preambleDetectCounter += 1
                }
                
                if (prevDecodedBit == decodedBit) {
                    preambleDetectCounter = 0
                }
                
                if (startDecoding) {
//                    if (abs(sampleCounterSum) > )
                    print(decodedBit, expected[expectedIndex], sampleCounterSum)
                    if (decodedBit != expected[expectedIndex]) {
                        mismatchedBits += 1
                    }
                    expectedIndex += 1
                    if (expectedIndex == expected.count) {
//                        compute BER
                        print("BER: ", Float(mismatchedBits)/Float(expected.count), " mismatchedBits: ", mismatchedBits)
                        mismatchedBits = 0
                        expectedIndex = 0
                        startDecoding = false
                    }
                }
                
                if (preambleDetectCounter == 8) {
                    print("DATA START")
                    startDecoding = true
                }
                
                prevDecodedBit = decodedBit
                
            }
        }
        
    }
    
    
    
}
