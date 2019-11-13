//
//  AudioVisualizationView.swift
//  Pods
//
//  Created by Bastien Falcou on 12/6/16.
//

import AVFoundation
import UIKit
import RxSwift

public class AudioVisualizationView: BaseNibView {
	public enum AudioVisualizationMode {
		case read
		case write
	}

	private enum LevelBarType {
		case upper
		case lower
		case single
	}

	@IBInspectable public var meteringLevelBarWidth: CGFloat = 3.0 {
		didSet {
			self.setNeedsDisplay()
		}
	}
	@IBInspectable public var meteringLevelBarInterItem: CGFloat = 2.0 {
		didSet {
			self.setNeedsDisplay()
		}
	}
	@IBInspectable public var meteringLevelBarCornerRadius: CGFloat = 2.0 {
		didSet {
			self.setNeedsDisplay()
		}
	}
	@IBInspectable public var meteringLevelBarSingleStick: Bool = false {
		didSet {
			self.setNeedsDisplay()
		}
	}

	public var audioVisualizationMode: AudioVisualizationMode = .read

	public var audioVisualizationTimeInterval: TimeInterval = 0.05 // Time interval between each metering bar representation

	// Specify a `gradientPercentage` to have the width of gradient be that percentage of the view width (starting from left)
	// The rest of the screen will be filled by `self.gradientStartColor` to display nicely.
	// Do not specify any `gradientPercentage` for gradient calculating fitting size automatically.
    public var currentGradientPercentage: Float?

	private var meteringLevelsArray: [Float] = []    // Mutating recording array (values are percentage: 0.0 to 1.0)
	private var meteringLevelsClusteredArray: [Float] = [] // Generated read mode array (values are percentage: 0.0 to 1.0)

	private var currentMeteringLevelsArray: [Float] {
		if !self.meteringLevelsClusteredArray.isEmpty {
			return meteringLevelsClusteredArray
		}
		return meteringLevelsArray
	}
    
    private let currentTimePublisher = BehaviorSubject<TimeInterval>(value: TimeInterval(floatLiteral: 0))
    public var currectTimeObservable: Observable<TimeInterval> { return currentTimePublisher }
    
    private lazy var playChronometer: Chronometer = Chronometer(withTimeInterval: self.audioVisualizationTimeInterval)
    public var timerDidComplete: TimerDidCompleteClosure? {
        didSet {
            playChronometer.timerDidComplete = timerDidComplete
        }
    }

	public var meteringLevels: [Float]? {
		didSet {
			if let meteringLevels = self.meteringLevels {
				self.meteringLevelsClusteredArray = meteringLevels
				self.currentGradientPercentage = 0.0
				_ = self.scaleSoundDataToFitScreen()
			}
		}
	}

	static var audioVisualizationDefaultGradientStartColor: UIColor {
		return UIColor(red: 61.0 / 255.0, green: 20.0 / 255.0, blue: 117.0 / 255.0, alpha: 1.0)
	}
	static var audioVisualizationDefaultGradientEndColor: UIColor {
		return UIColor(red: 166.0 / 255.0, green: 150.0 / 255.0, blue: 225.0 / 255.0, alpha: 1.0)
	}

	@IBInspectable public var gradientStartColor: UIColor = AudioVisualizationView.audioVisualizationDefaultGradientStartColor {
		didSet {
			self.setNeedsDisplay()
		}
	}
	@IBInspectable public var gradientEndColor: UIColor = AudioVisualizationView.audioVisualizationDefaultGradientEndColor {
		didSet {
			self.setNeedsDisplay()
		}
	}
    
