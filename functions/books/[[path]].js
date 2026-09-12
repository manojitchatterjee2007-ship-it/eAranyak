export async function onRequestGet(context) {
  const { request } = context;
  const url = new URL(request.url);

  // Supabase public configuration
  const SUPABASE_URL = 'https://btbcojfuipogpsarjcdw.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ0YmNvamZ1aXBvZ3BzYXJqY2R3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyNTU2OTYsImV4cCI6MjEwMjgzMTY5Nn0.q2wtTcZX15QWXMrRg9nWKleZC1F633Ng_d6ajsXuOng';

  const html = `<!DOCTYPE html>
<html lang="bn">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>এখন আরণ্যক — অনলাইন বই ঘর (Ekhon Aranyak Online Book Store)</title>
  <meta name="description" content="এখন আরণ্যক প্রকাশিত ও সহযোগিতায় প্রকাশিত বইয়ের অনলাইন সংস্করণ ও ক্যাটালগ।">

  <!-- Open Graph -->
  <meta property="og:title" content="এখন আরণ্যক — অনলাইন বই ঘর">
  <meta property="og:description" content="প্রকৃতি, বন্যপ্রাণ ও বনের সেরা বই সংগ্রহ করুন অনলাইন থেকে।">
  <meta property="og:image" content="https://earanyak.pages.dev/icons/Icon-512.png">
  <meta property="og:url" content="https://earanyak.pages.dev/books">
  <meta property="og:type" content="website">

  <!-- Styling -->
  <style>
    :root {
      --bg-color: #0D1410;
      --card-bg: #18221B;
      --card-border: #2A3D2D;
      --primary-color: #00E676;
      --secondary-color: #81C784;
      --text-main: #E0E0E0;
      --text-muted: #9E9E9E;
      --accent-red: #FF5252;
      --price-tag: #FFD54F;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      background-color: var(--bg-color);
      color: var(--text-main);
      font-family: 'Segoe UI', 'Arial', sans-serif, 'SolaimanLipi', 'Siyam Rupali';
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }

    header {
      background: linear-gradient(180deg, #142419 0%, #0D1410 100%);
      border-bottom: 1px solid var(--card-border);
      padding: 24px 16px;
      text-align: center;
      position: sticky;
      top: 0;
      z-index: 100;
      backdrop-filter: blur(10px);
    }

    header h1 {
      color: #FFFFFF;
      font-size: 1.8rem;
      font-weight: 700;
      margin-bottom: 6px;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
    }

    header p {
      color: var(--secondary-color);
      font-size: 0.95rem;
    }

    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 24px 16px;
      flex: 1;
      width: 100%;
    }

    .store-intro {
      background-color: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 12px;
      padding: 20px;
      margin-bottom: 28px;
      line-height: 1.6;
      font-size: 0.95rem;
      color: #CCCCCC;
    }

    .books-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 24px;
    }

    .book-card {
      background-color: var(--card-bg);
      border: 1px solid var(--card-border);
      border-radius: 14px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      transition: transform 0.25s ease, box-shadow 0.25s ease, border-color 0.25s ease;
    }

    .book-card:hover {
      transform: translateY(-6px);
      box-shadow: 0 12px 24px rgba(0, 0, 0, 0.5);
      border-color: var(--primary-color);
    }

    .book-cover-wrap {
      width: 100%;
      height: 280px;
      background-color: #121B12;
      position: relative;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .book-cover-wrap img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      transition: transform 0.3s ease;
    }

    .book-card:hover .book-cover-wrap img {
      transform: scale(1.04);
    }

    .availability-badge {
      position: absolute;
      top: 10px;
      right: 10px;
      padding: 4px 10px;
      border-radius: 20px;
      font-size: 0.75rem;
      font-weight: bold;
      backdrop-filter: blur(8px);
    }

    .badge-in-stock {
      background-color: rgba(0, 230, 118, 0.25);
      color: #00E676;
      border: 1px solid #00E676;
    }

    .badge-out-stock {
      background-color: rgba(255, 82, 82, 0.25);
      color: #FF5252;
      border: 1px solid #FF5252;
    }

    .book-info {
      padding: 18px;
      display: flex;
      flex-direction: column;
      flex: 1;
    }

    .book-title {
      font-size: 1.15rem;
      font-weight: 700;
      color: #FFFFFF;
      margin-bottom: 6px;
      line-height: 1.35;
    }

    .book-author {
      font-size: 0.9rem;
      color: var(--secondary-color);
      margin-bottom: 4px;
    }

    .book-publisher {
      font-size: 0.8rem;
      color: var(--text-muted);
      margin-bottom: 12px;
    }

    .book-price-row {
      display: flex;
      align-items: baseline;
      gap: 10px;
      margin-top: auto;
      padding-top: 12px;
      border-top: 1px solid rgba(255, 255, 255, 0.08);
      margin-bottom: 14px;
    }

    .current-price {
      font-size: 1.25rem;
      font-weight: 800;
      color: var(--price-tag);
    }

    .original-price {
      font-size: 0.9rem;
      color: var(--text-muted);
      text-decoration: line-through;
    }

    .discount-tag {
      font-size: 0.75rem;
      background-color: rgba(255, 82, 82, 0.2);
      color: #FF5252;
      padding: 2px 6px;
      border-radius: 4px;
      font-weight: bold;
    }

    .card-actions {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }

    .btn {
      padding: 10px 12px;
      border-radius: 8px;
      font-size: 0.85rem;
      font-weight: 700;
      text-align: center;
      cursor: pointer;
      text-decoration: none;
      border: none;
      transition: background-color 0.2s ease, transform 0.1s ease;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
    }

    .btn:active {
      transform: scale(0.98);
    }

    .btn-detail {
      background-color: transparent;
      color: var(--text-main);
      border: 1px solid var(--card-border);
    }

    .btn-detail:hover {
      background-color: rgba(255, 255, 255, 0.05);
      border-color: #81C784;
    }

    .btn-order {
      background-color: var(--primary-color);
      color: #000000;
    }

    .btn-order:hover {
      background-color: #00C853;
    }

    .btn-disabled {
      background-color: #333333;
      color: #777777;
      cursor: not-allowed;
    }

    /* Modal Styling */
    .modal-overlay {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background-color: rgba(0, 0, 0, 0.85);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 16px;
      z-index: 1000;
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.25s ease;
    }

    .modal-overlay.active {
      opacity: 1;
      pointer-events: auto;
    }

    .modal-content {
      background-color: var(--card-bg);
      border: 1px solid var(--primary-color);
      border-radius: 16px;
      max-width: 600px;
      width: 100%;
      max-height: 90vh;
      overflow-y: auto;
      padding: 24px;
      position: relative;
    }

    .modal-close {
      position: absolute;
      top: 16px;
      right: 16px;
      background: none;
      border: none;
      color: var(--text-muted);
      font-size: 1.5rem;
      cursor: pointer;
    }

    .modal-close:hover {
      color: #FFFFFF;
    }

    .modal-body {
      display: flex;
      flex-direction: column;
      gap: 16px;
      margin-top: 12px;
    }

    .modal-cover {
      width: 100%;
      max-height: 320px;
      object-fit: contain;
      background-color: #121B12;
      border-radius: 8px;
    }

    .loading-state, .error-state, .empty-state {
      text-align: center;
      padding: 60px 20px;
      color: var(--text-muted);
    }

    .spinner {
      width: 40px;
      height: 40px;
      border: 3px solid rgba(0, 230, 118, 0.2);
      border-top-color: var(--primary-color);
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 0 auto 16px;
    }

    @keyframes spin {
      to { transform: rotate(360deg); }
    }

    footer {
      text-align: center;
      padding: 24px 16px;
      border-top: 1px solid var(--card-border);
      color: var(--text-muted);
      font-size: 0.85rem;
      margin-top: auto;
    }

    @media (max-width: 600px) {
      .books-grid {
        grid-template-columns: 1fr;
      }
      .book-cover-wrap {
        height: 240px;
      }
    }
  </style>
</head>
<body>

  <header>
    <h1>📚 এখন আরণ্যক — অনলাইন বই ঘর</h1>
    <p>Ekhon Aranyak Online Book Store</p>
  </header>

  <div class="container">
    <div class="store-intro">
      🌿 <strong>স্বাগতম!</strong> এখন আরণ্যকের সহযোগিতায় ও বিভিন্ন প্রকাশনা থেকে প্রকাশিত প্রকৃতি, বন্যপ্রাণী, পাখি ও পরিবেশ ভিত্তিক গ্রন্থাবলি এখান থেকে সরাসরি অর্ডার করতে পারেন। পছন্দের বইটি বেছে নিয়ে বিস্তারিত জানুন এবং সরাসরি হোয়াটসঅ্যাপ বা অর্ডার লিঙ্কের মাধ্যমে সংগ্রহ করুন।
    </div>

    <div id="loading" class="loading-state">
      <div class="spinner"></div>
      <p>বইয়ের তালিকা লোড হচ্ছে...</p>
    </div>

    <div id="error" class="error-state" style="display: none;">
      <p>⚠️ বইয়ের তালিকা লোড করতে সমস্যা হয়েছে। অনুগ্রহ করে পেজটি রিফ্রেশ করুন।</p>
    </div>

    <div id="empty" class="empty-state" style="display: none;">
      <p>📚 এই মুহূর্তে কোনো অনলাইন বই পাওয়া যাচ্ছে না। শীঘ্রই নতুন বই আসছে!</p>
    </div>

    <div id="booksGrid" class="books-grid" style="display: none;"></div>
  </div>

  <!-- Detail Modal -->
  <div id="detailModal" class="modal-overlay">
    <div class="modal-content">
      <button class="modal-close" onclick="closeModal()">&times;</button>
      <div id="modalBody" class="modal-body"></div>
    </div>
  </div>

  <footer>
    <p>© ${new Date().getFullYear()} eআরণ্যক — প্রকৃতি ও বন্যপ্রাণ ডিজিটাল লাইব্রেরি</p>
  </footer>

  <script>
    const SUPABASE_URL = '${SUPABASE_URL}';
    const SUPABASE_ANON_KEY = '${SUPABASE_ANON_KEY}';

    let booksData = [];

    async function fetchBooks() {
      try {
        const response = await fetch(
          \`\${SUPABASE_URL}/rest/v1/online_books?is_published=eq.true&order=editorial_priority.desc,published_at.desc\`,
          {
            headers: {
              'apikey': SUPABASE_ANON_KEY,
              'Authorization': \`Bearer \${SUPABASE_ANON_KEY}\`
            }
          }
        );

        if (!response.ok) throw new Error('Failed to fetch');

        booksData = await response.json();
        renderBooks(booksData);
      } catch (err) {
        document.getElementById('loading').style.display = 'none';
        document.getElementById('error').style.display = 'block';
      }
    }

    function renderBooks(books) {
      document.getElementById('loading').style.display = 'none';

      if (!books || books.length === 0) {
        document.getElementById('empty').style.display = 'block';
        return;
      }

      const grid = document.getElementById('booksGrid');
      grid.style.display = 'grid';
      grid.innerHTML = '';

      books.forEach((book, idx) => {
        const card = document.createElement('div');
        card.className = 'book-card';

        const coverUrl = book.thumbnail_url || 'https://earanyak.pages.dev/icons/Icon-512.png';
        const isAvailable = book.is_available !== false;

        let discountHtml = '';
        if (book.original_price && book.original_price > book.price) {
          const pct = Math.round(((book.original_price - book.price) / book.original_price) * 100);
          discountHtml = \`<span class="original-price">₹\${book.original_price}</span> <span class="discount-tag">\${pct}% ছাড়</span>\`;
        }

        const currencySymbol = book.currency === 'INR' || !book.currency ? '₹' : book.currency;

        card.innerHTML = \`
          <div class="book-cover-wrap">
            <img src="\${coverUrl}" alt="\${escapeHtml(book.title)}" loading="lazy" onerror="this.src='https://earanyak.pages.dev/icons/Icon-512.png'">
            <span class="availability-badge \${isAvailable ? 'badge-in-stock' : 'badge-out-stock'}">
              \${isAvailable ? 'স্টকে আছে' : 'মজুদ নেই'}
            </span>
          </div>
          <div class="book-info">
            <h2 class="book-title">\${escapeHtml(book.title)}</h2>
            <div class="book-author">লেখক: \${escapeHtml(book.author || 'অন্যান্য')}</div>
            <div class="book-publisher">প্রকাশক: \${escapeHtml(book.publisher || 'এখন আরণ্যক')}</div>

            <div class="book-price-row">
              <span class="current-price">\${currencySymbol}\${book.price}</span>
              \${discountHtml}
            </div>

            <div class="card-actions">
              <button class="btn btn-detail" onclick="openDetail(\${idx})">
                📖 বিস্তারিত
              </button>
              \${isAvailable && book.order_url
                ? \`<a class="btn btn-order" href="\${escapeHtml(book.order_url)}" target="_blank" onclick="logOrderClick('\${book.id}')">🛒 অর্ডার</a>\`
                : \`<button class="btn btn-disabled" disabled>অপ্রাপ্য</button>\`
              }
            </div>
          </div>
        \`;

        grid.appendChild(card);
      });
    }

    function openDetail(idx) {
      const book = booksData[idx];
      if (!book) return;

      logOpenEvent(book.id);

      const coverUrl = book.thumbnail_url || 'https://earanyak.pages.dev/icons/Icon-512.png';
      const isAvailable = book.is_available !== false;
      const currencySymbol = book.currency === 'INR' || !book.currency ? '₹' : book.currency;

      let discountHtml = '';
      if (book.original_price && book.original_price > book.price) {
        const pct = Math.round(((book.original_price - book.price) / book.original_price) * 100);
        discountHtml = \`<span class="original-price">₹\${book.original_price}</span> <span class="discount-tag">\${pct}% ছাড়</span>\`;
      }

      const modalBody = document.getElementById('modalBody');
      modalBody.innerHTML = \`
        <img class="modal-cover" src="\${coverUrl}" alt="\${escapeHtml(book.title)}">
        <h2 style="font-size: 1.4rem; color: #FFF;">\${escapeHtml(book.title)}</h2>
        <p style="color: var(--secondary-color); font-weight: 600;">লেখক: \${escapeHtml(book.author || 'অন্যান্য')}</p>
        <p style="color: var(--text-muted); font-size: 0.9rem;">প্রকাশক: \${escapeHtml(book.publisher || 'এখন আরণ্যক')}</p>

        <div class="book-price-row" style="border: none; padding-top: 0; margin-bottom: 8px;">
          <span class="current-price" style="font-size: 1.5rem;">\${currencySymbol}\${book.price}</span>
          \${discountHtml}
        </div>

        <div style="line-height: 1.6; color: #DDD; font-size: 0.95rem; white-space: pre-wrap; background: #121B12; padding: 14px; border-radius: 8px;">
          \${escapeHtml(book.description || 'বিবরণ উপলব্ধ নেই।')}
        </div>

        <div style="margin-top: 12px;">
          \${isAvailable && book.order_url
            ? \`<a class="btn btn-order" style="width: 100%; padding: 14px; font-size: 1rem;" href="\${escapeHtml(book.order_url)}" target="_blank" onclick="logOrderClick('\${book.id}')">🛒 বইটি অর্ডার করুন (Order Now)</a>\`
            : \`<button class="btn btn-disabled" style="width: 100%; padding: 14px;" disabled>স্টক শেষ (Out of Stock)</button>\`
          }
        </div>
      \`;

      document.getElementById('detailModal').classList.add('active');
    }

    function closeModal() {
      document.getElementById('detailModal').classList.remove('active');
    }

    function logOpenEvent(bookId) {
      fetch(\`\${SUPABASE_URL}/rest/v1/content_analytics_events\`, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': \`Bearer \${SUPABASE_ANON_KEY}\`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          content_type: 'online_book',
          content_id: String(bookId),
          event_type: 'open'
        })
      }).catch(() => {});
    }

    function logOrderClick(bookId) {
      fetch(\`\${SUPABASE_URL}/rest/v1/content_analytics_events\`, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': \`Bearer \${SUPABASE_ANON_KEY}\`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          content_type: 'online_book',
          content_id: String(bookId),
          event_type: 'order_click'
        })
      }).catch(() => {});
    }

    function escapeHtml(str) {
      if (!str) return '';
      return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
    }

    fetchBooks();
  </script>
</body>
</html>`;

  return new Response(html, {
    headers: {
      'content-type': 'text/html;charset=UTF-8',
      'cache-control': 'public, max-age=60, s-maxage=300',
    },
  });
}
