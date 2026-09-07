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

  function wireOpenApp() {
    var open = document.getElementById('open-app');
    if (!open) return;
    var path = cart.appImportPath();
    var isAndroid = /Android/i.test(navigator.userAgent || '');
    var host = 'hotpotchef.com';
    var play = api.playStoreUrl();
    var httpsUrl = 'https://' + host + path;
    var intent =
      'intent://' +
      host +
      path +
      '#Intent;scheme=https;package=com.hotpotchef.app;S.browser_fallback_url=' +
      encodeURIComponent(play) +
      ';end';
    var custom = 'hotpotchef://app' + path;
    open.href = isAndroid ? intent : custom;
    open.addEventListener('click', function () {
      if (!isAndroid) return;
      setTimeout(function () {
        window.location.href = custom;
      }, 250);
    });
    // Also expose https for copy/share.
    open.setAttribute('data-https', httpsUrl);
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
      if (pay) pay.hidden = true;
      wireOpenApp();
      return;
    }

    if (empty) empty.hidden = true;
    var payWeb = document.getElementById('pay-web');
    if (payWeb) payWeb.hidden = false;
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
