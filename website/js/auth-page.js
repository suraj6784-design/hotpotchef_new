(function () {
  var api = window.HotPotApi;
  if (!api) return;

  var mode = 'signin';
  var params = new URLSearchParams(window.location.search);
  var next = params.get('next') || '/checkout';

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
    var isSignUp = mode === 'signup';
    if (title) title.textContent = isSignUp ? 'Create diner account' : 'Welcome back';
    if (submit) submit.textContent = isSignUp ? 'Create account' : 'Sign in';
    if (toggle) toggle.textContent = isSignUp ? 'Have an account? Sign in' : 'Create account';
    if (name) {
      name.hidden = !isSignUp;
      name.required = isSignUp;
    }
    if (password) {
      password.autocomplete = isSignUp ? 'new-password' : 'current-password';
    }
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
    setStatus(mode === 'signup' ? 'Creating account…' : 'Signing in…');
    try {
      if (mode === 'signup') {
        var created = await api.signUp(email, password, name);
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
})();
