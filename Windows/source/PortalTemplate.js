(() => {
  const cfg = /*CAMPUS_CONFIG*/;
  if (location.origin !== cfg.origin) return 'wrong-origin';
  if (window.__campusSubmitted) return 'already-submitted';
  if (document.readyState === 'loading') return 'waiting-ready';
  const ready = window.__campusReady;
  if (ready && (ready.failed || !ready.pageInfo || !ready.getServices)) return 'waiting-ready';
  const visible = e => e && !e.disabled && e.getClientRects().length > 0;
  const editable = e => e instanceof HTMLInputElement && !e.disabled && !e.readOnly;
  let user, pass, submit, portalUser, portalPass, portalButton;
  const tipFor = input => input === portalUser ? document.querySelector('#username_tip') :
    input === portalPass ? document.querySelector('#pwd_tip') : null;
  const available = input => editable(input) && (visible(input) ||
    (portalButton && visible(tipFor(input))));
  try {
    // Ruijie ePortal displays readonly tips over hidden real inputs. Its login
    // control is an image-only anchor, so text/button heuristics cannot find it.
    portalUser = document.querySelector('#username');
    portalPass = document.querySelector('#pwd');
    portalButton = document.querySelector('#loginLink');
    if (!editable(portalUser) || portalUser.type !== 'text' ||
        !editable(portalPass) || portalPass.type !== 'password' || !portalButton) {
      portalUser = portalPass = portalButton = null;
    }
    // Unknown ePortal variants retain full-load behavior; only inspected initialization is accelerated.
    if (portalButton && !ready && document.readyState !== 'complete') return 'waiting-ready';
    pass = cfg.passwordSelector ? document.querySelector(cfg.passwordSelector) :
      portalPass || [...document.querySelectorAll('input[type="password"]')].find(e => editable(e) && visible(e));
    const root = pass && pass.form ? pass.form : document;
    user = cfg.userSelector ? document.querySelector(cfg.userSelector) : portalUser ||
      [...root.querySelectorAll('input:not([type="password"]):not([type="hidden"]):not([type="checkbox"]):not([type="radio"]):not([type="submit"]):not([type="button"])')]
      .filter(e => editable(e) && visible(e)).find(e => /user|account|student|phone|login|学号|账号|手机/i.test([e.name,e.id,e.placeholder,e.autocomplete].join(' ')));
    if (!user && !cfg.userSelector) user = [...root.querySelectorAll('input[type="text"],input[type="tel"],input[type="email"],input:not([type])')].find(e => editable(e) && visible(e));
    submit = cfg.submitSelector ? document.querySelector(cfg.submitSelector) : portalButton ||
      [...root.querySelectorAll('button,input[type="submit"],input[type="button"],a,[role="button"]')].filter(visible)
        .find(e => e.type === 'submit' || /^(登录|登陆|认证|连接|login|log in|sign in|connect)(\s*(login|登录|登陆))?$/i.test((e.innerText || e.value || '').trim()));
  } catch (_) { return 'invalid-selector'; }
  if (!available(user) || !available(pass)) return 'missing-fields';
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
  for (const [input, value] of [[user,cfg.username],[pass,cfg.password]]) {
    if (!visible(input)) {
      const tip = tipFor(input);
      if (visible(tip)) tip.focus();
    }
    if (!visible(input)) return 'missing-fields';
    setter.call(input, value);
    input.dispatchEvent(new Event('input', {bubbles:true}));
    input.dispatchEvent(new Event('change', {bubbles:true}));
  }
  if (!cfg.submit) return 'filled';
  if (!visible(submit)) return 'missing-submit';
  if (portalButton && /doauthen/.test(submit.getAttribute('onclick') || '') &&
      typeof window.doauthen !== 'function') return 'waiting-ready';
  // Captchas and extra operator fields need the user's input; don't burn a login attempt.
  if (portalButton && ['#validCode','#operatorUserId','#operatorPwd'].some(selector => {
    const input = document.querySelector(selector);
    return visible(input) && !input.value.trim();
  })) return 'manual-required';
  window.__campusSubmitted = true;
  submit.click();
  return 'submitted';
})()
