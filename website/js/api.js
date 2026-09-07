(function (global) {
  var cfg = function () {
    return global.HOTPOTCHEF || {};
  };

  function restBase() {
    return (cfg().supabaseUrl || '').replace(/\/$/, '');
  }

  function restKey() {
    return cfg().supabaseAnonKey || '';
  }

  function configReady() {
    var key = restKey();
    return !!restBase() && !!key && key.indexOf('YOUR_') !== 0;
  }

  function money(value) {
    var n = Number(value);
    if (!isFinite(n) || n <= 0) return '';
    return '₹' + Math.round(n).toLocaleString('en-IN');
  }

  function escapeHtml(text) {
    return String(text || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function chefLabel(mealOrChef) {
    if (!mealOrChef) return 'Home kitchen';
    var local = (mealOrChef.local_kitchen_name || '').toString().trim();
    if (local) return local;
    var chef = (mealOrChef.chef_name || mealOrChef.name || mealOrChef.full_name || '')
      .toString()
      .trim();
    var lower = chef.toLowerCase();
    if (
      !chef ||
      lower === 'guest' ||
      lower === 'user account' ||
      /^(new)?chef\d+$/i.test(chef) ||
      /^hungry\d+$/i.test(chef) ||
      /^driver\d+$/i.test(chef)
    ) {
      return 'Home kitchen';
    }
    return chef;
  }

  function mealTitle(meal) {
    if (!meal) return 'Home kitchen plate';
    var title = (meal.title || meal.name || '').toString().trim();
    if (!title) return 'Home kitchen plate';
    var lower = title.toLowerCase();
    if (
      lower === 'guest' ||
      lower === 'user account' ||
      /^(new)?chef\d+$/i.test(title) ||
      /^hungry\d+$/i.test(title)
    ) {
      return 'Home kitchen plate';
    }
    return title;
  }

  async function supabaseGet(pathAndQuery) {
    var url = restBase();
    var key = restKey();
    if (!configReady()) {
      throw new Error('Site config is incomplete. Add Supabase URL and anon key in js/config.js.');
    }
    var res = await fetch(url + '/rest/v1/' + pathAndQuery, {
      headers: {
        apikey: key,
        Authorization: 'Bearer ' + key,
        Accept: 'application/json',
      },
    });
    if (!res.ok) throw new Error('Request failed (' + res.status + ')');
    return res.json();
  }

  function playStoreUrl() {
    return cfg().playStoreUrl || 'https://play.google.com/store/apps/details?id=com.hotpotchef.app';
  }

  function appDeepLink(kind, id) {
    return 'hotpotchef://app/' + kind + '/' + encodeURIComponent(id);
  }

  function androidIntent(kind, id) {
    var host = 'hotpotchef.com';
    var path = '/' + kind + '/' + encodeURIComponent(id);
    return (
      'intent://' +
      host +
      path +
      '#Intent;scheme=https;package=com.hotpotchef.app;S.browser_fallback_url=' +
      encodeURIComponent(playStoreUrl()) +
      ';end'
    );
  }

  function wireOpenApp(buttonId, playId, kind, id) {
    var open = document.getElementById(buttonId);
    var play = document.getElementById(playId);
    if (play) play.href = playStoreUrl();
    if (!open) return;
    if (!id) {
      open.href = playStoreUrl();
      return;
    }
    var isAndroid = /Android/i.test(navigator.userAgent || '');
    open.href = isAndroid ? androidIntent(kind, id) : appDeepLink(kind, id);
    open.addEventListener('click', function () {
      if (!isAndroid) return;
      setTimeout(function () {
        window.location.href = appDeepLink(kind, id);
      }, 250);
    });
  }

  function setOg(title, description, image, url) {
    function ensure(prop, content, isName) {
      if (!content) return;
      var attr = isName ? 'name' : 'property';
      var sel = 'meta[' + attr + '="' + prop + '"]';
      var el = document.head.querySelector(sel);
      if (!el) {
        el = document.createElement('meta');
        el.setAttribute(attr, prop);
        document.head.appendChild(el);
      }
      el.setAttribute('content', content);
    }
    document.title = title;
    ensure('og:title', title);
    ensure('og:description', description);
    ensure('description', description, true);
    ensure('og:url', url);
    if (image) {
      ensure('og:image', image);
      ensure('twitter:image', image);
    }
  }

  function siteOrigin() {
    return (cfg().siteOrigin || global.location.origin || 'https://hotpotchef.com').replace(/\/$/, '');
  }

  function idFromPath(segment) {
    var path = global.location.pathname || '';
    var re = new RegExp('\\/' + segment + '\\/([^\\/?#]+)', 'i');
    var match = path.match(re);
    if (match && match[1]) return decodeURIComponent(match[1]);
    var params = new URLSearchParams(global.location.search);
    return (params.get('id') || '').trim();
  }

  var SESSION_KEY = 'hotpotchef_auth_session_v1';

  function readSession() {
    try {
      var raw = global.localStorage.getItem(SESSION_KEY);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch (_) {
      return null;
    }
  }

  function writeSession(session) {
    if (!session) {
      global.localStorage.removeItem(SESSION_KEY);
      return;
    }
    global.localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  }

  function accessToken() {
    var s = readSession();
    return (s && s.access_token) || '';
  }

  function currentUser() {
    var s = readSession();
    return (s && s.user) || null;
  }

  function isSignedIn() {
    return !!accessToken();
  }

  async function authRequest(path, body) {
    if (!configReady()) throw new Error('Site config is incomplete.');
    var res = await fetch(restBase() + '/auth/v1/' + path, {
      method: 'POST',
      headers: {
        apikey: restKey(),
        Authorization: 'Bearer ' + restKey(),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    var data = await res.json().catch(function () {
      return {};
    });
    if (!res.ok) {
      throw new Error((data && (data.error_description || data.msg || data.error)) || 'Auth failed');
    }
    return data;
  }

  async function signIn(email, password) {
    var data = await authRequest('token?grant_type=password', {
      email: email,
      password: password,
    });
    writeSession(data);
    return data;
  }

  async function signUp(email, password, fullName) {
    var data = await authRequest('signup', {
      email: email,
      password: password,
      data: { role: 'Customer', full_name: fullName || '' },
    });
    if (data.access_token) writeSession(data);
    return data;
  }

  function signOut() {
    writeSession(null);
  }

  async function invokeFunction(name, body) {
    var token = accessToken();
    if (!token) throw new Error('Please sign in first.');
    var res = await fetch(restBase() + '/functions/v1/' + name, {
      method: 'POST',
      headers: {
        apikey: restKey(),
        Authorization: 'Bearer ' + token,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body || {}),
    });
    var data = await res.json().catch(function () {
      return {};
    });
    if (!res.ok && data && data.error) return data;
    if (!res.ok) throw new Error('Request failed (' + res.status + ')');
    return data;
  }

  function razorpayKeyId() {
    return (cfg().razorpayKeyId || '').trim();
  }

  global.HotPotApi = {
    configReady: configReady,
    money: money,
    escapeHtml: escapeHtml,
    chefLabel: chefLabel,
    mealTitle: mealTitle,
    supabaseGet: supabaseGet,
    playStoreUrl: playStoreUrl,
    wireOpenApp: wireOpenApp,
    setOg: setOg,
    siteOrigin: siteOrigin,
    idFromPath: idFromPath,
    punchline: function () {
      return cfg().punchline || 'Home kitchens. Near you. On your slot.';
    },
    readSession: readSession,
    accessToken: accessToken,
    currentUser: currentUser,
    isSignedIn: isSignedIn,
    signIn: signIn,
    signUp: signUp,
    signOut: signOut,
    invokeFunction: invokeFunction,
    razorpayKeyId: razorpayKeyId,
  };
})(window);
