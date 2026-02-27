//
//  AboutView.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI
import StoreKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = PurchaseManager()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header icon and text
                VStack(spacing: 12) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("Support Development")
                        .font(.title2).bold()
                    Text("GT ASCII Camera is free and ad‑free. If you find it useful, consider buying me a coffee to support continued development.")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                
                // Product Card
                Group {
                    if let product = store.product {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("GT Fractals In‑App Purchase")
                                        .font(.headline)
                                    Text("Support the development of GT Fractals.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice)
                                    .font(.headline)
                            }
                            
                            Button {
                                Task { await store.purchase() }
                            } label: {
                                HStack {
                                    Image(systemName: "cup.and.saucer")
                                    Text(store.isPurchased ? "Thank You!" : "Buy Me a Coffee")
                                        .bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(store.isPurchased ? Color.green.opacity(0.2) : Color.blue)
                                .foregroundStyle(store.isPurchased ? .green : .white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .disabled(store.isPurchased || store.isProcessing)
                        }
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    } else {
                        ProgressView().padding()
                    }
                }
                
                // Restore
                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                .disabled(store.isProcessing)
                .padding(.top, 8)
                
                Spacer()
            }
            .navigationTitle("Support Developer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AboutView()
}
