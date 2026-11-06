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

  function handleFocus(event) {
    const target = event.target;
    if (!isLoginCandidate(target)) return;

    currentActiveInput = target;

    postToNative('focus', {
      fieldType: isPasswordInput(target) ? 'password' : 'username',
      url: window.location.href,
      hostname: window.location.hostname,
      rect: getFieldRect(target)
    });
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

  document.addEventListener('focusin', handleFocus, true);
  document.addEventListener('focusout', handleBlur, true);
  document.addEventListener('submit', handleFormSubmit, true);
})();
