/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Firebase
import FirebaseRemoteConfig
import GoogleMaps
import UserNotifications

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var placeCarouselViewController: PlaceCarouselViewController?

    let locationMonitor = LocationMonitor()

    private var eventsNotificationsManager: EventNotificationsManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        SDKs.setUp()

        // create Window
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = UIColor.white;

        // create root view
        placeCarouselViewController = PlaceCarouselViewController()
        locationMonitor.delegate = placeCarouselViewController

        if AppConstants.BuildChannel != .MockLocation {
            window?.rootViewController = placeCarouselViewController
        } else {
            let mockLocationSelectionController = MockLocationSelectionTableViewController()
            mockLocationSelectionController.nextViewController = placeCarouselViewController
            mockLocationSelectionController.locationMonitor = locationMonitor
            window?.rootViewController = mockLocationSelectionController
        }

        if #available(iOS 10.0, *) {
            self.setupUserNotificationCenter()
        }

        if AppConstants.areNotificationsEnabled {
            application.setMinimumBackgroundFetchInterval(AppConstants.backgroundFetchInterval)
            self.eventsNotificationsManager = EventNotificationsManager(withLocationProvider: locationMonitor)
        }

        // display
        window?.makeKeyAndVisible()

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // if there is a timer running, cancel it. We'll wait until background app refresh fires instead
        locationMonitor.cancelTimeAtLocationTimer()
        eventsNotificationsManager?.persistNotificationCache()
        AppState.enterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        locationMonitor.startTimeAtLocationTimer()
        AppState.enterForeground()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        Analytics.startAppSession()
        if (AppState.getState() == AppState.State.initial || AppState.getState() == AppState.State.permissions) {
            AppState.enterLoading()
        }

        // Since we don't gracefully handle location updates, we defer a location
        // refresh until a mock location has been selected.
        if AppConstants.BuildChannel != .MockLocation {
            locationMonitor.refreshLocation()
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        locationMonitor.cancelTimeAtLocationTimer()
        eventsNotificationsManager?.persistNotificationCache()
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let currentLocation =  locationMonitor.getCurrentLocation() else {
            return completionHandler(.noData)
        }
        eventsNotificationsManager?.checkForEventsToNotify(forLocation: currentLocation, isBackground: AppConstants.cacheEvents) { (events, error) in
            if let _ = error {
                return completionHandler(.failed)
            }

            guard let events = events,
                !events.isEmpty else {
                return completionHandler(.noData)
            }

            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
        if let eventKey = notification.userInfo?[notificationEventIDKey] as? String,
            let placeKey = notification.userInfo?[notificationEventPlaceIDKey] as? String {
            if ( application.applicationState == .inactive || application.applicationState == .background  ) {
                placeCarouselViewController?.openPlace(placeKey: placeKey, forEventWithKey: eventKey)
                Analytics.logEvent(event: AnalyticsEvent.EVENT_NOTIFICATION, params: [AnalyticsEvent.PARAM_ACTION: AnalyticsEvent.BACKGROUND])
            } else if let body = notification.alertBody {
//                placeCarouselViewController?.presentInAppEventNotification(forEventWithKey: eventKey, atPlaceWithKey: placeKey, withDescription: body)
//                Analytics.logEvent(event: AnalyticsEvent.EVENT_NOTIFICATION, params: [AnalyticsEvent.PARAM_ACTION: AnalyticsEvent.FOREGROUND])
            }
        }
    }
}


@available(iOS 10.0, *)

extension AppDelegate: UNUserNotificationCenterDelegate {

    func setupUserNotificationCenter() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // show a badge.
        if let eventKey = notification.request.content.userInfo[notificationEventIDKey] as? String,
            let placeKey = notification.request.content.userInfo[notificationEventPlaceIDKey] as? String {
//            Analytics.logEvent(event: AnalyticsEvent.EVENT_NOTIFICATION, params: [AnalyticsEvent.PARAM_ACTION: AnalyticsEvent.BACKGROUND])
//            placeCarouselViewController?.presentInAppEventNotification(forEventWithKey: eventKey, atPlaceWithKey: placeKey, withDescription: notification.request.content.body)
        }
        completionHandler(UNNotificationPresentationOptions.badge)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == "EVENTS" {
            if let eventKey = response.notification.request.content.userInfo[notificationEventIDKey] as? String,
                let placeKey = response.notification.request.content.userInfo[notificationEventPlaceIDKey] as? String {
                Analytics.logEvent(event: AnalyticsEvent.EVENT_NOTIFICATION, params: [AnalyticsEvent.PARAM_ACTION: AnalyticsEvent.CLICKED])
                placeCarouselViewController?.openPlace(placeKey: placeKey, forEventWithKey: eventKey)
            }
        }
    }
}

