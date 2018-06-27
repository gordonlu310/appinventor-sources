// -*- mode: swift; swift-mode:basic-offset: 2; -*-
// Copyright © 2018 Massachusetts Institute of Technology, All rights reserved.

import UIKit
import UIKit.UIGestureRecognizerSubclass

fileprivate let kCanvasDefaultBackgroundColor = Color.white.rawValue
fileprivate let kCanvasDefaultPaintColor = Color.black.rawValue
fileprivate let kCanvasDefaultLineWidth: CGFloat = 2.0
fileprivate let kCanvasDefaultFontSize: Float = 14.0
fileprivate let FLING_INTERVAL: CGFloat = 1000
fileprivate let TAP_THRESHOLD = Float(1.5) //corresponds to 15 pixels
fileprivate let UNSET = CGFloat(-1)

// MARK: Canvas class
public class Canvas: ViewComponent, AbstractMethodsForViewComponent, ComponentContainer, UIGestureRecognizerDelegate {
  fileprivate var _view: UIView
  fileprivate var _backgroundColor = Int32(bitPattern: kCanvasDefaultBackgroundColor)
  fileprivate var _backgroundImage = ""
  fileprivate var _touchedAnySprite = false
  fileprivate var _paintColor = Int32(bitPattern: kCanvasDefaultPaintColor)
  fileprivate var _lineWidth = kCanvasDefaultLineWidth
  fileprivate var _fontSize = kCanvasDefaultFontSize
  fileprivate var _textAlignment = kCAAlignmentCenter
  fileprivate var _frame = CGRect(x:0, y:0, width:kCanvasPreferredWidth, height:kCanvasPreferredHeight)
  
  fileprivate var _flingStartX = CGFloat(0)
  fileprivate var _flingStartY = CGFloat(0)
  fileprivate var _dragStartX = CGFloat(0)
  fileprivate var _dragStartY = CGFloat(0)
  
  // Layers are split into four categories. There may be multiple layers in shapeLayers and textLayers.
  // There is always just one background image layer and one background color layer.
  fileprivate var shapeLayers = [CALayer]()
  fileprivate var textLayers = [CALayer]()
  fileprivate var _backgroundImageLayer = CALayer()
  fileprivate var _backgroundColorLayer = CALayer()

