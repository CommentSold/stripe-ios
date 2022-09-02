//
//  AuthFlowDataManager.swift
//  StripeFinancialConnections
//
//  Created by Vardges Avetisyan on 6/7/22.
//

import Foundation
@_spi(STP) import StripeCore

protocol AuthFlowDataManager: AnyObject {
    var manifest: FinancialConnectionsSessionManifest { get }
    var authorizationSession: FinancialConnectionsAuthorizationSession? { get }
    var institution: FinancialConnectionsInstitution? { get }
    var paymentAccountResource: FinancialConnectionsPaymentAccountResource? { get }
    var accountNumberLast4: String? { get }
    var linkedAccounts: [FinancialConnectionsPartnerAccount]? { get }
    var delegate: AuthFlowDataManagerDelegate? { get set }
    
    // MARK: - Read Calls
    
    func nextPane() -> FinancialConnectionsSessionManifest.NextPane

    // MARK: - Mutating Calls
    
    func consentAcquired()
    func requestedManualEntry()
    func picked(institution: FinancialConnectionsInstitution)
    func didCompletePartnerAuth(authSession: FinancialConnectionsAuthorizationSession)
    func didLinkAccounts(_ linkedAccounts: [FinancialConnectionsPartnerAccount])
    func didCompleteManualEntry(
        withPaymentAccountResource paymentAccountResource: FinancialConnectionsPaymentAccountResource,
        accountNumberLast4: String
    )
    func didSelectLinkMoreAccounts()
    func didSucceedSelectLinkMoreAccounts(manifest: FinancialConnectionsSessionManifest)
}

protocol AuthFlowDataManagerDelegate: AnyObject {
    func authFlowDataManagerDidUpdateNextPane(_ dataManager: AuthFlowDataManager)
    func authFlowDataManagerDidUpdateManifest(_ dataManager: AuthFlowDataManager)
    func authFlow(dataManager: AuthFlowDataManager,
                  failedToUpdateManifest error: Error)
}

class AuthFlowAPIDataManager: AuthFlowDataManager {
    
    // MARK: - Types
    
    struct VersionedNextPane {
        let pane: FinancialConnectionsSessionManifest.NextPane
        let version: Int
    }

    // MARK: - Properties
    
    weak var delegate: AuthFlowDataManagerDelegate?
    private(set) var manifest: FinancialConnectionsSessionManifest {
        didSet {
            delegate?.authFlowDataManagerDidUpdateManifest(self)
        }
    }
    private let api: FinancialConnectionsAPIClient
    private let clientSecret: String
    
    private(set) var authorizationSession: FinancialConnectionsAuthorizationSession?
    private(set) var institution: FinancialConnectionsInstitution?
    private(set) var paymentAccountResource: FinancialConnectionsPaymentAccountResource?
    private(set) var accountNumberLast4: String?
    private(set) var linkedAccounts: [FinancialConnectionsPartnerAccount]?
    private var currentNextPane: VersionedNextPane {
        didSet {
            delegate?.authFlowDataManagerDidUpdateNextPane(self)
        }
    }

    // MARK: - Init
    
    init(with initial: FinancialConnectionsSessionManifest,
         api: FinancialConnectionsAPIClient,
         clientSecret: String) {
        self.manifest = initial
        self.currentNextPane = VersionedNextPane(pane: initial.nextPane, version: 0)
        self.api = api
        self.clientSecret = clientSecret
    }

    // MARK: - FlowDataManager
    
    func nextPane() -> FinancialConnectionsSessionManifest.NextPane {
        return currentNextPane.pane
    }

    func consentAcquired() {
        let version = currentNextPane.version + 1
        api.markConsentAcquired(clientSecret: clientSecret)
            .observe(on: .main) { [weak self] result in
                guard let self = self else { return }
                switch(result) {
                case .failure(let error):
                    self.delegate?.authFlow(dataManager: self, failedToUpdateManifest: error)
                case .success(let manifest):
                    self.update(nextPane: manifest.nextPane, for: version)
                    self.manifest = manifest
                }
        }
    }
    
    func requestedManualEntry() {
        let version = currentNextPane.version + 1
        self.update(nextPane: .manualEntry, for: version)
    }
    
    func picked(institution: FinancialConnectionsInstitution) {
        self.institution = institution
        let version = currentNextPane.version + 1
        update(nextPane: .partnerAuth, for: version)
    }
    
    func didCompletePartnerAuth(authSession: FinancialConnectionsAuthorizationSession) {
        self.authorizationSession = authSession
        
        let version = currentNextPane.version + 1
        update(nextPane: .accountPicker, for: version)
    }
    
    func didLinkAccounts(_ linkedAccounts: [FinancialConnectionsPartnerAccount]) {
        self.linkedAccounts = linkedAccounts
        
        let version = currentNextPane.version + 1
        update(nextPane: .success, for: version)
    }
    
    func didCompleteManualEntry(
        withPaymentAccountResource paymentAccountResource: FinancialConnectionsPaymentAccountResource,
        accountNumberLast4: String
    ) {
        self.paymentAccountResource = paymentAccountResource
        self.accountNumberLast4 = accountNumberLast4
        
        if manifest.manualEntryUsesMicrodeposits {
            let version = currentNextPane.version + 1
            update(nextPane: .manualEntrySuccess, for: version)
        } else {
            assertionFailure("Unimplemented") // TODO(kgaidis): complete the session & close; this happens in multiple parts (manual entry, manual entry success pane, success pane)
        }
    }
    
    func didSelectLinkMoreAccounts() {
        let version = currentNextPane.version + 1
        update(nextPane: .linkMoreAccounts, for: version)
    }
    
    func didSucceedSelectLinkMoreAccounts(manifest: FinancialConnectionsSessionManifest) {
        // reset state
        self.authorizationSession = nil
        self.institution = nil
        self.paymentAccountResource = nil
        self.accountNumberLast4 = nil
        self.linkedAccounts = nil
        self.manifest = manifest
        
        let version = currentNextPane.version + 1
        update(nextPane: manifest.nextPane, for: version)
    }
}

// MARK: - Helpers

private extension AuthFlowAPIDataManager {
    func update(nextPane: FinancialConnectionsSessionManifest.NextPane, for version: Int) {
        if version > self.currentNextPane.version {
            self.currentNextPane = VersionedNextPane(pane: nextPane, version: version)
        }
    }
}
