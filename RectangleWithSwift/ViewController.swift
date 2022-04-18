//
//  ViewController.swift
//  RectangleWithSwift
//
//  Created by Joe Mestrovich on 4/13/22.
//

import UIKit
import SquarePointOfSaleSDK
import BRLMPrinterKit
import PDFKit

class ViewController: UIViewController {
	// Be sure to change the constants below
	let callbackString = "••• Your URL Scheme •••"
	let squareApplicationID = "••• Your Square Application ID •••"
	
	// The Square POS app will let you know if all is well
	var isTenderSuccessful: Bool?
	
	var wiFiDevicesInfo: [BRPtouchDeviceInfo]?
	var selectedDeviceInfo: BRPtouchDeviceInfo?
	var networkManager: BRPtouchNetworkManager?
	
	@IBOutlet weak var devices: UITableView!
	@IBOutlet weak var selectedShape: UISegmentedControl!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		let manager = BRPtouchNetworkManager()
		manager.delegate = self
		manager.isEnableIPv6Search = false
		manager.setPrinterNames(allBrotherPrinters())
		
		self.networkManager = manager
		fillDeviceList(manager: networkManager!)
		
		devices.delegate = self
		devices.dataSource = self
	}
	
	func fillDeviceList(manager: BRPtouchNetworkManager) {
		manager.startSearch(2)
	}

	func requestPayment(dollarAmount: Double, transactionName: String, callbackURL: String, applicationID: String) {
		// Square POS transactions must be converted to cents as an integer
		let cents = Int(dollarAmount * 100)
		
		// The callbackURL must be a type of URL
		// Pass in the URL Schemes name only; the URL initializer will build a URL for you
		let callback = URL(string: callbackURL + "://")!
		
		// Pass in the Square Production Application ID
		SCCAPIRequest.setApplicationID(applicationID)
		
		do {
			// Note the option to handle currency types other than dollars
			let transactionAmount = try SCCMoney(amountCents: cents, currencyCode: "USD")
			
			// A request with minimal configuration
			// To learn more about your available options, visit
			// https://developer.squareup.com/docs/api/point-of-sale#navsection-point-of-sale
			let apiRequest = try SCCAPIRequest(
				callbackURL: callback,
				amount: transactionAmount,
				userInfoString: nil,
				locationID: nil,
				notes: transactionName,
				customerID: nil,
				supportedTenderTypes: .all,
				clearsDefaultFees: false,
				returnsAutomaticallyAfterPayment: true,
				disablesKeyedInCardEntry: false,
				skipsReceipt: true
			)
			
			// Make the request
			try SCCAPIConnection.perform(apiRequest)
			
		} catch let error as NSError {
			print(error.localizedDescription)
		}
	}
	
	@IBAction func makePayment(_ sender: UIButton) {
		let index = selectedShape.selectedSegmentIndex
		let dollarAmount = Double(index + 1)
		
		requestPayment(
			dollarAmount: dollarAmount,
			transactionName: "Sold a shape",
			callbackURL: callbackString,
			applicationID: squareApplicationID)
	}
	
	@IBAction func printReceipt(_ sender: UIButton) {
		guard selectedDeviceInfo != nil else { return }
		guard let isTenderSuccessful = isTenderSuccessful else { return	}
		
		if isTenderSuccessful {
			printReceipt()
		} else {
			print("Do something with a bad transaction...")
		}
		
		self.isTenderSuccessful = nil
	}
	
	func printReceipt() {
		guard let selectedDeviceInfo = selectedDeviceInfo else { return }
		
		var item = "Square   "
		var price = "$1.00"
		if selectedShape.selectedSegmentIndex == 1 {
			item = "Circle   "
			price = "$2.00"
		}
		if selectedShape.selectedSegmentIndex == 2 {
			item = "Triangle"
			price = "$3.00"
		}
		
		// Build a PDF
		let pdfMetaData = [
			kCGPDFContextCreator: "Shapes Seller by the Seashore",
			kCGPDFContextAuthor: "mizmovac.com"
		  ]
		let format = UIGraphicsPDFRendererFormat()
		format.documentInfo = pdfMetaData as [String: Any]
		
		let pageWidth = 1.9 * 72.0
		let pageHeight = 1.3 * 72.0
		let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
		
		let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
		let data = renderer.pdfData { (context) in
			context.beginPage()
			
			var lastItemBottom = centerTitle(text: "Thank You!", pageRect: pageRect, textTop: 0.1)
			lastItemBottom = bodyText(text: "Qty\tItem\t\tPrice", pageRect: pageRect, textTop: lastItemBottom + 5)
			lastItemBottom = bodyText(text: "1\t\(item)\t\(price)", pageRect: pageRect, textTop: lastItemBottom)
			lastItemBottom = bodyText(text: "Total:\t\t\t\(price)", pageRect: pageRect, textTop: lastItemBottom + 5)
			lastItemBottom = bodyText(text: "Report lost and missing\nshapes to 1-800-POLYGON", pageRect: pageRect, textTop: lastItemBottom + 10)
		}
		
		// Save the PDF to a file
		let pdfReceipt = PDFDocument(data: data)
		let pdfReceiptUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RECEIPT.PDF")
		pdfReceipt?.write(to: pdfReceiptUrl)
		
		// Negotiate with the Brother print manager
		let channel = BRLMChannel(wifiIPAddress: selectedDeviceInfo.strIPAddress)
		let openChannelResult = BRLMPrinterDriverGenerator.open(channel)
		
		guard openChannelResult.error.code == BRLMOpenChannelErrorCode.noError,
			let printerDriver = openChannelResult.driver else {
				print("Channel Error: \(openChannelResult.error.code.rawValue)")
				return
		}
		
		defer {
			printerDriver.closeChannel()
		}
		
		let printerSettings = BRLMQLPrintSettings(defaultPrintSettingsWith: .QL_1110NWB)
		printerSettings?.labelSize = .rollW54
		printerSettings?.autoCut = true
		
		let error = printerDriver.printPDF(with: pdfReceiptUrl, settings: printerSettings!)
		print("Print result code: \(error.code.rawValue)")
	}
	
}

