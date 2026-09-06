(function () {
  var cfg = window.HOTPOTCHEF || {};

  function mealIdFromLocation() {
    var path = window.location.pathname || '';
    var match = path.match(/\/meal\/([^\/?#]+)/i);
    if (match && match[1]) return decodeURIComponent(match[1]);
    var params = new URLSearchParams(window.location.search);
    return (params.get('id') || '').trim();
  }

  function setText(id, text) {
    var el = document.getElementById(id);
    if (el) el.textContent = text || '';
  }

  function show(id, on) {
    var el = document.getElementById(id);
    if (!el) return;
    el.hidden = !on;
  }

  function money(value) {
    var n = Number(value);
    if (!isFinite(n) || n <= 0) return '';
    return '₹' + Math.round(n).toLocaleString('en-IN');
  }

  function appDeepLink(mealId) {
    return 'hotpotchef://app/meal/' + encodeURIComponent(mealId);
  }

  function androidIntent(mealId) {
    var host = 'hotpotchef.com';
    var path = '/meal/' + encodeURIComponent(mealId);
    return (
      'intent://' +
      host +
      path +
      '#Intent;scheme=https;package=com.hotpotchef.app;S.browser_fallback_url=' +
      encodeURIComponent(cfg.playStoreUrl || 'https://play.google.com/store/apps/details?id=com.hotpotchef.app') +
      ';end'
    );
  }

  function setOpenLinks(mealId) {
    var open = document.getElementById('open-app');
    var play = document.getElementById('play-cta');
    if (play && cfg.playStoreUrl) play.href = cfg.playStoreUrl;
    if (!open) return;

    var isAndroid = /Android/i.test(navigator.userAgent || '');
    open.href = isAndroid ? androidIntent(mealId) : appDeepLink(mealId);
    open.addEventListener('click', function () {
      // Also try custom scheme for browsers that ignore intent://.
      if (!isAndroid) return;
      setTimeout(function () {
        window.location.href = appDeepLink(mealId);
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

  function renderMissing(mealId, message) {
    setText('title', 'Dish unavailable');
    setText('meta', message || 'This plate is no longer on the menu.');
    show('status', true);
    setText(
      'status',
      'You can still open HotPotChef to browse neighbourhood kitchens near you.'
    );
    if (mealId) setOpenLinks(mealId);
  }

  function renderMeal(meal, mealId) {
    var title = (meal.title || meal.name || 'Home kitchen plate').toString();
    var chef = (meal.chef_name || 'Home kitchen').toString();
    var fssai = (meal.fssai_number || '').toString().trim();
    var price = money(meal.price);
    var desc = (meal.description || '').toString().trim();
    var image = (meal.image_url || '').toString().trim();
    var metaParts = ['Prepared by ' + chef];
    if (fssai) metaParts.push('FSSAI ' + fssai);

    setText('title', title);
    setText('meta', metaParts.join(' · '));
    if (price) {
      show('price', true);
      setText('price', price);
    }
    if (desc) {
      show('desc', true);
      setText('desc', desc);
    }

    var visual = document.getElementById('visual');
    if (visual && image) {
      var img = document.createElement('img');
      img.className = 'meal-visual';
      img.alt = title;
      img.src = image;
      visual.replaceWith(img);
    }

    var origin = (cfg.siteOrigin || window.location.origin || 'https://hotpotchef.com').replace(/\/$/, '');
    var pageUrl = origin + '/meal/' + encodeURIComponent(mealId);
    setOg(
      title + ' · HotPotChef',
      (cfg.punchline || 'Home kitchens. Near you. On your slot.') + ' · ' + chef,
      image || undefined,
      pageUrl
    );
    setOpenLinks(mealId);
  }

  async function loadMeal(mealId) {
    var url = (cfg.supabaseUrl || '').replace(/\/$/, '');
    var key = cfg.supabaseAnonKey || '';
    if (!url || !key || key.indexOf('YOUR_') === 0) {
      renderMissing(
        mealId,
        'Site config is incomplete. Add Supabase URL and anon key in js/config.js.'
      );
      return;
    }

    var endpoint =
      url +
      '/rest/v1/meals?id=eq.' +
      encodeURIComponent(mealId) +
      '&select=id,title,name,price,image_url,chef_name,fssai_number,description,quantity';

    try {
      var res = await fetch(endpoint, {
        headers: {
          apikey: key,
          Authorization: 'Bearer ' + key,
          Accept: 'application/json',
        },
      });
      if (!res.ok) throw new Error('Could not load dish (' + res.status + ')');
      var rows = await res.json();
      if (!rows || !rows.length) {
        renderMissing(mealId, 'This dish is no longer on the menu.');
        return;
      }
      renderMeal(rows[0], mealId);
    } catch (err) {
      renderMissing(mealId, 'Could not load this dish right now.');
    }
  }

  var mealId = mealIdFromLocation();
  if (!mealId) {
    renderMissing('', 'Missing dish link.');
    var open = document.getElementById('open-app');
    if (open) open.href = cfg.playStoreUrl || '/';
    return;
  }
  setOpenLinks(mealId);
  loadMeal(mealId);
})();
