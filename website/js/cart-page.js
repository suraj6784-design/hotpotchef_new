(function () {
  var api = window.HotPotApi;
  var cart = window.HotPotCart;
  if (!api || !cart) return;

  function moneySum(items) {
    var total = 0;
    items.forEach(function (i) {
      var p = Number(i.price);
      var q = Number(i.qty) || 0;
      if (isFinite(p) && p > 0) total += p * q;
    });
    return total > 0 ? api.money(total) : '';
  }

  function showAppHint(text) {
    var hint = document.getElementById('app-open-hint');
    if (!hint) return;
    hint.hidden = !text;
    hint.textContent = text || '';
  }

  function isPhone() {
    return /Android|iPhone|iPad|iPod/i.test(navigator.userAgent || '');
  }

  function goWebCheckout() {
    window.location.href = '/checkout';
  }

  function androidAppIntent(path) {
    return (
      'intent://app' +
      path +
      '#Intent;scheme=hotpotchef;package=com.hotpotchef.app;end'
    );
  }

  function wireOpenApp() {
    var open = document.getElementById('open-app');
    if (!open) return;
    var path = cart.appImportPath();
    var custom = 'hotpotchef://app' + path;
    open.href = '/checkout';
    open.setAttribute('data-custom', custom);

    if (open.getAttribute('data-wired') === '1') return;
    open.setAttribute('data-wired', '1');
    open.addEventListener('click', function (ev) {
      var path = cart.appImportPath();
      if (!path || path === '/cart') {
        ev.preventDefault();
        showAppHint('Add a plate first, then checkout.');
        return;
      }
      if (!isPhone()) {
        return;
      }
      ev.preventDefault();
      var custom = 'hotpotchef://app' + path;
      var openedAway = false;
      function onHide() {
        if (document.hidden) openedAway = true;
      }
      document.addEventListener('visibilitychange', onHide);
      window.location.href = /Android/i.test(navigator.userAgent || '')
        ? androidAppIntent(path)
        : custom;
      setTimeout(function () {
        document.removeEventListener('visibilitychange', onHide);
        if (!openedAway) goWebCheckout();
      }, 1400);
    });
  }

  function render() {
    var items = cart.read();
    var list = document.getElementById('cart-list');
    var empty = document.getElementById('cart-empty');
    var totalEl = document.getElementById('cart-total');
    if (!list) return;

    cart.syncBadge();
    if (!items.length) {
      list.innerHTML = '';
      if (empty) empty.hidden = false;
      if (totalEl) totalEl.hidden = true;
      var pay = document.getElementById('pay-web');
      var open = document.getElementById('open-app');
      if (pay) pay.hidden = true;
      if (open) open.hidden = true;
      showAppHint('');
      return;
    }

    if (empty) empty.hidden = true;
    var payWeb = document.getElementById('pay-web');
    var openApp = document.getElementById('open-app');
    var mixed = cart.kitchenIds().length > 1;
    if (payWeb) payWeb.hidden = mixed;
    if (openApp) openApp.hidden = false;
    if (mixed && empty) {
      empty.hidden = false;
      empty.textContent =
        'Web checkout is one kitchen at a time. Remove plates from extra kitchens, or checkout in the app.';
    }
    list.innerHTML = items
      .map(function (item) {
        var price = api.money(item.price);
        return (
          '<div class="web-cart-row" data-id="' +
          api.escapeHtml(item.id) +
          '">' +
          '<div><strong>' +
          api.escapeHtml(item.title || 'Plate') +
          '</strong>' +
          (item.chef_name
            ? '<span class="web-cart-chef">' + api.escapeHtml(item.chef_name) + '</span>'
            : '') +
          (price ? '<span class="web-cart-price">' + api.escapeHtml(price) + '</span>' : '') +
          '</div>' +
          '<div class="web-cart-qty">' +
          '<button type="button" data-act="dec" aria-label="Decrease">−</button>' +
          '<span>' +
          (Number(item.qty) || 1) +
          '</span>' +
          '<button type="button" data-act="inc" aria-label="Increase">+</button>' +
          '<button type="button" class="web-cart-remove" data-act="rm">Remove</button>' +
          '</div></div>'
        );
      })
      .join('');

    var sum = moneySum(items);
    if (totalEl) {
      if (sum) {
        totalEl.hidden = false;
        totalEl.textContent = 'Subtotal ' + sum;
      } else {
        totalEl.hidden = true;
      }
    }
    wireOpenApp();
  }

  document.getElementById('cart-list').addEventListener('click', function (ev) {
    var btn = ev.target.closest('[data-act]');
    if (!btn) return;
    var row = btn.closest('[data-id]');
    if (!row) return;
    var id = row.getAttribute('data-id');
    var item = cart.read().find(function (i) {
      return i.id === id;
    });
    if (!item) return;
    var act = btn.getAttribute('data-act');
    if (act === 'inc') cart.setQty(id, (Number(item.qty) || 1) + 1);
    if (act === 'dec') cart.setQty(id, (Number(item.qty) || 1) - 1);
    if (act === 'rm') cart.remove(id);
    render();
  });

  render();
})();