  public override init(_ parent: ComponentContainer) {
    _view = UIView()
    super.init(parent)
    super.setDelegate(self)

    // set up gesture recognizers
    let tapGesture = UITapGestureRecognizer(target: self, action: #selector(onTap(gesture:)))
    let longTouchGesture = UILongPressGestureRecognizer(target: self, action: #selector(onLongTouch))
    let flingGesture = UIPanGestureRecognizer(target: self, action: #selector(onFling))
    let dragGesture = DragGestureRecognizer(target: self, action: #selector(onDrag))
    _view.addGestureRecognizer(tapGesture)
    _view.addGestureRecognizer(longTouchGesture)
    _view.addGestureRecognizer(flingGesture)
    _view.addGestureRecognizer(dragGesture)
    dragGesture.delegate = self
    
    _view.translatesAutoresizingMaskIntoConstraints = false
    _view.clipsToBounds = true
    parent.add(self)
    
    Height = Int32(kCanvasPreferredHeight)
    Width = Int32(kCanvasPreferredWidth)
    BackgroundColor = _backgroundColor
  }
  
  // Returns a UIImage filled with the current background color
  func backgroundColorImage() -> UIImage? {
    let color = argbToColor(_backgroundColor)
    var width = Int(_view.bounds.width)
    var height = Int(_view.bounds.height)
    if width == 0 {
      width = kCanvasPreferredWidth
    }
    if height == 0 {
      height = kCanvasPreferredHeight
    }
    let centerX = CGFloat(width) / 2
    let centerY = CGFloat(height) / 2
    let rect = CGRect(x: 0, y: 0, width: centerX * 2, height: centerY * 2)
    UIGraphicsBeginImageContext(rect.size)
    color.setFill()
    UIRectFill(rect)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image
  }

  // MARK: Properties
  open var BackgroundColor: Int32 {
    get {
      return _backgroundColor
    }
    set(backgroundColor) {
      // Canvas is cleared whenever BackgroundColor is set.
      Clear()
      
      if backgroundColor != _backgroundColor {
        // _backgroundColorLayer is updated even when _backgroundImage is set; it is just hidden.
        // Changes to _backgroundColor are only visible when _backgroundImage is not set.
        _backgroundColor = backgroundColor

        if let backgroundImage = backgroundColorImage() {
          _backgroundColorLayer.removeFromSuperlayer()
          
          _backgroundColorLayer.contents = backgroundImage.cgImage
          _backgroundColorLayer.position = CGPoint(x: 0, y: 0)
          _backgroundColorLayer.contents = backgroundImage.cgImage
          
          let centerX = CGFloat(Width) / 2
          let centerY = CGFloat(Height) / 2
          
          _backgroundColorLayer.frame = CGRect(x: 0, y: 0, width: centerX * 2, height: centerY * 2)
          _backgroundColorLayer.bounds = CGRect(x: centerX, y: centerY, width: centerX * 2, height: centerY * 2)

          _view.layer.addSublayer(_backgroundColorLayer)
        }
      }
    }
  }

  open var BackgroundImage: String {
    get {
      return _backgroundImage
    }
    set(path) {
      // Canvas is cleared whenever BackgroundImage is set.
      Clear()
      
      if path != _backgroundImage {
        // There are two possibilities when the backgroud image is changed:
        // 1) the provided path is valid, so the background image is updated or
        // 2) the provided path is invalid, so the background color is shown
        _backgroundImageLayer.removeFromSuperlayer()
        
        if let image = UIImage(named: path) ?? UIImage(contentsOfFile: AssetManager.shared.pathForExistingFileAsset(path)) {
          _backgroundImage = path
          _backgroundImageLayer.contents = image.cgImage
          
          let centerX = CGFloat(Width) / 2
          let centerY = CGFloat(Height) / 2
          
          _backgroundImageLayer.backgroundColor = UIColor.clear.cgColor
          _backgroundImageLayer.position = CGPoint(x: centerX, y: centerY)
          _backgroundImageLayer.bounds = CGRect(x: centerX, y: centerY, width: centerX * 2, height: centerY * 2)
          _backgroundImageLayer.zPosition = -1

          _view.layer.addSublayer(_backgroundImageLayer)
          _backgroundColorLayer.isHidden = true
        } else {
          _backgroundImage = ""
          _backgroundColorLayer.isHidden = false
        }
      }
    }
  }

  override open var Width: Int32 {
    get {
      return super.Width
    }
    set(width) {
      let oldWidth = _view.bounds.width
      if width != super.Width {
        setNestedViewWidth(nestedView: _view, width: width, shouldAddConstraints: true)
        if width >= 0 {
          _view.frame.size.width = CGFloat(width)
        }
        
        // adjust background image layer size to fill the newly sized canvas
        let centerX = CGFloat(width) / 2
        let centerY = CGFloat(Height) / 2
        _backgroundImageLayer.position = CGPoint(x: centerX, y: centerY)
        _backgroundImageLayer.bounds = CGRect(x: centerX, y: centerY, width: centerX * 2, height: centerY * 2)
    
        // Resize background color layer
        if _backgroundImage == "" {
          _backgroundColorLayer.frame = CGRect(x: 0, y: 0, width: centerX * 2, height: centerY * 2)
          _backgroundColorLayer.bounds = CGRect(x: centerX, y: centerY, width: centerX * 2, height: centerY * 2)
          if let backgroundImage = backgroundColorImage() {
            _backgroundColorLayer.contents = backgroundImage.cgImage
          }
        }
        
        // Adjust all the shapeLayers transforms on the x-axis
        let xScaleFactor = CGFloat(width) / oldWidth
        for s in shapeLayers {
          transformLayerWidth(s, xScaleFactor)
        }
        
        // Adjust all the textLayers transforms and positions on the x-axis
        for s in textLayers {
          s.position.x *= xScaleFactor
          transformLayerWidth(s, xScaleFactor)
        }
      }
    }
  }
  
  override open var Height: Int32 {
    get {
      return super.Height
    }
    set(height) {
      let oldHeight = _view.bounds.height
      if height != super.Height {
        setNestedViewHeight(nestedView: _view, height: height, shouldAddConstraints: true)
        if height >= 0 {
          _view.frame.size.height = CGFloat(height)
        }
        
        // adjust background image layer size to fill the newly sized canvas
        let centerX = CGFloat(Width) / 2
        let centerY = CGFloat(height) / 2
        _backgroundImageLayer.position = CGPoint(x: centerX, y: centerY)
        _backgroundImageLayer.bounds = CGRect(x: centerX, y: centerY, width: centerX * 2, height: centerY * 2)

        // Resize background color layer
        if _backgroundImage == "" {
          _backgroundColorLayer.frame = CGRect(x: 0, y: 0, width: centerX * 2, height: centerY * 2)
          _backgroundColorLayer.bounds = CGRect(x: centerX, y: centerY, width: centerX * 2, height: centerY * 2)
          if let backgroundImage = backgroundColorImage() {
            _backgroundColorLayer.contents = backgroundImage.cgImage
          }
        }
        
        // Adjust all the shapeLayers transforms on the y-axis
        let yScaleFactor = CGFloat(height) / oldHeight
        for s in shapeLayers {
          transformLayerHeight(s, yScaleFactor)
        }
        
        // Adjust all the textLayers transforms and positions on the y-axis
        for s in textLayers {
          s.position.y *= yScaleFactor
          transformLayerHeight(s, yScaleFactor)
        }
      }
    }
  }
  
  open var PaintColor: Int32 {
    get {
      return _paintColor
    }
    set(color) {
      _paintColor = color
    }
  }

  open var FontSize: Float {
    get {
      return _fontSize
    }
    set(font) {
      _fontSize = font
    }
  }

  open var LineWidth: Float {
    get {
      return Float(_lineWidth)
    }
    set(width) {
      _lineWidth = CGFloat(width)
    }
  }

  open var TextAlignment: Int32 {
    get {
      switch _textAlignment {
        case kCAAlignmentRight: // ending at the specified point
          return Alignment.opposite.rawValue
        case kCAAlignmentLeft: // starting at the specified point
          return Alignment.normal.rawValue
        default:
          return Alignment.center.rawValue
      }
    }
    set(alignment) {
      switch alignment {
        case Alignment.normal.rawValue:
          _textAlignment = kCAAlignmentLeft
        case Alignment.opposite.rawValue:
          _textAlignment = kCAAlignmentRight
        default:
          _textAlignment = kCAAlignmentCenter
      }
    }
  }

  override open var view: UIView {
    get {
      return _view
    }
  }

  fileprivate func transformLayerWidth(_ s: CALayer, _ xScaleFactor: CGFloat) {
    s.transform.m11 *= xScaleFactor
    s.transform.m12 *= xScaleFactor
    s.transform.m13 *= xScaleFactor
    s.transform.m14 *= xScaleFactor
  }
  
  fileprivate func transformLayerHeight(_ s: CALayer, _ yScaleFactor: CGFloat) {
    s.transform.m21 *= yScaleFactor
    s.transform.m22 *= yScaleFactor
    s.transform.m23 *= yScaleFactor
    s.transform.m24 *= yScaleFactor
  }

  // MARK: Events

  // Allow drag and fling gestures to be recognized simultaneously
  public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    return (gestureRecognizer is DragGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer) || (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is DragGestureRecognizer)
  }
  
  open func onTap(gesture: UITapGestureRecognizer) {
    let _x = gesture.location(in: _view).x
    let _y = gesture.location(in: _view).y
    Touched(Float32(_x), Float32(_y), _touchedAnySprite)
  }

  open func Touched(_ x: Float32, _ y: Float32, _ touchedAnySprite: Bool) {
    EventDispatcher.dispatchEvent(of: self, called: "Touched", arguments: x as NSNumber, y as NSNumber, _touchedAnySprite as AnyObject)
  }

  func onLongTouch(gesture: UILongPressGestureRecognizer) {
    let _x = gesture.location(in: _view).x
    let _y = gesture.location(in: _view).y
    if gesture.state == UIGestureRecognizerState.began {
      TouchDown(Float(_x), Float(_y))
    } else if gesture.state == UIGestureRecognizerState.ended {
      TouchUp(Float(_x), Float(_y))
    }
  }

  open func TouchDown(_ x: Float, _ y: Float) {
    EventDispatcher.dispatchEvent(of: self, called: "TouchDown", arguments: x as NSNumber, y as NSNumber)
  }

  open func TouchUp(_ x: Float, _ y: Float) {
    EventDispatcher.dispatchEvent(of: self, called: "TouchUp", arguments: x as NSNumber, y as NSNumber)
  }

  // Fling and Gesture are simultaneously recognized.
  open func onFling(gesture: UIPanGestureRecognizer) {
    let flungSprite = false
    var velocity = gesture.velocity(in: _view)
    velocity.x = velocity.x / FLING_INTERVAL
    velocity.y = velocity.y / FLING_INTERVAL
    switch gesture.state {
    case .began:
      // save starting position
      _flingStartX = gesture.location(in: _view).x
      _flingStartY = gesture.location(in: _view).y
    case .ended:
      let speed = pow(pow(velocity.x, 2) + pow(velocity.y, 2), 0.5)
      let endX = gesture.location(in: _view).x
      let endY = gesture.location(in: _view).y
      let xDiff = endX - _flingStartX
      let yDiff = endY - _flingStartY
      // calculate the direction of the fling, assuming 0 degrees is 3 o'clock on a watch
      var heading = 180 * atan(yDiff / xDiff) / CGFloat.pi
      if xDiff == 0 {
        heading = yDiff > 0 ? CGFloat(180 * atan(Float.pi / 2)) / CGFloat.pi : CGFloat(180 * atan(3 * Float.pi / 2)) / CGFloat.pi
      }
      if heading != 0 {
        if xDiff < 0 {
          // adjust heading; it is in the range of 90 to 270 degrees
          heading = 180 + heading
        } else if yDiff < 0 {
          // adjust heading; it is in the range of 270 to 360 degrees
          heading = 360 + heading
        }
      }
      Flung(Float(_flingStartX), Float(_flingStartY), Float(speed), Float(heading),
            Float(velocity.x), Float(velocity.y), flungSprite)
    default:
      break
    }
  }

  open func Flung(_ flingStartX: Float, _ flingStartY: Float, _ speed: Float, _ heading: Float,
                  _ velocityX: Float, _ velocityY: Float, _ flungSprite: Bool) {
    EventDispatcher.dispatchEvent(of: self, called: "Flung", arguments: flingStartX as NSNumber,
                                  flingStartY as NSNumber, speed as NSNumber, heading as NSNumber,
                                  velocityX as NSNumber, velocityY as NSNumber,
                                  flungSprite as NSNumber)
  }

  open func onDrag(gesture: DragGestureRecognizer) {
    let draggedAnySprite = false
    if gesture.state == .began || gesture.state == .changed {
      let viewWidth = _view.bounds.width
      let viewHeight = _view.bounds.height
      if gesture.currentY <= viewHeight && gesture.currentX <= viewWidth {
        Dragged(Float(gesture.startX), Float(gesture.startY), Float(max(0, gesture.prevX)),
                Float(max(0, gesture.prevY)), Float(max(0, gesture.currentX)),
                Float(max(0, gesture.currentY)), draggedAnySprite)
      }
    }
  }

  open func Dragged(_ startX: Float, _ startY: Float, _ prevX: Float, _ prevY: Float,
                    _ currentX: Float, _ currentY: Float, _ draggedAnySprite: Bool) {
    EventDispatcher.dispatchEvent(of: self, called: "Dragged", arguments: startX as NSNumber,
                                  startY as NSNumber, prevX as NSNumber, prevY as NSNumber,
                                  currentX as NSNumber, currentY as NSNumber,
                                  draggedAnySprite as NSNumber)
  }
  
  //MARK: Container methods
  public var form: Form {
    get {
      return _container.form
    }
  }
  
  public func add(_ component: ViewComponent) {
    // unsupported
  }
  
  public func setChildWidth(of component: ViewComponent, width: Int32) {
    // unsupported
  }
  
  public func setChildHeight(of component: ViewComponent, height: Int32) {
    // unsupported
  }
  
  //MARK: Drawing methods
  func isInCanvasBoundaries(_ x: CGFloat, _ y: CGFloat) -> Bool {
    return x >= 0 && x <= _view.frame.size.width && y >= 0 && y <= _view.frame.size.height
  }
  
  open func Clear() {
    // background image and background color are not cleared
    for l in shapeLayers {
      l.removeFromSuperlayer()
    }
    for l in textLayers {
      l.removeFromSuperlayer()
    }
  }

  open func DrawCircle(_ centerX: Float, _ centerY: Float, _ radius: Float, _ fill: Bool) {
    let finalX = CGFloat(centerX)
    let finalY = CGFloat(centerY)
    if !isInCanvasBoundaries(finalX, finalY) {
      return
    }
    let shapeLayer = CAShapeLayer()
    let point = UIBezierPath(arcCenter: CGPoint(x: finalX, y: finalY), radius: CGFloat(radius), startAngle: 0, endAngle:CGFloat(Double.pi * 2), clockwise: true)
    if fill {
      shapeLayer.fillColor = argbToColor(_paintColor).cgColor
    } else {
      let clearColor = Int32(bitPattern: kCanvasDefaultBackgroundColor)
      shapeLayer.fillColor = argbToColor(clearColor).cgColor
    }
    shapeLayer.lineWidth = _lineWidth
    shapeLayer.strokeColor = argbToColor(_paintColor).cgColor
    shapeLayer.path = point.cgPath
    _view.layer.addSublayer(shapeLayer)
    shapeLayers.append(shapeLayer)
  }

  open func DrawLine(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
    let finalX1 = CGFloat(x1); let finalY1 = CGFloat(y1)
    var finalX2 = CGFloat(x2); var finalY2 = CGFloat(y2)
    if !isInCanvasBoundaries(finalX1, finalY1) {
      return
    }
    if !isInCanvasBoundaries(finalX2, finalY2) {
      // Setting finalX2 and finalY2 to be within the canvas bounds (between 0 and the view's width/height).
      finalX2 = max(0, min(finalX2, _view.frame.size.width))
      finalY2 = max(0, min(finalY2, _view.frame.size.height))
    }
    let shapeLayer = CAShapeLayer()
    let line = UIBezierPath()
    line.move(to: CGPoint(x: finalX1, y: finalY1))
    line.addLine(to: CGPoint(x: finalX2, y: finalY2))
    line.close()
    shapeLayer.path = line.cgPath
    shapeLayer.strokeColor = argbToColor(_paintColor).cgColor
    shapeLayer.lineWidth = _lineWidth
    _view.layer.addSublayer(shapeLayer)
    shapeLayers.append(shapeLayer)
  }
  
  open func DrawPoint(_ x: Float, _ y: Float) {
    let finalX = CGFloat(x)
    let finalY = CGFloat(y)
    if !isInCanvasBoundaries(finalX, finalY) {
      return
    }
    let shapeLayer = CAShapeLayer()
    let point = UIBezierPath(arcCenter: CGPoint(x: finalX, y:finalY), radius: 1.0, startAngle: 0, endAngle:CGFloat(Float.pi * 2), clockwise: true)
    shapeLayer.fillColor = argbToColor(_paintColor).cgColor
    shapeLayer.lineWidth = _lineWidth
    shapeLayer.path = point.cgPath
    _view.layer.addSublayer(shapeLayer)
    shapeLayers.append(shapeLayer)
  }

  fileprivate func makeTextLayer(text: String, x: Float, y: Float) -> CATextLayer {
    let textLayer = CATextLayer()
    textLayer.frame = _view.bounds
    textLayer.string = text
    textLayer.fontSize = CGFloat(_fontSize)
    textLayer.anchorPoint = CGPoint(x: 0, y: 0)
    switch _textAlignment {
    case kCAAlignmentRight: // text layer ends at x,y
      textLayer.anchorPoint = CGPoint(x: 1, y:0)
    case kCAAlignmentLeft: // text layer starts at x,y
      textLayer.anchorPoint = CGPoint(x: 0, y:0)
    default: // text layer is centered at x,y
      textLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
    }
    textLayer.position = CGPoint(x: CGFloat(x), y: CGFloat(y))
    textLayer.foregroundColor = argbToColor(_paintColor).cgColor
    textLayer.alignmentMode = _textAlignment
    return textLayer
  }
  
  open func DrawText(_ text: String, _ x: Float, _ y: Float) {
    if isInCanvasBoundaries(CGFloat(x), CGFloat(y)) {
      let textLayer = makeTextLayer(text: text, x: x, y: y)
      _view.layer.addSublayer(textLayer)
      textLayers.append(textLayer)
    }
  }

  open func DrawTextAtAngle(_ text: String, _ x: Float, _ y: Float, _ angle: Float) {
    if isInCanvasBoundaries(CGFloat(x), CGFloat(y)) {
      let textLayer = makeTextLayer(text: text, x: x, y: y)

      // this is counterclockwise, same as Android.
      let radians = CGFloat(angle * Float.pi / 180)
      textLayer.transform = CATransform3DMakeRotation(-radians, 0, 0, 1.0)
      _view.layer.addSublayer(textLayer)
      textLayers.append(textLayer)
    }
  }

  open func GetBackgroundPixelColor(_ x: Int32, _ y: Int32) -> Int32 {
    var pixel: [CUnsignedChar] = [0, 0, 0, 0]

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    if let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) {
      context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
      _view.layer.render(in: context)
    } else {
      return Int32(Color.none.rawValue)
    }

    let red: CGFloat   = CGFloat(pixel[0]) / 255.0
    let green: CGFloat = CGFloat(pixel[1]) / 255.0
    let blue: CGFloat  = CGFloat(pixel[2]) / 255.0
    let alpha: CGFloat = CGFloat(pixel[3]) / 255.0
    let color = UIColor(red:red, green: green, blue:blue, alpha:alpha)
    return colorToArgb(color)
  }

  open func SetBackgroundPixelColor(_ x: Float, _ y: Float, _ color: Int32) {
    let finalX = CGFloat(x); let finalY = CGFloat(y)
    if !isInCanvasBoundaries(finalX, finalY) {
      return
    }
    let shapeLayer = CAShapeLayer()
    let point = UIBezierPath(arcCenter: CGPoint(x: finalX,y: finalY), radius: 0.5, startAngle: 0, endAngle:CGFloat(Float.pi * 2), clockwise: true)
    shapeLayer.fillColor = argbToColor(color).cgColor
    shapeLayer.lineWidth = _lineWidth
    shapeLayer.path = point.cgPath
    _view.layer.addSublayer(shapeLayer)
    shapeLayers.append(shapeLayer)
  }

  //TODO: Update once we have sprites
  open func GetPixelColor(_ x: Int32, _ y: Int32) -> Int32 {
    return isInCanvasBoundaries(CGFloat(x), CGFloat(y)) ? GetBackgroundPixelColor(x, y) : Int32(Color.none.rawValue)
  }

  open func Save() -> String {
    // get image data
    UIGraphicsBeginImageContextWithOptions(_view.bounds.size, true, 0)
    _view.drawHierarchy(in: _view.bounds, afterScreenUpdates: true)
    guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
      _container.form.dispatchErrorOccurredEvent(self, "SaveAs", ErrorMessage.ERROR_MEDIA_IMAGE_FILE_FORMAT.code, ErrorMessage.ERROR_MEDIA_IMAGE_FILE_FORMAT.message)
      return ""
    }
    let data = UIImagePNGRepresentation(image)

    // save data to fileURL
    do {
      let filePath = try FileUtil.getPictureFile("png")
      let fileURL = URL(fileURLWithPath: filePath)
      try data?.write(to: fileURL)
      UIGraphicsEndImageContext()
      return fileURL.absoluteString
    } catch {
      _container.form.dispatchErrorOccurredEvent(self, "SaveAs", ErrorMessage.ERROR_MEDIA_IMAGE_FILE_FORMAT.code, ErrorMessage.ERROR_MEDIA_IMAGE_FILE_FORMAT.message)
      return ""
    }
  }
    
  open func SaveAs(_ fileName: String) -> String {
    UIGraphicsBeginImageContextWithOptions(_view.bounds.size, true, 0)
    _view.drawHierarchy(in: _view.bounds, afterScreenUpdates: true)
    var finalFileName = ""
    guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
      _container.form.dispatchErrorOccurredEvent(self, "SaveAs", ErrorMessage.ERROR_MEDIA_IMAGE_FILE_FORMAT.code, ErrorMessage.ERROR_MEDIA_IMAGE_FILE_FORMAT.message)
      return ""
    }
    
    // Get image data in the correct format
    var data: Data?
    let lowercaseFileName = fileName.lowercased()
    if lowercaseFileName.hasSuffix(".jpg") || lowercaseFileName.hasSuffix(".jpeg") {
      data = UIImageJPEGRepresentation(image, 1.0)
      finalFileName = fileName
    } else if lowercaseFileName.hasSuffix(".png") {
      data = UIImagePNGRepresentation(image)
      finalFileName = fileName
    } else if !lowercaseFileName.contains(".") {
      data = UIImagePNGRepresentation(image)
      finalFileName = fileName + ".png"
    } else {
      _container.form.dispatchErrorOccurredEvent(self, "SaveAs", ErrorMessage.ERROR_MEDIA_IMAGE_FILE_FORMAT.code, ErrorMessage.ERROR_MEDIA_IMAGE_FILE_FORMAT.message)
      return ""
    }
    
    // Get finalFileName
    finalFileName = AssetManager.shared.pathForPublicAsset(finalFileName)
    if let encoded = finalFileName.addingPercentEncoding(withAllowedCharacters:NSCharacterSet.urlPathAllowed) {
      finalFileName = "file://" + encoded
    }
    
    // Save image data to finalImageURL
    do {
      if let finalImageURL = URL(string: finalFileName) {
        try data?.write(to: finalImageURL)
      }
    } catch {
      _container.form.dispatchErrorOccurredEvent(self, "SaveAs", ErrorMessage.ERROR_MEDIA_FILE_ERROR.code, ErrorMessage.ERROR_MEDIA_FILE_ERROR.message)
      return ""
    }
    UIGraphicsEndImageContext()
    
    return finalFileName
  }
}

