import Foundation

struct PageLoadErrorPresentation: Equatable {
    let title: String
    let message: String
    let symbolName: String?
    let showsSecurityDetails: Bool

    init?(kind: PageLoadErrorKind) {
        switch kind {
        case .none:
            return nil
        case .offline:
            title = "没有网络连接"
            message = "请检查 Wi-Fi 或蜂窝网络，然后重试"
            symbolName = "wifi.slash"
            showsSecurityDetails = false
        case .timeout:
            title = "连接超时"
            message = "网络较慢或服务器无响应，请稍后重试"
            symbolName = "wifi.slash"
            showsSecurityDetails = false
        case .dns:
            title = "找不到该网站"
            message = "请检查网址是否正确，或确认网络已连接"
            symbolName = "icloud.slash"
            showsSecurityDetails = false
        case .certificate:
            title = "连接证书异常"
            message = "为保护你的隐私，浏览器不会自动绕过证书错误。"
            symbolName = nil
            showsSecurityDetails = true
        case .unknown:
            title = "页面加载失败"
            message = "无法完成页面加载，请稍后重试。"
            symbolName = nil
            showsSecurityDetails = false
        }
    }
}
