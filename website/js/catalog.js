(function () {
  var api = window.HotPotApi;
  if (!api) return;

  var LIMIT = 80;
  var allMeals = [];
  var dietFilter = 'all';
  var searchQuery = '';
  var chefFilterId = '';

  function setStatus(text, isError) {
    var el = document.getElementById('catalog-status');
    if (!el) return;
    el.hidden = !text;
    el.textContent = text || '';
    el.classList.toggle('is-error', !!isError);
  }

  function norm(s) {
    return (s || '').toString().toLowerCase().trim();
  }

  /** Drop seed/test rows so the public menu only shows orderable plates. */
  function isCatalogWorthy(meal) {
    var price = Number(meal.price);
    if (!isFinite(price) || price <= 0) return false;
    var title = (meal.title || '').toString().trim();
    if (!title) return false;
    var t = norm(title);
    if (
      t === 'guest' ||
      t === 'user account' ||
      t === 'test' ||
      t.indexOf('test') === 0 ||
      t.indexOf('discount') === 0 ||
      t.indexOf('promo') === 0 ||
      t.indexOf('fest') === 0
    ) {
      return false;
    }
    if (/^(new)?chef\d+$/i.test(title)) return false;
    if (/^hungry\d+$/i.test(title)) return false;
    if (/^user[_]?hungry/i.test(title)) return false;
    if (/^driver\d+$/i.test(title)) return false;
    // Placeholder rows often reuse the chef/login name as the dish title.
    var chef = norm(meal.chef_name || meal.local_kitchen_name || '');
    if (chef && t === chef) return false;
    return true;
  }

  function dietLabel(meal) {
    if (meal.is_veg === true || meal.is_veg === 'true') return 'Veg';
    if (meal.is_veg === false || meal.is_veg === 'false') return 'Non-veg';
    return 'Home plate';
  }

  function matchesQuery(meal, q) {
    if (!q) return true;
    var hay = [
      meal.title,
      meal.chef_name,
      meal.local_kitchen_name,
      meal.city,
    ]
      .map(norm)
      .join(' ');
    return hay.indexOf(q) !== -1;
  }

  function slotLabel(meal) {
    var raw = (meal.time_slot || '').toString();
    var m = raw.match(/(\d{1,2}:\d{2}\s*(?:AM|PM))\s+to\s+(\d{1,2}:\d{2}\s*(?:AM|PM))/i);
    if (m) return m[1].replace(/\s+/g, ' ') + '–' + m[2].replace(/\s+/g, ' ');
    if (!raw.trim() || /asap/i.test(raw)) return 'On your slot';
    return raw;
  }

  function dedupePlates(rows) {
    var seen = {};
    var out = [];
    rows.forEach(function (m) {
      var key = (m.chef_id || '') + '|' + norm(m.title);
      if (seen[key]) return;
      seen[key] = true;
      out.push(m);
    });
    return out;
  }

  function mealCard(meal) {
    var id = (meal.id || '').toString();
    var title = api.mealTitle(meal);
    var chef = api.chefLabel(meal);
    var price = api.money(meal.price);
    var image = (meal.image_url || '').toString().trim();
    var city = (meal.city || '').toString().trim();
    var href = '/meal/' + encodeURIComponent(id);
    var media = image
      ? '<img class="catalog-thumb" src="' +
        api.escapeHtml(image) +
        '" alt="' +
        api.escapeHtml(title) +
        '" loading="lazy" />'
      : '<div class="catalog-thumb catalog-thumb--empty" aria-hidden="true">HotPotChef</div>';
    var slot = slotLabel(meal);

    return (
      '<article class="catalog-card">' +
      '<a class="catalog-card-link" href="' +
      href +
      '">' +
      media +
      '<div class="catalog-body">' +
      '<p class="catalog-kicker">' +
      dietLabel(meal) +
      (city ? ' · ' + api.escapeHtml(city) : '') +
      ' · ' +
      api.escapeHtml(slot) +
      '</p>' +
      '<h3 class="catalog-title">' +
      api.escapeHtml(title) +
      '</h3>' +
      '<p class="catalog-chef">' +
      api.escapeHtml(chef) +
      '</p>' +
      '<p class="catalog-price">' +
      api.escapeHtml(price) +
      '</p>' +
      '</div></a>' +
      '<button type="button" class="catalog-add" data-add-id="' +
      api.escapeHtml(id) +
      '">Add</button>' +
      '</article>'
    );
  }

  function filteredMeals() {
    var q = norm(searchQuery);
    return allMeals.filter(function (m) {
      if (!isCatalogWorthy(m)) return false;
      if (chefFilterId && (m.chef_id || '').toString() !== chefFilterId) return false;
      var veg = m.is_veg === true || m.is_veg === 'true';
      var nonVeg = m.is_veg === false || m.is_veg === 'false';
      if (dietFilter === 'veg' && !veg) return false;
      if (dietFilter === 'nonveg' && !nonVeg) return false;
      return matchesQuery(m, q);
    });
  }

  function matchingChefs(q) {
    if (!q) return [];
    var map = {};
    allMeals.forEach(function (m) {
      if (!isCatalogWorthy(m)) return;
      var id = (m.chef_id || '').toString();
      if (!id) return;
      var label = api.chefLabel(m);
      var city = (m.city || '').toString();
      var hay = norm(label + ' ' + city + ' ' + (m.chef_name || ''));
      if (hay.indexOf(q) === -1) return;
      if (!map[id]) {
        map[id] = { id: id, name: label, city: city, count: 0 };
      }
      map[id].count += 1;
    });
    return Object.keys(map)
      .map(function (k) {
        return map[k];
      })
      .sort(function (a, b) {
        return b.count - a.count;
      })
      .slice(0, 8);
  }

  function renderChefs(q) {
    var strip = document.getElementById('chef-strip');
    var list = document.getElementById('chef-strip-list');
    if (!strip || !list) return;

    if (chefFilterId) {
      var active = allMeals.find(function (m) {
        return (m.chef_id || '').toString() === chefFilterId;
      });
      var label = active ? api.chefLabel(active) : 'This kitchen';
      strip.hidden = false;
      list.innerHTML =
        '<button type="button" class="chef-chip chef-chip--active" data-chef="">' +
        api.escapeHtml(label) +
        ' · clear</button>';
      return;
    }

    var chefs = matchingChefs(q);
    if (!chefs.length) {
      strip.hidden = true;
      list.innerHTML = '';
      return;
    }
    strip.hidden = false;
    list.innerHTML = chefs
      .map(function (c) {
        return (
          '<button type="button" class="chef-chip" data-chef="' +
          api.escapeHtml(c.id) +
          '">' +
          api.escapeHtml(c.name) +
          (c.city ? ' · ' + api.escapeHtml(c.city) : '') +
          ' <span>(' +
          c.count +
          ')</span></button>'
        );
      })
      .join('');
  }

  function render() {
    var grid = document.getElementById('catalog-grid');
    if (!grid) return;
    var rows = filteredMeals();
    var q = norm(searchQuery);
    renderChefs(q);

    if (!rows.length) {
      grid.innerHTML = '';
      setStatus(
        chefFilterId || q || dietFilter !== 'all'
          ? 'No plates match these filters. Try clearing search or diet.'
          : 'No Available plates right now. Open the app for kitchens near you.'
      );
      return;
    }

    grid.innerHTML = rows.map(mealCard).join('');
    var bits = [rows.length + ' plate' + (rows.length === 1 ? '' : 's')];
    if (chefFilterId) bits.push('from this kitchen');
    if (dietFilter === 'veg') bits.push('veg');
    if (dietFilter === 'nonveg') bits.push('non-veg');
    bits.push('add to cart or open the app');
    setStatus(bits.join(' · '));
  }

  async function loadCatalog() {
    var grid = document.getElementById('catalog-grid');
    if (!grid) return;

    if (!api.configReady()) {
      setStatus('Add Supabase keys in js/config.js to show live plates.', true);
      return;
    }

    setStatus('Loading neighbourhood plates…');
    try {
      var rows = await api.supabaseGet(
        'meals?status=eq.Available&price=gt.0&select=id,title,price,image_url,chef_name,chef_id,is_veg,time_slot,created_at&order=created_at.desc&limit=' +
          LIMIT
      );
      if (!rows || !rows.length) {
        allMeals = [];
        grid.innerHTML = '';
        setStatus('No Available plates right now. Open the app for kitchens near you.');
        return;
      }

      // Keep only orderable, non-seed rows before resolving kitchen labels.
      rows = rows.filter(isCatalogWorthy);
      if (!rows.length) {
        allMeals = [];
        grid.innerHTML = '';
        setStatus('No Available plates right now. Open the app for kitchens near you.');
        return;
      }

      var chefIds = [];
      var seen = {};
      rows.forEach(function (m) {
        var id = (m.chef_id || '').toString();
        if (id && !seen[id]) {
          seen[id] = true;
          chefIds.push(id);
        }
      });

      var kitchenByChef = {};
      var cityByChef = {};
      if (chefIds.length) {
        var inList = chefIds
          .map(function (id) {
            return '"' + id + '"';
          })
          .join(',');
        try {
          var profiles = await api.supabaseGet(
            'chef_profiles?user_id=in.(' + inList + ')&select=user_id,local_kitchen_name'
          );
          (profiles || []).forEach(function (p) {
            kitchenByChef[p.user_id] = (p.local_kitchen_name || '').toString().trim();
          });
        } catch (_) {}
        try {
          var users = await api.supabaseGet(
            'users?id=in.(' + inList + ')&select=id,city'
          );
          (users || []).forEach(function (u) {
            cityByChef[u.id] = (u.city || '').toString().trim();
          });
        } catch (_) {}
      }

      rows.forEach(function (m) {
        var kid = kitchenByChef[m.chef_id];
        if (kid) m.local_kitchen_name = kid;
        var city = cityByChef[m.chef_id];
        if (city) m.city = city;
      });

      allMeals = dedupePlates(rows);
      render();
    } catch (err) {
      allMeals = [];
      grid.innerHTML = '';
      setStatus('Could not load the live menu right now.', true);
    }
  }

  function wireControls() {
    var search = document.getElementById('catalog-search');
    var diet = document.getElementById('catalog-diet');
    var stripList = document.getElementById('chef-strip-list');

    if (search) {
      var timer = null;
      search.addEventListener('input', function () {
        clearTimeout(timer);
        timer = setTimeout(function () {
          searchQuery = search.value || '';
          if (!searchQuery) chefFilterId = '';
          render();
        }, 120);
      });
    }

    if (diet) {
      diet.addEventListener('change', function () {
        dietFilter = diet.value || 'all';
        render();
      });
    }

    if (stripList) {
      stripList.addEventListener('click', function (ev) {
        var btn = ev.target.closest('[data-chef]');
        if (!btn) return;
        var id = btn.getAttribute('data-chef') || '';
        chefFilterId = id;
        render();
      });
    }

    var grid = document.getElementById('catalog-grid');
    if (grid && window.HotPotCart) {
      grid.addEventListener('click', function (ev) {
        var btn = ev.target.closest('[data-add-id]');
        if (!btn) return;
        ev.preventDefault();
        var id = btn.getAttribute('data-add-id') || '';
        var meal = allMeals.find(function (m) {
          return (m.id || '').toString() === id;
        });
        if (!meal) return;
        var result = window.HotPotCart.add(meal, 1);
        if (!result.ok) {
          setStatus('Could not add that plate. Try again.', true);
          return;
        }
        btn.textContent = 'Added';
        setTimeout(function () {
          btn.textContent = 'Add';
        }, 1200);
      });
    }
  }

  var play = document.getElementById('play-cta');
  if (play) play.href = api.playStoreUrl();
  wireControls();
  loadCatalog();
})();
