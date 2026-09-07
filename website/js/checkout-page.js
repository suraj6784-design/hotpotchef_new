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
    if (!items.length) {
      list.innerHTML = '<p class="chef-empty">Cart is empty. Add a plate first.</p>';
      if (sub) sub.hidden = true;
      return;
    }
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
          '&select=id,title,name,price,chef_id,chef_name,quantity,status,time_slot,service_type'
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
        time_slot: meal.time_slot || '',
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
            setStatus('Order placed. Open the HotPotChef app to track it.');
            btn.textContent = 'Order placed';
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
})();
