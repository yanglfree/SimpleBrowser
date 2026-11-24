// ZhuoBrowser AutoFill agent
// Reports login-field focus / form submission to the native side and fills the fields on request.
//
// Deliberately minimal:
// * no passkey UI or trigger — WebKit in a non-browser app reports no platform authenticator,
//   so a "通行密钥" entry could only be faked;
// * no automatic submit after filling — the user decides when to sign in;
// * no iframe broadcasting — a page must never be able to receive a saved secret.

(() => {
  'use strict';

  if (typeof window === 'undefined' || window.__zhuoAutoFillInjected) {
    return;
  }
  window.__zhuoAutoFillInjected = true;

  let currentActiveInput = null;
  let lastEnteredUsername = '';
  let lastReportedKey = '';
  let lastReportedAt = 0;

  const USERNAME_KEYWORDS_REGEX = /(user|username|account|login|email|mail|phone|mobile|tel|identifier|账号|用户名|邮箱|手机)/i;
  const TOGGLE_BUTTON_REGEX = /(show|hide|reveal|toggle|eye|visibility|显示|隐藏)/i;

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

  // Field bounds in the viewport coordinate space the native panel expects.
  function getFieldRect(el) {
    if (!el) return null;
    const rect = el.getBoundingClientRect();
    return {
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height,
      bottom: rect.bottom,
      right: rect.right,
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

  function reportFocus(target) {
    if (!isLoginCandidate(target)) return;
    currentActiveInput = target;

    postToNative('focus', {
      fieldType: isPasswordInput(target) ? 'password' : 'username',
      url: window.location.href,
      hostname: window.location.hostname,
      rect: getFieldRect(target)
    });
  }

  function handleFocus(event) {
    reportFocus(event.target);
  }

  function handleBlur() {
    setTimeout(() => {
      const active = document.activeElement;
      if (!isLoginCandidate(active)) {
        currentActiveInput = null;
        postToNative('blur', {});
      }
    }, 200);
  }

  function handleUsernameUpdate(event) {
    const target = event.target;
    if (isUsernameInput(target)) {
      const trimmed = (target.value || '').trim();
      if (trimmed) {
        lastEnteredUsername = trimmed;
      }
    }
  }

  function isPasswordVisibilityToggle(button) {
    if (!button) return false;
    const meta = [
      button.getAttribute('aria-label') || '',
      button.getAttribute('title') || '',
      button.className || '',
      button.id || ''
    ].join(' ');
    return TOGGLE_BUTTON_REGEX.test(meta);
  }

  function findCredentialsInContainer(root) {
    if (!root || !root.querySelectorAll) return { username: '', password: '' };
    let submittedUser = '';
    let submittedPass = '';
    const inputs = Array.from(root.querySelectorAll('input'));
    for (const input of inputs) {
      if (!submittedPass && isPasswordInput(input) && input.value) {
        submittedPass = input.value;
      } else if (!submittedUser && isUsernameInput(input) && input.value) {
        submittedUser = input.value.trim();
      }
    }
    return { username: submittedUser, password: submittedPass };
  }

  function reportSubmissionCandidate(root) {
    let found = findCredentialsInContainer(root);
    if (!found.password && root !== document) {
      found = findCredentialsInContainer(document);
    }

    const submittedPass = found.password;
    if (!submittedPass || submittedPass.length === 0) return;

    const submittedUser = found.username || lastEnteredUsername;
    const dedupKey = submittedUser + '\u0000' + submittedPass;
    const now = Date.now();
    if (dedupKey === lastReportedKey && now - lastReportedAt < 3000) {
      return;
    }
    lastReportedKey = dedupKey;
    lastReportedAt = now;

    postToNative('submitted', {
      url: window.location.href,
      hostname: window.location.hostname,
      username: submittedUser,
      password: submittedPass
    });
  }

  function handleClick(event) {
    const target = event.target;
    if (isLoginCandidate(target) && (target === document.activeElement || typeof target.focus === 'function')) {
      reportFocus(target);
      return;
    }

    const button = target && target.closest ? target.closest('button, input[type="submit"], [role="button"]') : null;
    if (button && !isPasswordVisibilityToggle(button)) {
      reportSubmissionCandidate(button.closest('form') || document);
    }
  }

  function handleKeydown(event) {
    if (event.key === 'Enter' && isPasswordInput(event.target) && event.target.value) {
      reportSubmissionCandidate(event.target.closest('form') || document);
    }
  }

  // Set the value through the native setter so React / Vue controlled inputs see the change.
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

  // Exposed API for the native controller. Only called after the user selected a saved password
  // and passed the Touch ID / login-password check on the native side.
  window.__zhuoAutoFill = {
    fill: function(username, password) {
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

      if (!usernameField && currentActiveInput && isEditableInput(currentActiveInput)) {
        usernameField = currentActiveInput;
      }

      let filledAny = false;
      if (username && usernameField) {
        setNativeValue(usernameField, username);
        lastEnteredUsername = username.trim();
        filledAny = true;
      }
      if (password && passwordField) {
        setNativeValue(passwordField, password);
        filledAny = true;
      }

      return filledAny;
    }
  };

  // Report successful-looking submissions so the native side can persist the password.
  function handleFormSubmit(event) {
    reportSubmissionCandidate(event.target);
  }

  document.addEventListener('focusin', handleFocus, true);
  document.addEventListener('focusout', handleBlur, true);
  document.addEventListener('input', handleUsernameUpdate, true);
  document.addEventListener('change', handleUsernameUpdate, true);
  document.addEventListener('click', handleClick, true);
  document.addEventListener('keydown', handleKeydown, true);
  document.addEventListener('submit', handleFormSubmit, true);

  // If the page auto-focused an input before atDocumentEnd injection, report it immediately.
  if (isLoginCandidate(document.activeElement)) {
    reportFocus(document.activeElement);
  }
})();
