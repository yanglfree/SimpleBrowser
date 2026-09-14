import SwiftUI

struct ProPaywallView: View {
    @EnvironmentObject private var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var selection = ProPaywallSelection(products: [])

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    benefits
                    plans
                    purchaseArea
                }
                .padding(20)
            }
            .background(DesignTokens.pageBackground)
            .navigationTitle("卓阅 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("pro-close")
                }
            }
        }
        .task {
            await session.pro.fetchProducts()
            selection.updateProducts(session.pro.products)
        }
        .onChange(of: session.pro.products) { _, products in
            selection.updateProducts(products)
        }
        .accessibilityIdentifier("pro-paywall")
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(DesignTokens.accent)
            Text(session.pro.isPro ? "Pro 已激活" : "把重要网页真正留在身边")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
                .multilineTextAlignment(.center)
            Text(session.pro.isPro ? activeDetail : "离线文章、批注整理与可迁移导出，一次保存，长期可读。")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var benefits: some View {
        VStack(spacing: 10) {
            benefit(icon: "arrow.down.doc.fill", title: "离线保存", detail: "正文与页面资源保存在本机")
            benefit(icon: "highlighter", title: "批注整理", detail: "标签、主题、笔记与高亮集中管理")
            benefit(icon: "square.and.arrow.up", title: "开放导出", detail: "随时导出 Markdown 或 HTML")
        }
    }

    private var plans: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("选择方案")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if session.pro.isLoadingProducts {
                    ProgressView()
                }
            }
            ForEach(session.pro.products) { product in
                Button {
                    selection.select(product.id, products: session.pro.products)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selection.productID == product.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.productID == product.id ? DesignTokens.accent : DesignTokens.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(product.plan.title)
                                    .font(.system(size: 16, weight: .semibold))
                                if product.plan == .yearly {
                                    Text("推荐")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(DesignTokens.accent, in: Capsule())
                                }
                            }
                            Text(product.plan.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                        Spacer()
                        Text(product.displayPrice)
                            .font(.system(size: 17, weight: .bold))
                    }
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(14)
                    .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(selection.productID == product.id ? DesignTokens.accent : DesignTokens.border, lineWidth: selection.productID == product.id ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(session.pro.isPurchasing)
                .accessibilityIdentifier("pro-plan-\(product.plan.rawValue)")
            }
            if session.pro.products.isEmpty && !session.pro.isLoadingProducts {
                VStack(spacing: 8) {
                    Text(session.pro.statusMessage ?? "App Store 商品暂不可用。")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("重新加载") {
                        Task { await session.pro.fetchProducts() }
                    }
                    .accessibilityIdentifier("pro-retry-products")
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var purchaseArea: some View {
        VStack(spacing: 12) {
            if !session.pro.isPro {
                Toggle(isOn: acceptedTermsBinding) {
                    Text("我已阅读并同意会员方案、自动续订说明、用户协议与隐私政策")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .tint(DesignTokens.accent)
                .accessibilityIdentifier("pro-terms-toggle")

                Button {
                    guard let productID = selection.productID else { return }
                    Task {
                        if await session.pro.purchase(productID: productID) {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if session.pro.isPurchasing { ProgressView().tint(.white) }
                        Text(session.pro.isPurchasing ? "处理中…" : purchaseButtonTitle)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
                .disabled(!selection.canPurchase || session.pro.isPurchasing)
                .accessibilityIdentifier("pro-purchase")
            }

            HStack(spacing: 18) {
                Button("恢复购买") {
                    Task { _ = await session.pro.restorePurchases() }
                }
                .accessibilityIdentifier("pro-restore")
                Button("管理订阅") {
                    Task { await session.pro.manageSubscriptions() }
                }
                .accessibilityIdentifier("pro-manage-subscription")
            }
            .font(.system(size: 13, weight: .medium))

            if let status = session.pro.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pro-status")
            }

            Text(legalText)
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Link("用户协议", destination: AppInformation.termsURL)
                Link("隐私政策", destination: AppInformation.privacyURL)
                Link("联系支持", destination: AppInformation.supportURL)
            }
            .font(.system(size: 12))
        }
    }

    private func benefit(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
        }
        .foregroundStyle(DesignTokens.textPrimary)
        .padding(12)
        .background(DesignTokens.surfacePanel, in: RoundedRectangle(cornerRadius: 12))
    }

    private var acceptedTermsBinding: Binding<Bool> {
        Binding(
            get: { selection.hasAcceptedTerms },
            set: { selection.setAcceptedTerms($0) }
        )
    }

    private var selectedPlan: ProPlan? {
        session.pro.products.first(where: { $0.id == selection.productID })?.plan
    }

    private var purchaseButtonTitle: String {
        selectedPlan == .lifetime ? "立即购买" : "立即订阅"
    }

    private var legalText: String {
        selectedPlan == .lifetime
            ? "终身会员为一次性购买，可在同一 Apple 账户下恢复。"
            : "订阅将由 Apple 账户确认付款并自动续订，可在系统订阅管理中随时取消。"
    }

    private var activeDetail: String {
        guard let entitlement = session.pro.entitlement else { return "会员权益已生效。" }
        if entitlement.plan == .lifetime { return "终身会员权益已生效。" }
        guard entitlement.expiresAt > 0 else { return "会员权益已生效。" }
        return "有效期至 \(Date(timeIntervalSince1970: entitlement.expiresAt / 1_000).formatted(date: .abbreviated, time: .omitted))"
    }
}
