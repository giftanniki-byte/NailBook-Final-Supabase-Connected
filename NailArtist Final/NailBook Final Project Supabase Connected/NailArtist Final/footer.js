/* ==========================================================
   NailBook shared footer
   - The copyright footer appears on every page.
   - The larger navigation footer appears only on:
       1. Find artist.html
       2. helpandsupport.html
   ========================================================== */
(function () {
  const target = document.getElementById('siteFooter');
  if (!target) return;

  const currentPage = decodeURIComponent(
    (window.location.pathname.split('/').pop() || '').toLowerCase()
  );

  const showExtendedFooter =
    currentPage === 'find artist.html' ||
    currentPage === 'helpandsupport.html';

  const extendedFooter = showExtendedFooter ? `
    <footer class="nb-footer nb-footer-extended">
      <div class="nb-footer-inner">
        <div class="nb-footer-brand">
          <a class="nb-footer-logo" href="Home%20page.html">
            <span class="nb-footer-icon">✧</span>
            NailBook
          </a>
          <p>Find and book talented nail artists in your area.</p>
        </div>

        <div class="nb-footer-col">
          <h3>For Clients</h3>
          <a href="Find%20artist.html">Find Artists</a>
          <a href="dashboardclient.html">My Bookings</a>
          <a href="signupclient.html">join as Client</a>
        </div>

        <div class="nb-footer-col">
          <h3>For Artists</h3>
          <a href="signupArtist.html">Join as Artist</a>
          <a href="DashboardArtist.html">Artist Dashboard</a>
          <a href="loginArtist.html">Artist Login</a>
        </div>

        <div class="nb-footer-col">
          <h3>Support</h3>
          <a href="helpandsupport.html">Help Center</a>
          <a href="Contact%20us.html">Contact Us</a>
        </div>
      </div>
    </footer>
  ` : '';

  target.innerHTML = `
    ${extendedFooter}
    <footer class="nb-copyright-footer">
      <div class="nb-copyright-text">© 2026 NailBook. All rights reserved.</div>
    </footer>
  `;
})();
