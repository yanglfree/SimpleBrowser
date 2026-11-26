package com.youdroid.zhuobrowser.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.youdroid.zhuobrowser.account.RegionAuthPolicy
import com.youdroid.zhuobrowser.session.BrowserSession
import java.text.DateFormat
import java.util.Date
import java.util.Locale

@Composable
fun AccountPane(session: BrowserSession) {
    val state by session.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val googleAllowed = remember { RegionAuthPolicy.isGoogleSignInAvailable(Locale.getDefault().country) }

    var useOtpMode by remember { mutableStateOf(true) }
    var isRegisterMode by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var otpSent by remember { mutableStateOf(false) }
    var showDeleteConfirm by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Tokens.pageBackground)
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "账号与云同步",
                fontSize = 24.sp,
                fontWeight = FontWeight.Medium,
                color = Tokens.textPrimary,
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = { session.setShowsAccount(false) }) {
                Text("完成", color = Tokens.accent)
            }
        }

        val user = state.accountUser
        if (user != null) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Tokens.surfacePanel)
                    .border(1.dp, Tokens.border, RoundedCornerShape(14.dp))
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(user.displayName, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = Tokens.textPrimary)
                Text(user.email, fontSize = 14.sp, color = Tokens.textSecondary)
                if (state.isPro) {
                    Text("Pro 权益已在当前账号跨端生效", fontSize = 13.sp, color = Tokens.accent)
                }
                if (state.lastSyncAt > 0L) {
                    val timeLabel = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
                        .format(Date(state.lastSyncAt))
                    Text("上次同步：$timeLabel", fontSize = 12.sp, color = Tokens.textSecondary)
                }
            }

            Button(
                onClick = { session.syncNow() },
                enabled = !state.isSyncing,
                colors = ButtonDefaults.buttonColors(containerColor = Tokens.accent),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(if (state.isSyncing) "正在同步…" else "立即同步")
            }

            if (state.remoteDeviceTabs.isNotEmpty()) {
                HorizontalDivider(color = Tokens.border)
                Text("其他设备的标签页", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Tokens.textSecondary)
                state.remoteDeviceTabs.forEach { group ->
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(Tokens.surfacePanel)
                            .border(1.dp, Tokens.border, RoundedCornerShape(12.dp))
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text("${group.deviceName} (${group.platform})", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Tokens.textPrimary)
                        group.tabs.take(10).forEach { tab ->
                            Text(
                                text = tab.title,
                                fontSize = 14.sp,
                                color = Tokens.accent,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        session.setShowsAccount(false)
                                        session.openInActiveTab(tab.url)
                                    }
                                    .padding(vertical = 4.dp)
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = { session.logoutAccount() },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("退出登录", color = Tokens.textPrimary)
            }

            if (showDeleteConfirm) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(Tokens.surfaceSubtle)
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        "将永久删除账号及所有云端书签、设置和文章同步数据，操作不可撤销。",
                        fontSize = 13.sp,
                        color = Tokens.textPrimary
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        OutlinedButton(
                            onClick = { showDeleteConfirm = false },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("取消", color = Tokens.textPrimary)
                        }
                        Button(
                            onClick = {
                                showDeleteConfirm = false
                                session.deleteAccount()
                            },
                            colors = ButtonDefaults.buttonColors(containerColor = androidx.compose.ui.graphics.Color(0xFFB3261E)),
                            modifier = Modifier.weight(1f)
                        ) {
                            Text("确认注销")
                        }
                    }
                }
            } else {
                TextButton(
                    onClick = { showDeleteConfirm = true },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("永久注销账号", color = androidx.compose.ui.graphics.Color(0xFFB3261E))
                }
            }
        } else {
            Text(
                text = "未登录时仍可完整使用本地浏览、去广告、书签与阅读器。登录可跨端同步书签、设置、站点控制与其他设备标签页。",
                fontSize = 13.sp,
                color = Tokens.textSecondary
            )

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = { useOtpMode = true },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (useOtpMode) "✓ 邮箱验证码" else "邮箱验证码", color = Tokens.textPrimary)
                }
                OutlinedButton(
                    onClick = { useOtpMode = false },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(if (!useOtpMode) "✓ 邮箱密码" else "邮箱密码", color = Tokens.textPrimary)
                }
            }

            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("邮箱") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            if (useOtpMode) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = code,
                        onValueChange = { code = it },
                        label = { Text("6位验证码") },
                        singleLine = true,
                        modifier = Modifier.weight(1f)
                    )
                    Button(
                        onClick = {
                            session.sendOtp(email) { sent ->
                                if (sent) otpSent = true
                            }
                        },
                        enabled = !state.isSyncing && email.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = Tokens.accent)
                    ) {
                        Text(if (otpSent) "重发" else "发送")
                    }
                }
                Button(
                    onClick = { session.verifyOtp(email, code, displayName) },
                    enabled = !state.isSyncing && email.isNotBlank() && code.length >= 6,
                    colors = ButtonDefaults.buttonColors(containerColor = Tokens.accent),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("验证码登录 / 注册")
                }
            } else {
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("密码") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth()
                )
                if (isRegisterMode) {
                    OutlinedTextField(
                        value = displayName,
                        onValueChange = { displayName = it },
                        label = { Text("昵称（可选）") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                Button(
                    onClick = {
                        if (isRegisterMode) {
                            session.registerPassword(email, password, displayName)
                        } else {
                            session.loginPassword(email, password)
                        }
                    },
                    enabled = !state.isSyncing && email.isNotBlank() && password.isNotBlank(),
                    colors = ButtonDefaults.buttonColors(containerColor = Tokens.accent),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (isRegisterMode) "注册并登录" else "登录")
                }
                TextButton(
                    onClick = { isRegisterMode = !isRegisterMode },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(if (isRegisterMode) "已有账号？切换登录" else "没有账号？注册新账号", color = Tokens.accent)
                }
            }

            if (googleAllowed) {
                HorizontalDivider(color = Tokens.border)
                OutlinedButton(
                    onClick = {
                        val url = session.startGoogleSignInUrl()
                        if (url != null) {
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("使用 Google 账号登录", color = Tokens.textPrimary)
                }
            }
        }

        state.accountError?.takeIf { it.isNotBlank() }?.let { err ->
            Text(err, fontSize = 13.sp, color = androidx.compose.ui.graphics.Color(0xFFB3261E))
        }
    }
}
