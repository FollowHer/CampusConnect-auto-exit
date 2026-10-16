  // Activate required login checkboxes through school handlers.
  // The caller has already checked network/origin and identified the login inputs.
  {
    const root = pass.form || document;
    const attempted = window.__campusAgreementAttempts ||= new WeakMap();
    const candidates = [...root.querySelectorAll('input[type="checkbox"],[role="checkbox"]')]
      .filter(box => box instanceof HTMLInputElement ? box.type === 'checkbox' : box.getAttribute?.('role') === 'checkbox');
    for (const box of candidates) {
      if (box.form && box.form !== pass.form) continue;
      const labels = [...(box.labels || [])];
      const wrapper = box.closest('label,[role=checkbox],.checkbox,.agreement,.protocol');
      if (wrapper && !labels.includes(wrapper)) labels.push(wrapper);
      for (const id of (box.getAttribute('aria-labelledby') || '').split(/\s+/)) {
        const label = document.getElementById(id);
        if (label) labels.push(label);
      }
      const text = [box.getAttribute('aria-label'), ...labels.map(label => label.textContent),
        box.getAttribute('role') === 'checkbox' ? box.textContent : '', box.id, box.name].join(' ');
      if (/记住|自动登录|保持登录|订阅|推广|广告|促销|营销|优惠|newsletter|marketing|remember|stay\s+signed/i.test(text)) continue;
      const agreement = /同意|已阅读|阅读并|服务(?:使用)?协议|用户协议|隐私政策|使用条款|\bagree\b|\baccept\b|\bterms\b|\bprivacy\b/i.test(text);
      if (!box.required && box.getAttribute('aria-required') !== 'true' && !agreement) continue;
      if (!visible(box) && !labels.some(visible)) continue;
      const checked = () => box instanceof HTMLInputElement ? box.checked : box.getAttribute('aria-checked') === 'true';
      if (checked()) continue;
      if (box.disabled || box.getAttribute('aria-disabled') === 'true') return 'agreement-required';
      const previous = attempted.get(box);
      if (previous) return Date.now() - previous.started < 2000 ? 'waiting-agreement' : 'agreement-required';
      attempted.set(box, { started: Date.now() });
      box.click();
      if (!checked()) return 'waiting-agreement';
    }
  }