// Find and select a Brother printer
extension ViewController: BRPtouchNetworkDelegate {
	func didFinishSearch(_ sender: Any!) {
		guard let foundDevices = networkManager?.getPrinterNetInfo() else { return }
		
		wiFiDevicesInfo = foundDevices as? [BRPtouchDeviceInfo] ?? []
		
		devices.reloadData()
	}
	
	func allBrotherPrinters() -> [String] {
		guard let printNamesURL = Bundle.main.url(forResource: "PrinterList", withExtension: "plist")
			else { fatalError("PrinterList.plist missing in bundle") }
		
		let printersDict = NSDictionary.init(contentsOf: printNamesURL)!
		let printersArray = printersDict.allKeys as! [String]
		
		return printersArray
	}
	
}

// TableView support
extension ViewController: UITableViewDataSource, UITableViewDelegate {
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard let deviceCount = wiFiDevicesInfo?.count else { return 0 }
		
		return deviceCount
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		guard
			let devices = wiFiDevicesInfo,
			let cell = tableView.dequeueReusableCell(withIdentifier: "networkDevice")
		else { return UITableViewCell() }
		
		cell.textLabel?.text = devices[indexPath.row].strModelName
		
		return cell
	}
	
	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
			guard let deviceInfo = wiFiDevicesInfo?[indexPath.row] else { return }
			
			selectedDeviceInfo = deviceInfo
		}
}

// Methods that help build a PDF
extension ViewController {
	func centerTitle(text: String, pageRect: CGRect, textTop: CGFloat) -> CGFloat {
		let titleFont = UIFont(name: "Marker Felt", size: 24)!
		
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.alignment = .natural
		paragraphStyle.lineBreakMode = .byWordWrapping
		
		let titleAttributes: [NSAttributedString.Key: Any] = [
			NSAttributedString.Key.font: titleFont,
			NSAttributedString.Key.paragraphStyle: paragraphStyle
		]
		  
		let attributedText = NSAttributedString(string: text, attributes: titleAttributes)
		let textStringSize = attributedText.size()
		  
		let textStringRect = CGRect(x: (pageRect.width - textStringSize.width) / 2.0,
									 y: textTop, width: textStringSize.width,
									 height: textStringSize.height)
		attributedText.draw(in: textStringRect)
		
		return textStringRect.origin.y + textStringRect.size.height
	}
	
	func bodyText(text: String, pageRect: CGRect, textTop: CGFloat) -> CGFloat {
		let textFont = UIFont.systemFont(ofSize: 8.0, weight: .regular)

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.alignment = .natural
		paragraphStyle.lineBreakMode = .byWordWrapping

		let textAttributes = [
			NSAttributedString.Key.paragraphStyle: paragraphStyle,
			NSAttributedString.Key.font: textFont
		]
		let attributedText = NSAttributedString(string: text, attributes: textAttributes)
		
		let textRect = CGRect(x: 10, y: textTop, width: pageRect.width - 2,
							  height: attributedText.size().height)
		attributedText.draw(in: textRect)

		return textRect.origin.y + textRect.size.height
	}
}