// MARK: Custom Drag Gesture Recognizer

struct LocationSample {
  let location: CGPoint
  
  init(location: CGPoint) {
    self.location = location
  }
}

open class DragGestureRecognizer: UIGestureRecognizer {
  fileprivate var _startX = UNSET
  fileprivate var _startY = UNSET
  fileprivate var _prevX = UNSET
  fileprivate var _prevY = UNSET
  fileprivate var _currentX = UNSET
  fileprivate var _currentY = UNSET
  fileprivate var _touchedAnySprite = false
  fileprivate var _isDrag = false
  
  var samples = [LocationSample]()

  public override init(target:Any?, action:Selector?) {
    super.init(target: target, action: action)
  }

  open var prevX: CGFloat {
    get {
      return _prevX
    }
  }

  open var prevY: CGFloat {
    get {
      return _prevY
    }
  }

  open var startX: CGFloat {
    get {
      return _startX
    }
  }

  open var startY: CGFloat {
    get {
      return _startY
    }
  }
  
  open var currentX: CGFloat {
    get {
      return _currentX
    }
  }
  
  open var currentY: CGFloat {
    get {
      return _currentY
    }
  }

  override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    state = .possible
    if let touch = touches.first as UITouch? {
      addSample(for: touch)
      _startX = touch.location(in: self.view).x
      _startY = touch.location(in: self.view).y
      _prevX = _startX
      _prevY = _startY
      _currentX = _startX
      _currentY = _startY
      _isDrag = false
    }
  }

  override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    if let touch = touches.first {
      self.addSample(for: touch)
      let x = touch.location(in: self.view).x
      let y = touch.location(in: self.view).y
      if !_isDrag && Float(abs(x - _startX)) < TAP_THRESHOLD && Float(abs(y - _startY)) < TAP_THRESHOLD {
        state = .possible
      } else {
        _isDrag = true
        if state == .began {
          state = .changed
        } else {
          state = .began
        }
        _prevX = _currentX
        _currentX = x
        _prevY = _currentY
        _currentY = y
      }
    }
  }

  override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    if let firstTouch = touches.first {
      self.addSample(for: firstTouch)
      let x = firstTouch.location(in: self.view).x
      let y = firstTouch.location(in: self.view).y
      if self.samples.count == 2 {
        // this would be a touch event, not a drag event.
        state = .failed
      } else {
        _prevX = _currentX
        _currentX = x
        _prevY = _currentY
        _currentY = y
        state = .ended
      }
    }
  }

  override open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    self.samples.removeAll()
    state = .cancelled
  }
  
  override open func reset() {
    self.samples.removeAll()
  }
  
  func addSample(for touch: UITouch) {
    let newSample = LocationSample(location: touch.location(in: self.view))
    self.samples.append(newSample)
  }
}
