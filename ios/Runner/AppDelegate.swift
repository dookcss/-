import Flutter
import UIKit
import Network

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var networkChannel: FlutterMethodChannel?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // 设置MethodChannel用于原生网络访问
        if let controller = window?.rootViewController as? FlutterViewController {
            networkChannel = FlutterMethodChannel(
                name: "com.dlnacast/network",
                binaryMessenger: controller.binaryMessenger
            )
            
            networkChannel?.setMethodCallHandler { [weak self] call, result in
                self?.handleNetworkCall(call: call, result: result)
            }
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func handleNetworkCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "fetchUrl":
            guard let args = call.arguments as? [String: Any],
                  let urlString = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing url", details: nil))
                return
            }
            fetchUrlNative(urlString: urlString, result: result)
            
        case "checkConnection":
            guard let args = call.arguments as? [String: Any],
                  let host = args["host"] as? String,
                  let port = args["port"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing host/port", details: nil))
                return
            }
            checkConnectionNative(host: host, port: port, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    /// 使用原生URLSession获取URL内容
    private func fetchUrlNative(urlString: String, result: @escaping FlutterResult) {
        guard let url = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_URL", message: "Invalid URL: \(urlString)", details: nil))
            return
        }
        
        print("iOS Native: Fetching \(urlString)")
        
        // 配置URLSession允许本地网络
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        
        let session = URLSession(configuration: config)
        
        let task = session.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("iOS Native: Error - \(error.localizedDescription)")
                    result(FlutterError(
                        code: "NETWORK_ERROR",
                        message: error.localizedDescription,
                        details: "\(error)"
                    ))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    result(FlutterError(code: "NO_RESPONSE", message: "No HTTP response", details: nil))
                    return
                }
                
                print("iOS Native: HTTP \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200, let data = data {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    result([
                        "statusCode": httpResponse.statusCode,
                        "body": body
                    ])
                } else {
                    result(FlutterError(
                        code: "HTTP_ERROR",
                        message: "HTTP \(httpResponse.statusCode)",
                        details: nil
                    ))
                }
            }
        }
        task.resume()
    }
    
    /// 使用Network.framework测试TCP连接
    private func checkConnectionNative(host: String, port: Int, result: @escaping FlutterResult) {
        print("iOS Native: Testing connection to \(host):\(port)")
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        let connection = NWConnection(to: endpoint, using: parameters)
        
        var hasResult = false
        
        connection.stateUpdateHandler = { state in
            guard !hasResult else { return }
            
            switch state {
            case .ready:
                hasResult = true
                print("iOS Native: Connection ready!")
                connection.cancel()
                DispatchQueue.main.async {
                    result(["connected": true, "message": "Connection successful"])
                }
                
            case .failed(let error):
                hasResult = true
                print("iOS Native: Connection failed - \(error)")
                connection.cancel()
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "CONNECTION_FAILED",
                        message: error.localizedDescription,
                        details: "\(error)"
                    ))
                }
                
            case .waiting(let error):
                print("iOS Native: Waiting - \(error)")
                
            case .cancelled:
                if !hasResult {
                    hasResult = true
                    DispatchQueue.main.async {
                        result(FlutterError(code: "CANCELLED", message: "Connection cancelled", details: nil))
                    }
                }
                
            default:
                break
            }
        }
        
        connection.start(queue: .global())
        
        // 超时处理
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if !hasResult {
                hasResult = true
                connection.cancel()
                DispatchQueue.main.async {
                    result(FlutterError(code: "TIMEOUT", message: "Connection timeout", details: nil))
                }
            }
        }
    }
}
