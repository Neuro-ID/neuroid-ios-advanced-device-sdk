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
    func getAdvancedDeviceSignal(_ apiKey: String, clientID: String?, linkedSiteID: String?, completion: @escaping (Result<(String, Double), Error>) -> Void)
    func getAdvancedDeviceSignal(_ apiKey: String, completion: @escaping (Result<(String, Double), Error>) -> Void)
}

public class NeuroIDADV: NSObject, DeviceSignalService {
    public func getAdvancedDeviceSignal(_ apiKey: String, completion: @escaping (Result<(String, Double), Error>) -> Void) {
        getAdvancedDeviceSignal(apiKey, clientID: nil, linkedSiteID: nil, completion: completion)
    }

    public func getAdvancedDeviceSignal(_ apiKey: String, clientID: String?, linkedSiteID: String?, completion: @escaping (Result<(String, Double), Error>) -> Void) {
        NeuroIDADV.getAPIKey(apiKey, clientID: clientID, linkedSiteID: linkedSiteID) { result in
            switch result {
            case .success(let fAPiKey):
                NeuroIDADV.retryAPICall(apiKey: fAPiKey, maxRetries: 3, delay: 2) { result in
                    switch result {
                    case .success(let (value, duration)):
                        completion(.success((value, duration)))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public static func getAdvancedDeviceSignal(_ apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        NeuroIDADV.getAPIKey(apiKey) { result in
            switch result {
            case .success(let fAPiKey):
                NeuroIDADV.retryAPICall(apiKey: fAPiKey, maxRetries: 3, delay: 2) { result in
                    switch result {
                    case .success(let (value, _)):
                        completion(.success(value))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func getAPIKey(
        _ apiKey: String,
        clientID: String? = "",
        linkedSiteID: String? = "",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let apiURL = URL(string: "https://receiver.neuroid.cloud/a/\(apiKey)?clientId=\(clientID ?? "")&linkedSiteId=\(linkedSiteID ?? "")")!
        let task = URLSession.shared.dataTask(with: apiURL) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    completion(
                        .failure(
                            createError(code: 1, description: "403")
                        )
                    )
                    return
                }

                if httpResponse.statusCode == 204 {
                    completion(
                        .failure(
                            createError(code: 8, description: "204")
                        )
                    )
                    return
                }
            }

            guard let data = data else {
                completion(
                    .failure(
                        createError(code: 2, description: "NeuroID API Error: No Data Received")
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
                                createError(code: 3, description: "NeuroID API Error: Unable to convert to string")
                            )
                        )
                    }
                } else {
                    completion(
                        .failure(
                            createError(code: 4, description: "NeuroID API Error: Error Retrieving Data")
                        )
                    )
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    static func getRequestID(
        _ apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if #available(iOS 12.0, *) {
            let region: Region = .custom(domain: "https://advanced.neuro-id.com")
            let configuration = Configuration(apiKey: apiKey, region: region)
            let client = FingerprintProFactory.getInstance(configuration)
            client.getVisitorIdResponse { result in
                switch result {
                case .success(let fResponse):
                    completion(.success(fResponse.requestId))
                case .failure(let error):
                    completion(
                        .failure(
                            createError(code: 6, description: "Fingerprint Response Failure (code 6): \(error.localizedDescription)")
                        )
                    )
                }
            }
        } else {
            completion(
                .failure(
                    createError(code: 7, description: "Fingerprint Response Failure (code 7): Method Not Available")
                )
            )
        }
    }

    static func retryAPICall(
        apiKey: String,
        maxRetries: Int,
        delay: TimeInterval,
        completion: @escaping (Result<(String, TimeInterval), Error>) -> Void
    ) {
        var currentRetry = 0

        func attemptAPICall() {
            let startTime = Date()

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
                    let duration = Date().timeIntervalSince(startTime) * 1000
                    completion(.success((value, duration)))
                }
            }
        }

        attemptAPICall()
    }

    static func createError(code: Int, description: String) -> NSError {
        return NSError(
            domain: "NeuroIDAdvancedDevice",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: description,
            ]
        )
    }
}
