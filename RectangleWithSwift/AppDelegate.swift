//
//  AppDelegate.swift
//  RectangleWithSwift
//
//  Created by Joe Mestrovich on 4/13/22.
//

import UIKit
import SquarePointOfSaleSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
	var window: UIWindow?

	func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
		// Verify that the response is from the Square app
		guard SCCAPIResponse.isSquareResponse(url) else {
			return false
		}
		
		do {
			// Build a SCCAPIResponse object for error handling and
			// passing transaction data
			let response = try SCCAPIResponse(responseURL: url)
			
			if let error = response.error {
				// Handle a failed request.
				print(error.localizedDescription)
			} else {
				// Do something interesting with the response like
				// adjust inventory or track customer purchases
				if let viewController = self.window?.rootViewController as? ViewController {
					viewController.isTenderSuccessful = response.isSuccessResponse
				}
			}
			
		} catch let error as NSError {
			// Handle unexpected errors.
			print(error.localizedDescription)
		}
		
		return true
	}

	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
		// Override point for customization after application launch.
		return true
	}

}

