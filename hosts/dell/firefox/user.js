// Firefox prefs for Dell (linked into the profile by setup.sh).

// Gruvbox theme: an unsigned local theme (theme/manifest.json), which ESR allows.
// setup.sh drops it into the profile's extensions/ folder; these let it load.
// Firefox only switches themes from about:addons, so enable it there once.
user_pref("xpinstall.signatures.required", false);
user_pref("extensions.autoDisableScopes", 0);

// The few spots no theme key reaches (see chrome/*.css).
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Ask websites for their dark version; compact toolbars on the small screen.
user_pref("layout.css.prefers-color-scheme.content-override", 0);
user_pref("browser.compactmode.show", true);
user_pref("browser.uidensity", 1);

// Closing the last tab opens a new tab instead of closing the window.
user_pref("browser.tabs.closeWindowWithLastTab", false);

// System highlight/accent colours (text selection, focused list items, toggles,
// checkboxes) default to GTK blue; make them gruvbox.
user_pref("ui.highlight", "#fabd2f");
user_pref("ui.highlighttext", "#282828");
user_pref("ui.selecteditem", "#504945");
user_pref("ui.selecteditemtext", "#ebdbb2");
user_pref("ui.accentcolor", "#fabd2f");
user_pref("ui.accentcolortext", "#282828");
user_pref("ui.-moz-field", "#282828");
user_pref("ui.-moz-fieldtext", "#ebdbb2");
