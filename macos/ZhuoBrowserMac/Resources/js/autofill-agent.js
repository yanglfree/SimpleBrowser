// ZhuoBrowser AutoFill & Quick Login Web Agent
// Detects login/password input fields, anchors the Safari-style autofill popover,
// renders inline keychain key icons, handles credential injection, and listens for form submission.

(() => {
  'use strict';

  if (typeof window === 'undefined' || window.__zhuoAutoFillInjected) {
    return;
  }
  window.__zhuoAutoFillInjected = true;

  let currentActiveInput = null;
  let activeKeyIcon = null;

  const USERNAME_KEYWORDS_REGEX = /(user|username|account|login|email|mail|phone|mobile|tel|identifier|账号|用户名|邮箱|手机)/i;

  function isEditableInput(el) {
    if (!el || el.tagName !== 'INPUT') return false;
    const type = (el.type || 'text').toLowerCase();
    const disallowedTypes = ['hidden', 'submit', 'reset', 'button', 'image', 'checkbox', 'radio', 'file', 'range', 'color', 'date', 'time', 'datetime-local', 'month', 'week'];
    return !disallowedTypes.includes(type) && !el.disabled && !el.readOnly;
  }

  function isPasswordInput(el) {
    if (!isEditableInput(el)) return false;
    const type = (el.type || '').toLowerCase();
    const ac = (el.getAttribute('autocomplete') || '').toLowerCase();
    return type === 'password' || ac.includes('password');
  }

  function isUsernameInput(el) {
    if (!isEditableInput(el) || isPasswordInput(el)) return false;
    const ac = (el.getAttribute('autocomplete') || '').toLowerCase();
    if (ac.includes('username') || ac.includes('email') || ac.includes('webauthn')) {
      return true;
    }
    const meta = [
      el.name || '',
      el.id || '',
      el.placeholder || '',
      el.getAttribute('aria-label') || '',
      el.getAttribute('title') || ''
    ].join(' ');
    return USERNAME_KEYWORDS_REGEX.test(meta);
  }

  function isLoginCandidate(el) {
    return isPasswordInput(el) || isUsernameInput(el);
  }

  // Calculate field bounds relative to top window viewport where possible
  function getFieldRect(el) {
    if (!el) return null;
    const rect = el.getBoundingClientRect();
    let totalX = rect.left;
    let totalY = rect.top;

    // If inside an accessible iframe, accumulate parent offsets
    let curWin = window;
    while (curWin !== curWin.top) {
      try {
        const parentWin = curWin.parent;
        const frames = parentWin.document.querySelectorAll('iframe, frame');
        let matchedFrame = null;
        for (const f of frames) {
          if (f.contentWindow === curWin) {
            matchedFrame = f;
            break;
          }
        }
        if (matchedFrame) {
          const fRect = matchedFrame.getBoundingClientRect();
          totalX += fRect.left;
          totalY += fRect.top;
          curWin = parentWin;
        } else {
          break;
        }
      } catch (_) {
        // Cross-origin iframe boundaries: stop traversal and let native bridge assist offset
        break;
      }
    }

    return {
      x: totalX,
      y: totalY,
      width: rect.width,
      height: rect.height,
      bottom: totalY + rect.height,
      right: totalX + rect.width,
      isTopFrame: window === window.top
    };
  }

  function postToNative(action, payload) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zhuoAutoFill) {
        window.webkit.messageHandlers.zhuoAutoFill.postMessage(Object.assign({ action: action }, payload || {}));
      }
    } catch (_) {}
  }

  // Render or remove inline key icon inside input field (similar to Safari screenshot 2)
  function removeInlineKeyIcon() {
    if (activeKeyIcon && activeKeyIcon.parentNode) {
      activeKeyIcon.parentNode.removeChild(activeKeyIcon);
    }
    activeKeyIcon = null;
  }

  function attachInlineKeyIcon(input) {
    removeInlineKeyIcon();
    if (!input || !input.getBoundingClientRect) return;
    const rect = input.getBoundingClientRect();
    if (rect.width < 100 || rect.height < 20) return;

    const iconWrapper = document.createElement('div');
    iconWrapper.className = 'zhuo-autofill-key-icon';
    iconWrapper.title = '使用已保存的密码或通行密钥快速登录';
    iconWrapper.style.position = 'absolute';
    iconWrapper.style.cursor = 'pointer';
    iconWrapper.style.zIndex = '2147483640';
    iconWrapper.style.display = 'flex';
    iconWrapper.style.alignItems = 'center';
    iconWrapper.style.justifyContent = 'center';
    iconWrapper.style.userSelect = 'none';
    iconWrapper.style.opacity = '0.75';
    iconWrapper.style.transition = 'opacity 0.15s ease';
    
    const iconSize = Math.min(20, Math.max(14, rect.height * 0.6));
    const rightMargin = 8;
    iconWrapper.style.width = (iconSize + 8) + 'px';
    iconWrapper.style.height = iconSize + 'px';
    iconWrapper.style.left = (rect.right + window.scrollX - (iconSize + 8) - rightMargin) + 'px';
    iconWrapper.style.top = (rect.top + window.scrollY + (rect.height - iconSize) / 2) + 'px';

    iconWrapper.innerHTML = `
      <svg width="${iconSize}" height="${iconSize}" viewBox="0 0 16 16" fill="currentColor" style="color: #4A4A4A;">
        <path fill-rule="evenodd" d="M11.5 1a3.5 3.5 0 0 0-3.46 4.02l-6.89 6.89a1 1 0 0 0-.29.71V14a1 1 0 0 0 1 1h1.5a1 1 0 0 0 1-1v-.5h1.5a1 1 0 0 0 1-1v-.5H9a1 1 0 0 0 .71-.29l.77-.77A3.5 3.5 0 1 0 11.5 1zm1.5 3.5a1 1 0 1 1-2 0 1 1 0 0 1 2 0z"/>
      </svg>
    `;

    iconWrapper.onmouseenter = () => { iconWrapper.style.opacity = '1.0'; };
    iconWrapper.onmouseleave = () => { iconWrapper.style.opacity = '0.75'; };
    iconWrapper.onclick = (e) => {
      e.preventDefault();
      e.stopPropagation();
      input.focus();
      const freshRect = getFieldRect(input);
      postToNative('focus', {
        fieldType: isPasswordInput(input) ? 'password' : 'username',
        url: window.location.href,
        hostname: window.location.hostname,
        rect: freshRect,
        forceOpen: true
      });
    };

    document.body.appendChild(iconWrapper);
    activeKeyIcon = iconWrapper;
  }

  function handleFocus(event) {
    const target = event.target;
    if (!isLoginCandidate(target)) return;

    currentActiveInput = target;
    const rect = getFieldRect(target);
    const isPw = isPasswordInput(target);

    attachInlineKeyIcon(target);

    postToNative('focus', {
      fieldType: isPw ? 'password' : 'username',
      url: window.location.href,
      hostname: window.location.hostname,
      rect: rect
    });
  }

  function handleBlur(event) {
    setTimeout(() => {
      const active = document.activeElement;
      if (!isLoginCandidate(active)) {
        removeInlineKeyIcon();
        postToNative('blur', {});
      }
    }, 200);
  }

  function handleScrollOrResize() {
    if (!currentActiveInput) return;
    const rect = getFieldRect(currentActiveInput);
    if (!rect || rect.bottom < 0 || rect.top > window.innerHeight) {
      removeInlineKeyIcon();
      postToNative('blur', {});
      return;
    }
    attachInlineKeyIcon(currentActiveInput);
    postToNative('update-rect', { rect: rect });
  }

  // Set input value cleanly and dispatch events to trigger web framework listeners (React, Vue, etc.)
  function setNativeValue(element, value) {
    if (!element) return;
    element.focus();
    const valueSetter = Object.getOwnPropertyDescriptor(element.__proto__, 'value') ||
                        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    if (valueSetter && valueSetter.set) {
      valueSetter.set.call(element, value);
    } else {
      element.value = value;
    }
    element.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
    element.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
  }

  // Helper to trigger next step (like clicking continue or submitting form)
  function attemptContinue() {
    if (!currentActiveInput) return;
    const form = currentActiveInput.closest('form') || document;
    
    // Look for submit or continue buttons
    const candidates = Array.from(form.querySelectorAll('button, input[type="submit"], [role="button"], a.button'));
    const continueBtn = candidates.find(btn => {
      const text = (btn.textContent || btn.value || btn.id || btn.className || '').toLowerCase();
      const aria = (btn.getAttribute('aria-label') || '').toLowerCase();
      return text.includes('continue') || text.includes('sign in') || text.includes('下一步') || text.includes('登录') || text.includes('arrow') || aria.includes('continue') || btn.type === 'submit';
    });

    if (continueBtn && typeof continueBtn.click === 'function') {
      setTimeout(() => continueBtn.click(), 100);
      return;
    }

    // Fallback: Dispatch Enter key on the input
    const enterEvent = new KeyboardEvent('keydown', {
      key: 'Enter',
      code: 'Enter',
      keyCode: 13,
      which: 13,
      bubbles: true,
      cancelable: true
    });
    currentActiveInput.dispatchEvent(enterEvent);
  }

  // Exposed API for native controller
  window.__zhuoAutoFill = {
    fill: function(username, password, shouldContinue) {
      let usernameField = null;
      let passwordField = null;

      const currentForm = currentActiveInput ? currentActiveInput.closest('form') : null;
      const root = currentForm || document;

      const inputs = Array.from(root.querySelectorAll('input'));
      for (const input of inputs) {
        if (!passwordField && isPasswordInput(input)) {
          passwordField = input;
        } else if (!usernameField && isUsernameInput(input)) {
          usernameField = input;
        }
      }

      if (currentActiveInput && isPasswordInput(currentActiveInput)) {
        passwordField = currentActiveInput;
        if (!usernameField) {
          const allInputs = Array.from(document.querySelectorAll('input'));
          const idx = allInputs.indexOf(currentActiveInput);
          for (let i = idx - 1; i >= 0; i--) {
            if (isEditableInput(allInputs[i]) && !isPasswordInput(allInputs[i])) {
              usernameField = allInputs[i];
              break;
            }
          }
        }
      } else if (currentActiveInput && isUsernameInput(currentActiveInput)) {
        usernameField = currentActiveInput;
      }

      // If active input is neither explicitly identified but active, use active input as target
      if (!usernameField && currentActiveInput && isEditableInput(currentActiveInput)) {
        usernameField = currentActiveInput;
      }

      let filledAny = false;
      if (username && usernameField) {
        setNativeValue(usernameField, username);
        filledAny = true;
      }
      if (password && passwordField) {
        setNativeValue(passwordField, password);
        filledAny = true;
      }

      removeInlineKeyIcon();

      if (shouldContinue) {
        attemptContinue();
      }

      return filledAny;
    },

    triggerPasskey: function() {
      // Find possible passkey triggers or conditional WebAuthn inputs
      const passkeyBtn = document.querySelector('[data-test*="passkey"], [data-provider*="passkey"], button[id*="passkey"], button[name*="passkey"]');
      if (passkeyBtn && typeof passkeyBtn.click === 'function') {
        passkeyBtn.click();
        return true;
      }
      return false;
    }
  };

  // Cross-frame messaging listener (allows filling inside any iframe)
  window.addEventListener('message', (event) => {
    if (event.data && event.data.type === 'zhuo-autofill-broadcast-fill') {
      const u = event.data.username || '';
      const p = event.data.password || '';
      const cont = Boolean(event.data.shouldContinue);
      window.__zhuoAutoFill.fill(u, p, cont);
    }
  });

  // Form submit interception for saving passwords
  function handleFormSubmit(event) {
    const form = event.target;
    if (!form || !form.querySelectorAll) return;

    let submittedUser = '';
    let submittedPass = '';

    const inputs = Array.from(form.querySelectorAll('input'));
    for (const input of inputs) {
      if (isPasswordInput(input) && input.value) {
        submittedPass = input.value;
      } else if (isUsernameInput(input) && input.value) {
        submittedUser = input.value;
      }
    }

    if (submittedPass && submittedPass.length > 0) {
      postToNative('submitted', {
        url: window.location.href,
        hostname: window.location.hostname,
        username: submittedUser,
        password: submittedPass
      });
    }
  }

  // Global listeners
  document.addEventListener('focusin', handleFocus, true);
  document.addEventListener('focusout', handleBlur, true);
  window.addEventListener('scroll', handleScrollOrResize, { passive: true });
  window.addEventListener('resize', handleScrollOrResize, { passive: true });
  document.addEventListener('submit', handleFormSubmit, true);
})();
