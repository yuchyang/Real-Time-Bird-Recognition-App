import CoreMedia
import CoreML
import UIKit
import Vision
import Toast_Swift

class ViewController: UIViewController {
    
    @IBOutlet var videoPreview: UIView!
    var videoCapture: VideoCapture!
    var currentBuffer: CVPixelBuffer?
    var pinchGesture  = UIPinchGestureRecognizer()
    var bufferImmage = CIImage()
    let coreMLModel = MobileNetV2_SSDLite()
    var dannMlMoodel = coreml_model_30c()
    let dann30Model =  coreml_model_30c()
    let dann200Model = coreml_model_200c()
    var answerLabel = UILabel()
    var resultBuffer = Dictionary<String,Float>()
    var touch = false
    var timer = Timer()
    var currentTime = Float()
    
    var frames = 1
    @IBOutlet weak var shotButton: UIButton!
    
    @IBOutlet weak var ModeSegment: UISegmentedControl!
    //    let coreMLModel = mobile()
    @IBOutlet weak var modelControll: UISegmentedControl!
    
    @IBOutlet weak var birdLabel: UILabel!
    lazy var visionModel: VNCoreMLModel = {
        do {
            return try VNCoreMLModel(for: coreMLModel.model)
        } catch {
        fatalError("Failed to create VNCoreMLModel: \(error)")
        }
    }()

        lazy var visionRequest: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: visionModel, completionHandler: {
            [weak self] request, error in
            self?.processObservations(for: request, error: error)
        })

        request.imageCropAndScaleOption = .scaleFill
        return request
    }()

    let maxBoundingBoxViews = 10
    var boundingBoxViews = [BoundingBoxView]()
    var colors: [String: UIColor] = [:]
    
    @objc func modeChange(){
        if  ModeSegment.selectedSegmentIndex == 1{
            self.shotButton.isHidden = false
            self.birdLabel.isHidden = true
        }
        else{
            self.shotButton.isHidden = true
            self.birdLabel.isHidden = false
        }

    }
    @objc func touchDown(){
        if ModeSegment.selectedSegmentIndex == 1 {
            self.touch = true
            self.view.makeToast("Analyzing", position: .center)
        }
    }

    @objc func touchUp(){
        if ModeSegment.selectedSegmentIndex == 1 {
            print(self.currentTime)
            self.touch = false
            var temp = Float(0)
            var maxResult = ""
            var total =  0.0
            let exp  = 2.718282
            for (key,value) in self.resultBuffer{
                total = total + exp*Double(value)
                if value > temp{
                    temp = value
                    maxResult = key
                }
            }
            for (key,value) in self.resultBuffer{
                self.resultBuffer[key] = Float(exp*Double(value)/total)
            }
            let results =  self.resultBuffer.sorted(by: {$0.1 > $1.1})
            var result = ""
            for i in 0...4{
                result.append(results[i].key)
                result.append(":")
                result.append(String(format: "%.2f", results[i].value))
                result.append("\n")
            }
            print(temp / Float(frames))
//            if temp / Float(frames)<0.5{
//                result = "It seems like a context"
//            }
            self.frames = 1
            self.resultBuffer.removeAll()
            self.view.hideAllToasts()
            let alert = UIAlertController(title: "Result", message: String(result), preferredStyle: .alert)
            let ok = UIAlertAction(title: "OK", style: .default, handler: {
                ACTION in
                print("OK")
            })
            alert.addAction(ok)
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.ModeSegment.setTitle("RealTime", forSegmentAt: 0)
        self.ModeSegment.setTitle("Shot", forSegmentAt: 1)
        self.ModeSegment.addTarget(self, action: #selector(modeChange), for: .valueChanged)
        self.modelControll.setTitle("AU top30", forSegmentAt: 0)
        self.modelControll.setTitle("CUB200", forSegmentAt: 1)
        
        shotButton.setImage(UIImage(named: "shutter_btn"), for: .normal)
        shotButton.addTarget(self, action: #selector(touchDown), for: .touchDown)
        shotButton.addTarget(self, action: #selector(touchUp), for: .touchUpInside)
        shotButton.isHidden = true
//        shotButton.isHidden = false
        setUpBoundingBoxViews()
        setUpCamera()
        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(ViewController.pinchedView))
        videoPreview.isUserInteractionEnabled = true
        videoPreview.addGestureRecognizer(pinchGesture)
        print(videoPreview.layer.bounds)
    }
    
    @objc func update() {

    }
    @objc func pinchedView(sender:UIPinchGestureRecognizer){
        guard let device = videoCapture.captureDevice else { return }

        if sender.state == .changed {

            let maxZoomFactor = device.activeFormat.videoMaxZoomFactor
            let pinchVelocityDividerFactor: CGFloat = 5.0

            do {

                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let desiredZoomFactor = device.videoZoomFactor + atan2(sender.velocity, pinchVelocityDividerFactor)
                device.videoZoomFactor = max(1.0, min(desiredZoomFactor, maxZoomFactor))

            } catch {
                print(error)
            }
        }
    }
    func setUpBoundingBoxViews() {
        for _ in 0..<maxBoundingBoxViews {
          boundingBoxViews.append(BoundingBoxView())
        }

    // The label names are stored inside the MLModel's metadata.
    //    guard let userDefined = coreMLModel.model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String],
    //       let allLabels = userDefined["classes"] else {
    //      fatalError("Missing metadata")
    //    }
    //
    //    let labels = allLabels.components(separatedBy: ",")
    var labels = [String]()
        for i in 1...200{
            labels.append(String(i))
        }
    // Assign random colors to the classes.
        for label in labels {
          colors[label] = UIColor(red: CGFloat.random(in: 0...1),
                                  green: CGFloat.random(in: 0...1),
                                  blue: CGFloat.random(in: 0...1),
                                  alpha: 1)
        }
    }

    func setUpCamera() {
    videoCapture = VideoCapture()
    videoCapture.delegate = self

        videoCapture.setUp(sessionPreset: .hd1280x720) { success in
            if success {
            // Add the video preview into the UI.
                if let previewLayer = self.videoCapture.previewLayer {
                  self.videoPreview.layer.addSublayer(previewLayer)
                  self.resizePreviewLayer()
                }

                // Add the bounding box layers to the UI, on top of the video preview.
                for box in self.boundingBoxViews {
                  box.addToLayer(self.videoPreview.layer)
                }

                // Once everything is set up, we can start capturing live video.
                self.videoCapture.start()
            }
        }
    }
      

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        resizePreviewLayer()
    }

    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }

    func predict(sampleBuffer: CMSampleBuffer) {
        if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            currentBuffer = pixelBuffer
            
            var options: [VNImageOption : Any] = [:]
            if let cameraIntrinsicMatrix = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            options[.cameraIntrinsics] = cameraIntrinsicMatrix
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: options)
            do {
            try handler.perform([self.visionRequest])
            } catch {
                print("Failed to perform Vision request: \(error)")
            }
            self.bufferImmage = CIImage(cvPixelBuffer: pixelBuffer)
            currentBuffer = nil
        }
    }

    func processObservations(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
          if let results = request.results as? [VNRecognizedObjectObservation] {
            self.show(predictions: results)
          } else {
            self.show(predictions: [])
          }
        }
    }
