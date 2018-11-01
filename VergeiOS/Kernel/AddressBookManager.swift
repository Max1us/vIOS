//
//  AddressBookManager.swift
//  VergeiOS
//
//  Created by Swen van Zanten on 10-09-18.
//  Copyright © 2018 Verge Currency. All rights reserved.
//

import Foundation
import SwiftyJSON
import CoreStore

class AddressBookManager {
    
    func name(byAddress address: String) -> String? {
        let entity = CoreStore.fetchOne(From<AddressType>().where(\.address == address))

        return entity?.name
    }

    func get(byName name: String) -> Address? {
        return transform(entity: CoreStore.fetchOne(From<AddressType>().where(\.name == name)))
    }

    func get(byAddress address: String) -> Address? {
        return transform(entity: CoreStore.fetchOne(From<AddressType>().where(\.address == address)))
    }
    
    func all() -> [Address] {
        let entities = CoreStore.fetchAll(From<AddressType>())
        var addresses: [Address] = []

        for entity in entities ?? [] {
            addresses.append(transform(entity: entity))
        }
        
        return addresses
    }

    func put(address: Address) {
        var entity: AddressType? = nil
        if let existingEntity = CoreStore.fetchOne(From<AddressType>().where(\.address == address.address)) {
            entity = existingEntity
        }
        
        do {
            let _ = try CoreStore.perform(synchronous: { transaction -> Bool in
                if entity == nil {
                    entity = transaction.create(Into<AddressType>())
                } else {
                    entity = transaction.edit(entity)
                }

                entity?.name = address.name
                entity?.address = address.address

                return transaction.hasChanges
            })
        } catch {
            print(error.localizedDescription)
        }
    }

    func remove(address: Address) {
        let entity = CoreStore.fetchOne(From<AddressType>().where(\.name == address.name))

        do {
            let _ = try CoreStore.perform(synchronous: { transaction -> Bool in
                transaction.delete(entity)

                return transaction.hasChanges
            })
        } catch {
            print(error.localizedDescription)
        }
    }

    private func transform(entity: AddressType?) -> Address {
        let address = Address()
        address.name = entity?.name ?? ""
        address.address = entity?.address ?? ""

        return address
    }

}