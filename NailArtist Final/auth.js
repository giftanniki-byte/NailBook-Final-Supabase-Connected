/* ============================================================
   NailBook shared authentication
   ============================================================ */

function showAuthMessage(element, text, type = 'error') {
  if (!element) return;
  element.textContent = text || '';
  element.style.color = type === 'success' ? '#199b4b' : '#e63863';
}

function safeText(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function initials(name) {
  return String(name || 'N')
    .trim()
    .split(/\s+/)
    .map(x => x[0])
    .join('')
    .slice(0, 2)
    .toUpperCase() || 'N';
}

async function getSignedInUser() {
  const { data, error } = await supabaseClient.auth.getUser();
  if (error || !data?.user) return null;
  return data.user;
}

async function getProfile(userId) {
  const { data, error } = await supabaseClient
    .from('profiles')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle();

  if (error) throw error;
  return data;
}

async function provisionProfile(options = {}) {
  const {
    role = null,
    fullName = null,
    phone = null,
    city = null,
    location = null,
    businessName = null,
    services = null
  } = options;

  const { data, error } = await supabaseClient.rpc('ensure_nailbook_profile', {
    p_role: role,
    p_full_name: fullName,
    p_phone: phone,
    p_city: city,
    p_location: location,
    p_business_name: businessName,
    p_services: services
  });

  if (error) throw error;
  return data;
}

async function signUpNailBookUser({
  role,
  email,
  password,
  fullName,
  phone = '',
  city = '',
  location = '',
  businessName = '',
  services = []
}) {
  if (!['artist', 'client'].includes(role)) {
    throw new Error('Please choose Artist or Client account type.');
  }

  const metadata = {
    role,
    full_name: fullName,
    phone,
    city,
    location,
    business_name: businessName || fullName,
    services
  };

  const { data, error } = await supabaseClient.auth.signUp({
    email: email.trim().toLowerCase(),
    password,
    options: { data: metadata }
  });

  if (error) {
    throw normalizeAuthError(error);
  }

  // If email confirmation is OFF, the session exists immediately and we can
  // create the public NailBook profile immediately.
  if (data.session) {
    try {
      await provisionProfile({
        role,
        fullName,
        phone,
        city,
        location,
        businessName: businessName || fullName,
        services
      });
    } catch (provisionError) {
      // Auth signup already succeeded. Do not tell the user that the account
      // itself failed. The login flow will retry provisioning.
      console.error('Profile provisioning after signup failed:', provisionError);
    }
  }

  return data;
}

async function signInNailBookUser({ email, password, expectedRole }) {
  const { data, error } = await supabaseClient.auth.signInWithPassword({
    email: email.trim().toLowerCase(),
    password
  });

  if (error) throw normalizeAuthError(error);

  try {
    await provisionProfile({});
  } catch (provisionError) {
    await supabaseClient.auth.signOut();
    throw new Error('Your Supabase account was created, but the NailBook profile could not be prepared. Check that nailbook.sql was run completely. Details: ' + provisionError.message);
  }

  const profile = await getProfile(data.user.id);

  if (!profile) {
    await supabaseClient.auth.signOut();
    throw new Error('Your NailBook profile was not found. Run nailbook.sql in Supabase and try again.');
  }

  if (expectedRole && profile.role !== expectedRole) {
    await supabaseClient.auth.signOut();
    throw new Error(
      expectedRole === 'artist'
        ? 'This account is not registered as an artist.'
        : 'This account is not registered as a client.'
    );
  }

  return { user: data.user, session: data.session, profile };
}

async function requireLogin(expectedRole) {
  const user = await getSignedInUser();
  if (!user) {
    window.location.href = expectedRole === 'artist' ? 'loginArtist.html' : 'loginclient.html';
    return null;
  }

  try {
    await provisionProfile({});
    const profile = await getProfile(user.id);

    if (!profile || (expectedRole && profile.role !== expectedRole)) {
      await supabaseClient.auth.signOut();
      window.location.href = expectedRole === 'artist' ? 'loginArtist.html' : 'loginclient.html';
      return null;
    }

    return { authUser: user, profile };
  } catch (error) {
    console.error('NailBook profile error:', error);
    alert('NailBook could not load your profile. Please run nailbook.sql completely in Supabase.\n\n' + error.message);
    return null;
  }
}

async function logout() {
  await supabaseClient.auth.signOut();
  window.location.href = 'Home%20page.html';
}

async function logoutClient() {
  return logout();
}

function normalizeAuthError(error) {
  const message = String(error?.message || error || 'Authentication failed.');
  const lower = message.toLowerCase();

  if (lower.includes('database error saving new user')) {
    return new Error(
      'Supabase Auth is still being blocked by a database trigger or Auth Hook. Run the latest nailbook.sql in the NailBook Supabase project, then check the final query for remaining custom auth.users triggers.'
    );
  }

  if (lower.includes('user already registered')) {
    return new Error('An account with this email already exists. Please log in instead.');
  }

  if (lower.includes('email not confirmed')) {
    return new Error('Please confirm your email address first, then log in.');
  }

  if (lower.includes('invalid login credentials')) {
    return new Error('Incorrect email or password.');
  }

  return error instanceof Error ? error : new Error(message);
}

window.safeText = safeText;
window.initials = initials;
window.getSignedInUser = getSignedInUser;
window.getProfile = getProfile;
window.provisionProfile = provisionProfile;
window.requireLogin = requireLogin;
window.signUpNailBookUser = signUpNailBookUser;
window.signInNailBookUser = signInNailBookUser;
window.logout = logout;
window.logoutClient = logoutClient;
window.showAuthMessage = showAuthMessage;
