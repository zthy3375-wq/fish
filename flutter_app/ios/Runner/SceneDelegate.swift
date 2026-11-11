import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    private var academic: AcademicSession?
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                        options connectionOptions: UIScene.ConnectionOptions) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        guard let controller = window?.rootViewController as? FlutterViewController else { return }
        academic = AcademicSession(controller: controller)
        FlutterMethodChannel(name: "org.handancampus.flutter/academic",
                             binaryMessenger: controller.binaryMessenger)
            .setMethodCallHandler { [weak self] call, result in
                guard let handler = self?.academic else {
                    result(FlutterError(code: "CANCELLED", message: "学校连接已关闭", details: nil))
                    return
                }
                handler.handle(call, result: result)
            }
    }
    override func sceneDidDisconnect(_ scene: UIScene) {
        academic?.dispose()
        academic = nil
        super.sceneDidDisconnect(scene)
    }
}
