import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusLabel = UILabel()
    private let actionStack = UIStackView()
    private var rawURL: String?
    private var sharedTitle = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        Task { await loadSharedContent() }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        titleLabel.text = "发送到卓阅"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.text = "正在读取分享内容…"
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 3

        statusLabel.text = "选择操作后，请打开卓阅继续。iOS 不允许分享扩展直接启动主应用。"
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        actionStack.axis = .vertical
        actionStack.spacing = 10
        actionStack.isHidden = true
        [
            ("清理跟踪参数后打开", InboundShareAction.cleanOpen),
            ("无痕打开", InboundShareAction.privateOpen),
            ("阅读并关闭", InboundShareAction.readAndClose),
            ("保存离线文章", InboundShareAction.saveArticle),
            ("打开原始链接", InboundShareAction.originalOpen)
        ].forEach { label, action in
            var configuration = UIButton.Configuration.tinted()
            configuration.title = label
            configuration.cornerStyle = .medium
            let button = UIButton(configuration: configuration)
            button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { [weak self] _ in self?.enqueue(action) }, for: .touchUpInside)
            actionStack.addArrangedSubview(button)
        }

        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = "取消"
        let cancelButton = UIButton(configuration: cancelConfiguration)
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, actionStack, statusLabel, cancelButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    @MainActor
    private func loadSharedContent() async {
        guard let content = await firstSharedContent() else {
            detailLabel.text = "没有找到可访问的 HTTP 或 HTTPS 链接。"
            statusLabel.text = "请返回并分享网页链接或包含网页链接的文本。"
            return
        }
        rawURL = content.url
        sharedTitle = content.title
        detailLabel.text = URL(string: content.url)?.host ?? content.url
        actionStack.isHidden = false
    }

    private func enqueue(_ action: InboundShareAction) {
        guard let rawURL,
              let request = InboundSharePolicy.create(
                rawURL: rawURL,
                title: sharedTitle,
                action: action
              ) else {
            showError("无法识别这个链接。")
            return
        }
        do {
            try InboundShareQueue.enqueue(request)
            actionStack.isUserInteractionEnabled = false
            statusLabel.textColor = .systemGreen
            statusLabel.text = "已发送到卓阅。下次打开应用时会继续处理。"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        } catch {
            showError("无法写入卓阅共享收件箱。请确认 App Group 能力已启用。")
        }
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.text = message
    }

    private func firstSharedContent() async -> (url: String, title: String)? {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in items {
            let title = item.attributedTitle?.string ?? ""
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let value = try? await loadItem(from: provider, typeIdentifier: UTType.url.identifier),
                   let url = urlString(from: value),
                   InboundSharePolicy.create(rawURL: url, action: .cleanOpen) != nil {
                    return (url, title)
                }
            }
        }
        for item in items {
            let title = item.attributedTitle?.string ?? ""
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let value = try? await loadItem(from: provider, typeIdentifier: UTType.plainText.identifier),
                   let text = textString(from: value),
                   let url = InboundSharePolicy.extractHTTPURL(from: text) {
                    return (url, title)
                }
            }
        }
        return nil
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
                }
            }
        }
    }

    private func urlString(from value: NSSecureCoding?) -> String? {
        if let url = value as? URL { return url.absoluteString }
        if let url = value as? NSURL { return url.absoluteString }
        if let text = value as? String { return text }
        if let text = value as? NSString { return text as String }
        return nil
    }

    private func textString(from value: NSSecureCoding?) -> String? {
        if let text = value as? String { return text }
        if let text = value as? NSString { return text as String }
        if let text = value as? NSAttributedString { return text.string }
        return nil
    }
}
