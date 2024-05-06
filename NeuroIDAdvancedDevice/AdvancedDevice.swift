//
//  AdvancedDevice.swift
//  NeuroIDAdvancedDevice
//
//  Created by Kevin Sites on 10/12/23.
//

import FingerprintPro
import Foundation

struct NIDResponse: Codable {
    let key: String
}

/** Interface that allows for testing */
public protocol DeviceSignalService {
    func getAdvancedDeviceSignal(_ apiKey: String, completion: @escaping (Result<String, Error>) -> Void)
}

internal class DeviceSignalServiceImpl: DeviceSignalService {
    public func getAdvancedDeviceSignal(_ apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        NeuroIDADV.getAPIKey(apiKey) { result in
            switch result {
            case .success(let fAPiKey):
                NeuroIDADV.retryAPICall(apiKey: fAPiKey, maxRetries: 3, delay: 2) { result in
                    completion(result)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

public class NeuroIDADV: NSObject, DeviceSignalService {
    internal static var deviceSignalService: DeviceSignalService = DeviceSignalServiceImpl()

    public func getAdvancedDeviceSignal(_ apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        NeuroIDADV.deviceSignalService.getAdvancedDeviceSignal(apiKey, completion: completion)
   }

    internal static func getAPIKey(
        _ apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let apiURL = URL(string: "https://receiver.neuroid.cloud/a/\(apiKey)")!
        let task = URLSession.shared.dataTask(with: apiURL) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    completion(
                        .failure(
                            NSError(
                                domain: "NeuroIDAdvancedDevice",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "403",
                                ]
                            )
                        )
                    )
                    return
                }
            }

            guard let data = data else {
                completion(
                    .failure(
                        NSError(
                            domain: "NeuroIDAdvancedDevice",
                            code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey: "No data received",
                            ]
                        )
                    )
                )
                return
            }

            do {
                let decoder = JSONDecoder()
                let myResponse = try decoder.decode(NIDResponse.self, from: data)

                if let data = Data(base64Encoded: myResponse.key) {
                    if let string = String(data: data, encoding: .utf8) {
                        completion(.success(string))
                    } else {
                        completion(
                            .failure(
                                NSError(
                                    domain: "NeuroIDAdvancedDevice",
                                    code: 3,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: "Unable to convert to string",
                                    ]
                                )
                            )
                        )
                    }
                } else {
                    completion(
                        .failure(
                            NSError(
                                domain: "NeuroIDAdvancedDevice",
                                code: 4,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Error retrieving data",
                                ]
                            )
                        )
                    )
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    internal static func getRequestID(
        _ apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let region: Region = .custom(domain: "https://advanced.neuro-id.com")
        let configuration = Configuration(apiKey: apiKey, region: region)
        let client = FingerprintProFactory.getInstance(configuration)
        if #available(iOS 12.0, *) {
            client.getVisitorIdResponse { result in
                switch result {
                case .success(let fResponse):
                    completion(.success(fResponse.requestId))
                case .failure(let error):
                    completion(.failure(NSError(
                        domain: "NeuroIDAdvancedDevice",
                        code: 6,
                        userInfo: [
                            NSLocalizedDescriptionKey: error.localizedDescription,
                        ]
                    )))
                }
            }
        } else {
            completion(.failure(NSError(
                domain: "NeuroIDAdvancedDevice",
                code: 7,
                userInfo: [
                    NSLocalizedDescriptionKey: "Method not available",
                ]
            )))
        }
    }

    internal static func retryAPICall(
        apiKey: String,
        maxRetries: Int,
        delay: TimeInterval,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var currentRetry = 0

        func attemptAPICall() {
            getRequestID(apiKey) { result in

                if case .failure(let error) = result {
                    if error.localizedDescription.contains("Method not available") {
                        completion(.failure(error))
                    } else if currentRetry < maxRetries {
                        currentRetry += 1
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                            attemptAPICall()
                        }
                    } else {
                        completion(.failure(error))
                    }
                } else if case .success(let value) = result {
                    completion(.success(value))
                }
            }
        }

        attemptAPICall()
    }
}
