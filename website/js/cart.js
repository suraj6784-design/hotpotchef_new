(function (global) {
  var STORAGE_KEY = 'hotpotchef_web_cart_v1';

  function read() {
    try {
      var raw = global.localStorage.getItem(STORAGE_KEY);
      if (!raw) return [];
      var parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  }

  function write(items) {
    global.localStorage.setItem(STORAGE_KEY, JSON.stringify(items || []));
    syncBadge();
  }

  function count() {
    return read().reduce(function (sum, item) {
      return sum + (Number(item.qty) || 0);
    }, 0);
  }

  function syncBadge() {
    var n = count();
    var nodes = global.document.querySelectorAll('[data-cart-count]');
    nodes.forEach(function (el) {
      if (n > 0) {
        el.hidden = false;
        el.textContent = String(n);
      } else {
        el.hidden = true;
        el.textContent = '';
      }
    });
  }

  function kitchenIds() {
    var ids = {};
    read().forEach(function (i) {
      var chef = (i.chef_id || '').toString();
      if (chef) ids[chef] = true;
    });
    return Object.keys(ids);
  }

  function add(meal, qty) {
    var id = (meal && meal.id ? meal.id : '').toString();
    if (!id) return { ok: false, reason: 'missing' };
    var amount = Math.max(1, Number(qty) || 1);
    var items = read();
    var chefId = (meal.chef_id || '').toString();
    var kitchens = kitchenIds();
    if (chefId && kitchens.length && kitchens.indexOf(chefId) === -1) {
      return { ok: false, reason: 'kitchen' };
    }
    var existing = items.find(function (i) {
      return i.id === id;
    });
    if (existing) {
      existing.qty = (Number(existing.qty) || 0) + amount;
      existing.title = meal.title || meal.name || existing.title;
      existing.price = meal.price != null ? meal.price : existing.price;
      existing.chef_id = meal.chef_id || existing.chef_id;
      existing.chef_name = meal.local_kitchen_name || meal.chef_name || existing.chef_name;
      existing.image_url = meal.image_url || existing.image_url;
    } else {
      items.push({
        id: id,
        qty: amount,
        title: (meal.title || meal.name || 'Plate').toString(),
        price: meal.price,
        chef_id: meal.chef_id,
        chef_name: meal.local_kitchen_name || meal.chef_name || '',
        image_url: meal.image_url || '',
      });
    }
    write(items);
    return { ok: true };
  }

  function setQty(id, qty) {
    var items = read().filter(function (i) {
      if (i.id !== id) return true;
      var n = Number(qty) || 0;
      if (n <= 0) return false;
      i.qty = n;
      return true;
    });
    write(items);
  }

  function remove(id) {
    write(
      read().filter(function (i) {
        return i.id !== id;
      })
    );
  }

  function clear() {
    write([]);
  }

  function itemsParam() {
    return read()
      .map(function (i) {
        return encodeURIComponent(i.id) + ':' + (Number(i.qty) || 1);
      })
      .join(',');
  }

  function appImportPath() {
    var param = itemsParam();
    return param ? '/cart?items=' + param : '/cart';
  }

  global.HotPotCart = {
    read: read,
    add: add,
    kitchenIds: kitchenIds,
    setQty: setQty,
    remove: remove,
    clear: clear,
    count: count,
    syncBadge: syncBadge,
    itemsParam: itemsParam,
    appImportPath: appImportPath,
  };

  if (global.document.readyState === 'loading') {
    global.document.addEventListener('DOMContentLoaded', syncBadge);
  } else {
    syncBadge();
  }
})(window);
