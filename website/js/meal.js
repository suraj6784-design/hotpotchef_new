(function () {
  var api = window.HotPotApi;
  if (!api) return;

  function setText(id, text) {
    var el = document.getElementById(id);
    if (el) el.textContent = text || '';
  }

  function show(id, on) {
    var el = document.getElementById(id);
    if (!el) return;
    el.hidden = !on;
  }

  function renderMissing(mealId, message) {
    setText('title', 'Dish unavailable');
    setText('meta', message || 'This plate is no longer on the menu.');
    show('status', true);
    setText(
      'status',
      'You can still open HotPotChef to browse neighbourhood kitchens near you.'
    );
    api.wireOpenApp('open-app', 'play-cta', 'meal', mealId || '');
  }

  function miniCard(meal) {
    var id = (meal.id || '').toString();
    var title = api.mealTitle(meal);
    var price = api.money(meal.price);
    var image = (meal.image_url || '').toString().trim();
    var media = image
      ? '<img class="catalog-thumb" src="' +
        api.escapeHtml(image) +
        '" alt="' +
        api.escapeHtml(title) +
        '" loading="lazy" />'
      : '<div class="catalog-thumb catalog-thumb--empty" aria-hidden="true">HotPotChef</div>';
    return (
      '<a class="catalog-card" href="/meal/' +
      encodeURIComponent(id) +
      '">' +
      media +
      '<div class="catalog-body"><h3 class="catalog-title">' +
      api.escapeHtml(title) +
      '</h3>' +
      (price ? '<p class="catalog-price">' + api.escapeHtml(price) + '</p>' : '') +
      '</div></a>'
    );
  }

  async function loadMore(chefId, excludeId) {
    var section = document.getElementById('more-kitchen');
    var grid = document.getElementById('more-grid');
    if (!section || !grid || !chefId) return;
    try {
      var rows = await api.supabaseGet(
        'meals?chef_id=eq.' +
          encodeURIComponent(chefId) +
          '&status=eq.Available&select=id,title,price,image_url&order=created_at.desc&limit=6'
      );
      var others = (rows || []).filter(function (m) {
        return (m.id || '').toString() !== excludeId;
      });
      if (!others.length) {
        section.hidden = true;
        return;
      }
      grid.innerHTML = others.map(miniCard).join('');
      section.hidden = false;
    } catch (_) {
      section.hidden = true;
    }
  }

  function renderMeal(meal, mealId) {
    var title = api.mealTitle(meal);
    var chef = api.chefLabel(meal);
    var fssai = (meal.fssai_number || '').toString().trim();
    var price = api.money(meal.price);
    var desc = (meal.description || '').toString().trim();
    var image = (meal.image_url || '').toString().trim();
    var chefId = (meal.chef_id || '').toString().trim();
    var veg = meal.is_veg === true || meal.is_veg === 'true';
    var qty = Number(meal.quantity);
    var metaParts = ['Prepared by ' + chef];
    if (fssai) metaParts.push('FSSAI ' + fssai);
    if (isFinite(qty) && qty > 0) metaParts.push(qty + ' left');

    setText('kicker', veg ? 'Veg · Home kitchen plate' : 'Non-veg · Home kitchen plate');
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

    var chefLink = document.getElementById('chef-link');
    if (chefLink && chefId) {
      chefLink.hidden = false;
      chefLink.href = '/chef/' + encodeURIComponent(chefId);
      chefLink.textContent = 'View ' + chef;
    }

    var addBtn = document.getElementById('add-cart');
    if (addBtn && window.HotPotCart && meal.status === 'Available') {
      addBtn.hidden = false;
      addBtn.onclick = function () {
        window.HotPotCart.add(meal, 1);
        addBtn.textContent = 'Added · view cart';
        addBtn.onclick = function () {
          window.location.href = '/cart';
        };
      };
    }

    var pageUrl = api.siteOrigin() + '/meal/' + encodeURIComponent(mealId);
    api.setOg(title + ' · HotPotChef', api.punchline() + ' · ' + chef, image || undefined, pageUrl);
    api.wireOpenApp('open-app', 'play-cta', 'meal', mealId);
    if (chefId) loadMore(chefId, mealId);
  }

  async function loadMeal(mealId) {
    if (!api.configReady()) {
      renderMissing(
        mealId,
        'Site config is incomplete. Add Supabase URL and anon key in js/config.js.'
      );
      return;
    }

    try {
      var rows = await api.supabaseGet(
        'meals?id=eq.' +
          encodeURIComponent(mealId) +
          '&select=id,title,price,image_url,chef_name,chef_id,fssai_number,description,quantity,status,is_veg'
      );
      if (!rows || !rows.length) {
        renderMissing(mealId, 'This dish is no longer on the menu.');
        return;
      }
      var meal = rows[0];
      if (meal.chef_id) {
        try {
          var profiles = await api.supabaseGet(
            'chef_profiles?user_id=eq.' +
              encodeURIComponent(meal.chef_id) +
              '&select=local_kitchen_name'
          );
          if (profiles && profiles[0] && profiles[0].local_kitchen_name) {
            meal.local_kitchen_name = profiles[0].local_kitchen_name;
          }
        } catch (_) {}
      }
      renderMeal(meal, mealId);
      if (meal.status && meal.status !== 'Available') {
        show('status', true);
        setText(
          'status',
          'This plate is not Available right now — open the app for other dishes from this kitchen.'
        );
      }
    } catch (err) {
      renderMissing(mealId, 'Could not load this dish right now.');
    }
  }

  var mealId = api.idFromPath('meal');
  if (!mealId) {
    renderMissing('', 'Missing dish link.');
    return;
  }
  api.wireOpenApp('open-app', 'play-cta', 'meal', mealId);
  loadMeal(mealId);
})();
