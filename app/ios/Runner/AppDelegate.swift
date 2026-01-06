import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Bildirim izinlerini iste ve delegate'i ayarla
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      
      // Bildirim izinlerini iste
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
        DispatchQueue.main.async {
          if granted {
            print("✅ Bildirim izni verildi")
            // İzin verildikten sonra bildirimleri etkinleştir
            application.registerForRemoteNotifications()
          } else {
            print("❌ Bildirim izni reddedildi: \(error?.localizedDescription ?? "bilinmeyen hata")")
          }
        }
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Bildirim izinleri için delegate metodları
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // Uygulama açıkken bildirim göster
    completionHandler([.alert, .badge, .sound])
  }
  
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    // Bildirime tıklandığında
    completionHandler()
  }
}
