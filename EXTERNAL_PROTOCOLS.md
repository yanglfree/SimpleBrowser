# External Protocol Support

ZhuoBrowser treats HTTP(S) navigation and external application protocols as
different security boundaries. ArkWeb keeps normal web navigation. Main-frame
navigation to an external protocol is intercepted, shown to the user, and only
then passed to HarmonyOS through an implicit `ohos.want.action.viewData` Want.

## Supported protocol families

| Family | Known schemes | Typical targets |
| --- | --- | --- |
| App installation and stores | `store`, `market`, `appmarket`, `intent`, `hap` | HarmonyOS specified-device installer, AppGallery, application stores |
| Communication | `tel`, `sms`, `smsto`, `mms`, `mmsto`, `mailto`, `sip`, `im` | Dialer, Messages, Mail, VoIP clients |
| Navigation | `geo`, `map`, `maps`, `amap`, `baidumap`, `petalmaps` | Petal Maps and third-party map clients |
| Payment | `alipay`, `alipays`, `weixin`, `wechat`, `wxp`, `unionpay`, `upwallet` | Payment and wallet applications |
| Social and content | `mqq`, `mqqapi`, `qq`, `sinaweibo`, `weibo`, `zhihu`, `bilibili`, `taobao`, `openapp.jdmobile` | Messaging, social, video, and commerce applications |
| File transfer | `ftp`, `ftps`, `sftp`, `magnet`, `ed2k` | File managers and transfer clients |
| Other registered applications | Any syntactically valid custom scheme | Applications installed with a matching HarmonyOS URI skill |

The known list drives user-facing categorization, not a restrictive allowlist.
This lets newly installed applications work without a ZhuoBrowser release while
preserving a confirmation boundary and a clear failure message when HarmonyOS
cannot resolve the link.

## Schemes kept inside or blocked by the browser

- ArkWeb navigation: `http`, `https`, `about`, `data`, `blob`, `file`,
  `resource`, and the internal `browser` scheme.
- Never handed to another application: `javascript`, `arkweb`, `chrome`,
  `chrome-devtools`, and `devtools`.

Only main-frame navigation can request an external application. Subresources,
iframes, tracking pixels, and intercepted network requests cannot launch one.
The confirmation UI displays the source host and target scheme without logging
or uploading the full target URL or its query parameters.

## HarmonyOS installation contract

Specified-device installation links use this shape:

```text
store://enterprise/manifest?url=<percent-encoded HTTPS manifest URL>
```

ZhuoBrowser passes the complete URI unchanged to HarmonyOS. The operating
system remains responsible for validating the signed manifest, package hash,
device authorization, API compatibility, and the final installation consent.
