(function () {
  var api = window.HotPotApi;
  var cart = window.HotPotCart;
  if (!api || !cart) return;

  if (!api.isSignedIn()) {
    window.location.replace('/auth?next=' + encodeURIComponent('/checkout'));
    return;
  }

  var user = api.currentUser();
  var userEl = document.getElementById('checkout-user');
  if (userEl) {
    userEl.textContent =
      (user && user.email ? user.email : 'Signed in') +
      ' · <button type="button" id="sign-out-link" class="text-link">Sign out</button>';
    // textContent escapes HTML — set properly:
    userEl.textContent = '';
    userEl.appendChild(document.createTextNode((user && user.email) || 'Signed in'));
    userEl.appendChild(document.createTextNode(' · '));
    var out = document.createElement('button');
    out.type = 'button';
    out.className = 'text-link';
    out.textContent = 'Sign out';
    out.addEventListener('click', function () {
      api.signOut();
      window.location.href = '/auth?next=/checkout';
    });
    userEl.appendChild(out);
  }

  function setStatus(text, isError) {
    var el = document.getElementById('co-status');
    if (!el) return;
    el.hidden = !text;
    el.textContent = text || '';
    el.classList.toggle('is-error', !!isError);
  }

  function renderCart() {
    var items = cart.read();
    var list = document.getElementById('checkout-items');
    var sub = document.getElementById('checkout-subtotal');
    if (!list) return;
    var form = document.getElementById('checkout-form');
    var payBtn = document.getElementById('co-pay');
    if (!items.length) {
      list.innerHTML =
        '<p class="chef-empty">Cart is empty. <a href="/#live-menu">Browse the live menu</a> first.</p>';
      if (sub) sub.hidden = true;
      if (form) form.hidden = true;
      if (payBtn) payBtn.disabled = true;
      return;
    }
    if (form) form.hidden = false;
    if (payBtn) payBtn.disabled = false;
    var total = 0;
    list.innerHTML = items
      .map(function (item) {
        var p = Number(item.price) || 0;
        var q = Number(item.qty) || 1;
        total += p * q;
        return (
          '<div class="web-cart-row"><div><strong>' +
          api.escapeHtml(item.title || 'Plate') +
          '</strong><span class="web-cart-chef">Qty ' +
          q +
          '</span></div></div>'
        );
      })
      .join('');
    if (sub) {
      sub.hidden = false;
      sub.textContent = 'Food subtotal ' + api.money(total);
    }
  }

  async function buildCheckoutItems() {
    var local = cart.read();
    if (!local.length) throw new Error('Your cart is empty');
    var out = [];
    for (var i = 0; i < local.length; i++) {
      var row = local[i];
      var meals = await api.supabaseGet(
        'meals?id=eq.' +
          encodeURIComponent(row.id) +
          '&select=id,title,price,chef_id,chef_name,quantity,status,time_slot,service_type'
      );
      if (!meals || !meals[0]) throw new Error('A plate in your cart is no longer available');
      var meal = meals[0];
      if (meal.status && meal.status !== 'Available') {
        throw new Error((meal.title || meal.name || 'A plate') + ' is not Available');
      }
      var qty = Math.max(1, Number(row.qty) || 1);
      out.push({
        id: meal.id,
        meal_id: meal.id,
        source_meal_id: meal.id,
        chef_id: meal.chef_id,
        title: meal.title || meal.name,
        name: meal.name || meal.title,
        price: meal.price,
        quantity: qty,
        // Kitchen windows like "Sat, Sun (9:00 AM to 11:00 PM)" are not a diner drop-off.
        time_slot: 'ASAP',
        service_type: (meal.service_type || 'Delivery Partner').toString().split(',')[0].trim(),
      });
    }
    var chefs = {};
    out.forEach(function (m) {
      chefs[(m.chef_id || '').toString()] = true;
    });
    if (Object.keys(chefs).filter(Boolean).length > 1) {
      throw new Error('Web checkout supports one kitchen at a time. Remove other kitchens from the cart.');
    }
    return out;
  }

  async function pay(ev) {
    ev.preventDefault();
    var phone = (document.getElementById('co-phone').value || '').replace(/\D/g, '');
    if (phone.length > 10) phone = phone.slice(-10);
    var address = (document.getElementById('co-address').value || '').trim();
    var notes = (document.getElementById('co-notes').value || '').trim();
    var deliveryFee = document.getElementById('co-delivery-fee').checked ? 40 : 0;
    var btn = document.getElementById('co-pay');

    if (phone.length < 10) {
      setStatus('Enter a valid 10-digit phone number.', true);
      return;
    }
    if (!address) {
      setStatus('Enter a delivery address.', true);
      return;
    }
    var key = api.razorpayKeyId();
    if (!key || key.indexOf('YOUR_') === 0) {
      setStatus('Add razorpayKeyId in js/config.js (same Key ID as the app).', true);
      return;
    }
    if (typeof Razorpay === 'undefined') {
      setStatus('Razorpay Checkout failed to load. Check your network.', true);
      return;
    }

    btn.disabled = true;
    setStatus('Preparing secure payment…');
    try {
      var cartItems = await buildCheckoutItems();
      var created = await api.invokeFunction('create-split-order', {
        cart_items: cartItems,
        customer_email: user && user.email,
        customer_phone: phone,
        delivery_address: address,
        instructions: notes,
        delivery_fee: deliveryFee,
        tip_amount: 0,
        apply_coins: false,
      });
      if (!created || created.success !== true) {
        throw new Error((created && created.error) || 'Could not start payment');
      }

      var options = {
        key: key,
        amount: created.amount,
        currency: created.currency || 'INR',
        name: 'HotPotChef',
        description: 'Home kitchen order',
        order_id: created.order_id,
        prefill: {
          email: (user && user.email) || '',
          contact: phone,
        },
        theme: { color: '#F4511E' },
        handler: async function (response) {
          setStatus('Payment received — recording your order…');
          try {
            var placed = await api.invokeFunction('recover-payment', {
              payment_id: response.razorpay_payment_id,
              razorpay_order_id: response.razorpay_order_id,
              razorpay_signature: response.razorpay_signature,
              customer_phone: phone,
              delivery_address: address,
              instructions: notes,
              cart_items: cartItems,
              apply_coins: false,
              tip_amount: 0,
              delivery_fee: deliveryFee,
            });
            if (!placed || placed.success !== true) {
              throw new Error((placed && placed.error) || 'Payment received but order was not recorded');
            }
            cart.clear();
            cart.syncBadge();
            setStatus('Order placed. Open the HotPotChef app to track it.');
            btn.textContent = 'Order placed';
            var form = document.getElementById('checkout-form');
            var done = document.getElementById('co-done');
            if (form) form.hidden = true;
            if (done) done.hidden = false;
          } catch (err) {
            setStatus((err && err.message) || 'Could not record order after payment.', true);
            btn.disabled = false;
          }
        },
        modal: {
          ondismiss: function () {
            btn.disabled = false;
            setStatus('Payment cancelled. Your cart is still saved.');
          },
        },
      };

      var rzp = new Razorpay(options);
      rzp.on('payment.failed', function (resp) {
        btn.disabled = false;
        var desc =
          resp && resp.error && (resp.error.description || resp.error.reason)
            ? resp.error.description || resp.error.reason
            : 'Payment failed';
        setStatus(desc, true);
      });
      rzp.open();
      setStatus('Complete payment in the Razorpay window…');
    } catch (err) {
      btn.disabled = false;
      setStatus((err && err.message) || 'Checkout failed.', true);
    }
  }

  document.getElementById('checkout-form').addEventListener('submit', pay);
  renderCart();
  cart.syncBadge();
  loadAccountDetails();

  async function loadAccountDetails() {
    var phoneEl = document.getElementById('co-phone');
    var addressEl = document.getElementById('co-address');
    var notesEl = document.getElementById('co-notes');
    var savedWrap = document.getElementById('co-saved-wrap');
    var savedSelect = document.getElementById('co-saved-address');
    if (!user || !user.id) return;

    setStatus('Loading your saved details…');
    try {
      var profiles = await api.supabaseAuthedGet(
        'users?id=eq.' +
          encodeURIComponent(user.id) +
          '&select=phone,address,house_no,street,city,state,pincode,full_name,name'
      );
      var profile = profiles && profiles[0];
      var meta = (user && user.user_metadata) || {};
      var phone =
        (profile && profile.phone) || meta.phone || user.phone || '';
      phone = String(phone || '').trim();
      if (phoneEl && phone && !phoneEl.value) phoneEl.value = phone;

      var addresses = [];
      try {
        addresses = await api.supabaseAuthedGet(
          'user_addresses?user_id=eq.' +
            encodeURIComponent(user.id) +
            '&select=*&order=is_default.desc,updated_at.desc'
        );
      } catch (_) {
        try {
          addresses = await api.supabaseAuthedGet(
            'user_addresses?user_id=eq.' + encodeURIComponent(user.id) + '&select=*'
          );
        } catch (_) {}
      }

      var formatted = (addresses || [])
        .map(function (row) {
          return {
            row: row,
            text: api.formatSavedAddress(row),
            isDefault: row.is_default === true || row.is_default === 'true',
          };
        })
        .filter(function (item) {
          return item.text;
        });

      if (!formatted.length && profile) {
        var fallback = api.formatSavedAddress(profile);
        if (fallback) {
          formatted.push({ row: profile, text: fallback, isDefault: true });
        }
      }

      if (formatted.length && savedWrap && savedSelect) {
        savedWrap.hidden = false;
        var initial = 0;
        for (var i = 0; i < formatted.length; i++) {
          if (formatted[i].isDefault) {
            initial = i;
            break;
          }
        }

        savedSelect.innerHTML = formatted
          .map(function (item, index) {
            var label = item.text;
            if (item.isDefault) label = 'Default · ' + label;
            return (
              '<option value="' +
              index +
              '"' +
              (index === initial ? ' selected' : '') +
              '>' +
              api.escapeHtml(label) +
              '</option>'
            );
          })
          .join('');

        function applySaved(index) {
          var item = formatted[index];
          if (!item || !addressEl) return;
          addressEl.value = item.text;
          if (notesEl && !notesEl.value) {
            var gate = (item.row.gate_instructions || item.row.delivery_notes || '')
              .toString()
              .trim();
            if (gate) notesEl.value = gate.indexOf('Gate:') === 0 ? gate : 'Gate: ' + gate;
          }
        }

        savedSelect.value = String(initial);
        applySaved(initial);
        savedSelect.addEventListener('change', function () {
          applySaved(Number(savedSelect.value) || 0);
        });
      } else if (addressEl && !addressEl.value && profile) {
        var only = api.formatSavedAddress(profile);
        if (only) addressEl.value = only;
      }

      setStatus('');
    } catch (err) {
      setStatus('Could not load saved phone/address — enter them below.', true);
    }
  }
})();
