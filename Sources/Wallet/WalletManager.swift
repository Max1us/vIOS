//
//  WalletManager.swift
//  VergeiOS
//
//  Created by Swen van Zanten on 26/10/2019.
//  Copyright © 2019 Verge Currency. All rights reserved.
//

import Foundation
import Logging
import Promises

class WalletManager: WalletManagerProtocol {
    private let walletClient: WalletClientProtocol
    private let walletTicker: TickerProtocol
    private let applicationRepository: ApplicationRepository
    private let credentials: Credentials
    private let log: Logger

    private let walletName = "ioswallet"
    private let copayerName = "iosuser"
    private let walletM = 1
    private let walletN = 1

    init(
        walletClient: WalletClientProtocol,
        walletTicker: TickerProtocol,
        applicationRepository: ApplicationRepository,
        credentials: Credentials,
        log: Logger
    ) {
        self.walletClient = walletClient
        self.walletTicker = walletTicker
        self.applicationRepository = applicationRepository
        self.credentials = credentials
        self.log = log
    }

    func getWallet() -> Promise<Vws.WalletStatus> {
        self.walletTicker.stop()

        return self.create()
            .then(self.storeWalletCredentials)
            .then(self.join)
            .then(self.open)
            .then { walletStatus -> Promise<Vws.WalletStatus> in
                self.walletTicker.start()

                return Promise {
                    return walletStatus
                }
            }
    }

    func scanWallet() -> Promise<Bool> {
        return Promise { fulfill, reject in
            self.walletClient.scanAddresses { error in
                if let error = error {
                    self.log.error("wallet manager wallet scan error: \(error.localizedDescription)")

                    return reject(error)
                }

                self.log.info("wallet manager wallet scan requested")

                fulfill(true)
            }
        }
    }

    private func create() -> Promise<Vws.WalletID?> {
        return Promise { fulfill, reject in
            self.walletClient.createWallet(
                walletName: self.walletName,
                copayerName: self.copayerName,
                m: self.walletM,
                n: self.walletN,
                options: nil
            ) { walletId, errorResponse, error in
                if let walletId = walletId {
                    self.log.info("wallet manager successfully created wallet", metadata: [
                        "walletId": Logger.MetadataValue(stringLiteral: walletId.identifier)
                    ])

                    self.applicationRepository.walletName = self.walletName

                    return fulfill(walletId)
                }

                if errorResponse?.code == .WalletAlreadyExists {
                    self.log.notice("wallet manager wallet already exists")

                    return fulfill(nil)
                }

                let error = errorResponse?.error ?? error ?? NSError("??")
                let errorMessage = errorResponse?.message ?? error.localizedDescription

                self.log.error("wallet manager creating wallet failed with: \(errorMessage)")

                reject(error)
            }
        }
    }
    
    private func storeWalletCredentials(_ walletId: Vws.WalletID?) -> Promise<Vws.WalletID?>  {
        return Promise { fulfill, _ in
            guard let walletId = walletId else {
                return fulfill(nil)
            }
            
            self.applicationRepository.walletId = walletId.identifier
            self.applicationRepository.walletSecret = try self.credentials.buildSecret(walletId: walletId.identifier)

            self.log.info("wallet manager store wallet secret: \(self.applicationRepository.walletSecret!)")

            fulfill(walletId)
        }
    }

    private func join(_ walletId: Vws.WalletID?) -> Promise<Vws.WalletJoin?> {
        return Promise { fulfill, reject in
            guard let walletIdentifier = walletId?.identifier else {
                return fulfill(nil)
            }

            self.walletClient.joinWallet(walletIdentifier: walletIdentifier) { walletJoin, errorResponse, error in
                if let walletJoin = walletJoin {
                    self.log.info("wallet manager successfully joined wallet", metadata: [
                        "copayerId": Logger.MetadataValue(stringLiteral: walletJoin.copayerId),
                        "walletId": Logger.MetadataValue(stringLiteral: walletJoin.wallet.id)
                    ])

                    return fulfill(walletJoin)
                }

                if errorResponse?.code == .CopayerRegistered {
                    self.log.notice("wallet manager wallet already exists")

                    return fulfill(nil)
                }

                let error = errorResponse?.error ?? error ?? NSError("??")
                let errorMessage = errorResponse?.message ?? error.localizedDescription

                self.log.error("wallet manager joining wallet failed with: \(errorMessage)")

                reject(error)
            }
        }
    }

    private func open(_ walletJoin: Vws.WalletJoin?) -> Promise<Vws.WalletStatus> {
        return Promise { fulfill, reject in
            self.walletClient.openWallet { walletStatus, errorResponse, error in
                if let walletStatus = walletStatus {
                    self.log.info("wallet manager successfully opened wallet", metadata: [
                        "walletId": Logger.MetadataValue(stringLiteral: walletStatus.wallet.id)
                    ])

                    return fulfill(walletStatus)
                }

                let error = errorResponse?.error ?? error ?? NSError("??")
                let errorMessage = errorResponse?.message ?? error.localizedDescription

                self.log.error("wallet manager opening wallet failed with: \(errorMessage)")

                reject(error)
            }
        }
    }
}
