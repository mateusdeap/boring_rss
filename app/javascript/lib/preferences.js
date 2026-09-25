// Saves some of the signed-in user's preferences in the background
// (PreferencesController#update, JSON). Resolves to whether it was saved.
export async function savePreferences(attributes) {
  try {
    const response = await fetch("/preferences", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: JSON.stringify({ user: attributes })
    })
    return response.ok
  } catch {
    return false
  }
}