//    func show2(predictions: [VNCoreMLFeatureValueObservation]) {
//        let coordinates = predictions[0].featureValue.multiArrayValue!
//        let confidence = predictions[1].featureValue.multiArrayValue!
//
//        let confidenceThreshold = Float(10)
//        var unorderedPredictions = [Prediction]()
//        let numBoundingBoxes = confidence.shape[1].intValue
//        print(numBoundingBoxes)
//
//        let numClasses = confidence.shape[2].intValue
//        let confidencePointer = UnsafeMutablePointer<Float>(OpaquePointer(confidence.dataPointer))
//        let coordinatesPointer = UnsafeMutablePointer<Float>(OpaquePointer(coordinates.dataPointer))
//
//        for b in 0..<numBoundingBoxes {
//            var maxConfidence = Float(0)
//            var maxIndex = 0
//            for c in 0..<numClasses {
//                let conf = confidencePointer[b * numClasses + c]
//                if conf > maxConfidence {
//                    maxConfidence = conf
//                    maxIndex = c
//                }
//            }
//            if maxConfidence > confidenceThreshold {
//                let x = coordinatesPointer[b * 4]
//                let y = coordinatesPointer[b * 4 + 1]
//                let w = coordinatesPointer[b * 4 + 2]
//                let h = coordinatesPointer[b * 4 + 3]
//
//                let rect = CGRect(x: CGFloat(x - w/2), y: CGFloat(y - h/2),
//                                  width: CGFloat(w), height: CGFloat(h))
//                print(maxConfidence)
//                }
//            }
//        }
    func show(predictions: [VNRecognizedObjectObservation]) {
        var best_score = Float(0)
        var best_rect = CGRect(x: 0,y: 0,width: 0,height: 0)
        var birdImage = CIImage()
        var image2 = CIImage()
        for i in 0..<boundingBoxViews.count {
            if i < predictions.count {
                let prediction = predictions[i]
                let width = view.bounds.width
                let height = width * 16 / 9
                let offsetY = (view.bounds.height - height) / 2 - 78.5
                let scale = CGAffineTransform.identity.scaledBy(x: width, y: height)
                let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height - offsetY)
                let rect = prediction.boundingBox.applying(scale).applying(transform)

                // The labels array is a list of VNClassificationObservation objects,
                // with the highest scoring class first in the list.
                let bestClass = prediction.labels[0].identifier
                let confidence = prediction.labels[0].confidence
                
                
                
                if bestClass == "bird"{
                    let label = String(format: "%@ %.1f", bestClass, confidence * 100)
                    let color = colors[bestClass] ?? UIColor.red
                //                print(label)
                    if confidence > best_score{
                        best_score = confidence
                        best_rect = prediction.boundingBox
                    }
                    boundingBoxViews[i].show(frame: rect, label: label, color: color)
                }
                else{
                    self.birdLabel.text = ""
                }
                // Show the bounding box.
            }
            else {
                boundingBoxViews[i].hide()
            }
        }
        if self.ModeSegment.selectedSegmentIndex == 0{
            if (best_score > Float(0.9)){
                let scale2 = CGAffineTransform.identity.scaledBy(x: 720, y: 1280)
                best_rect = best_rect.applying(scale2)
                birdImage = self.bufferImmage.cropped(to: best_rect)
                image2 = self.bufferImmage
    //            var image3 = UIImage(ciImage: image2)
    //            var newBuffer = image3.toCVPixelBuffer()!
                detectScene(image: image2)
            }
        }
        else{
            if self.touch == true{
                detectScene(image: self.bufferImmage)
            }
        }

    }
}

