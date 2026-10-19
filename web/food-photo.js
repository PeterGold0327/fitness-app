/* Windows meal-photo recognition. The B.ai secret stays in Supabase Edge Function secrets. */
(function () {
  let aiClient = null;
  let selectedPhoto = null;

  function cloudClient() {
    if (aiClient) return aiClient;
    const cfg = window.DUODUO_CLOUD_CONFIG;
    if (!window.supabase || !cfg?.supabaseUrl || !cfg?.supabaseAnonKey) return null;
    aiClient = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
    return aiClient;
  }

  function manualForm() {
    modal(`
      <div class="photo-modal-head">
        <div><div class="hero-kicker">MANUAL MEAL</div><h2>手动记录这一餐</h2></div>
        <button type="button" class="secondary compact-btn" onclick="openMeal()">← 图片识别</button>
      </div>
      <div class="field"><label>吃了什么</label><input id="mealName" placeholder="例如：米饭 + 鸡腿肉 + 西红柿炒蛋"></div>
      <div class="grid2">
        <div class="field"><label>热量 kcal</label><input id="mealCal" type="number" min="0" step="1"></div>
        <div class="field"><label>蛋白质 g</label><input id="mealPro" type="number" min="0" step="0.1"></div>
        <div class="field"><label>碳水 g</label><input id="mealCarbs" type="number" min="0" step="0.1"></div>
        <div class="field"><label>脂肪 g</label><input id="mealFat" type="number" min="0" step="0.1"></div>
      </div>
      <button type="button" class="primary" onclick="saveMeal()">保存这一餐</button>
    `);
  }

  window.openManualMeal = manualForm;

  window.openMeal = function openMeal() {
    selectedPhoto = null;
    modal(`
      <div class="photo-modal-head">
        <div>
          <div class="hero-kicker">AI MEAL PHOTO</div>
          <h2>上传饭菜照片</h2>
          <p class="subtle">自动拆分食物并给出一组最可能的克数、热量和三大营养素。结果保存前都可以修改。</p>
        </div>
        <button type="button" class="secondary compact-btn" onclick="openManualMeal()">手动记录</button>
      </div>

      <label class="photo-drop" for="mealPhotoInput">
        <input id="mealPhotoInput" type="file" accept="image/*" hidden onchange="window.pickMealPhoto(this.files?.[0])">
        <div id="photoDropInner" class="photo-drop-inner">
          <div class="photo-drop-icon">📷</div>
          <strong>选择照片</strong>
          <span>JPG / PNG / HEIC 均可，上传前会在本机压缩</span>
        </div>
        <img id="mealPhotoPreview" class="meal-photo-preview" alt="饭菜预览" hidden>
      </label>

      <div class="field meal-context-field">
        <label>补充说明（可选）</label>
        <input id="mealPhotoContext" maxlength="500" placeholder="例如：鸡腿去皮；米饭大约一碗。没有就留空">
      </div>

      <div id="photoAnalysisStatus" class="photo-analysis-status">不会保存原始照片，只用于本次识别。</div>
      <button id="analyzeMealButton" type="button" class="primary photo-analyze-btn" onclick="window.analyzeMealPhoto()">识别这顿饭</button>
      <div id="foodEstimateArea"></div>
    `);
  };

  window.pickMealPhoto = function pickMealPhoto(file) {
    if (!file) return;
    selectedPhoto = file;
    const preview = document.querySelector('#mealPhotoPreview');
    const inner = document.querySelector('#photoDropInner');
    if (preview) {
      preview.src = URL.createObjectURL(file);
      preview.hidden = false;
    }
    if (inner) inner.hidden = true;
    setStatus('照片已选择，可以开始识别。');
  };

  function setStatus(text, tone = '') {
    const el = document.querySelector('#photoAnalysisStatus');
    if (!el) return;
    el.textContent = text;
    el.dataset.tone = tone;
  }

  async function compressToJpeg(file) {
    const bitmap = await createImageBitmap(file);
    const maxSide = 1600;
    const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
    const width = Math.max(1, Math.round(bitmap.width * scale));
    const height = Math.max(1, Math.round(bitmap.height * scale));
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d', { alpha: false });
    ctx.drawImage(bitmap, 0, 0, width, height);
    bitmap.close?.();
    const blob = await new Promise((resolve, reject) => canvas.toBlob(b => b ? resolve(b) : reject(new Error('图片压缩失败')), 'image/jpeg', 0.82));
    if (blob.size > 6 * 1024 * 1024) throw new Error('图片仍然过大，请换一张更小的照片');
    const buffer = await blob.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    let binary = '';
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
    return btoa(binary);
  }

  window.analyzeMealPhoto = async function analyzeMealPhoto() {
    if (!selectedPhoto) { setStatus('先选择一张饭菜照片。', 'bad'); return; }
    const client = cloudClient();
    if (!client) { setStatus('云端还没连接，先在顶部登录 Supabase。', 'bad'); return; }
    const { data: sessionData } = await client.auth.getSession();
    if (!sessionData?.session) { setStatus('请先点击顶部云端状态并登录，再使用图片识别。', 'bad'); return; }

    const button = document.querySelector('#analyzeMealButton');
    if (button) { button.disabled = true; button.textContent = '正在识别…'; }
    setStatus('正在压缩并识别照片，通常需要几秒。', 'working');

    try {
      const imageBase64 = await compressToJpeg(selectedPhoto);
      const context = document.querySelector('#mealPhotoContext')?.value?.trim() || '';
      const { data, error } = await client.functions.invoke('analyze-food', { body: { imageBase64, context } });
      if (error) throw new Error(error.message || 'AI 识别失败');
      if (!data?.items?.length) throw new Error('没有识别到可用食物');
      renderEstimate(data);
      setStatus('识别完成。检查一下克数和营养值，确认后保存。', 'good');
    } catch (error) {
      console.error(error);
      setStatus('识别失败：' + (error?.message || '请稍后重试'), 'bad');
    } finally {
      if (button) { button.disabled = false; button.textContent = '重新识别'; }
    }
  };

  function cleanNumber(value) {
    const n = Number(value);
    return Number.isFinite(n) && n >= 0 ? n : 0;
  }

  function renderEstimate(estimate) {
    const area = document.querySelector('#foodEstimateArea');
    if (!area) return;
    const items = estimate.items.slice(0, 12);
    area.innerHTML = `
      <section class="food-estimate-card">
        <div class="section-head">
          <div><div class="hero-kicker">AI ESTIMATE</div><div class="section-title">${esc(estimate.name || '这一餐')}</div></div>
          <span class="pill">${items.length} 项食物</span>
        </div>
        <div class="food-estimate-head"><span>食物</span><span>克数</span><span>kcal</span><span>P</span><span>C</span><span>F</span><span></span></div>
        <div id="foodEstimateRows">${items.map((item, i) => foodRow(item, i)).join('')}</div>
        <button type="button" class="secondary add-food-row" onclick="window.addFoodEstimateRow()">＋ 添加食物</button>
        <div class="food-estimate-total">
          <span>合计</span><strong id="foodEstimateTotals">--</strong>
        </div>
        <div class="quick-row photo-save-row">
          <button type="button" class="primary" onclick="window.savePhotoMeal('${escapeAttr(estimate.name || 'AI 图片识别')}')">确认并保存这一餐</button>
          <button type="button" class="secondary" onclick="window.analyzeMealPhoto()">重新识别</button>
        </div>
      </section>`;
    updateEstimateTotals();
  }

  function escapeAttr(value) {
    return String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, ' ');
  }

  function foodRow(item, index) {
    const grams = cleanNumber(item.grams);
    const calories = cleanNumber(item.calories);
    const protein = cleanNumber(item.protein);
    const carbs = cleanNumber(item.carbs);
    const fat = cleanNumber(item.fat);
    return `<div class="food-estimate-row" data-base-grams="${grams}" data-base-calories="${calories}" data-base-protein="${protein}" data-base-carbs="${carbs}" data-base-fat="${fat}">
      <input class="food-name" value="${esc(item.name || ('食物 ' + (index + 1)))}" oninput="window.updateEstimateTotals()">
      <input class="food-grams" type="number" min="0" step="1" value="${Math.round(grams)}" oninput="window.resizeFoodEstimate(this)">
      <input class="food-calories" type="number" min="0" step="1" value="${Math.round(calories)}" oninput="window.updateEstimateTotals()">
      <input class="food-protein" type="number" min="0" step="0.1" value="${Math.round(protein * 10) / 10}" oninput="window.updateEstimateTotals()">
      <input class="food-carbs" type="number" min="0" step="0.1" value="${Math.round(carbs * 10) / 10}" oninput="window.updateEstimateTotals()">
      <input class="food-fat" type="number" min="0" step="0.1" value="${Math.round(fat * 10) / 10}" oninput="window.updateEstimateTotals()">
      <button type="button" class="set-remove" onclick="window.removeFoodEstimateRow(this)" aria-label="删除食物">×</button>
    </div>`;
  }

  window.resizeFoodEstimate = function resizeFoodEstimate(input) {
    const row = input.closest('.food-estimate-row');
    if (!row) return;
    const baseGrams = Number(row.dataset.baseGrams) || 0;
    const grams = Math.max(0, Number(input.value) || 0);
    if (baseGrams > 0) {
      const ratio = grams / baseGrams;
      [['calories','Calories',1],['protein','Protein',10],['carbs','Carbs',10],['fat','Fat',10]].forEach(([key, cls, precision]) => {
        const base = Number(row.dataset['base' + cls]) || 0;
        const field = row.querySelector('.food-' + key);
        if (field) field.value = precision === 1 ? Math.round(base * ratio) : Math.round(base * ratio * precision) / precision;
      });
    }
    updateEstimateTotals();
  };

  window.removeFoodEstimateRow = function removeFoodEstimateRow(button) {
    button.closest('.food-estimate-row')?.remove();
    updateEstimateTotals();
  };

  window.addFoodEstimateRow = function addFoodEstimateRow() {
    const list = document.querySelector('#foodEstimateRows');
    if (!list) return;
    const wrap = document.createElement('div');
    wrap.innerHTML = foodRow({ name: '', grams: 0, calories: 0, protein: 0, carbs: 0, fat: 0 }, list.children.length);
    list.appendChild(wrap.firstElementChild);
    updateEstimateTotals();
  };

  function estimateRows() {
    return [...document.querySelectorAll('#foodEstimateRows .food-estimate-row')].map(row => ({
      name: row.querySelector('.food-name')?.value?.trim() || '食物',
      grams: cleanNumber(row.querySelector('.food-grams')?.value),
      calories: cleanNumber(row.querySelector('.food-calories')?.value),
      protein: cleanNumber(row.querySelector('.food-protein')?.value),
      carbs: cleanNumber(row.querySelector('.food-carbs')?.value),
      fat: cleanNumber(row.querySelector('.food-fat')?.value)
    })).filter(x => x.name && (x.grams || x.calories || x.protein || x.carbs || x.fat));
  }

  function totals(items) {
    return items.reduce((a, x) => ({
      calories: a.calories + x.calories,
      protein: a.protein + x.protein,
      carbs: a.carbs + x.carbs,
      fat: a.fat + x.fat
    }), { calories: 0, protein: 0, carbs: 0, fat: 0 });
  }

  function updateEstimateTotals() {
    const t = totals(estimateRows());
    const el = document.querySelector('#foodEstimateTotals');
    if (el) el.textContent = `${Math.round(t.calories)} kcal · P ${Math.round(t.protein)}g · C ${Math.round(t.carbs)}g · F ${Math.round(t.fat)}g`;
  }
  window.updateEstimateTotals = updateEstimateTotals;

  window.savePhotoMeal = function savePhotoMeal(defaultName) {
    const items = estimateRows();
    if (!items.length) { setStatus('至少保留一项食物再保存。', 'bad'); return; }
    const t = totals(items);
    const generatedName = items.slice(0, 3).map(x => x.name).join(' + ') || defaultName || 'AI 图片识别';
    state.meals.push({
      id: crypto.randomUUID(), date: key(), name: generatedName,
      calories: Math.round(t.calories), protein: Math.round(t.protein * 10) / 10,
      carbs: Math.round(t.carbs * 10) / 10, fat: Math.round(t.fat * 10) / 10,
      items, source: 'ai-photo-web'
    });
    closeModal();
    save();
  };

  const priorNutrition = window.nutrition;
  if (typeof priorNutrition === 'function') {
    window.nutrition = function nutritionWithPhoto() {
      const html = priorNutrition();
      return html.replace(
        '<button class="primary" onclick="openMeal()">＋ 手动记录今天吃的</button>',
        '<div class="meal-entry-actions"><button class="primary" onclick="openMeal()">📷 上传照片识别</button><button class="secondary" onclick="openManualMeal()">＋ 手动记录</button></div>'
      );
    };
  }

  if (typeof render === 'function') render();
})();
