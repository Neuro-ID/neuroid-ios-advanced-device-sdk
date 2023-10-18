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

public class NeuroIDADV: NSObject {
    public static func getAdvancedDeviceSignal(_ apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        self.getAPIKey(apiKey) { result in
            switch result {
            case .success(let fAPiKey):
                let client = FingerprintProFactory.getInstance(fAPiKey)
                if #available(iOS 12.0, *) {
                    client.getVisitorIdResponse { result in
                        switch result {
                        case .success(let fResponse):
                            completion(.success(fResponse.requestId))
                        case .failure(let error):
                            completion(.failure(NSError(
                                domain: "NeuroIDAdvancedDevice",
                                code: 4,
                                userInfo: [
                                    NSLocalizedDescriptionKey: error.localizedDescription,
                                ]
                            )))
                        }
                    }
                } else {
                    completion(.failure(NSError(
                        domain: "NeuroIDAdvancedDevice",
                        code: 5,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Method not available",
                        ]
                    )))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    internal static func getAPIKey(_ apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        let apiURL = URL(string: "https://receiver.neuro-id.com/a/\(apiKey)")!
        let task = URLSession.shared.dataTask(with: apiURL) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(
                    .failure(
                        NSError(
                            domain: "NeuroIDAdvancedDevice",
                            code: 1,
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
                                    code: 2,
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
                                code: 3,
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
}
