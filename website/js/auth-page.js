(function () {
  var api = window.HotPotApi;
  if (!api) return;

  var mode = 'signin';
  var params = new URLSearchParams(window.location.search);
  var next = params.get('next') || '/checkout';
  var ref = (params.get('ref') || '').trim().toUpperCase().replace(/\s+/g, '');
  var REF_KEY = 'hotpotchef_referral_code_v1';

  if (!ref) {
    try {
      ref = (window.sessionStorage.getItem(REF_KEY) || '').trim().toUpperCase();
    } catch (_) {}
  }
  if (ref) {
    try {
      window.sessionStorage.setItem(REF_KEY, ref);
    } catch (_) {}
    mode = 'signup';
  }

  function setStatus(text, isError) {
    var el = document.getElementById('auth-status');
    if (!el) return;
    el.hidden = !text;
    el.textContent = text || '';
    el.classList.toggle('is-error', !!isError);
  }

  function renderMode() {
    var title = document.getElementById('auth-title');
    var submit = document.getElementById('auth-submit');
    var toggle = document.getElementById('auth-toggle');
    var name = document.getElementById('auth-name');
    var password = document.getElementById('auth-password');
    var meta = document.getElementById('auth-meta');
    var refWrap = document.getElementById('auth-ref-wrap');
    var refInput = document.getElementById('auth-ref');
    var isSignUp = mode === 'signup';
    if (title) title.textContent = isSignUp ? 'Create diner account' : 'Welcome back';
    if (submit) submit.textContent = isSignUp ? 'Create account' : 'Sign in';
    if (toggle) toggle.textContent = isSignUp ? 'Have an account? Sign in' : 'Create account';
    if (meta) {
      meta.textContent = ref
        ? 'Code ' + ref + ' is ready. Create an account so you both earn 50 HotPot Coins on your first order.'
        : 'Use the same email and password as the HotPotChef app.';
    }
    if (name) {
      name.hidden = !isSignUp;
      name.required = isSignUp;
    }
    if (refWrap) refWrap.hidden = !isSignUp;
    if (refInput && isSignUp && ref && !refInput.value) refInput.value = ref;
    var termsWrap = document.getElementById('auth-terms-wrap');
    var terms = document.getElementById('auth-terms');
    if (termsWrap) termsWrap.hidden = !isSignUp;
    if (terms) terms.required = isSignUp;
    if (password) {
      password.autocomplete = isSignUp ? 'new-password' : 'current-password';
    }
  }

  function wireOpenApp() {
    var wrap = document.getElementById('auth-open-wrap');
    var open = document.getElementById('open-app');
    if (!wrap || !open || !ref) return;
    wrap.hidden = false;
    var path = '/auth?ref=' + encodeURIComponent(ref);
    var https = 'https://hotpotchef.com' + path;
    var custom = 'hotpotchef://app/auth?ref=' + encodeURIComponent(ref);
    var isAndroid = /Android/i.test(navigator.userAgent || '');
    open.href = isAndroid
      ? 'intent://hotpotchef.com' +
        path +
        '#Intent;scheme=https;package=com.hotpotchef.app;S.browser_fallback_url=' +
        encodeURIComponent(https) +
        ';end'
      : custom;
  }

  if (api.isSignedIn()) {
    window.location.replace(next);
    return;
  }

  document.getElementById('auth-toggle').addEventListener('click', function () {
    mode = mode === 'signin' ? 'signup' : 'signin';
    setStatus('');
    renderMode();
  });

  document.getElementById('auth-form').addEventListener('submit', async function (ev) {
    ev.preventDefault();
    var email = (document.getElementById('auth-email').value || '').trim();
    var password = document.getElementById('auth-password').value || '';
    var name = (document.getElementById('auth-name').value || '').trim();
    var typedRef = ((document.getElementById('auth-ref') || {}).value || ref || '')
      .trim()
      .toUpperCase()
      .replace(/\s+/g, '');
    if (mode === 'signup' && !document.getElementById('auth-terms').checked) {
      setStatus('Please agree to the Terms and Privacy policy.', true);
      return;
    }
    setStatus(mode === 'signup' ? 'Creating account…' : 'Signing in…');
    try {
      if (mode === 'signup') {
        var created = await api.signUp(email, password, name, typedRef || null);
        if (!created.access_token) {
          setStatus('Check your email to confirm, then sign in.', false);
          mode = 'signin';
          renderMode();
          return;
        }
      } else {
        await api.signIn(email, password);
      }
      window.location.href = next;
    } catch (err) {
      setStatus((err && err.message) || 'Could not sign in.', true);
    }
  });

  renderMode();
  wireOpenApp();
})();
