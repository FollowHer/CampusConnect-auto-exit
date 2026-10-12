(() => {
  // No credentials or native bridge: only accelerate the inspected school's
  // initialization, preserving its original callbacks and encryption settings.
  if (window !== window.top || location.origin !== /*CAMPUS_ORIGIN*/) return;
  const start = () => {
    const load = window.onload;
    const known = typeof load === 'function' &&
      /^function\s*\([^)]*\)\s*\{\s*fillData\(\);\s*getServices\(\);\s*autosize\(\);?\s*\}$/.test(Function.prototype.toString.call(load));
    if (!known || !document.querySelector('#loginLink') ||
        typeof window.AuthInterFace?.pageInfo !== 'function' ||
        typeof window.AuthInterFace?.getServices !== 'function') return;
    const state = window.__campusReady = {pageInfo:false, getServices:false, failed:false};
    for (const name of ['pageInfo','getServices']) {
      const original = AuthInterFace[name];
      AuthInterFace[name] = function(...args) {
        const callback = args[args.length-1];
        if (typeof callback !== 'function') return original.apply(this,args);
        args[args.length-1] = function(...values) {
          // Mark ready only AFTER the school has installed handlers, selected
          // the service, and loaded its encryption key / captcha requirements.
          try { const result = callback.apply(this,values); state[name] = true; return result; }
          catch (error) { state.failed = true; throw error; }
        };
        return original.apply(this,args);
      };
    }
    // This exact handler has no load-event dependency. Invoke once at DOM ready;
    // late background images must not initialize it again or overwrite fields.
    window.onload = null;
    try { load.call(window); } catch (_) { state.failed = true; }
  };
  document.addEventListener('DOMContentLoaded', start, {once:true});
})();
