//
//  TorClient.swift
//  VergeiOS
//
//  Created by Swen van Zanten on 25-07-18.
//  Copyright © 2018 Verge Currency. All rights reserved.
//

import Foundation
import Tor
import Promises
import Logging

class TorClient: TorClientProtocol, HiddenClientProtocol {

    enum Error: Swift.Error {
        case controllerNotSet
        case waitedTooLongForConnection
    }

    private var applicationRepository: ApplicationRepository!
    private var log: Logger!
    private var config: TorConfiguration = TorConfiguration()
    private var thread: TorThread?
    private var controller: TorController!

    // Client status?
    private(set) var isOperational: Bool = false
    private var isConnected: Bool {
        return self.controller?.isConnected ?? false
    }

    // The tor url session configuration.
    // Start with default config as fallback.
    private var sessionConfiguration: URLSessionConfiguration = .default

    // The tor client url session including the tor configuration.
    var session: URLSession {
        self.sessionConfiguration.httpAdditionalHeaders = ["User-Agent": UUID().uuidString]
        return URLSession(configuration: self.sessionConfiguration)
    }

    public init(applicationRepository: ApplicationRepository, log: Logger) {
        self.applicationRepository = applicationRepository
        self.log = log
    }

    private func setupThread() {
        #if DEBUG
            let log_loc = "notice stdout"
        #else
            let log_loc = "notice file /dev/null"
        #endif

        self.config.cookieAuthentication = true
        self.config.dataDirectory = URL(fileURLWithPath: self.createDataDirectory())
        self.config.arguments = [
            "--allow-missing-torrc",
            "--ignore-missing-torrc",
            "--ClientOnly", "1",
            "--AvoidDiskWrites", "1",
            "--SocksPort", "127.0.0.1:39050",
            "--ControlPort", "127.0.0.1:39060",
            "--Log", log_loc,
        ]

        self.thread = TorThread(configuration: self.config)
    }

    // Start the tor client.
    func start(completion: @escaping (Bool) -> Void = { bool in }) {
        // If already operational don't start a new client.
        if self.isOperational || self.turnedOff() {
            NotificationCenter.default.post(name: .didFinishTorStart, object: self)

            return completion(true)
        }

        // Make sure we don't have a thread already.
        if self.thread == nil {
            self.setupThread()
        }

        // Initiate the controller.
        self.controller = TorController(socketHost: "127.0.0.1", port: 39060)

        // Start a tor thread.
        if (self.thread?.isExecuting ?? false) == false {
            self.thread?.start()

            NotificationCenter.default.post(name: .didStartTorThread, object: self)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Connect Tor controller.
            self.connectController(self.controller) { success in
                NotificationCenter.default.post(name: .didFinishTorStart, object: self)

                completion(success)
            }
        }
    }

    // Resign the tor client.
    func restart() {
        self.resign()

        if !self.isOperational {
            self.log.notice("Tor couldn't restart cause it's still operational")

            return
        }

        while self.controller.isConnected ?? true {
            self.log.notice("Tor controller is still connected")
        }

        NotificationCenter.default.post(name: .didResignTorConnection, object: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.start()
        }
    }

    func resign() {
        if !self.isOperational {
            self.log.notice("Tor couldn't resign cause it's still operational")

            return
        }

        self.log.notice("Disconnecting Tor controller")
        self.controller.disconnect()
        self.controller = nil

        self.log.notice("Cancelling Tor thread")
        self.thread?.cancel()
        self.thread = nil

        self.isOperational = false
        self.sessionConfiguration = .default
        self.log.notice("Tor resign sequence completed")

        NotificationCenter.default.post(name: .didTurnOffTor, object: self)
    }

    func turnedOff() -> Bool {
        return !self.applicationRepository.useTor
    }

    func getURLSession() -> Promise<URLSession> {
        return Promise<URLSession> { fulfill, reject in
            if self.isOperational || self.turnedOff() {
                return fulfill(self.session)
            }

            let started: DispatchTime = .now()
            let _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                if self.isOperational {
                    timer.invalidate()

                    self.log.notice("Successfully got a Tor URL session")

                    return fulfill(self.session)
                }

                // Wait a full minute to conclude its not gonna happen.
                if DispatchTime.now().uptimeNanoseconds > (started.uptimeNanoseconds + (60 * 1000000000)) {
                    timer.invalidate()

                    self.log.error("Waiting for Tor URL session took too long, aborting")

                    return reject(Error.waitedTooLongForConnection)
                }
            }
        }
    }

    private func connectController(_ controller: TorController, completion: @escaping (Bool) -> Void) {
        do {
            if !controller.isConnected {
                try self.controller?.connect()
                NotificationCenter.default.post(name: .didConnectTorController, object: self)
            }

            try self.authenticateController(controller) { success in
                self.log.notice("Tor tunnel successfully started")

                NotificationCenter.default.post(name: .didEstablishTorConnection, object: self)

                completion(success)
            }
        } catch {
            self.log.error("Error during tor connection: \(error.localizedDescription)")

            NotificationCenter.default.post(name: .errorDuringTorConnection, object: error)

            completion(false)
        }
    }

    private func authenticateController(_ controller: TorController, completion: @escaping (Bool) -> Void) throws {
        let cookie = try Data(
            contentsOf: config.dataDirectory!.appendingPathComponent("control_auth_cookie"),
            options: NSData.ReadingOptions(rawValue: 0)
        )

        controller.authenticate(with: cookie) { _, error in
            if let error = error {
                NotificationCenter.default.post(name: .errorDuringTorConnection, object: error)

                return completion(false)
            }

            var observer: Any?
            observer = controller.addObserver(forCircuitEstablished: { established in
                guard established else {
                    return
                }

                self.log.notice("Tor controller connected")

                controller.getSessionConfiguration { sessionConfig in
                    self.sessionConfiguration = sessionConfig!

                    self.isOperational = true
                    completion(true)
                }

                self.controller?.removeObserver(observer)
            })

            var progressObs: Any?
            progressObs = controller.addObserver { type, severity, action, arguments in
                print(type, severity, action, arguments)

                return true
            }
        }
    }

    private func createDataDirectory() -> String {
        let torPath = self.getTorPath()

        do {
            try FileManager.default.createDirectory(atPath: torPath, withIntermediateDirectories: false, attributes: [
                FileAttributeKey.posixPermissions: 0o700
            ])

            self.log.notice("Tor data directory created")
        } catch {
            self.log.error("Tor data directory couldn't be created: \(error.localizedDescription)")
        }

        return torPath
    }

    private func getTorPath() -> String {
        var documentsDirectory = ""
        if Platform.isSimulator {
            let path = NSSearchPathForDirectoriesInDomains(.applicationDirectory, .userDomainMask, true).first ?? ""
            documentsDirectory = "\(path.split(separator: Character("/"))[0..<2].joined(separator: "/"))/.tor_tmp"
        } else {
            documentsDirectory =
            "\(NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "")/t"
        }

        return documentsDirectory
    }
}
