//
//  PurchaseManager.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import StoreKit

/// Manages in-app purchases using StoreKit 2
@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var product: StoreKit.Product?
    @Published private(set) var isPurchased: Bool = false
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    
    static let productID = "GTFractalsPurchase"
    
    init() {
        Task { await self.initialize() }
    }
    
    func initialize() async {
        await loadProduct()
        await refreshPurchasedState()
        // Observe transaction updates
        Task { await listenForTransactions() }
    }
    
    private func loadProduct() async {
        do {
            let products = try await StoreKit.Product.products(for: [Self.productID])
            self.product = products.first
        } catch {
            self.errorMessage = "Failed to load product. Please try again later."
#if DEBUG
            print("[IAP] loadProduct error: \(error)")
#endif
        }
    }
    
    private func listenForTransactions() async {
        for await result in StoreKit.Transaction.updates {
            do {
                let transaction = try self.checkVerified(result)
                await self.handle(transaction)
            } catch {
#if DEBUG
                print("[IAP] Transaction verification failed: \(error)")
#endif
            }
        }
    }
    
    private func checkVerified<T>(_ result: StoreKit.VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "IAP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unverified transaction"])
        case .verified(let safe):
            return safe
        }
    }
    
    private func handle(_ transaction: StoreKit.Transaction) async {
        // Finish and update state
        await transaction.finish()
        await refreshPurchasedState()
    }
    
    func refreshPurchasedState() async {
        var purchased = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID {
                purchased = true
                break
            }
        }
        self.isPurchased = purchased
    }
    
    func purchase() async {
        guard let product else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                _ = try checkVerified(verification)
                await refreshPurchasedState()
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
#if DEBUG
            print("[IAP] purchase error: \(error)")
#endif
        }
    }
    
    func restore() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await StoreKit.AppStore.sync()
            await refreshPurchasedState()
        } catch {
            self.errorMessage = (error as NSError).localizedDescription
#if DEBUG
            print("[IAP] restore error: \(error)")
#endif
        }
    }
}