	override public init(frame: CGRect) {
		super.init(frame: frame)
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(panGesture))
        self.addGestureRecognizer(gesture)
	}
    
    @objc
    func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard gestureRecognizer.view != nil else { return }
        if gestureRecognizer.state == .began || gestureRecognizer.state == .changed, let duration = duration {
            let location = gestureRecognizer.location(in: self)
            let percantage = location.x / self.bounds.size.width
            self.changeTimer(timeInterval: duration * Double(percantage), percantage: Float(percantage))
        }
    }

	required public init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(panGesture))
        self.addGestureRecognizer(gesture)
	}

	override public func draw(_ rect: CGRect) {
		super.draw(rect)

		if let context = UIGraphicsGetCurrentContext() {
			self.drawLevelBarsMaskAndGradient(inContext: context)
		}
	}
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self), let duration = self.duration else { return }
        
        let percantage = location.x / self.bounds.size.width
        self.changeTimer(timeInterval: duration * Double(percantage), percantage: Float(percantage))
    }

	public func reset() {
		self.meteringLevels = nil
		self.currentGradientPercentage = nil
		self.meteringLevelsClusteredArray.removeAll()
		self.meteringLevelsArray.removeAll()
		self.setNeedsDisplay()
	}
    
    public func resetWavesWithTimer() {
        self.currentGradientPercentage = nil
        self.playChronometer.timerCurrentValue = 0.0
        self.playChronometer.stop()
        self.setNeedsDisplay()
    }
    
    public func setCurrentGradientPercentage() {
        guard let duration = self.duration else { return }
        let timerDuration = self.playChronometer.timerCurrentValue
        self.currentGradientPercentage = Float(timerDuration) / Float(duration)
        self.setNeedsDisplay()
    }

	// MARK: - Record Mode Handling

	public func add(meteringLevel: Float) {
		guard self.audioVisualizationMode == .write else {
			fatalError("trying to populate audio visualization view in read mode")
		}

		self.meteringLevelsArray.append(meteringLevel)
		self.setNeedsDisplay()
	}

	public func scaleSoundDataToFitScreen() -> [Float] {
		if self.meteringLevelsArray.isEmpty {
			return []
		}

		self.meteringLevelsClusteredArray.removeAll()
		var lastPosition: Int = 0

		for index in 0..<self.maximumNumberBars {
			let position: Float = Float(index) / Float(self.maximumNumberBars) * Float(self.meteringLevelsArray.count)
			var h: Float = 0.0

			if self.maximumNumberBars > self.meteringLevelsArray.count && floor(position) != position {
				let low: Int = Int(floor(position))
				let high: Int = Int(ceil(position))

				if high < self.meteringLevelsArray.count {
					h = self.meteringLevelsArray[low] + ((position - Float(low)) * (self.meteringLevelsArray[high] - self.meteringLevelsArray[low]))
				} else {
					h = self.meteringLevelsArray[low]
				}
			} else {
				for nestedIndex in lastPosition...Int(position) {
					h += self.meteringLevelsArray[nestedIndex]
				}
				let stepsNumber = Int(1 + position - Float(lastPosition))
				h = h / Float(stepsNumber)
			}

			lastPosition = Int(position)
			self.meteringLevelsClusteredArray.append(h)
		}
		self.setNeedsDisplay()
		return self.meteringLevelsClusteredArray
	}

	// PRAGMA: - Play Mode Handling

	public func play(from url: URL) {
		guard self.audioVisualizationMode == .read else {
			print("trying to read audio visualization in write mode")
            return
		}

		AudioContext.load(fromAudioURL: url) { audioContext in
			guard let audioContext = audioContext else {
				print("Couldn't create the audioContext")
                return
			}
			self.meteringLevels = audioContext.render(targetSamples: 100)
			self.play(for: 2)
		}
	}
    
    public var duration: TimeInterval?
    
	public func play(for duration: TimeInterval) {
        if self.duration == nil {
            self.duration = duration
        }
        
		guard self.audioVisualizationMode == .read else {
            print("trying to read audio visualization in write mode")
            return
		}

		guard self.meteringLevels != nil else {
			print("trying to read audio visualization of non initialized sound record")
            return
		}

//		if let currentChronometer = self.playChronometer {
//			currentChronometer.start() // resume current
//			return
//		}

//		self.playChronometer = Chronometer(withTimeInterval: self.audioVisualizationTimeInterval)
		self.playChronometer.start()
//        self.playChronometer.timerDidComplete = self.timerDidComplete

		self.playChronometer.timerDidUpdate = { [weak self] timerDuration in
			guard let this = self else {
				return
			}

			if timerDuration >= duration {
				this.stop()
				return
			}

			this.currentGradientPercentage = Float(timerDuration) / Float(duration)
			this.setNeedsDisplay()
		}
    }

	public func pause() {
		guard playChronometer.isPlaying else {
			print("trying to pause audio visualization view when not playing")
            return
		}
		self.playChronometer.pause()
	}

	public func stop() {
		self.playChronometer.stop()
//		self.playChronometer = nil

		self.currentGradientPercentage = 1.0
		self.setNeedsDisplay()
		self.currentGradientPercentage = nil
	}

	// MARK: - Mask + Gradient

	private func drawLevelBarsMaskAndGradient(inContext context: CGContext) {
		if self.currentMeteringLevelsArray.isEmpty {
			return
		}

		context.saveGState()

		UIGraphicsBeginImageContextWithOptions(self.frame.size, false, 0.0)

		let maskContext = UIGraphicsGetCurrentContext()
		UIColor.black.set()

		self.drawMeteringLevelBars(inContext: maskContext!)

		let mask = UIGraphicsGetCurrentContext()?.makeImage()
		UIGraphicsEndImageContext()

		context.clip(to: self.bounds, mask: mask!)

		self.drawGradient(inContext: context)

		context.restoreGState()
	}

	private func drawGradient(inContext context: CGContext) {
		if self.currentMeteringLevelsArray.isEmpty {
			return
		}

		context.saveGState()

		var endPoint = CGPoint(x: self.xLeftMostBar() + self.meteringLevelBarWidth, y: self.centerY)

		if let gradientPercentage = self.currentGradientPercentage {
			endPoint = CGPoint(x: self.frame.size.width * CGFloat(gradientPercentage), y: self.centerY)
		}
        
		context.restoreGState()
        
        if self.audioVisualizationMode == .write {
            self.drawPlainBackground(inContext: context, color: gradientEndColor, fillFromXCoordinate: 0)
        }
		else if self.currentGradientPercentage != nil {
             self.drawPlainBackground(inContext: context, color: gradientEndColor, fillFromXCoordinate: 0, fillToXCoordinate: endPoint.x)
            self.drawPlainBackground(inContext: context, color: gradientStartColor, fillFromXCoordinate: endPoint.x)
		}
        else {
             self.drawPlainBackground(inContext: context, color: gradientStartColor, fillFromXCoordinate: 0)
        }
	}

	private func drawPlainBackground(
        inContext context: CGContext,
        color: UIColor,
        fillFromXCoordinate xCoordinate: CGFloat,
        fillToXCoordinate toXCoordinate: CGFloat? = nil
        ) {
		context.saveGState()

		let squarePath = UIBezierPath()

		squarePath.move(to: CGPoint(x: xCoordinate, y: 0.0))
		squarePath.addLine(to: CGPoint(x: toXCoordinate ?? self.frame.size.width, y: 0.0))
		squarePath.addLine(to: CGPoint(x: toXCoordinate ?? self.frame.size.width, y: self.frame.size.height))
		squarePath.addLine(to: CGPoint(x: xCoordinate, y: self.frame.size.height))

		squarePath.close()
		squarePath.addClip()

		color.setFill()
		squarePath.fill()

		context.restoreGState()
	}

	// MARK: - Bars

	private func drawMeteringLevelBars(inContext context: CGContext) {
		let offset = max(self.currentMeteringLevelsArray.count - self.maximumNumberBars, 0)

		for index in offset..<self.currentMeteringLevelsArray.count {
			if self.meteringLevelBarSingleStick {
				self.drawBar(index - offset, meteringLevelIndex: index, levelBarType: .single, context: context)
			} else {
				self.drawBar(index - offset, meteringLevelIndex: index, levelBarType: .upper, context: context)
				self.drawBar(index - offset, meteringLevelIndex: index, levelBarType: .lower, context: context)
			}
		}
	}

	private func drawBar(_ barIndex: Int, meteringLevelIndex: Int, levelBarType: LevelBarType, context: CGContext) {
		context.saveGState()

		var barRect: CGRect

		let xPointForMeteringLevel = self.xPointForMeteringLevel(barIndex)
		let heightForMeteringLevel = self.heightForMeteringLevel(self.currentMeteringLevelsArray[meteringLevelIndex])

		switch levelBarType {
		case .upper:
			barRect = CGRect(x: xPointForMeteringLevel,
							 y: self.centerY - heightForMeteringLevel,
							 width: self.meteringLevelBarWidth,
							 height: heightForMeteringLevel)
		case .lower:
			barRect = CGRect(x: xPointForMeteringLevel,
							 y: self.centerY,
							 width: self.meteringLevelBarWidth,
							 height: heightForMeteringLevel)
		case .single:
			barRect = CGRect(x: xPointForMeteringLevel,
							 y: self.centerY - heightForMeteringLevel,
							 width: self.meteringLevelBarWidth,
							 height: heightForMeteringLevel * 2)
		}

		let barPath: UIBezierPath = UIBezierPath(roundedRect: barRect, cornerRadius: self.meteringLevelBarCornerRadius)

		UIColor.black.set()
		barPath.fill()

		context.restoreGState()
	}
    
    public func changeTimer(timeInterval: TimeInterval, percantage: Float?) {
        let newCurrentTime = timeInterval >= 0 ? timeInterval : 0
        playChronometer.timerCurrentValue = newCurrentTime
        currentTimePublisher.onNext(newCurrentTime)
        if !playChronometer.isPlaying {
            self.currentGradientPercentage = percantage
        }
        self.setNeedsDisplay()
    }

	// MARK: - Points Helpers

	private var centerY: CGFloat {
		return self.frame.size.height / 2.0
	}

	private var maximumBarHeight: CGFloat {
		return self.frame.size.height / 2.0
	}

	private var maximumNumberBars: Int {
		return Int(self.frame.size.width / (self.meteringLevelBarWidth + self.meteringLevelBarInterItem))
	}

	private func xLeftMostBar() -> CGFloat {
		return self.xPointForMeteringLevel(min(self.maximumNumberBars - 1, self.currentMeteringLevelsArray.count - 1))
	}

	private func heightForMeteringLevel(_ meteringLevel: Float) -> CGFloat {
		return CGFloat(meteringLevel) * self.maximumBarHeight
	}

	private func xPointForMeteringLevel(_ atIndex: Int) -> CGFloat {
		return CGFloat(atIndex) * (self.meteringLevelBarWidth + self.meteringLevelBarInterItem)
	}
}