extension ViewController: VideoCaptureDelegate {
  func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
    predict(sampleBuffer: sampleBuffer)
  }
}

extension UIImage {
    func toCVPixelBuffer() -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(self.size.width), Int(self.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard status == kCVReturnSuccess else {
            return nil
        }

        if let pixelBuffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)

            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(data: pixelData, width: Int(self.size.width), height: Int(self.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

            context?.translateBy(x: 0, y: self.size.height)
            context?.scaleBy(x: 1.0, y: -1.0)

            UIGraphicsPushContext(context!)
            self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
            UIGraphicsPopContext()
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

            return pixelBuffer
        }

        return nil
    }
}
extension ViewController {
    
  func detectScene(image: CIImage) {
    // Load the ML model through its generated class
    
    answerLabel.text = "detecting scene..."
    guard let model1 = try? VNCoreMLModel(for: dann30Model.model) else {
      fatalError("can't load Places ML model")
    }
    guard let model2 = try? VNCoreMLModel(for: dann200Model.model) else {
      fatalError("can't load Places ML model")
    }
    let model = self.modelControll.selectedSegmentIndex == 0 ? model1:model2
    // Create a Vision request with completion handler
    let request = VNCoreMLRequest(model: model) { [weak self] request, error in
      guard let results = request.results as? [VNClassificationObservation],
        let topResult = results.first  else {
          fatalError("unexpected result type from VNCoreMLRequest")
      }

      // Update UI on main queue
      DispatchQueue.main.async { [weak self] in
//        self?.answerLabel.text = topResult.
        if self?.ModeSegment.selectedSegmentIndex == 0{
            if self?.birdLabel.text  != topResult.identifier{
                self?.birdLabel.text  = topResult.identifier
            }
            
        }
        else{
            if self?.touch == true{
                for i in results{
                    if !((self?.resultBuffer.keys.contains(i.identifier))!){
                        self!.resultBuffer[i.identifier] =  i.confidence
                    }
                    else{
                        self?.resultBuffer[i.identifier] = self!.resultBuffer[i.identifier]! + i.confidence
                        self?.frames = self!.frames+1
                    }
                    print(self!.frames)

                }

            }
        }
      }
    }
    let handler = VNImageRequestHandler(ciImage: image)
    DispatchQueue.global(qos: .userInteractive).async {
      do {
        try handler.perform([request])
      } catch {
        print(error)
      }
    }
  }
}
