package com.youdroid.zhuobrowser.account

import java.util.Locale

enum class AuthProviderKind {
    EMAIL_OTP,
    EMAIL_PASSWORD,
    GOOGLE
}

/**
 * Resolves region-aware authentication providers for Android.
 * Google Sign-In is strictly hidden when the device region resolves to Mainland China ("CN")
 * or when no valid region can be determined.
 */
object RegionAuthPolicy {
    fun normalizedRegionCode(regionCode: String?): String {
        return regionCode?.trim()?.uppercase(Locale.ROOT).orEmpty()
    }

    fun isMainlandChinaRegion(regionCode: String?): Boolean {
        val code = normalizedRegionCode(regionCode)
        return code == "CN" || code == "CHN" || code == "ZH-CN"
    }

    fun isGoogleSignInAvailable(regionCode: String?): Boolean {
        val code = normalizedRegionCode(regionCode)
        if (code.isEmpty() || isMainlandChinaRegion(code)) {
            return false
        }
        return true
    }

    fun availableProviders(regionCode: String?): List<AuthProviderKind> {
        val providers = mutableListOf(
            AuthProviderKind.EMAIL_OTP,
            AuthProviderKind.EMAIL_PASSWORD
        )
        if (isGoogleSignInAvailable(regionCode)) {
            providers.add(AuthProviderKind.GOOGLE)
        }
        return providers
    }
}
